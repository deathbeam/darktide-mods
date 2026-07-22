local mod = get_mod('CharacterStats')

local Shared = mod:io_dofile('CharacterStats/scripts/mods/CharacterStats/shared/shared_detail_blueprints')
local Text = mod:original_require('scripts/utilities/ui/text')
local UIFontSettings = mod:original_require('scripts/managers/ui/ui_font_settings')

local INDENT_PX = 18
local STAT_ROW_HEIGHT = 21
local COLOR_STRIPE = Color.terminal_grid_background(60, true)
local STAT_LABEL_FONT_SIZE = 16
local STAT_VALUE_FONT_SIZE = 16

local function make_blueprints(width)
    local blueprints = Shared.make_blueprints(width)

    blueprints.stat = {
        size = { width, STAT_ROW_HEIGHT },
        pass_template_function = function(_, config)
            local label_style = {
                font_type = 'proxima_nova_bold',
                font_size = STAT_LABEL_FONT_SIZE,
                text_vertical_alignment = 'center',
                text_horizontal_alignment = 'left',
                text_color = Shared.colors.label,
                offset = { 0, 0, 2 },
                size = { width * 0.55, STAT_ROW_HEIGHT },
                text_overflow_mode = 'truncate',
            }
            local value_style = {
                font_type = 'proxima_nova_bold',
                font_size = STAT_VALUE_FONT_SIZE,
                text_vertical_alignment = 'center',
                text_horizontal_alignment = 'left',
                text_color = Shared.colors.value,
                offset = { width * 0.55, 0, 2 },
                size = { width * 0.45, STAT_ROW_HEIGHT },
                text_overflow_mode = 'truncate',
            }
            return {
                {
                    pass_type = 'rect',
                    style_id = 'stripe',
                    style = {
                        color = COLOR_STRIPE,
                        offset = { 0, 0, 0 },
                    },
                    visibility_function = function(content)
                        return content.stripe == true
                    end,
                },
                {
                    pass_type = 'text',
                    style_id = 'label',
                    value_id = 'label',
                    value = '',
                    style = label_style,
                },
                {
                    pass_type = 'text',
                    style_id = 'value',
                    value_id = 'value',
                    value = '',
                    style = value_style,
                },
            }
        end,
        init = function(_, widget, element)
            local content = widget.content
            content.label = element.label or ''
            content.value = element.value or ''
            content.stripe = element.stripe == true
            local style = widget.style
            style.label.offset[1] = (element.indent or 0) * INDENT_PX
            style.value.offset[1] = (element.indent or 0) * INDENT_PX + width * 0.55
            if element.label_color then
                style.label.text_color = element.label_color
            end
            if element.value_color then
                style.value.text_color = element.value_color
            end
        end,
    }

    blueprints.text = {
        size_function = function(_, config, ui_renderer)
            local text = config.text or ''
            if text == '' then
                return { width, 16 }
            end
            local indent = (config.indent or 0) * INDENT_PX
            local style = table.clone(UIFontSettings.body)
            style.font_size = 15
            style.size = { width - indent - 8, 1000 }
            style.text_horizontal_alignment = 'left'
            style.text_vertical_alignment = 'top'
            style.offset = { 0, 0, 0 }
            local ok, h = pcall(Text.text_height, ui_renderer, text, style, nil, true)
            return { width, math.max(ok and h or 16, 16) + 4 }
        end,
        pass_template_function = function(_, config)
            local indent = (config.indent or 0) * INDENT_PX
            local style = table.clone(UIFontSettings.body)
            style.font_size = 15
            style.text_vertical_alignment = 'top'
            style.text_horizontal_alignment = 'left'
            style.text_color = Shared.colors.value
            style.word_wrap = true
            style.offset = { indent + 8, 0, 2 }
            style.size = { width - indent - 8, 2000 }
            return {
                {
                    pass_type = 'text',
                    value_id = 'text',
                    style = style,
                },
            }
        end,
        init = function(_, widget, element)
            widget.content.text = element.text or ''
        end,
    }

    return blueprints
end

return make_blueprints
