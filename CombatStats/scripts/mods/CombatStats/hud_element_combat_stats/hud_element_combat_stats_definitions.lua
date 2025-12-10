local mod = get_mod('CombatStats')

local UIWorkspaceSettings = require('scripts/settings/ui/ui_workspace_settings')
local UIFontSettings = require('scripts/managers/ui/ui_font_settings')
local UIWidget = require('scripts/managers/ui/ui_widget')
local UIHudSettings = require('scripts/settings/ui/ui_hud_settings')

local scenegraph_definition = {
    screen = UIWorkspaceSettings.screen,
    session_stats = {
        parent = 'screen',
        vertical_alignment = 'top',
        horizontal_alignment = 'left',
        size = { 400, 200 },
        position = { 20, 100, 55 },
    },
}

local widget_definitions = {
    session_stats = UIWidget.create_definition({
        {
            pass_type = 'text',
            style_id = 'duration_text',
            value_id = 'duration_text',
            value = 'Time: 0s',
            style = {
                font_size = 18,
                text_vertical_alignment = 'top',
                text_horizontal_alignment = 'left',
                font_type = 'proxima_nova_bold',
                text_color = UIHudSettings.color_tint_main_1,
                offset = { 0, 0, 2 },
            },
        },
        {
            pass_type = 'text',
            style_id = 'kills_text',
            value_id = 'kills_text',
            value = 'Kills: 0',
            style = {
                font_size = 18,
                text_vertical_alignment = 'top',
                text_horizontal_alignment = 'left',
                font_type = 'proxima_nova_bold',
                text_color = UIHudSettings.color_tint_main_1,
                offset = { 0, 25, 2 },
            },
        },
        {
            pass_type = 'text',
            style_id = 'dps_text',
            value_id = 'dps_text',
            value = 'DPS: 0',
            style = {
                font_size = 20,
                text_vertical_alignment = 'top',
                text_horizontal_alignment = 'left',
                font_type = 'proxima_nova_bold',
                text_color = Color.ui_hud_green_light(255, true),
                offset = { 0, 50, 2 },
            },
        },
        {
            pass_type = 'text',
            style_id = 'damage_text',
            value_id = 'damage_text',
            value = 'Damage: 0',
            style = {
                font_size = 16,
                text_vertical_alignment = 'top',
                text_horizontal_alignment = 'left',
                font_type = 'proxima_nova_bold',
                text_color = UIHudSettings.color_tint_main_2,
                offset = { 0, 75, 2 },
            },
        },
        {
            pass_type = 'text',
            style_id = 'hits_text',
            value_id = 'hits_text',
            value = 'Hits: 0',
            style = {
                font_size = 16,
                text_vertical_alignment = 'top',
                text_horizontal_alignment = 'left',
                font_type = 'proxima_nova_bold',
                text_color = UIHudSettings.color_tint_main_2,
                offset = { 0, 95, 2 },
            },
        },
        {
            pass_type = 'text',
            style_id = 'breakdown_text',
            value_id = 'breakdown_text',
            value = '',
            style = {
                font_size = 14,
                text_vertical_alignment = 'top',
                text_horizontal_alignment = 'left',
                font_type = 'proxima_nova_bold',
                text_color = UIHudSettings.color_tint_main_2,
                offset = { 0, 115, 2 },
            },
        },
    }, 'session_stats'),
}

return {
    scenegraph_definition = scenegraph_definition,
    widget_definitions = widget_definitions,
}
