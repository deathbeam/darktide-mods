local mod = get_mod('CombatStats')

local UIFontSettings = mod:original_require('scripts/managers/ui/ui_font_settings')
local UISoundEvents = mod:original_require('scripts/settings/ui/ui_sound_events')
local ButtonPassTemplates = mod:original_require('scripts/ui/pass_templates/button_pass_templates')

local CombatStatsUtils = mod:io_dofile('CombatStats/scripts/mods/CombatStats/combat_stats_utils')

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
            local style = widget.style

            content.hotspot.pressed_callback = function()
                callback(parent, callback_name, widget, entry)()
            end

            content.text = entry.name
            content.subtext = entry.subtext
            content.entry = entry

            if entry.subtext_color then
                style.subtext.text_color = entry.subtext_color
            end
        end,
    },
}

return blueprints
