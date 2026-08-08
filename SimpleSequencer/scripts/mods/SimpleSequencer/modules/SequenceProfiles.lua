local mod = get_mod('SimpleSequencer')
local Profiles = {
    sequence_step_count = 6,
    sequence_step_prefix = 'sequence_step_',
    kinds = { 'MELEE', 'RANGED' },
    defaults = {
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
        },
    },
}

function Profiles.clone(value)
    if type(value) ~= 'table' then
        return value
    end

    local result = {}

    for key, child in pairs(value) do
        result[key] = Profiles.clone(child)
    end

    return result
end

function Profiles.keys(kind)
    local keys = {}

    for key in pairs(Profiles.defaults[kind] or {}) do
        keys[#keys + 1] = key
    end

    table.sort(keys)

    return keys
end

local function _new_profile(kind)
    return Profiles.clone(Profiles.defaults[kind])
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

        for _, kind in ipairs(Profiles.kinds) do
            local profiles = mode_data[kind] or {}
            mode_data[kind] = profiles

            local global_key = kind == 'MELEE' and 'global_melee' or 'global_ranged'
            _ensure_profile(data, mode, kind, global_key)

            local defaults = Profiles.defaults[kind]
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

function Profiles.build_sequence(profile, kind, ranged_mode)
    local steps = {}
    local cycle_step = 0
    local repeating = false

    if profile and kind == 'MELEE' then
        local cycle_point = profile.sequence_cycle_point or Profiles.defaults.MELEE.sequence_cycle_point
        local no_repeat = cycle_point == 'no_repeat'

        repeating = not no_repeat
        local selected_step = tonumber(string.match(cycle_point, '%d+')) or 1

        for i = 1, Profiles.sequence_step_count do
            if not no_repeat and selected_step == i then
                cycle_step = #steps + 1
            end

            local action = profile[Profiles.sequence_step_prefix .. i]

            if action and action ~= 'none' then
                steps[#steps + 1] = action
            end
        end
    elseif profile and kind == 'RANGED' then
        local fire_mode = ranged_mode == 'ads' and profile.automatic_fire_ads or profile.automatic_fire_hip

        if fire_mode and fire_mode ~= 'none' then
            steps[1] = fire_mode
            cycle_step = 1
            repeating = true
        end
    end

    return {
        steps = steps,
        cycle_step = cycle_step,
        repeating = repeating,
    }
end

return Profiles
