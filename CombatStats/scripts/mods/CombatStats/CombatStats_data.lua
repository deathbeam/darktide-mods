local mod = get_mod('CombatStats')

return {
    name = mod:localize('mod_name'),
    description = mod:localize('mod_description'),
    is_togglable = true,
    options = {
        widgets = {
            {
                setting_id = 'show_hud_overlay',
                type = 'checkbox',
                default_value = true,
            },
            {
                setting_id = 'only_in_psykanium',
                type = 'checkbox',
                default_value = true,
            },
            {
                setting_id = 'persist_stats_in_hub',
                type = 'checkbox',
                default_value = false,
            },
            {
                setting_id = 'max_kill_history',
                type = 'numeric',
                default_value = 10,
                range = { 5, 50 },
                decimals_number = 0,
            },
            {
                setting_id = 'window_group',
                type = 'group',
                sub_widgets = {
                    {
                        setting_id = 'toggle_window_keybind',
                        type = 'keybind',
                        default_value = {},
                        keybind_trigger = 'pressed',
                        keybind_type = 'function_call',
                        function_name = 'toggle_window',
                    },
                    {
                        setting_id = 'toggle_window_focus_keybind',
                        type = 'keybind',
                        default_value = {},
                        keybind_trigger = 'pressed',
                        keybind_type = 'function_call',
                        function_name = 'toggle_window_focus',
                    },
                    {
                        setting_id = 'window_width',
                        type = 'numeric',
                        default_value = 600,
                        range = { 200, 1000 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = 'window_height',
                        type = 'numeric',
                        default_value = 800,
                        range = { 200, 1000 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = 'window_x',
                        type = 'numeric',
                        default_value = 20,
                        range = { 0, 1200 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = 'window_y',
                        type = 'numeric',
                        default_value = 20,
                        range = { 0, 1200 },
                        decimals_number = 0,
                    },
                },
            },
        },
    },
}
