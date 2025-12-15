local mod = get_mod('CombatStats')

local UIWidget = mod:original_require('scripts/managers/ui/ui_widget')
local UIWorkspaceSettings = mod:original_require('scripts/settings/ui/ui_workspace_settings')
local UIFontSettings = mod:original_require('scripts/managers/ui/ui_font_settings')
local ScrollbarPassTemplates = mod:original_require('scripts/ui/pass_templates/scrollbar_pass_templates')
local TextInputPassTemplates = mod:original_require('scripts/ui/pass_templates/text_input_pass_templates')

-- Dynamic sizing based on screen
local screen_width = UIWorkspaceSettings.screen.size[1] -- 1920
local screen_height = UIWorkspaceSettings.screen.size[2] -- 1080

local left_padding = 100
local right_padding = 100
local top_padding = 150
local bottom_padding = 50
local gap = 20
local scrollbar_width = 7
local content_padding = 10
local search_height = 50
local search_gap = 10

local grid_width = 500
local grid_height = screen_height - top_padding - bottom_padding - search_height - search_gap
local detail_height = grid_height + search_height + search_gap -- Match the left side total height
local detail_width = screen_width - grid_width - left_padding - right_padding - gap

local scenegraph_definition = {
    screen = UIWorkspaceSettings.screen,
    combat_stats_search = {
        vertical_alignment = 'top',
        parent = 'screen',
        horizontal_alignment = 'left',
        size = { grid_width, search_height },
        position = { left_padding, top_padding, 1 },
    },
    combat_stats_list_background = {
        vertical_alignment = 'top',
        parent = 'screen',
        horizontal_alignment = 'left',
        size = { grid_width, grid_height },
        position = { left_padding, top_padding + search_height + search_gap, 1 },
    },
    combat_stats_list_pivot = {
        vertical_alignment = 'top',
        parent = 'combat_stats_list_background',
        horizontal_alignment = 'left',
        size = { 0, 0 },
        position = { content_padding, content_padding, 1 },
    },
    combat_stats_list_scrollbar = {
        vertical_alignment = 'center',
        parent = 'combat_stats_list_background',
        horizontal_alignment = 'right',
        size = { scrollbar_width, grid_height - content_padding * 2 },
        position = { -content_padding, 0, 10 },
    },
    combat_stats_list_interaction = {
        vertical_alignment = 'top',
        parent = 'combat_stats_list_background',
        horizontal_alignment = 'left',
        size = { grid_width, grid_height },
        position = { 0, 0, 10 },
    },
    combat_stats_detail_background = {
        vertical_alignment = 'top',
        parent = 'screen',
        horizontal_alignment = 'left',
        size = { detail_width, detail_height },
        position = { left_padding + grid_width + gap, top_padding, 1 },
    },
    combat_stats_detail_content = {
        vertical_alignment = 'top',
        parent = 'combat_stats_detail_background',
        horizontal_alignment = 'left',
        size = { detail_width - content_padding * 4 - scrollbar_width, detail_height - content_padding * 4 },
        position = { content_padding * 2, content_padding * 2, 1 },
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
        size = { scrollbar_width, detail_height - content_padding * 4 },
        position = { -content_padding, 0, 10 },
    },
    combat_stats_detail_interaction = {
        vertical_alignment = 'top',
        parent = 'combat_stats_detail_content',
        horizontal_alignment = 'left',
        size = { detail_width - content_padding * 4 - scrollbar_width, detail_height - content_padding * 4 },
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
            value = mod:localize('mod_name'),
            style = table.clone(UIFontSettings.header_1),
        },
    }, 'combat_stats_title_text'),
    combat_stats_search = UIWidget.create_definition(
        TextInputPassTemplates.terminal_input_field,
        'combat_stats_search',
        { grid_width, search_height }
    ),
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
    {
        input_action = 'hotkey_menu_special_2',
        on_pressed_callback = 'cb_on_history_pressed',
        display_name = 'loc_combat_stats_view_history',
        alignment = 'right_alignment',
        visibility_function = function(parent)
            return not parent._viewing_history and not parent._viewing_history_entry
        end,
    },
    {
        input_action = 'hotkey_menu_special_2',
        on_pressed_callback = 'cb_on_back_to_current_pressed',
        display_name = 'loc_combat_stats_back_to_history',
        alignment = 'right_alignment',
        visibility_function = function(parent)
            return parent._viewing_history_entry
        end,
    },
    {
        input_action = 'hotkey_menu_special_2',
        on_pressed_callback = 'cb_on_back_to_current_pressed',
        display_name = 'loc_combat_stats_back_to_current',
        alignment = 'right_alignment',
        visibility_function = function(parent)
            return parent._viewing_history
        end,
    },
    {
        input_action = 'hotkey_menu_special_1',
        on_pressed_callback = 'cb_on_reset_pressed',
        display_name = 'loc_combat_stats_reset_stats',
        alignment = 'right_alignment',
        visibility_function = function(parent)
            return not parent._viewing_history and not parent._viewing_history_entry
        end,
    },
    {
        input_action = 'hotkey_menu_special_1',
        on_pressed_callback = 'cb_on_delete_entry_pressed',
        display_name = 'loc_combat_stats_delete_entry',
        alignment = 'right_alignment',
        visibility_function = function(parent)
            return parent._viewing_history_entry
        end,
    },
}

return {
    widget_definitions = widget_definitions,
    scenegraph_definition = scenegraph_definition,
    legend_inputs = legend_inputs,
}
