local mod = get_mod('SimpleSequencer')
local ProfileSchema = mod:io_dofile('SimpleSequencer/scripts/mods/SimpleSequencer/modules/ProfileSchema')
local Profiles = {}

-- The phase mappings are adapted from Skitarius (GPL-3.0-only). See SimpleSequencer/NOTICE and SimpleSequencer/LICENSE.
local ACTION_PLANS = {
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

local function _new_profile(kind)
    return ProfileSchema.clone(ProfileSchema.defaults[kind])
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

        for _, kind in ipairs(ProfileSchema.kinds) do
            local profiles = mode_data[kind] or {}
            mode_data[kind] = profiles

            local global_key = kind == 'MELEE' and 'global_melee' or 'global_ranged'
            _ensure_profile(data, mode, kind, global_key)

            local defaults = ProfileSchema.defaults[kind]
            for _, profile in pairs(profiles) do
                _merge_defaults(profile, defaults)
            end
        end
    end

    return data
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

local function _append_plan(queue, action)
    local phases = ACTION_PLANS[action]

    if not phases then
        return
    end

    for i = 1, #phases do
        queue[#queue + 1] = phases[i]
    end
end

local function _new_plan(commands, cycle_index, repeating)
    return {
        commands = commands,
        cycle_index = cycle_index,
        repeating = repeating,
    }
end

function Profiles.compile(profile, kind, ranged_mode, has_special)
    if not profile then
        return _new_plan({}, 0, false)
    end

    local queue = {}
    local cycle_index = 0
    local repeating = false
    local cycle_point = profile.sequence_cycle_point or ProfileSchema.defaults.MELEE.sequence_cycle_point
    local no_repeat = cycle_point == 'no_repeat'

    if kind == 'MELEE' then
        repeating = not no_repeat
        local cycle_step = tonumber(string.match(cycle_point, '%d+')) or 1

        for i = 1, ProfileSchema.sequence_step_count do
            if not no_repeat and cycle_step == i then
                cycle_index = #queue + 1
            end

            local action = profile[ProfileSchema.sequence_step_prefix .. i]

            if action and action ~= 'none' then
                _append_plan(queue, action)
            end
        end
    else
        local fire_mode

        if kind == 'RANGED' then
            fire_mode = ranged_mode == 'ads' and profile.automatic_fire_ads or profile.automatic_fire_hip
        end

        if not fire_mode or fire_mode == 'none' then
            return _new_plan(queue, cycle_index, repeating)
        end
        if fire_mode == 'special' and not has_special then
            fire_mode = 'special_standard'
        elseif fire_mode == 'special_charged' and not has_special then
            fire_mode = 'special_standard'
        end

        _append_plan(queue, fire_mode)
        cycle_index = 1
        repeating = true
    end

    return _new_plan(queue, cycle_index, repeating)
end

return Profiles
