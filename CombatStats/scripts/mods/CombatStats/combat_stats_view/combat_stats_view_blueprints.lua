local mod = get_mod('CombatStats')

local make_shared_blueprints = mod:io_dofile('CombatStats/scripts/mods/CombatStats/shared/shared_view_blueprints')

return function(width)
    return make_shared_blueprints(width, {
        entry_type = 'stats_entry',
        entry_height = 80,
    })
end
