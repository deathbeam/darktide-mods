local mod = get_mod('SimpleMovement')

return {
    name = mod:localize('mod_name'),
    description = mod:localize('mod_description'),
    is_togglable = true,
    options = {
        widgets = {
            {
                setting_id = 'sprint_by_default',
                type = 'checkbox',
                tooltip = 'sprint_by_default_description',
                default_value = true,
            },
            {
                setting_id = 'walk_while_melee_attacking',
                type = 'checkbox',
                tooltip = 'walk_while_melee_attacking_description',
                default_value = false,
            },
            {
                setting_id = 'repeat_dodge',
                type = 'checkbox',
                tooltip = 'repeat_dodge_description',
                default_value = true,
            },
            {
                setting_id = 'dodge_slide',
                type = 'checkbox',
                tooltip = 'dodge_slide_description',
                default_value = true,
            },
            {
                setting_id = 'sprint_dodge',
                type = 'checkbox',
                tooltip = 'sprint_dodge_description',
                default_value = true,
            },
            {
                setting_id = 'auto_vault',
                type = 'checkbox',
                tooltip = 'auto_vault_description',
                default_value = true,
            },
        },
    },
}
