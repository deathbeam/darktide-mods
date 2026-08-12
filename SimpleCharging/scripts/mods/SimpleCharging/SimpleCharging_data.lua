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
            {
                setting_id = 'bar_color',
                title = 'bar_color',
                type = 'group',
                sub_widgets = {
                    {
                        setting_id = 'bar_color_red',
                        title = 'bar_color_red',
                        type = 'numeric',
                        default_value = 216,
                        range = { 0, 255 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = 'bar_color_green',
                        title = 'bar_color_green',
                        type = 'numeric',
                        default_value = 229,
                        range = { 0, 255 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = 'bar_color_blue',
                        title = 'bar_color_blue',
                        type = 'numeric',
                        default_value = 207,
                        range = { 0, 255 },
                        decimals_number = 0,
                    },
                    {
                        setting_id = 'bar_color_alpha',
                        title = 'bar_color_alpha',
                        type = 'numeric',
                        default_value = 255,
                        range = { 0, 255 },
                        decimals_number = 0,
                    },
                },
            },
        },
    },
}
