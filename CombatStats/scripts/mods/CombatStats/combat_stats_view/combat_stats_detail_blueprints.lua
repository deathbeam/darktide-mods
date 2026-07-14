local BAR_HEIGHT = 20
local BAR_WIDGET_HEIGHT = 30
local ICON_SIZE = 24
local ICON_SPACING = 5
local TEXT_PADDING = 10

local COLOR_LABEL = Color.terminal_text_body(255, true)
local COLOR_BAR_BG = { 100, 50, 50, 50 }

local function make_blueprints(width)
    local blueprints = {}

    blueprints.spacer = {
        size_function = function(_, config)
            return { width, config.height or 10 }
        end,
        pass_template = {
            {
                pass_type = 'rect',
                style = { color = { 0, 0, 0, 0 } },
            },
        },
    }

    blueprints.header = {
        size_function = function(_, config)
            return { width, (config.font_size or 26) + TEXT_PADDING }
        end,
        pass_template_function = function(_, config)
            local font_size = config.font_size or 26
            return {
                {
                    pass_type = 'text',
                    style_id = 'text',
                    value_id = 'text',
                    value = config.text or '',
                    style = {
                        font_type = 'proxima_nova_bold',
                        font_size = font_size,
                        text_vertical_alignment = 'top',
                        text_horizontal_alignment = 'left',
                        text_color = config.color or Color.terminal_text_body(255, true),
                        offset = { 0, 0, 2 },
                        size = { width, font_size + TEXT_PADDING },
                    },
                },
            }
        end,
    }

    blueprints.subtext = {
        size_function = function(_, config)
            return { width, (config.font_size or 18) + TEXT_PADDING }
        end,
        pass_template_function = function(_, config)
            local font_size = config.font_size or 18
            return {
                {
                    pass_type = 'text',
                    style_id = 'text',
                    value_id = 'text',
                    value = config.text or '',
                    style = {
                        font_type = 'proxima_nova_bold',
                        font_size = font_size,
                        text_vertical_alignment = 'top',
                        text_horizontal_alignment = 'left',
                        text_color = config.color or Color.terminal_text_body_sub_header(255, true),
                        offset = { 0, 0, 2 },
                        size = { width, font_size + TEXT_PADDING },
                    },
                },
            }
        end,
    }

    blueprints.section = {
        size = { width, 30 },
        pass_template = {
            {
                pass_type = 'text',
                style_id = 'text',
                value_id = 'text',
                value = '',
                style = {
                    font_type = 'proxima_nova_bold',
                    font_size = 20,
                    text_vertical_alignment = 'top',
                    text_horizontal_alignment = 'left',
                    text_color = Color.terminal_text_header(255, true),
                    offset = { 0, 0, 2 },
                    size = { width, 30 },
                },
            },
        },
        init = function(_, widget, element)
            widget.content.text = element.text or ''
        end,
    }

    blueprints.text = {
        size_function = function(_, config)
            return { width, (config.font_size or 18) + TEXT_PADDING }
        end,
        pass_template_function = function(_, config)
            local font_size = config.font_size or 18
            return {
                {
                    pass_type = 'text',
                    style_id = 'text',
                    value_id = 'text',
                    value = config.text or '',
                    style = {
                        font_type = 'proxima_nova_bold',
                        font_size = font_size,
                        text_vertical_alignment = 'top',
                        text_horizontal_alignment = 'left',
                        text_color = config.color or COLOR_LABEL,
                        offset = { 0, 0, 2 },
                        size = { width, font_size + TEXT_PADDING },
                    },
                },
            }
        end,
    }

    blueprints.substat = {
        size = { width, 28 },
        pass_template = {
            {
                pass_type = 'text',
                style_id = 'text',
                value_id = 'text',
                value = '',
                style = {
                    font_type = 'proxima_nova_bold',
                    font_size = 16,
                    text_vertical_alignment = 'center',
                    text_horizontal_alignment = 'left',
                    text_color = Color.terminal_text_body_sub_header(255, true),
                    offset = { 20, 0, 2 },
                    size = { width - 20, 28 },
                    text_overflow_mode = 'truncate',
                },
            },
        },
        init = function(_, widget, element)
            widget.content.text = element.text or ''
        end,
    }

    blueprints.progress_bar = {
        size = { width, BAR_WIDGET_HEIGHT },
        pass_template_function = function(_, config)
            local has_icon = config.icon ~= nil
            local icon_size = has_icon and ICON_SIZE or 0
            local icon_spacing = has_icon and ICON_SPACING or 0
            local label_width = width * 0.5 - icon_size - icon_spacing
            local bar_x = width * 0.5 + 10
            local bar_width = width * 0.5 - 20
            local passes = {}

            if has_icon then
                passes[#passes + 1] = {
                    pass_type = 'texture',
                    style_id = 'icon',
                    value = 'content/ui/materials/icons/buffs/hud/buff_container_with_background',
                    style = {
                        horizontal_alignment = 'left',
                        vertical_alignment = 'center',
                        offset = { 0, 0, 2 },
                        size = { ICON_SIZE, ICON_SIZE },
                        color = Color.white(255, true),
                        material_values = {
                            talent_icon = config.icon,
                            gradient_map = config.gradient_map,
                        },
                    },
                }
            end

            passes[#passes + 1] = {
                pass_type = 'text',
                style_id = 'label',
                value_id = 'label',
                value = config.label or '',
                style = {
                    font_type = 'proxima_nova_bold',
                    font_size = 16,
                    text_vertical_alignment = 'center',
                    text_horizontal_alignment = 'left',
                    text_color = COLOR_LABEL,
                    offset = { icon_size + icon_spacing, 0, 2 },
                    size = { label_width, BAR_HEIGHT },
                    text_overflow_mode = 'truncate',
                },
            }

            passes[#passes + 1] = {
                pass_type = 'rect',
                style_id = 'bar_bg',
                style = {
                    offset = { bar_x, 0, 1 },
                    size = { bar_width, BAR_HEIGHT },
                    color = COLOR_BAR_BG,
                },
            }

            passes[#passes + 1] = {
                pass_type = 'rect',
                style_id = 'bar',
                style = {
                    offset = { bar_x, 0, 2 },
                    size = { bar_width, BAR_HEIGHT },
                    color = config.color or Color.ui_terminal(255, true),
                },
            }

            passes[#passes + 1] = {
                pass_type = 'text',
                style_id = 'percentage',
                value_id = 'percentage',
                value = '',
                style = {
                    font_type = 'proxima_nova_bold',
                    font_size = 14,
                    text_vertical_alignment = 'center',
                    text_horizontal_alignment = 'center',
                    text_color = Color.white(255, true),
                    offset = { bar_x, 0, 3 },
                    size = { bar_width, BAR_HEIGHT },
                },
            }

            return passes
        end,
        init = function(_, widget, element)
            local value = element.value or 0
            local max_value = element.max_value or 0
            local pct = max_value > 0 and math.min(value / max_value, 1.0) or 0
            local bar_width = width * 0.5 - 20

            widget.content.percentage = string.format('%.1f%%', pct * 100)
            widget.style.bar.size[1] = bar_width * pct
        end,
    }

    return blueprints
end

return make_blueprints
