local mod = get_mod('EnemyStats')

return {
    name = mod:localize('mod_name'),
    description = mod:localize('mod_description'),
    is_togglable = true,
    options = {
        widgets = {
            {
                setting_id = 'add_to_esc_menu',
                type = 'checkbox',
                default_value = true,
            },
            {
                setting_id = 'toggle_view_keybind',
                type = 'keybind',
                default_value = {},
                keybind_trigger = 'pressed',
                keybind_type = 'view_toggle',
                view_name = 'enemy_stats_view',
            },
        },
    },
}
