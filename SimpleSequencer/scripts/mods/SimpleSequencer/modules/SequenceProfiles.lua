local Profiles = {}

local PROFILE_DATA_VERSION = 1
local WeaponTemplates

local MELEE_STEPS = {
    'sequence_step_one',
    'sequence_step_two',
    'sequence_step_three',
    'sequence_step_four',
    'sequence_step_five',
    'sequence_step_six',
    'sequence_step_seven',
    'sequence_step_eight',
    'sequence_step_nine',
    'sequence_step_ten',
    'sequence_step_eleven',
    'sequence_step_twelve',
}

local MELEE_EXPANSIONS = {
    light_attack = { 'start_attack', 'light_attack', 'idle' },
    heavy_attack = { 'start_attack', 'heavy_attack', 'idle' },
    special_action = { 'special_action', 'idle' },
    special_heavy = { 'special_start_attack', 'special_heavy_execute', 'idle' },
    special_invert = { 'special_invert', 'idle' },
    block = { 'block', 'idle' },
    push = { 'block', 'push', 'idle' },
    push_attack = { 'block', 'push', 'push_follow_up' },
    wield = { 'quick_wield' },
}

local RANGED_EXPANSIONS = {
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

local function _new_melee_profile()
    local profile = {
        sequence_cycle_point = 'sequence_step_1',
    }

    for i = 1, #MELEE_STEPS do
        profile[MELEE_STEPS[i]] = 'none'
    end

    return profile
end

local function _new_ranged_profile()
    return {
        automatic_fire_hip = 'none',
        automatic_fire_ads = 'none',
        auto_charge_threshold = 100,
        rate_of_fire_hip = 0,
        rate_of_fire_ads = 0,
    }
end

local function _ensure_profile(data, mode, kind, weapon_key)
    data[mode] = data[mode] or { MELEE = {}, RANGED = {} }
    data[mode][kind] = data[mode][kind] or {}
    data[mode][kind][weapon_key] = data[mode][kind][weapon_key]
        or _clone(kind == 'MELEE' and _new_melee_profile() or _new_ranged_profile())

    return data[mode][kind][weapon_key]
end

function Profiles.new_data()
    local data = {
        _version = PROFILE_DATA_VERSION,
    }

    for i = 1, 4 do
        local mode = 'mode_' .. i
        data[mode] = {
            MELEE = { global_melee = _new_melee_profile() },
            RANGED = { global_ranged = _new_ranged_profile() },
        }
    end

    return data
end

function Profiles.ensure(data)
    data = type(data) == 'table' and data or Profiles.new_data()

    for i = 1, 4 do
        local mode = 'mode_' .. i
        local melee = _ensure_profile(data, mode, 'MELEE', 'global_melee')
        local ranged = _ensure_profile(data, mode, 'RANGED', 'global_ranged')
        local melee_defaults = _new_melee_profile()
        local ranged_defaults = _new_ranged_profile()

        if ranged.automatic_fire and ranged.automatic_fire_hip == nil then
            ranged.automatic_fire_hip = ranged.automatic_fire
            ranged.automatic_fire_ads = ranged.automatic_fire
        end

        for key, value in pairs(melee_defaults) do
            if melee[key] == nil then
                melee[key] = value
            end
        end

        for key, value in pairs(ranged_defaults) do
            if ranged[key] == nil then
                ranged[key] = value
            end
        end

        for _, profile in pairs(data[mode].MELEE) do
            for key, value in pairs(melee_defaults) do
                if profile[key] == nil then
                    profile[key] = value
                end
            end
        end

        for _, profile in pairs(data[mode].RANGED) do
            if profile.automatic_fire and profile.automatic_fire_hip == nil then
                profile.automatic_fire_hip = profile.automatic_fire
                profile.automatic_fire_ads = profile.automatic_fire
            end

            for key, value in pairs(ranged_defaults) do
                if profile[key] == nil then
                    profile[key] = value
                end
            end
        end
    end

    if data._version == nil then
        for i = 1, 4 do
            local mode = 'mode_' .. i

            for _, profile in pairs(data[mode].MELEE) do
                if profile.sequence_cycle_point == 'no_repeat' then
                    profile.sequence_cycle_point = 'sequence_step_1'
                end
            end
        end

        data._version = PROFILE_DATA_VERSION
    end

    return data
end

function Profiles.clone(value)
    return _clone(value)
end

function Profiles.keys(kind)
    if kind == 'MELEE' then
        return {
            'sequence_cycle_point',
            'sequence_step_one',
            'sequence_step_two',
            'sequence_step_three',
            'sequence_step_four',
            'sequence_step_five',
            'sequence_step_six',
            'sequence_step_seven',
            'sequence_step_eight',
            'sequence_step_nine',
            'sequence_step_ten',
            'sequence_step_eleven',
            'sequence_step_twelve',
        }
    end

    return {
        'automatic_fire_hip',
        'automatic_fire_ads',
        'auto_charge_threshold',
        'rate_of_fire_hip',
        'rate_of_fire_ads',
    }
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
    local expansion = MELEE_EXPANSIONS[action] or RANGED_EXPANSIONS[action]

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

    if kind == 'MELEE' then
        local cycle_step = tonumber(string.match(profile.sequence_cycle_point or '', '%d+'))

        for i = 1, #MELEE_STEPS do
            if cycle_step == i then
                cycle_index = #queue + 1
            end

            local action = profile[MELEE_STEPS[i]]

            if action and action ~= 'none' then
                _append_expansion(queue, action)
            end
        end
    else
        local fire_mode

        if kind == 'RANGED' then
            fire_mode = ranged_mode == 'ads' and (profile.automatic_fire_ads or profile.automatic_fire)
                or (profile.automatic_fire_hip or profile.automatic_fire)
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
