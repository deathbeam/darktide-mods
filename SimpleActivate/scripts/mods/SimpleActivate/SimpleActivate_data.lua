local mod = get_mod('SimpleActivate')

return {
    name = mod:localize('mod_name'),
    description = mod:localize('mod_description'),
    is_togglable = true,
    options = {
        widgets = {
            {
                setting_id = 'auto_use_crate',
                type = 'checkbox',
                default_value = true,
            },
            {
                setting_id = 'auto_use_stimm',
                type = 'checkbox',
                default_value = true,
            },
            {
                setting_id = 'auto_use_blitz',
                type = 'checkbox',
                default_value = true,
            },
        },
    },
}
