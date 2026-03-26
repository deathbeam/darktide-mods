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
                offset = { 0, 0, 3 },
                size = { 16, 16 },
                color = UIHudSettings.color_tint_main_1,
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
    marker._widget = UIWidget.init('objective', marker._widget)
end

local function get_objective_letter(objective_name)
    if not objective_name then
        return 'O'
    end
    local first_word = objective_name:match('^%a+')
    if first_word then
        return first_word:sub(1, 1):upper()
    end
    return 'O'
end

function marker.collect(hud_element, dt, t)
    if not mod.settings.show_objectives then
        return nil
    end

    local objectives = {}
    local drawn_units = {}

    if hud_element._world_markers_list then
        for i = 1, #hud_element._world_markers_list do
            local wm = hud_element._world_markers_list[i]
            local template_name = wm.template and wm.template.name

            if template_name == 'objective' or template_name == 'hub_objective' then
                local world_pos = wm.position and wm.position:unbox()
                local objective_name = nil

                if not world_pos and wm.unit and Unit.alive(wm.unit) then
                    world_pos = Unit.world_position(wm.unit, 1)
                    if wm.unit then
                        drawn_units[wm.unit] = true
                    end

                    if ScriptUnit.has_extension(wm.unit, 'mission_objective_target_system') then
                        local target_ext = ScriptUnit.extension(wm.unit, 'mission_objective_target_system')
                        pcall(function()
                            objective_name = target_ext:objective_name()
                        end)
                    end
                end

                if world_pos then
                    table.insert(objectives, {
                        world_pos = Vector3Box(world_pos),
                        letter = get_objective_letter(objective_name),
                    })
                end
            end
        end
    end

    local mission_objective_system = Managers.state
        and Managers.state.extension
        and Managers.state.extension:system('mission_objective_system')

    if mission_objective_system then
        local success, active_objectives = pcall(function()
            return mission_objective_system:active_objectives()
        end)

        if success and active_objectives then
            for objective, _ in pairs(active_objectives) do
                local show, marked_units = pcall(function()
                    return objective:use_hud() and not objective:hide_marker(), objective:marked_units()
                end)

                if show and marked_units then
                    local objective_name = nil
                    pcall(function()
                        objective_name = objective:name()
                    end)

                    for unit, _ in pairs(marked_units) do
                        if Unit.alive(unit) and not drawn_units[unit] then
                            local world_pos = Unit.world_position(unit, 1)
                            table.insert(objectives, {
                                world_pos = Vector3Box(world_pos),
                                letter = get_objective_letter(objective_name),
                            })
                            drawn_units[unit] = true
                        end
                    end
                end
            end
        end
    end

    return objectives
end

function marker.draw(hud_element, ui_renderer, dt, t, cached_data)
    if not cached_data then
        return
    end

    local widget = marker._widget

    for i = 1, #cached_data do
        local obj = cached_data[i]
        local pos = hud_element:world_to_minimap(obj.world_pos:unbox())

        if pos then
            widget.style.circle.offset[1] = pos.x
            widget.style.circle.offset[2] = pos.y
            widget.style.text.offset[1] = pos.x
            widget.style.text.offset[2] = pos.y
            widget.content.text = obj.letter
            UIWidget.draw(widget, ui_renderer)
        end
    end
end

return marker
