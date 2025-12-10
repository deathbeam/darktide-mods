local mod = get_mod('CombatStats')

local UIWidget = mod:original_require('scripts/managers/ui/ui_widget')
local UIWorkspaceSettings = mod:original_require('scripts/settings/ui/ui_workspace_settings')
local UIFontSettings = mod:original_require('scripts/managers/ui/ui_font_settings')
local ScrollbarPassTemplates = mod:original_require('scripts/ui/pass_templates/scrollbar_pass_templates')

-- Dynamic sizing based on screen
local screen_width = UIWorkspaceSettings.screen.size[1] -- 1920
local screen_height = UIWorkspaceSettings.screen.size[2] -- 1080

local padding = 100
local vertical_padding = 150
local gap = 20
local scrollbar_width = 7

local grid_width = 500
local grid_height = screen_height - (vertical_padding * 2) -- 1080 - 300 = 780
local detail_width = screen_width - grid_width - (padding * 2) - gap -- 1920 - 500 - 200 - 20 = 1200

local scenegraph_definition = {
    screen = UIWorkspaceSettings.screen,
    combat_stats_list_background = {
        vertical_alignment = 'top',
        parent = 'screen',
        horizontal_alignment = 'left',
        size = { grid_width, grid_height },
        position = { 100, 150, 1 },
    },
    combat_stats_list_pivot = {
        vertical_alignment = 'top',
        parent = 'combat_stats_list_background',
        horizontal_alignment = 'left',
        size = { 0, 0 },
        position = { 10, 10, 1 },
    },
    combat_stats_list_scrollbar = {
        vertical_alignment = 'center',
        parent = 'combat_stats_list_background',
        horizontal_alignment = 'right',
        size = { scrollbar_width, grid_height - 20 },
        position = { -10, 0, 10 },
    },
    combat_stats_detail_background = {
        vertical_alignment = 'top',
        parent = 'screen',
        horizontal_alignment = 'left',
        size = { detail_width, grid_height },
        position = { grid_width + 120, 150, 1 },
    },
    combat_stats_detail_content = {
        vertical_alignment = 'top',
        parent = 'combat_stats_detail_background',
        horizontal_alignment = 'left',
        size = { detail_width - 40 - scrollbar_width, grid_height - 40 },
        position = { 20, 20, 1 },
    },
    combat_stats_detail_pivot = {
        vertical_alignment = 'top',
        parent = 'combat_stats_detail_content',
        horizontal_alignment = 'left',
        size = { 0, 0 },
        position = { 0, 0, 1 },
    },
    combat_stats_detail_scrollbar = {
        vertical_alignment = 'center',
        parent = 'combat_stats_detail_background',
        horizontal_alignment = 'right',
        size = { scrollbar_width, grid_height - 40 },
        position = { -10, 0, 10 },
    },
    combat_stats_detail_interaction = {
        vertical_alignment = 'top',
        parent = 'combat_stats_detail_content',
        horizontal_alignment = 'left',
        size = { detail_width - 40 - scrollbar_width, grid_height - 40 },
        position = { 0, 0, 10 },
    },
    combat_stats_list_interaction = {
        vertical_alignment = 'top',
        parent = 'combat_stats_list_background',
        horizontal_alignment = 'left',
        size = { grid_width, grid_height },
        position = { 0, 0, 10 },
    },
    combat_stats_title_text = {
        vertical_alignment = 'top',
        parent = 'screen',
        horizontal_alignment = 'left',
        size = { 1200, 50 },
        position = { 100, 80, 1 },
    },
}

local icon_size = { 40, 40 }

local widget_definitions = {
    combat_stats_title_text = UIWidget.create_definition({
        {
            value_id = 'text',
            style_id = 'text',
            pass_type = 'text',
            value = mod:localize('combat_stats_view_title'),
            style = table.clone(UIFontSettings.header_1),
        },
    }, 'combat_stats_title_text'),
    combat_stats_list_background = UIWidget.create_definition({
        {
            pass_type = 'rect',
            style = {
                color = { 200, 0, 0, 0 },
            },
        },
    }, 'combat_stats_list_background'),
    combat_stats_list_scrollbar = UIWidget.create_definition(
        ScrollbarPassTemplates.default_scrollbar,
        'combat_stats_list_scrollbar'
    ),
    combat_stats_detail_scrollbar = UIWidget.create_definition(
        ScrollbarPassTemplates.default_scrollbar,
        'combat_stats_detail_scrollbar'
    ),
    combat_stats_detail_background = UIWidget.create_definition({
        {
            pass_type = 'rect',
            style = {
                color = { 200, 0, 0, 0 },
            },
        },
    }, 'combat_stats_detail_background'),
    combat_stats_detail_interaction = UIWidget.create_definition({
        {
            pass_type = 'hotspot',
            content_id = 'hotspot',
        },
    }, 'combat_stats_detail_interaction'),
    combat_stats_list_interaction = UIWidget.create_definition({
        {
            pass_type = 'hotspot',
            content_id = 'hotspot',
        },
    }, 'combat_stats_list_interaction'),
}
local legend_inputs = {
    {
        input_action = 'back',
        on_pressed_callback = 'cb_on_close_pressed',
        display_name = 'loc_settings_menu_close_menu',
        alignment = 'left_alignment',
    },
}

return {
    widget_definitions = widget_definitions,
    scenegraph_definition = scenegraph_definition,
    legend_inputs = legend_inputs,
}
