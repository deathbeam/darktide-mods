local mod = get_mod('WeaponStats')

return {
    name = mod:localize('mod_name'),
    description = mod:localize('mod_description'),
    is_togglable = true,
    options = {
        widgets = {
            {
                setting_id = 'toggle_view_keybind',
                type = 'keybind',
                default_value = {},
                keybind_trigger = 'pressed',
                keybind_type = 'view_toggle',
                view_name = 'weapon_stats_view',
            },
        },
    },
}
