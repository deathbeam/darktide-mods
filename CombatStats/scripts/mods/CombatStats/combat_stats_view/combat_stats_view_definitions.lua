local mod = get_mod('CombatStats')

local make_shared_definitions = mod:io_dofile('CombatStats/scripts/mods/CombatStats/shared/shared_view_definitions')

local extra_legend_inputs = {
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

return make_shared_definitions({
    prefix = 'combat_stats',
    mod = mod,
    extra_legend_inputs = extra_legend_inputs,
})
