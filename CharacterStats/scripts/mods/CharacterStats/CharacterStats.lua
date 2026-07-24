local mod = get_mod('CharacterStats')

local SharedUtils = mod:io_dofile('CharacterStats/scripts/mods/CharacterStats/shared/shared_utils')
local _loc = mod:io_dofile('CharacterStats/scripts/mods/CharacterStats/CharacterStats_localization')
SharedUtils.apply_loc_settings(mod, _loc)

-- Register Character Stats View (and its ESC-menu button)
SharedUtils.register_stats_view(mod, {
    view_name = 'character_stats_view',
    class_name = 'CharacterStatsView',
    path = 'CharacterStats/scripts/mods/CharacterStats/character_stats_view/character_stats_view',
    button_text_loc = 'loc_character_stats_menu_button',
    setting_ids = { 'weapon_slot', 'assume_proc_stacks', 'coherency_allies', 'havoc_rank' },
})
