local mod = get_mod('CombatStats')

local UIFontSettings = mod:original_require('scripts/managers/ui/ui_font_settings')
local UISoundEvents = mod:original_require('scripts/settings/ui/ui_sound_events')
local ButtonPassTemplates = mod:original_require('scripts/ui/pass_templates/button_pass_templates')

local entry_width = 480
local entry_height = 80

local list_button_text_style = table.clone(UIFontSettings.list_button)
list_button_text_style.offset = { 10, -10, 3 }
list_button_text_style.font_size = 22

local list_button_subtext_style = table.clone(UIFontSettings.list_button_second_row)
list_button_subtext_style.offset = { 10, 22, 4 }
list_button_subtext_style.font_size = 16
list_button_subtext_style.text_color = Color.terminal_text_body_sub_header(255, true)

local list_button_hotspot_style = {
    anim_hover_speed = 8,
    anim_input_speed = 8,
    anim_select_speed = 8,
    anim_focus_speed = 8,
    on_hover_sound = UISoundEvents.default_mouse_hover,
    on_pressed_sound = UISoundEvents.default_click,
}

local blueprints = {
    stats_entry = {
        size = { entry_width, entry_height },
        pass_template = {
            {
                style_id = 'hotspot',
                pass_type = 'hotspot',
                content_id = 'hotspot',
                content = {
                    use_is_focused = true,
                },
                style = list_button_hotspot_style,
            },
            {
                pass_type = 'texture',
                style_id = 'background_selected',
                value = 'content/ui/materials/backgrounds/default_square',
                style = {
                    color = Color.ui_terminal(0, true),
                    offset = { 0, 0, 0 },
                },
                change_function = function(content, style)
                    style.color[1] = 255 * content.hotspot.anim_select_progress
                end,
                visibility_function = ButtonPassTemplates.list_button_focused_visibility_function,
            },
            {
                pass_type = 'texture',
                style_id = 'highlight',
                value = 'content/ui/materials/frames/hover',
                style = {
                    hdr = true,
                    scale_to_material = true,
                    color = Color.ui_terminal(255, true),
                    offset = { 0, 0, 3 },
                    size_addition = { 0, 0 },
                },
                change_function = ButtonPassTemplates.list_button_highlight_change_function,
                visibility_function = ButtonPassTemplates.list_button_focused_visibility_function,
            },
            {
                pass_type = 'text',
                style_id = 'text',
                value_id = 'text',
                style = table.clone(list_button_text_style),
                change_function = ButtonPassTemplates.list_button_label_change_function,
            },
            {
                pass_type = 'text',
                style_id = 'subtext',
                value_id = 'subtext',
                style = table.clone(list_button_subtext_style),
            },
        },
        init = function(parent, widget, entry, callback_name)
            local content = widget.content
            local hotspot = content.hotspot

            hotspot.pressed_callback = function()
                callback(parent, callback_name, widget, entry)()
            end

            content.text = entry.name

            if not entry.is_session then
                -- Enemy stats
                local status_color = Color.terminal_text_body(255, true)

                if entry.end_time then
                    status_color = Color.ui_green_light(255, true)
                elseif entry.start_time then
                    status_color = Color.ui_hud_yellow_light(255, true)
                end

                local dps = 0
                if entry.duration > 0 and entry.stats and entry.stats.total_damage then
                    dps = entry.stats.total_damage / entry.duration
                end

                local enemy_type_label = mod:localize('breed_' .. entry.type)
                content.subtext =
                    string.format('%s | %.1fs | %.0f %s', enemy_type_label, entry.duration, dps, mod:localize('dps'))
                widget.style.subtext.text_color = status_color
            else
                -- Session stats
                local dps = 0
                if entry.duration > 0 and entry.stats and entry.stats.total_damage > 0 then
                    dps = entry.stats.total_damage / entry.duration
                end
                content.subtext = string.format('%.1fs | %.0f %s', entry.duration, dps, mod:localize('dps'))
                widget.style.subtext.text_color = Color.terminal_text_body_sub_header(255, true)
            end

            content.entry = entry
        end,
    },
}

return blueprints
