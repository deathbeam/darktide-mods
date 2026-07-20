local mod = get_mod('EnemyStats')

local make_shared_blueprints = mod:io_dofile('EnemyStats/scripts/mods/EnemyStats/shared/shared_view_blueprints')

return function(width)
    return make_shared_blueprints(width, {
        entry_type = 'enemy_entry',
        entry_height = 80,
        include_category_header = true,
        icon_size = { 60, 60 },
        icon_margin = 10,
    })
end
