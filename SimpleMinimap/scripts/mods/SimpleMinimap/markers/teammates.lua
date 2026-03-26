-- Teammates marker - shows teammate positions
local mod = get_mod('SimpleMinimap')
local UIWidget = require('scripts/managers/ui/ui_widget')
local UIHudSettings = require('scripts/settings/ui/ui_hud_settings')

local marker = {}

function marker.init(hud_element)
    marker._widget = UIWidget.create_definition({
        {
            pass_type = 'circle',
            style_id = 'circle',
            style = {
                vertical_alignment = 'center',
                horizontal_alignment = 'center',
                color = UIHudSettings.color_tint_main_1,
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
                font_size = 16,
                text_color = Color.white(255, true),
                offset = { 0, 0, 4 },
                size = { 20, 20 },
            },
        },
    }, 'minimap')
    marker._widget = UIWidget.init('teammate', marker._widget)
end

-- Collect teammate data (called periodically by HUD element)
function marker.collect(hud_element, dt, t)
    if not mod.settings.show_teammates or not hud_element._world_markers_list then
        return nil
    end

    local teammates = {}
    local world_markers = hud_element._world_markers_list

    local local_player = Managers.player and Managers.player:local_player(1)
    local local_player_unit = local_player and local_player.player_unit

    local teammate_templates = {
        nameplate = true,
        nameplate_party = true,
        nameplate_party_hud = true,
        nameplate_combat = true,
        nameplate_companion = true,
        nameplate_companion_hub = true,
        ringhud_teammate_tile = true,
    }

    for i = 1, #world_markers do
        local wm = world_markers[i]
        local template_name = wm.template and wm.template.name

        if teammate_templates[template_name] then
            if wm.unit and wm.unit == local_player_unit then
                -- Skip local player
            else
                local world_pos = wm.position and wm.position:unbox()
                if not world_pos and wm.unit and Unit.alive(wm.unit) then
                    world_pos = Unit.world_position(wm.unit, 1)
                end

                if world_pos then
                    local archetype = wm.data
                        and wm.data.player
                        and wm.data.player.profile
                        and wm.data.player.profile.archetype
                        and wm.data.player.profile.archetype.name

                    table.insert(teammates, {
                        world_pos = Vector3Box(world_pos),
                        archetype = archetype,
                    })
                end
            end
        end
    end

    return teammates
end

-- Draw teammates (called every frame with cached data)
function marker.draw(hud_element, ui_renderer, dt, t, cached_data)
    if not cached_data then
        return
    end

    local widget = marker._widget
    local show_class = mod.settings.show_class_icons
    local icons = { psyker = 'P', veteran = 'V', zealot = 'Z', ogryn = 'O' }

    for i = 1, #cached_data do
        local teammate = cached_data[i]
        local pos = hud_element:world_to_minimap(teammate.world_pos:unbox())

        if pos then
            widget.style.circle.offset[1] = pos.x
            widget.style.circle.offset[2] = pos.y
            widget.style.text.offset[1] = pos.x
            widget.style.text.offset[2] = pos.y

            if show_class and teammate.archetype then
                widget.content.text = icons[teammate.archetype] or '?'
                widget.style.text.visible = true
                widget.style.circle.visible = false
            else
                widget.content.text = ''
                widget.style.text.visible = false
                widget.style.circle.visible = true
            end

            UIWidget.draw(widget, ui_renderer)
        end
    end
end

return marker
