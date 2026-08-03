local mod = get_mod('SimpleSequencer')

local UiSettings = require('scripts/settings/ui/ui_settings')
local WeaponTemplates = require('scripts/settings/equipment/weapon_templates/weapon_templates')
local ProfileSchema = mod:io_dofile('SimpleSequencer/scripts/mods/SimpleSequencer/modules/ProfileSchema')

local SPECIAL_DISPLAY_NAMES = {
    psyker_throwing_knives = 'loc_ability_psyker_blitz_throwing_knives',
    psyker_chain_lightning = 'loc_ability_psyker_chain_lightning',
}

local ICON_OPTIONS = {
    {
        text = 'Skull: Uprising',
        value = 'content/ui/materials/icons/difficulty/flat/difficulty_skull_uprising',
        icon = 'content/ui/materials/icons/difficulty/flat/difficulty_skull_uprising',
    },
    {
        text = 'Skull: Malice',
        value = 'content/ui/materials/icons/difficulty/flat/difficulty_skull_malice',
        icon = 'content/ui/materials/icons/difficulty/flat/difficulty_skull_malice',
    },
    {
        text = 'Skull: Heresy',
        value = 'content/ui/materials/icons/difficulty/flat/difficulty_skull_heresy',
        icon = 'content/ui/materials/icons/difficulty/flat/difficulty_skull_heresy',
    },
    {
        text = 'Skull: Damnation',
        value = 'content/ui/materials/icons/difficulty/flat/difficulty_skull_damnation',
        icon = 'content/ui/materials/icons/difficulty/flat/difficulty_skull_damnation',
    },
    {
        text = 'Skull: Auric',
        value = 'content/ui/materials/icons/difficulty/flat/difficulty_skull_auric',
        icon = 'content/ui/materials/icons/difficulty/flat/difficulty_skull_auric',
    },
    {
        text = 'Servo Skull',
        value = 'content/ui/materials/backgrounds/scanner/scanner_decoration_skull',
        icon = 'content/ui/materials/backgrounds/scanner/scanner_decoration_skull',
    },
    {
        text = 'Preset 01',
        value = 'content/ui/materials/icons/presets/preset_01',
        icon = 'content/ui/materials/icons/presets/preset_01',
    },
    {
        text = 'Preset 05',
        value = 'content/ui/materials/icons/presets/preset_05',
        icon = 'content/ui/materials/icons/presets/preset_05',
    },
    {
        text = 'Preset 10',
        value = 'content/ui/materials/icons/presets/preset_10',
        icon = 'content/ui/materials/icons/presets/preset_10',
    },
    {
        text = 'Preset 13',
        value = 'content/ui/materials/icons/presets/preset_13',
        icon = 'content/ui/materials/icons/presets/preset_13',
    },
    {
        text = 'Preset 17',
        value = 'content/ui/materials/icons/presets/preset_17',
        icon = 'content/ui/materials/icons/presets/preset_17',
    },
    {
        text = 'Preset 20',
        value = 'content/ui/materials/icons/presets/preset_20',
        icon = 'content/ui/materials/icons/presets/preset_20',
    },
    {
        text = 'Ability',
        value = 'content/ui/materials/icons/abilities/default',
        icon = 'content/ui/materials/icons/abilities/default',
    },
    {
        text = 'Interaction',
        value = 'content/ui/materials/hud/interactions/icons/default',
        icon = 'content/ui/materials/hud/interactions/icons/default',
    },
    {
        text = 'Loot',
        value = 'content/ui/materials/icons/generic/loot',
        icon = 'content/ui/materials/icons/generic/loot',
    },
    {
        text = 'Attention',
        value = 'content/ui/materials/hud/interactions/icons/attention',
        icon = 'content/ui/materials/hud/interactions/icons/attention',
    },
    {
        text = 'Enemy',
        value = 'content/ui/materials/hud/interactions/icons/enemy',
        icon = 'content/ui/materials/hud/interactions/icons/enemy',
    },
}

ICON_OPTIONS.localize = false

