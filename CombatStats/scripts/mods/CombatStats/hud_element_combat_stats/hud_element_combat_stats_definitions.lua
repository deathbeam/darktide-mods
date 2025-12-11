local mod = get_mod('CombatStats')

local UIWorkspaceSettings = require('scripts/settings/ui/ui_workspace_settings')
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
            style = {
                font_size = 16,
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
            style = {
                font_size = 16,
                text_vertical_alignment = 'top',
                text_horizontal_alignment = 'left',
                font_type = 'proxima_nova_bold',
                text_color = UIHudSettings.color_tint_main_1,
                offset = { 0, 22, 2 },
            },
        },
        {
            pass_type = 'text',
            style_id = 'dps_text',
            value_id = 'dps_text',
            style = {
                font_size = 22,
                text_vertical_alignment = 'top',
                text_horizontal_alignment = 'left',
                font_type = 'proxima_nova_bold',
                text_color = Color.ui_hud_green_light(255, true),
                offset = { 0, 46, 2 },
            },
        },
        {
            pass_type = 'text',
            style_id = 'damage_text',
            value_id = 'damage_text',
            style = {
                font_size = 15,
                text_vertical_alignment = 'top',
                text_horizontal_alignment = 'left',
                font_type = 'proxima_nova_bold',
                text_color = UIHudSettings.color_tint_main_2,
                offset = { 0, 73, 2 },
            },
        },
        {
            pass_type = 'texture',
            style_id = 'damage_type_1_icon',
            value_id = 'damage_type_1_icon',
            style = {
                size = { 18, 18 },
                offset = { 0, 95, 3 },
                color = Color.white(255, true),
            },
            visibility_function = function(content, style)
                return content.damage_type_1_icon ~= nil
            end,
        },
        {
            pass_type = 'text',
            style_id = 'damage_type_1_text',
            value_id = 'damage_type_1_text',
            style = {
                font_size = 14,
                text_vertical_alignment = 'top',
                text_horizontal_alignment = 'left',
                font_type = 'proxima_nova_bold',
                text_color = UIHudSettings.color_tint_main_2,
                offset = { 22, 95, 2 },
            },
            visibility_function = function(content, style)
                return content.damage_type_1_text ~= nil and content.damage_type_1_text ~= ''
            end,
        },
        {
            pass_type = 'texture',
            style_id = 'damage_type_2_icon',
            value_id = 'damage_type_2_icon',
            style = {
                size = { 18, 18 },
                offset = { 110, 95, 3 },
                color = Color.white(255, true),
            },
            visibility_function = function(content, style)
                return content.damage_type_2_icon ~= nil
            end,
        },
        {
            pass_type = 'text',
            style_id = 'damage_type_2_text',
            value_id = 'damage_type_2_text',
            style = {
                font_size = 14,
                text_vertical_alignment = 'top',
                text_horizontal_alignment = 'left',
                font_type = 'proxima_nova_bold',
                text_color = UIHudSettings.color_tint_main_2,
                offset = { 132, 95, 2 },
            },
            visibility_function = function(content, style)
                return content.damage_type_2_text ~= nil and content.damage_type_2_text ~= ''
            end,
        },
        {
            pass_type = 'texture',
            style_id = 'damage_type_3_icon',
            value_id = 'damage_type_3_icon',
            style = {
                size = { 18, 18 },
                offset = { 220, 95, 3 },
                color = Color.white(255, true),
            },
            visibility_function = function(content, style)
                return content.damage_type_3_icon ~= nil
            end,
        },
        {
            pass_type = 'text',
            style_id = 'damage_type_3_text',
            value_id = 'damage_type_3_text',
            style = {
                font_size = 14,
                text_vertical_alignment = 'top',
                text_horizontal_alignment = 'left',
                font_type = 'proxima_nova_bold',
                text_color = UIHudSettings.color_tint_main_2,
                offset = { 242, 95, 2 },
            },
            visibility_function = function(content, style)
                return content.damage_type_3_text ~= nil and content.damage_type_3_text ~= ''
            end,
        },
        {
            pass_type = 'texture',
            style_id = 'damage_type_4_icon',
            value_id = 'damage_type_4_icon',
            style = {
                size = { 18, 18 },
                offset = { 305, 95, 3 },
                color = Color.white(255, true),
            },
            visibility_function = function(content, style)
                return content.damage_type_4_icon ~= nil
            end,
        },
        {
            pass_type = 'text',
            style_id = 'damage_type_4_text',
            value_id = 'damage_type_4_text',
            style = {
                font_size = 14,
                text_vertical_alignment = 'top',
                text_horizontal_alignment = 'left',
                font_type = 'proxima_nova_bold',
                text_color = UIHudSettings.color_tint_main_2,
                offset = { 327, 95, 2 },
            },
            visibility_function = function(content, style)
                return content.damage_type_4_text ~= nil and content.damage_type_4_text ~= ''
            end,
        },
        {
            pass_type = 'texture',
            style_id = 'buff_type_1_icon',
            value_id = 'buff_type_1_icon',
            style = {
                size = { 18, 18 },
                offset = { 0, 118, 3 },
                color = Color.white(255, true),
            },
            visibility_function = function(content, style)
                return content.buff_type_1_icon ~= nil
            end,
        },
        {
            pass_type = 'text',
            style_id = 'buff_type_1_text',
            value_id = 'buff_type_1_text',
            style = {
                font_size = 14,
                text_vertical_alignment = 'top',
                text_horizontal_alignment = 'left',
                font_type = 'proxima_nova_bold',
                text_color = UIHudSettings.color_tint_main_2,
                offset = { 22, 118, 2 },
            },
            visibility_function = function(content, style)
                return content.buff_type_1_text ~= nil and content.buff_type_1_text ~= ''
            end,
        },
        {
            pass_type = 'texture',
            style_id = 'buff_type_2_icon',
            value_id = 'buff_type_2_icon',
            style = {
                size = { 18, 18 },
                offset = { 62, 118, 3 },
                color = Color.white(255, true),
            },
            visibility_function = function(content, style)
                return content.buff_type_2_icon ~= nil
            end,
        },
        {
            pass_type = 'text',
            style_id = 'buff_type_2_text',
            value_id = 'buff_type_2_text',
            style = {
                font_size = 14,
                text_vertical_alignment = 'top',
                text_horizontal_alignment = 'left',
                font_type = 'proxima_nova_bold',
                text_color = UIHudSettings.color_tint_main_2,
                offset = { 84, 118, 2 },
            },
            visibility_function = function(content, style)
                return content.buff_type_2_text ~= nil and content.buff_type_2_text ~= ''
            end,
        },
        {
            pass_type = 'texture',
            style_id = 'buff_type_3_icon',
            value_id = 'buff_type_3_icon',
            style = {
                size = { 18, 18 },
                offset = { 124, 118, 3 },
                color = Color.white(255, true),
            },
            visibility_function = function(content, style)
                return content.buff_type_3_icon ~= nil
            end,
        },
        {
            pass_type = 'text',
            style_id = 'buff_type_3_text',
            value_id = 'buff_type_3_text',
            style = {
                font_size = 14,
                text_vertical_alignment = 'top',
                text_horizontal_alignment = 'left',
                font_type = 'proxima_nova_bold',
                text_color = UIHudSettings.color_tint_main_2,
                offset = { 146, 118, 2 },
            },
            visibility_function = function(content, style)
                return content.buff_type_3_text ~= nil and content.buff_type_3_text ~= ''
            end,
        },
    }, 'session_stats'),
}

return {
    scenegraph_definition = scenegraph_definition,
    widget_definitions = widget_definitions,
}
