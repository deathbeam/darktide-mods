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
                setting_id = 'enable_in_hub',
                type = 'checkbox',
                default_value = false,
            },
            {
                setting_id = 'enable_in_missions',
                type = 'checkbox',
                default_value = false,
            },
            {
                setting_id = 'toggle_view_keybind',
                type = 'keybind',
                default_value = {},
                keybind_trigger = 'pressed',
                keybind_type = 'function_call',
                function_name = 'toggle_view',
            },
        },
    },
}
