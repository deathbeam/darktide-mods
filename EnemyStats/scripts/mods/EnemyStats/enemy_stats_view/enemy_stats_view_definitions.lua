local mod = get_mod('EnemyStats')

local make_shared_definitions = mod:io_dofile('EnemyStats/scripts/mods/EnemyStats/shared/shared_view_definitions')

return make_shared_definitions('enemy_stats', mod)
