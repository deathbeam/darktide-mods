local mod = get_mod('SimpleMinimap')
local UIWidget = require('scripts/managers/ui/ui_widget')

local marker = {}

function marker.init(hud_element)
    marker._widget = UIWidget.create_definition({
        {
            pass_type = 'circle',
            style_id = 'circle',
            style = {
                vertical_alignment = 'center',
                horizontal_alignment = 'center',
                color = Color.red(255, true),
                offset = { 0, 0, 3 },
                size = { 12, 12 },
            },
        },
        {
            pass_type = 'text',
            value_id = 'text',
            style_id = 'text',
            value = '',
            style = {
                horizontal_alignment = 'center',
                vertical_alignment = 'center',
                text_horizontal_alignment = 'center',
                text_vertical_alignment = 'center',
                font_type = 'proxima_nova_bold',
                font_size = 14,
                text_color = Color.white(255, true),
                offset = { 0, 0, 4 },
                size = { 20, 20 },
            },
        },
    }, 'minimap')
    marker._widget = UIWidget.init('enemy', marker._widget)
end

local breed_abbreviations = {
    chaos_hound = 'H',
    renegade_netgunner = 'T',
    renegade_sniper = 'S',
    renegade_flamer = 'F',
    cultist_flamer = 'F',
    renegade_grenadier = 'G',
    cultist_grenadier = 'G',
    chaos_poxwalker_bomber = 'B',
    cultist_mutant = 'M',
    chaos_ogryn_executor = 'X',
    renegade_executor = 'X',
    cultist_berzerker = 'R',
    renegade_berzerker = 'R',
    renegade_plasma_gunner = 'P',
    chaos_ogryn_bulwark = 'W',
    renegade_shocktrooper = 'K',
    cultist_shocktrooper = 'K',
    renegade_gunner = 'N',
    cultist_gunner = 'N',
    chaos_ogryn_gunner = 'N',
    chaos_spawn = 'S',
    chaos_beast_of_nurgle = 'N',
    chaos_plague_ogryn = 'O',
    chaos_daemonhost = 'D',
}

function marker.collect(hud_element, dt, t)
    if not mod.settings.show_enemies then
        return nil
    end

    local enemies = {}

    local local_player = Managers.player and Managers.player:local_player(1)
    if not local_player then
        return nil
    end

    local player_unit = local_player.player_unit
    if not player_unit or not Unit.alive(player_unit) then
        return nil
    end

    local broadphase_system = Managers.state
        and Managers.state.extension
        and Managers.state.extension:system('broadphase_system')
    local broadphase = broadphase_system and broadphase_system.broadphase
    if not broadphase then
        return nil
    end

    local side_system = Managers.state and Managers.state.extension and Managers.state.extension:system('side_system')
    local side = side_system and side_system.side_by_unit[player_unit]
    if not side then
        return nil
    end

    local from_pos = Unit.world_position(player_unit, 1)
    local enemy_sides = side:relation_side_names('enemy')
    local range = mod.settings.enemy_radar_range or 30
    local results = {}
    local count = broadphase.query(broadphase, from_pos, range, results, enemy_sides)

    if count and count > 0 then
        for i = 1, count do
            local enemy_unit = results[i]
            if Unit.alive(enemy_unit) then
                local color = Color.red(255, true)
                local breed_letter = '?'
                local show_letter = false
                local should_show = false

                if ScriptUnit.has_extension(enemy_unit, 'unit_data_system') then
                    local unit_data = ScriptUnit.extension(enemy_unit, 'unit_data_system')
                    local breed = unit_data:breed()
                    if breed then
                        local breed_name = breed.name
                        local tags = breed.tags

                        breed_letter = breed_abbreviations[breed_name] or '?'

                        if tags then
                            if tags.monster or tags.captain or tags.cultist_captain then
                                should_show = mod.settings.show_enemy_monsters
                                color = Color.purple(255, true)
                                show_letter = true
                            elseif tags.elite then
                                should_show = mod.settings.show_enemy_elites
                                color = Color.orange(255, true)
                                show_letter = true
                            elseif tags.special then
                                should_show = mod.settings.show_enemy_specials
                                color = Color.magenta(255, true)
                                show_letter = true
                            elseif tags.horde then
                                should_show = mod.settings.show_enemy_horde
                                color = Color.gray(255, true)
                                show_letter = false
                            elseif tags.roamer then
                                should_show = mod.settings.show_enemy_roamer
                                color = Color.white(255, true)
                                show_letter = false
                            end
                        end
                    end
                end

                if should_show then
                    table.insert(enemies, {
                        unit = enemy_unit,
                        color = color,
                        breed_letter = breed_letter,
                        show_letter = show_letter,
                    })
                end
            end
        end
    end

    return enemies
end

function marker.draw(hud_element, ui_renderer, dt, t, cached_data)
    if not cached_data then
        return
    end

    local widget = marker._widget

    for i = 1, #cached_data do
        local enemy_data = cached_data[i]
        if Unit.alive(enemy_data.unit) then
            local enemy_pos = Unit.world_position(enemy_data.unit, 1)
            local pos = hud_element:world_to_minimap(enemy_pos)

            if pos then
                widget.style.circle.offset[1] = pos.x
                widget.style.circle.offset[2] = pos.y
                widget.style.text.offset[1] = pos.x
                widget.style.text.offset[2] = pos.y

                if enemy_data.show_letter then
                    widget.content.text = enemy_data.breed_letter
                    widget.style.text.visible = true
                    widget.style.circle.visible = false
                    widget.style.text.text_color = enemy_data.color
                else
                    widget.content.text = ''
                    widget.style.text.visible = false
                    widget.style.circle.visible = true
                    widget.style.circle.color = enemy_data.color
                end

                UIWidget.draw(widget, ui_renderer)
            end
        end
    end
end

return marker
