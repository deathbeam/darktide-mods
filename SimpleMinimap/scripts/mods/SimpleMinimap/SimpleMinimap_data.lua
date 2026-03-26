local mod = get_mod('SimpleMinimap')

return {
    name = mod:localize('mod_name'),
    description = mod:localize('mod_description'),
    is_togglable = true,
    options = {
        widgets = {
            {
                setting_id = 'minimap_size',
                type = 'numeric',
                default_value = 200,
                range = { 100, 400 },
            },
            {
                setting_id = 'minimap_max_range',
                type = 'numeric',
                default_value = 50,
                range = { 20, 100 },
            },
            {
                setting_id = 'background_opacity',
                type = 'numeric',
                default_value = 128,
                range = { 0, 255 },
            },
            {
                setting_id = 'show_teammates',
                type = 'checkbox',
                default_value = true,
            },
            {
                setting_id = 'show_class_icons',
                type = 'checkbox',
                default_value = true,
            },
            {
                setting_id = 'show_objectives',
                type = 'checkbox',
                default_value = true,
            },
            {
                setting_id = 'show_pings',
                type = 'checkbox',
                default_value = true,
            },
            {
                setting_id = 'show_enemies',
                type = 'checkbox',
                default_value = false,
            },
            {
                setting_id = 'enemy_radar_range',
                type = 'numeric',
                default_value = 30,
                range = { 10, 100 },
            },
            {
                setting_id = 'enemy_categories',
                type = 'group',
                sub_widgets = {
                    {
                        setting_id = 'show_enemy_monsters',
                        type = 'checkbox',
                        default_value = true,
                    },
                    {
                        setting_id = 'show_enemy_elites',
                        type = 'checkbox',
                        default_value = true,
                    },
                    {
                        setting_id = 'show_enemy_specials',
                        type = 'checkbox',
                        default_value = true,
                    },
                    {
                        setting_id = 'show_enemy_horde',
                        type = 'checkbox',
                        default_value = false,
                    },
                    {
                        setting_id = 'show_enemy_roamer',
                        type = 'checkbox',
                        default_value = false,
                    },
                },
            },
        },
    },
}
