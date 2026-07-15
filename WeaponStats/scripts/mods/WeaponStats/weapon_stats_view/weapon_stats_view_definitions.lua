local mod = get_mod('WeaponStats')

local make_shared_definitions = mod:io_dofile('WeaponStats/scripts/mods/WeaponStats/shared/shared_view_definitions')

return make_shared_definitions('weapon_stats', mod)
