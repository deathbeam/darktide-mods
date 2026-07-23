local mod = get_mod('CharacterStats')

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
                view_name = 'character_stats_view',
            },
            {
                setting_id = 'weapon_slot',
                type = 'dropdown',
                default_value = 'slot_primary',
                options = {
                    { value = 'slot_primary', text = 'weapon_slot_primary' },
                    { value = 'slot_secondary', text = 'weapon_slot_secondary' },
                },
            },
            {
                setting_id = 'assume_proc_stacks',
                type = 'checkbox',
                default_value = true,
            },
            {
                setting_id = 'coherency_allies',
                type = 'numeric',
                default_value = 3,
                range = { 0, 3 },
            },
            {
                setting_id = 'havoc_rank',
                type = 'numeric',
                default_value = 0,
                range = { 0, 40 },
            },
        },
    },
}
