local UIFontSettings = require('scripts/managers/ui/ui_font_settings')
local UISoundEvents = require('scripts/settings/ui/ui_sound_events')
local ButtonPassTemplates = require('scripts/ui/pass_templates/button_pass_templates')

-- Build list-view blueprints shared across the stats mods.
-- config:
--   entry_type             - widget name for the list entry (e.g. "weapon_entry")
--   entry_height           - row height in px (default 80)
--   text_offset            - {x, y, z} for the entry title (default {10, -10, 3})
--   text_font_size         - title font size (default 22)
--   subtext_offset         - {x, y, z} for the entry subtext (default {10, 22, 4})
--   subtext_font_size      - subtext font size (default 16)
--   include_category_header- add a category_header widget (default false)
--   icon_size              - {w, h} for the optional entry icon (default nil = no icon)
--   icon_margin            - horizontal gap after the icon (default 10)
local function make_blueprints(width, config)
    config = config or {}
    local entry_height = config.entry_height or 80
    local entry_type = config.entry_type or 'entry'
    local icon_size = config.icon_size
    local icon_margin = config.icon_margin or 10
    local icon_area_w = icon_size and (icon_size[1] + icon_margin) or 0

    local list_button_text_style = table.clone(UIFontSettings.list_button)
    list_button_text_style.offset = config.text_offset or { 10, -10, 3 }
    list_button_text_style.font_size = config.text_font_size or 22

    local list_button_subtext_style = table.clone(UIFontSettings.list_button_second_row)
    list_button_subtext_style.offset = config.subtext_offset or { 10, 22, 4 }
    list_button_subtext_style.font_size = config.subtext_font_size or 16
    list_button_subtext_style.text_color = Color.terminal_text_body_sub_header(255, true)

    local list_button_hotspot_style = {
        anim_hover_speed = 8,
        anim_input_speed = 8,
        anim_select_speed = 8,
        anim_focus_speed = 8,
        on_hover_sound = UISoundEvents.default_mouse_hover,
        on_pressed_sound = UISoundEvents.default_click,
    }

    local blueprints = {}

    if config.include_category_header then
        local header_style = table.clone(UIFontSettings.header_3)
        header_style.font_size = 18
        header_style.text_color = Color.terminal_text_body_sub_header(255, true)
        header_style.text_horizontal_alignment = 'left'
        header_style.offset = { 4, 0, 2 }

        blueprints.category_header = {
            size = { width, 28 },
            pass_template = {
                {
                    pass_type = 'text',
                    style_id = 'text',
                    value_id = 'text',
                    value = '',
                    style = header_style,
                },
            },
            init = function(_, widget, element)
                widget.content.text = element.text or ''
            end,
        }
    end

    local pass_template = {
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
                color = { 255, 49, 56, 49 },
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
    }

    if icon_size then
        pass_template[#pass_template + 1] = {
            pass_type = 'texture',
            style_id = 'icon',
            value_id = 'icon',
            value = 'content/ui/materials/base/ui_default_base',
            style = {
                horizontal_alignment = 'left',
                vertical_alignment = 'center',
                size = { icon_size[1], icon_size[2] },
                color = Color.terminal_text_body(255, true),
                offset = { icon_margin / 2, 0, 2 },
            },
            visibility_function = function(content)
                return content.icon ~= nil
            end,
        }
    end

    local text_base_x = list_button_text_style.offset[1]
    local subtext_base_x = list_button_subtext_style.offset[1]

    local text_style = table.clone(list_button_text_style)
    text_style.offset = {
        text_base_x + icon_area_w,
        list_button_text_style.offset[2],
        list_button_text_style.offset[3],
    }
    text_style.size = { width - icon_area_w - text_base_x, entry_height }
    text_style.text_overflow_mode = 'truncate'

    local subtext_style = table.clone(list_button_subtext_style)
    subtext_style.offset = {
        subtext_base_x + icon_area_w,
        list_button_subtext_style.offset[2],
        list_button_subtext_style.offset[3],
    }
    subtext_style.size = { width - icon_area_w - subtext_base_x, entry_height }
    subtext_style.text_overflow_mode = 'truncate'

    pass_template[#pass_template + 1] = {
        pass_type = 'text',
        style_id = 'text',
        value_id = 'text',
        style = text_style,
        change_function = ButtonPassTemplates.list_button_label_change_function,
    }
    pass_template[#pass_template + 1] = {
        pass_type = 'text',
        style_id = 'subtext',
        value_id = 'subtext',
        style = subtext_style,
    }

    blueprints[entry_type] = {
        size = { width, entry_height },
        pass_template = pass_template,
        init = function(parent, widget, entry, callback_name)
            local content = widget.content
            local style = widget.style

            content.hotspot.pressed_callback = callback(parent, callback_name, widget, entry)

            content.text = entry.name
            content.subtext = entry.subtext
            content.entry = entry
            content.element = entry

            if entry.subtext_color then
                style.subtext.text_color = entry.subtext_color
            end

            if icon_size and entry.icon then
                content.icon = entry.icon
                style.text.offset[1] = text_base_x + icon_area_w
                style.text.size[1] = width - icon_area_w - text_base_x
                style.subtext.offset[1] = subtext_base_x + icon_area_w
                style.subtext.size[1] = width - icon_area_w - subtext_base_x
            elseif icon_size then
                content.icon = nil
                style.text.offset[1] = text_base_x
                style.text.size[1] = width - text_base_x
                style.subtext.offset[1] = subtext_base_x
                style.subtext.size[1] = width - subtext_base_x
            end
        end,
    }

    return blueprints
end

return make_blueprints
