local mod = get_mod('WeaponStats')

local make_shared_blueprints = mod:io_dofile('WeaponStats/scripts/mods/WeaponStats/shared/shared_view_blueprints')

return function(width)
    return make_shared_blueprints(width, {
        entry_type = 'weapon_entry',
        entry_height = 70,
        text_offset = { 10, -8, 3 },
        text_font_size = 20,
        subtext_offset = { 10, 18, 4 },
        subtext_font_size = 14,
        icon_size = { 96, 48 },
        icon_margin = 8,
    })
end
