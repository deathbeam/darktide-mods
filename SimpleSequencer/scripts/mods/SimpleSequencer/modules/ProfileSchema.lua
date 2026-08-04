local PROFILE_SCHEMA = {
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

function PROFILE_SCHEMA.clone(value)
    return _clone(value)
end

function PROFILE_SCHEMA.keys(kind)
    local keys = {}

    for key in pairs(PROFILE_SCHEMA.defaults[kind] or {}) do
        keys[#keys + 1] = key
    end

    table.sort(keys)

    return keys
end

return PROFILE_SCHEMA
