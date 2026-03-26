local mod = get_mod('SimpleMinimap')
local UIWidget = require('scripts/managers/ui/ui_widget')

local marker = {}

function marker.init(hud_element)
    marker._widget = UIWidget.create_definition({
        {
            pass_type = 'triangle',
            style_id = 'triangle',
            style = {
                vertical_alignment = 'center',
                horizontal_alignment = 'center',
                color = Color.yellow(255, true),
                offset = { 0, 0, 3 },
                size = { 14, 14 },
                triangle_corners = {
                    { 7, 0 },
                    { 0, 14 },
                    { 14, 14 },
                },
            },
        },
    }, 'minimap')
    marker._widget = UIWidget.init('ping', marker._widget)
end

function marker.collect(hud_element, dt, t)
    if not mod.settings.show_pings or not hud_element._world_markers_list then
        return nil
    end

    local pings = {}
    local world_markers = hud_element._world_markers_list

    local ping_templates = {
        location_ping = true,
        location_attention = true,
        location_threat = true,
        unit_threat = true,
        unit_threat_adamant = true,
        unit_threat_veteran = true,
        beacon = true,
    }

    for i = 1, #world_markers do
        local wm = world_markers[i]
        local template_name = wm.template and wm.template.name

        if ping_templates[template_name] then
            local world_pos = wm.position and wm.position:unbox()
            if not world_pos and wm.unit and Unit.alive(wm.unit) then
                world_pos = Unit.world_position(wm.unit, 1)
            end

            if world_pos then
                table.insert(pings, { world_pos = Vector3Box(world_pos) })
            end
        end
    end

    return pings
end

function marker.draw(hud_element, ui_renderer, dt, t, cached_data)
    if not cached_data then
        return
    end

    local widget = marker._widget

    for i = 1, #cached_data do
        local ping = cached_data[i]
        local pos = hud_element:world_to_minimap(ping.world_pos:unbox())

        if pos then
            widget.style.triangle.offset[1] = pos.x
            widget.style.triangle.offset[2] = pos.y

            -- Pulse effect
            local pulse = 0.5 + 0.5 * math.sin(Application.time_since_launch() * 4)
            widget.style.triangle.color[1] = 128 + pulse * 127

            UIWidget.draw(widget, ui_renderer)
        end
    end
end

return marker
