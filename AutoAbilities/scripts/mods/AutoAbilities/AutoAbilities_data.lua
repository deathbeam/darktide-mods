local mod = get_mod('AutoAbilities')

return {
    name = mod:localize('mod_name'),
    description = mod:localize('mod_description'),
    is_togglable = true,
    options = {
        widgets = {
            {
                setting_id = 'chemical_autostim',
                type = 'group',
                sub_widgets = {
                    {
                        setting_id = 'chemical_autostim_enabled',
                        type = 'checkbox',
                        default_value = false,
                    },
                },
            },
            {
                setting_id = 'quick_deploy',
                type = 'group',
                sub_widgets = {
                    {
                        setting_id = 'quick_deploy_enabled',
                        tooltip = 'quick_deploy_enabled_tooltip',
                        type = 'checkbox',
                        default_value = false,
                    },
                },
            },
            {
                setting_id = 'auto_blitz',
                type = 'group',
                sub_widgets = {
                    {
                        setting_id = 'auto_blitz_enabled',
                        tooltip = 'auto_blitz_enabled_tooltip',
                        type = 'checkbox',
                        default_value = false,
                    },
                },
            },
        },
    },
}
