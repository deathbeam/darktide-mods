local mod = get_mod('EnemyStats')

local make_shared_definitions = mod:io_dofile('EnemyStats/scripts/mods/EnemyStats/shared/shared_view_definitions')

local extra_legend_inputs = {
    {
        input_action = 'hotkey_menu_special_1',
        on_pressed_callback = 'cb_on_copy_pressed',
        display_name = 'loc_enemy_stats_copy',
        alignment = 'right_alignment',
    },
}

return make_shared_definitions({
    prefix = 'enemy_stats',
    mod = mod,
    extra_legend_inputs = extra_legend_inputs,
})
