local mod = get_mod('SimpleSequencer')

local UiSettings = require('scripts/settings/ui/ui_settings')
local WeaponTemplates = require('scripts/settings/equipment/weapon_templates/weapon_templates')

local SPECIAL_DISPLAY_NAMES = {
    psyker_throwing_knives = 'loc_ability_psyker_blitz_throwing_knives',
    psyker_chain_lightning = 'loc_ability_psyker_chain_lightning',
}

local function _try_localize(key)
    if type(Localize) ~= 'function' then
        return nil
    end

    local ok, value = pcall(Localize, key)

    if not ok or type(value) ~= 'string' or value == '' or value == '<' .. key .. '>' then
        return nil
    end

    if string.find(value, '<unlocalized', 1, true) then
        return nil
    end

    return value
end

local function _weapon_display_name(name, family_name, family_data)
    local mark = _try_localize('loc_weapon_mark_' .. name)
    local pattern = _try_localize('loc_weapon_pattern_' .. name)

    if not pattern then
        pattern = _try_localize('loc_weapon_pattern_' .. string.gsub(name, '_m%d+$', '_m1'))
    end

    local family_key = family_data.display_name or 'loc_weapon_family_' .. family_name
    local family = _try_localize(family_key)

    if pattern and mark and family then
        return string.format('%s %s %s', pattern, mark, family)
    elseif pattern and mark then
        return string.format('%s %s', pattern, mark)
    elseif mark and family then
        return string.format('%s %s', mark, family)
    end

    return mark
end

local function _weapon_options(kind)
    local global_value = kind == 'MELEE' and 'global_melee' or 'global_ranged'
    local global_text = mod:localize(global_value)
    local options = { { text = global_text, value = global_value } }
    local seen = { [global_value] = true }

    for family_name, family_data in pairs(UiSettings.weapon_patterns or {}) do
        if string.sub(family_name, 1, 4) ~= 'bot_' then
            for _, mark in ipairs(family_data.marks or {}) do
                local name = mark.name
                local template = WeaponTemplates[name]
                local keywords = template and template.keywords or {}
                local matches = false

                for _, keyword in ipairs(keywords) do
                    if keyword == string.lower(kind) then
                        matches = true
                        break
                    end
                end

                if matches and not seen[name] then
                    options[#options + 1] = {
                        text = _weapon_display_name(name, family_name, family_data) or name,
                        value = name,
                    }
                    seen[name] = true
                end
            end
        end
    end

    if kind == 'RANGED' then
        for _, name in ipairs({ 'psyker_throwing_knives', 'psyker_chain_lightning' }) do
            if not seen[name] then
                options[#options + 1] = {
                    text = _try_localize(SPECIAL_DISPLAY_NAMES[name]) or name,
                    value = name,
                }
                seen[name] = true
            end
        end
    end

    table.sort(options, function(left, right)
        if left.value == global_value then
            return true
        elseif right.value == global_value then
            return false
        end

        return left.text < right.text
    end)
    options.localize = false

    return options
end

local function _clone_options(options)
    local result = {}

    for i = 1, #options do
        result[i] = { text = options[i].text, value = options[i].value }
    end

    result.localize = options.localize

    return result
end

local function _keybind(setting_id, function_name)
    return {
        setting_id = setting_id,
        type = 'keybind',
        default_value = {},
        keybind_trigger = 'pressed',
        keybind_type = 'function_call',
        function_name = function_name,
    }
end

local MELEE_OPTIONS = {
    { text = 'none', value = 'none' },
    { text = 'light_attack', value = 'light_attack' },
    { text = 'heavy_attack', value = 'heavy_attack' },
    { text = 'special_action', value = 'special_action' },
    { text = 'special_heavy', value = 'special_heavy' },
    { text = 'special_invert', value = 'special_invert' },
    { text = 'block', value = 'block' },
    { text = 'push', value = 'push' },
    { text = 'push_attack', value = 'push_attack' },
    { text = 'wield', value = 'wield' },
}

local CYCLE_OPTIONS = { { text = 'no_repeat', value = 'no_repeat' } }

for i = 1, 12 do
    CYCLE_OPTIONS[#CYCLE_OPTIONS + 1] = {
        text = 'sequence_step_' .. i,
        value = 'sequence_step_' .. i,
    }
end

local MELEE_PREFIX = 'melee_'
local RANGED_PREFIX = 'ranged_'

