local mod = get_mod('CharacterStats')

local make_shared_blueprints = mod:io_dofile('CharacterStats/scripts/mods/CharacterStats/shared/shared_view_blueprints')

return function(width)
    return make_shared_blueprints(width, {
        entry_type = 'character_entry',
        entry_height = 64,
        text_offset = { 10, -6, 3 },
        text_font_size = 20,
        subtext_offset = { 10, 16, 4 },
        subtext_font_size = 14,
    })
end
