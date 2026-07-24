local mod = get_mod('CharacterStats')

local make_shared_definitions =
    mod:io_dofile('CharacterStats/scripts/mods/CharacterStats/shared/shared_view_definitions')

local extra_legend_inputs = {
    {
        input_action = 'hotkey_menu_special_1',
        on_pressed_callback = 'cb_on_copy_pressed',
        display_name = 'loc_character_stats_copy',
        alignment = 'right_alignment',
    },
}

-- Left panel holds settings, not a searchable list.
return make_shared_definitions({
    prefix = 'character_stats',
    mod = mod,
    extra_legend_inputs = extra_legend_inputs,
    single_detail = false,
    search = false,
})
