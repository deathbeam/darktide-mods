local Profiles = {}

local WeaponTemplates

local SEQUENCE_STEP_COUNT = 6
local SEQUENCE_STEP_PREFIX = 'sequence_step_'
local PROFILE_KINDS = { 'MELEE', 'RANGED' }
local PROFILE_DEFAULTS = {
    MELEE = {
        sequence_cycle_point = 'sequence_step_1',
        sequence_step_1 = 'none',
        sequence_step_2 = 'none',
        sequence_step_3 = 'none',
        sequence_step_4 = 'none',
        sequence_step_5 = 'none',
        sequence_step_6 = 'none',
    },
    RANGED = {
        automatic_fire_hip = 'none',
        automatic_fire_ads = 'none',
        auto_charge_threshold = 100,
        rate_of_fire_hip = 0,
        rate_of_fire_ads = 0,
    },
}

-- Profile commands expand into the action states observed by the weapon system.
local COMMAND_STEPS = {
    light_attack = { 'start_attack', 'light_attack', 'idle' },
    heavy_attack = { 'start_attack', 'heavy_attack', 'idle' },
    special_action = { 'special_action', 'idle' },
    special_heavy = { 'special_start_attack', 'special_heavy_execute', 'idle' },
    special_invert = { 'special_invert', 'idle' },
    block = { 'block', 'idle' },
    push = { 'block', 'push', 'idle' },
    push_attack = { 'block', 'push', 'push_follow_up' },
    wield = { 'quick_wield' },
    standard = { 'shoot', 'idle' },
    charged = { 'charge', 'shoot', 'idle' },
    special = { 'special_start_attack', 'special_light_attack', 'idle' },
    special_charged = { 'special_start_attack', 'special_heavy_execute', 'idle' },
    special_standard = { 'special_action', 'shoot', 'idle' },
}

local function _has_ranged_special_attack(weapon_name)
    if not WeaponTemplates then
        WeaponTemplates = require('scripts/settings/equipment/weapon_templates/weapon_templates')
    end
    local template = weapon_name and WeaponTemplates[weapon_name]
    local action_inputs = template and template.action_inputs

    return action_inputs
        and (
                action_inputs.special_action
                or action_inputs.special_action_hold
                or action_inputs.special_action_light
                or action_inputs.special_action_heavy
            )
            ~= nil
end

local function _clone(value)
    if type(value) ~= 'table' then
        return value
    end

    local result = {}

    for key, child in pairs(value) do
        result[key] = _clone(child)
    end

    return result
end

local function _new_profile(kind)
    return _clone(PROFILE_DEFAULTS[kind])
end

local function _merge_defaults(profile, defaults)
    for key, value in pairs(defaults) do
        if profile[key] == nil then
            profile[key] = value
        end
    end
end

local function _ensure_profile(data, mode, kind, weapon_key)
    local mode_data = data[mode] or {}
    local profiles = mode_data[kind] or {}
    mode_data[kind] = profiles
    data[mode] = mode_data
    profiles[weapon_key] = profiles[weapon_key] or _new_profile(kind)

    return profiles[weapon_key]
end

function Profiles.new_data()
    local data = {}

    for i = 1, 4 do
        local mode = 'mode_' .. i
        data[mode] = {
            MELEE = { global_melee = _new_profile('MELEE') },
            RANGED = { global_ranged = _new_profile('RANGED') },
        }
    end

    return data
end

function Profiles.ensure(data)
    data = type(data) == 'table' and data or Profiles.new_data()

    for i = 1, 4 do
        local mode = 'mode_' .. i
        local mode_data = data[mode] or {}
        data[mode] = mode_data

        for _, kind in ipairs(PROFILE_KINDS) do
            local profiles = mode_data[kind] or {}
            mode_data[kind] = profiles

            local global_key = kind == 'MELEE' and 'global_melee' or 'global_ranged'
            _ensure_profile(data, mode, kind, global_key)

            local defaults = PROFILE_DEFAULTS[kind]
            for _, profile in pairs(profiles) do
                _merge_defaults(profile, defaults)
            end
        end
    end

    return data
end

function Profiles.clone(value)
    return _clone(value)
end

function Profiles.keys(kind)
    local defaults = PROFILE_DEFAULTS[kind]
    local keys = {}

    for key in pairs(defaults or {}) do
        keys[#keys + 1] = key
    end

    table.sort(keys)
    return keys
end

function Profiles.get(data, mode, kind, weapon_name)
    local mode_data = data and data[mode]
    local kind_data = mode_data and mode_data[kind]

    if not kind_data then
        return nil, nil
    end

    local specific = weapon_name and kind_data[weapon_name]
    local global_key = kind == 'MELEE' and 'global_melee' or 'global_ranged'

    if specific then
        return specific, weapon_name
    end

    return kind_data[global_key], global_key
end

local function _append_expansion(queue, action)
    local expansion = COMMAND_STEPS[action]

    if expansion then
        for i = 1, #expansion do
            queue[#queue + 1] = expansion[i]
        end
    end
end

function Profiles.build(profile, kind, weapon_name, ranged_mode)
    if not profile then
        return {}, 0, false
    end

    local queue = {}
    local cycle_index = 0
    local repeating = false
    local cycle_point = profile.sequence_cycle_point or 'sequence_step_1'
    local no_repeat = cycle_point == 'no_repeat'

    if kind == 'MELEE' then
        repeating = not no_repeat
        local cycle_step = tonumber(string.match(cycle_point, '%d+')) or 1

        for i = 1, SEQUENCE_STEP_COUNT do
            if not no_repeat and cycle_step == i then
                cycle_index = #queue + 1
            end

            local action = profile[SEQUENCE_STEP_PREFIX .. i]

            if action and action ~= 'none' then
                _append_expansion(queue, action)
            end
        end
    else
        local fire_mode

        if kind == 'RANGED' then
            fire_mode = ranged_mode == 'ads' and profile.automatic_fire_ads or profile.automatic_fire_hip
        end

        if not fire_mode or fire_mode == 'none' then
            return queue, cycle_index, repeating
        end

        if fire_mode == 'special' and not _has_ranged_special_attack(weapon_name) then
            fire_mode = 'special_standard'
        elseif fire_mode == 'special_charged' and not _has_ranged_special_attack(weapon_name) then
            fire_mode = 'special_standard'
        end

        _append_expansion(queue, fire_mode)
        cycle_index = 1
        repeating = true
    end

    return queue, cycle_index, repeating
end

return Profiles
