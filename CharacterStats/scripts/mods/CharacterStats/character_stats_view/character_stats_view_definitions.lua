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

-- single_detail: drop the left list/search and span the detail panel full-width.
return make_shared_definitions('character_stats', mod, extra_legend_inputs, true)
