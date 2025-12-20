local mod = get_mod('CombatStats')

return {
    name = mod:localize('mod_name'),
    description = mod:localize('mod_description'),
    is_togglable = true,
    options = {
        widgets = {
            {
                setting_id = 'save_history',
                type = 'checkbox',
                default_value = false,
            },
            {
                setting_id = 'toggle_view_keybind',
                type = 'keybind',
                default_value = {},
                keybind_trigger = 'pressed',
                keybind_type = 'view_toggle',
                view_name = 'combat_stats_view',
            },
            {
                setting_id = 'hud',
                type = 'group',
                sub_widgets = {
                    {
                        setting_id = 'show_hud_in_missions',
                        type = 'checkbox',
                        default_value = true,
                    },
                    {
                        setting_id = 'show_hud_in_hub',
                        type = 'checkbox',
                        default_value = false,
                    },
                    {
                        setting_id = 'hud_pos_x',
                        type = 'numeric',
                        default_value = 20,
                        range = { 0, 1920 },
                    },
                    {
                        setting_id = 'hud_pos_y',
                        type = 'numeric',
                        default_value = 100,
                        range = { 0, 1080 },
                    },
                },
            },
            {
                setting_id = 'combat_detection',
                type = 'group',
                sub_widgets = {
                    {
                        setting_id = 'track_incoming_attacks',
                        type = 'checkbox',
                        default_value = true,
                    },
                    {
                        setting_id = 'engagement_timeout',
                        type = 'numeric',
                        default_value = 5,
                        range = { 1, 30 },
                    },
                },
            },
            {
                setting_id = 'enemy_types_to_track',
                type = 'group',
                sub_widgets = {
                    {
                        setting_id = 'breed_monster',
                        type = 'checkbox',
                        default_value = true,
                    },
                    {
                        setting_id = 'breed_ritualist',
                        type = 'checkbox',
                        default_value = true,
                    },
                    {
                        setting_id = 'breed_disabler',
                        type = 'checkbox',
                        default_value = true,
                    },
                    {
                        setting_id = 'breed_special',
                        type = 'checkbox',
                        default_value = true,
                    },
                    {
                        setting_id = 'breed_elite',
                        type = 'checkbox',
                        default_value = true,
                    },
                    {
                        setting_id = 'breed_horde',
                        type = 'checkbox',
                        default_value = true,
                    },
                    {
                        setting_id = 'breed_unknown',
                        type = 'checkbox',
                        default_value = true,
                    },
                },
            },
        },
    },
}
