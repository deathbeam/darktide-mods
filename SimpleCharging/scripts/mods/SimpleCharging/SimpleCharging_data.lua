local mod = get_mod('SimpleCharging')

return {
    name = mod:localize('mod_name'),
    description = mod:localize('mod_description'),
    is_togglable = true,
    options = {
        widgets = {
            {
                setting_id = 'show_only_longest_charge',
                type = 'checkbox',
                tooltip = 'show_only_longest_charge_description',
                default_value = false,
            },
        },
    },
}
