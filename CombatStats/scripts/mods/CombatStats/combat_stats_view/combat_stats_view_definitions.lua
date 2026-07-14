local mod = get_mod('CombatStats')

local UIWidget = mod:original_require('scripts/managers/ui/ui_widget')
local UIWorkspaceSettings = mod:original_require('scripts/settings/ui/ui_workspace_settings')
local UIFontSettings = mod:original_require('scripts/managers/ui/ui_font_settings')
local TextInputPassTemplates = mod:original_require('scripts/ui/pass_templates/text_input_pass_templates')

local screen_width = UIWorkspaceSettings.screen.size[1]
local screen_height = UIWorkspaceSettings.screen.size[2]

local left_padding = 100
local right_padding = 100
local top_padding = 150
local bottom_padding = 50
local gap = 20
local scrollbar_width = 7
local search_height = 50
local search_gap = 10

local grid_width = 500
local grid_height = screen_height - top_padding - bottom_padding - search_height - search_gap
local detail_height = grid_height + search_height + search_gap
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
    combat_stats_list_content = {
        vertical_alignment = 'top',
        parent = 'combat_stats_list_background',
        horizontal_alignment = 'left',
        size = { grid_width, grid_height },
        position = { 0, 0, 1 },
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
        size = { detail_width, detail_height },
        position = { 0, 0, 1 },
    },
    combat_stats_title_text = {
        vertical_alignment = 'top',
        parent = 'screen',
        horizontal_alignment = 'left',
        size = { 1200, 50 },
        position = { 100, 80, 1 },
    },
}

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
    combat_stats_detail_background = UIWidget.create_definition({
        {
            pass_type = 'rect',
            style = {
                color = { 200, 0, 0, 0 },
            },
        },
    }, 'combat_stats_detail_background'),
}

local fade_margin = 16

local list_grid_width = grid_width
local list_grid_height = grid_height - 13
local list_grid_settings = {
    grid_id = 'list_grid',
    scrollbar_width = scrollbar_width,
    scrollbar_horizontal_offset = -scrollbar_width,
    use_is_focused_for_navigation = false,
    use_select_on_focused = false,
    use_terminal_background = false,
    hide_dividers = true,
    hide_background = true,
    using_custom_gamepad_navigation = false,
    enable_gamepad_scrolling = true,
    widget_icon_load_margin = 0,
    top_padding = 0,
    edge_padding = fade_margin,
    grid_spacing = { 0, 2 },
    grid_size = { list_grid_width - fade_margin, list_grid_height },
    mask_size = { list_grid_width, list_grid_height },
    title_height = 0,
}

local detail_grid_width = detail_width
local detail_grid_height = detail_height - 13
local detail_grid_settings = {
    grid_id = 'detail_grid',
    scrollbar_width = scrollbar_width,
    scrollbar_horizontal_offset = -scrollbar_width,
    use_is_focused_for_navigation = false,
    use_select_on_focused = false,
    use_terminal_background = false,
    hide_dividers = true,
    hide_background = true,
    using_custom_gamepad_navigation = false,
    enable_gamepad_scrolling = true,
    widget_icon_load_margin = 0,
    top_padding = 0,
    edge_padding = fade_margin,
    grid_spacing = { 0, 2 },
    grid_size = { detail_grid_width - fade_margin, detail_grid_height },
    mask_size = { detail_grid_width, detail_grid_height },
    title_height = 0,
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
            return parent._viewing_history_entry and not parent._history_entry_loading
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
            return parent._viewing_history_entry and not parent._history_entry_loading
        end,
    },
}

return {
    widget_definitions = widget_definitions,
    scenegraph_definition = scenegraph_definition,
    legend_inputs = legend_inputs,
    list_grid_settings = list_grid_settings,
    detail_grid_settings = detail_grid_settings,
}
