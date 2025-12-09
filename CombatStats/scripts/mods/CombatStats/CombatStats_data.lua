local mod = get_mod('CombatStats')

return {
    name = mod:localize('mod_name'),
    description = mod:localize('mod_description'),
    is_togglable = true,
    options = {
        widgets = {
            {
                setting_id = 'only_in_psykanium',
                type = 'checkbox',
                default_value = true,
            },
            {
                setting_id = 'max_kill_history',
                type = 'numeric',
                default_value = 10,
                range = { 5, 50 },
                decimals_number = 0,
            },
            {
                setting_id = 'toggle_stats_keybind',
                type = 'keybind',
                default_value = {},
                keybind_trigger = 'pressed',
                keybind_type = 'function_call',
                function_name = 'toggle_kill_stats',
            },
        },
    },
}
