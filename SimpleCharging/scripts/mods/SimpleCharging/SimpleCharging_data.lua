local mod = get_mod('SimpleCharging')

return {
    name = mod:localize('mod_name'),
    description = mod:localize('mod_description'),
    is_togglable = true,
    options = {
        widgets = {
            {
                setting_id = 'bar_distance',
                type = 'numeric',
                default_value = 64,
                range = { 8, 160 },
                decimals_number = 0,
            },
            {
                setting_id = 'bar_spacing',
                type = 'numeric',
                default_value = 28,
                range = { 8, 80 },
                decimals_number = 0,
            },
            {
                setting_id = 'show_weapon_charge',
                type = 'checkbox',
                default_value = true,
            },
        },
    },
}
