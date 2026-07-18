local mod = get_mod('EnemyStats')

local SharedUtils = mod:io_dofile('EnemyStats/scripts/mods/EnemyStats/shared/shared_utils')
local _loc = mod:io_dofile('EnemyStats/scripts/mods/EnemyStats/EnemyStats_localization')
SharedUtils.apply_loc_settings(mod, _loc)

-- Register Enemy Stats View (and its ESC-menu button)
SharedUtils.register_stats_view(
    mod,
    'enemy_stats_view',
    'EnemyStatsView',
    'EnemyStats/scripts/mods/EnemyStats/enemy_stats_view/enemy_stats_view',
    'loc_enemy_stats_menu_button'
)