local function _localized(key)
    if type(Localize) ~= 'function' then
        return nil
    end

    local success, value = pcall(Localize, key)

    if not success or type(value) ~= 'string' or value == '' then
        return nil
    end

    if value == '<' .. key .. '>' or string.find(value, '<unlocalized', 1, true) then
        return nil
    end

    return value
end

local function _weapon_label(name, family_name, family_data)
    local mark = _localized('loc_weapon_mark_' .. name)
    local pattern = _localized('loc_weapon_pattern_' .. name)
    local family_key = family_data and family_data.display_name or 'loc_weapon_family_' .. family_name
    local family = _localized(family_key)

    if not pattern then
        pattern = _localized('loc_weapon_pattern_' .. string.gsub(name, '_m%d+$', '_m1'))
    end

    if pattern and mark then
        local parts = { pattern, mark }

        if family then
            parts[#parts + 1] = family
        end

        return table.concat(parts, ' ')
    elseif mark and family then
        return table.concat({ mark, family }, ' ')
    end

    return mark
end

local function _weapon_options(kind)
    local global_value = kind == 'MELEE' and 'global_melee' or 'global_ranged'
    local options = {
        { text = mod:localize(global_value), value = global_value },
    }
    local seen = { [global_value] = true }
    local expected_kind = string.lower(kind)

    for family_name, family_data in pairs(UiSettings.weapon_patterns or {}) do
        if string.sub(family_name, 1, 4) ~= 'bot_' then
            for _, mark in ipairs(family_data.marks or {}) do
                local name = mark.name
                local template = name and WeaponTemplates[name]
                local keywords = template and template.keywords
                local matches = false

                if keywords then
                    for i = 1, #keywords do
                        if keywords[i] == expected_kind then
                            matches = true
                            break
                        end
                    end
                end

                if matches and name and not seen[name] then
                    options[#options + 1] = {
                        text = _weapon_label(name, family_name, family_data) or name,
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
                    text = _localized(SPECIAL_DISPLAY_NAMES[name]) or name,
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
        result[i] = {
            text = options[i].text,
            value = options[i].value,
            icon = options[i].icon,
            icon_colour = options[i].icon_colour,
        }
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

local mode_display_widgets = {
    {
        setting_id = 'mode_display_name',
        type = 'text_input',
        default_value = {},
        -- DMF currently validates text inputs through its keybind path.
        keybind_trigger = 'pressed',
        keybind_type = 'function_call',
        function_name = '_simple_sequencer_text_input',
    },
    {
        setting_id = 'mode_display_icon',
        type = 'dropdown',
        default_value = ICON_OPTIONS[1].value,
        options = _clone_options(ICON_OPTIONS),
    },
    {
        setting_id = 'mode_display_color_r',
        type = 'numeric',
        default_value = 255,
        range = { 0, 255 },
        decimals_number = 0,
    },
    {
        setting_id = 'mode_display_color_g',
        type = 'numeric',
        default_value = 190,
        range = { 0, 255 },
        decimals_number = 0,
    },
    {
        setting_id = 'mode_display_color_b',
        type = 'numeric',
        default_value = 80,
        range = { 0, 255 },
        decimals_number = 0,
    },
}

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

local RANGED_FIRE_OPTIONS = {
    { text = 'none', value = 'none' },
    { text = 'standard', value = 'standard' },
    { text = 'charged', value = 'charged' },
    { text = 'special', value = 'special' },
    { text = 'special_charged', value = 'special_charged' },
    { text = 'special_standard', value = 'special_standard' },
}

local CYCLE_OPTIONS = { { text = 'no_repeat', value = 'no_repeat' } }

for i = 1, ProfileSchema.sequence_step_count do
    CYCLE_OPTIONS[#CYCLE_OPTIONS + 1] = {
        text = ProfileSchema.sequence_step_prefix .. i,
        value = ProfileSchema.sequence_step_prefix .. i,
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
        setting_id = MELEE_PREFIX .. 'use_current_weapon',
        type = 'checkbox',
        default_value = false,
    },
    {
        setting_id = MELEE_PREFIX .. 'sequence_cycle_point',
        type = 'dropdown',
        default_value = ProfileSchema.defaults.MELEE.sequence_cycle_point,
        options = CYCLE_OPTIONS,
    },
}

for i = 1, ProfileSchema.sequence_step_count do
    melee_widgets[#melee_widgets + 1] = {
        setting_id = MELEE_PREFIX .. ProfileSchema.sequence_step_prefix .. i,
        type = 'dropdown',
        default_value = ProfileSchema.defaults.MELEE[ProfileSchema.sequence_step_prefix .. i],
        options = _clone_options(MELEE_OPTIONS),
        title = ProfileSchema.sequence_step_prefix .. i,
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
        setting_id = RANGED_PREFIX .. 'use_current_weapon',
        type = 'checkbox',
        default_value = false,
    },
    {
        setting_id = RANGED_PREFIX .. 'automatic_fire_hip',
        type = 'dropdown',
        default_value = ProfileSchema.defaults.RANGED.automatic_fire_hip,
        options = _clone_options(RANGED_FIRE_OPTIONS),
    },
    {
        setting_id = RANGED_PREFIX .. 'automatic_fire_ads',
        type = 'dropdown',
        default_value = ProfileSchema.defaults.RANGED.automatic_fire_ads,
        options = _clone_options(RANGED_FIRE_OPTIONS),
    },
    {
        setting_id = RANGED_PREFIX .. 'auto_charge_threshold',
        type = 'numeric',
        default_value = ProfileSchema.defaults.RANGED.auto_charge_threshold,
        range = { 0, 100 },
        decimals_number = 0,
    },
    {
        setting_id = RANGED_PREFIX .. 'rate_of_fire_hip',
        type = 'numeric',
        default_value = ProfileSchema.defaults.RANGED.rate_of_fire_hip,
        range = { 0, 800 },
        decimals_number = 0,
    },
    {
        setting_id = RANGED_PREFIX .. 'rate_of_fire_ads',
        type = 'numeric',
        default_value = ProfileSchema.defaults.RANGED.rate_of_fire_ads,
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
                tab = mod:localize('general_settings'),
                sub_widgets = {
                    {
                        setting_id = 'hud_display_mode',
                        type = 'dropdown',
                        default_value = 'icon_and_name',
                        options = {
                            { text = 'hud_display_disabled', value = 'disabled' },
                            { text = 'hud_display_icon', value = 'icon' },
                            { text = 'hud_display_name', value = 'name' },
                            { text = 'hud_display_icon_and_name', value = 'icon_and_name' },
                        },
                    },
                    {
                        setting_id = 'reset_on_interrupt',
                        type = 'checkbox',
                        default_value = true,
                    },
                    _keybind('select_mode_previous', 'select_mode_previous'),
                    _keybind('select_mode_next', 'select_mode_next'),
                    _keybind('select_mode_toggle', 'select_mode_toggle'),
                    {
                        setting_id = 'hud_position_x',
                        type = 'numeric',
                        default_value = 0,
                        range = { -900, 900 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = 'hud_position_y',
                        type = 'numeric',
                        default_value = 70,
                        range = { -450, 600 },
                        decimals_number = 0,
                    },
                },
            },
            {
                setting_id = 'mode_keybinds',
                type = 'group',
                tab = mod:localize('mode_keybinds'),
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
                    _keybind('mode_1_select', 'select_mode_1'),
                    _keybind('mode_2_select', 'select_mode_2'),
                    _keybind('mode_3_select', 'select_mode_3'),
                    _keybind('mode_4_select', 'select_mode_4'),
                    {
                        setting_id = 'mode_display_settings',
                        type = 'group',
                        sub_widgets = mode_display_widgets,
                    },
                },
            },
            {
                setting_id = 'melee_settings',
                type = 'group',
                tab = mod:localize('melee_settings'),
                sub_widgets = melee_widgets,
            },
            {
                setting_id = 'ranged_settings',
                type = 'group',
                tab = mod:localize('ranged_settings'),
                sub_widgets = ranged_widgets,
            },
        },
    },
}
