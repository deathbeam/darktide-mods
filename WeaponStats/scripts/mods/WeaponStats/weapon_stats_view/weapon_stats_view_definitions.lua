local mod = get_mod('WeaponStats')

local make_shared_definitions = mod:io_dofile('WeaponStats/scripts/mods/WeaponStats/shared/shared_view_definitions')

local extra_legend_inputs = {
    {
        input_action = 'hotkey_menu_special_1',
        on_pressed_callback = 'cb_on_copy_pressed',
        display_name = 'loc_weapon_stats_copy',
        alignment = 'right_alignment',
    },
}

return make_shared_definitions({
    prefix = 'weapon_stats',
    mod = mod,
    extra_legend_inputs = extra_legend_inputs,
})