local melee_widgets = {
    {
        setting_id = MELEE_PREFIX .. 'weapon_selection',
        type = 'dropdown',
        default_value = 'global_melee',
        options = _weapon_options('MELEE'),
    },
    {
        setting_id = MELEE_PREFIX .. 'sequence_cycle_point',
        type = 'dropdown',
        default_value = 'sequence_step_1',
        options = CYCLE_OPTIONS,
    },
}

local step_names = {
    'one',
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
    'eight',
    'nine',
    'ten',
    'eleven',
    'twelve',
}

for i, name in ipairs(step_names) do
    melee_widgets[#melee_widgets + 1] = {
        setting_id = MELEE_PREFIX .. 'sequence_step_' .. name,
        type = 'dropdown',
        default_value = 'none',
        options = _clone_options(MELEE_OPTIONS),
        title = 'sequence_step_' .. i,
    }
end

local ranged_widgets = {
    {
        setting_id = RANGED_PREFIX .. 'weapon_selection',
        type = 'dropdown',
        default_value = 'global_ranged',
        options = _weapon_options('RANGED'),
    },
    {
        setting_id = RANGED_PREFIX .. 'automatic_fire_hip',
        type = 'dropdown',
        default_value = 'none',
        options = {
            { text = 'none', value = 'none' },
            { text = 'standard', value = 'standard' },
            { text = 'charged', value = 'charged' },
            { text = 'special', value = 'special' },
            { text = 'special_charged', value = 'special_charged' },
            { text = 'special_standard', value = 'special_standard' },
        },
    },
    {
        setting_id = RANGED_PREFIX .. 'automatic_fire_ads',
        type = 'dropdown',
        default_value = 'none',
        options = {
            { text = 'none', value = 'none' },
            { text = 'standard', value = 'standard' },
            { text = 'charged', value = 'charged' },
            { text = 'special', value = 'special' },
            { text = 'special_charged', value = 'special_charged' },
            { text = 'special_standard', value = 'special_standard' },
        },
    },
    {
        setting_id = RANGED_PREFIX .. 'auto_charge_threshold',
        type = 'numeric',
        default_value = 100,
        range = { 0, 100 },
        decimals_number = 0,
    },
    {
        setting_id = RANGED_PREFIX .. 'rate_of_fire_hip',
        type = 'numeric',
        default_value = 0,
        range = { 0, 800 },
        decimals_number = 0,
    },
    {
        setting_id = RANGED_PREFIX .. 'rate_of_fire_ads',
        type = 'numeric',
        default_value = 0,
        range = { 0, 800 },
        decimals_number = 0,
    },
}

return {
    name = mod:localize('mod_name'),
    description = mod:localize('mod_description'),
    is_togglable = true,
    options = {
        widgets = {
            {
                setting_id = 'general_settings',
                type = 'group',
                sub_widgets = {
                    {
                        setting_id = 'hud_enabled',
                        type = 'checkbox',
                        default_value = true,
                    },
                    {
                        setting_id = 'reset_on_interrupt',
                        type = 'checkbox',
                        default_value = true,
                    },
                    _keybind('select_mode_previous', 'select_mode_previous'),
                    _keybind('select_mode_next', 'select_mode_next'),
                    _keybind('select_mode_toggle', 'select_mode_toggle'),
                },
            },
            {
                setting_id = 'mode_keybinds',
                type = 'group',
                sub_widgets = {
                    {
                        setting_id = 'editing_mode',
                        type = 'dropdown',
                        default_value = 'mode_1',
                        options = {
                            { text = 'mode_1', value = 'mode_1' },
                            { text = 'mode_2', value = 'mode_2' },
                            { text = 'mode_3', value = 'mode_3' },
                            { text = 'mode_4', value = 'mode_4' },
                        },
                    },
                    _keybind('mode_1_select', 'select_mode_one'),
                    _keybind('mode_2_select', 'select_mode_two'),
                    _keybind('mode_3_select', 'select_mode_three'),
                    _keybind('mode_4_select', 'select_mode_four'),
                },
            },
            {
                setting_id = 'melee_settings',
                type = 'group',
                sub_widgets = melee_widgets,
            },
            {
                setting_id = 'ranged_settings',
                type = 'group',
                sub_widgets = ranged_widgets,
            },
        },
    },
}
