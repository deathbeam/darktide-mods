local mod = get_mod('WeaponStats')
local Text = mod:original_require('scripts/utilities/ui/text')
local UIFontSettings = mod:original_require('scripts/managers/ui/ui_font_settings')
local INDENT_PX = 18
local STAT_ROW_HEIGHT = 21
local TABLE_HEADER_HEIGHT = 26
local TABLE_ROW_HEIGHT = 22
local TABLE_NAME_WIDTH = 150
local TABLE_FRAME_COLOR = Color.terminal_frame(180, true)
local TABLE_CORNER_COLOR = Color.terminal_corner(180, true)
local TABLE_BG_COLOR = Color.terminal_grid_background(90, true)
local TABLE_HEADER_BG_COLOR = Color.terminal_grid_background(160, true)
local TABLE_GRID_COLOR = Color.terminal_frame(50, true)
local COLOR_LABEL = Color.terminal_text_header(255, true)
local COLOR_VALUE = Color.terminal_text_header(255, true)
local COLOR_RULE = Color.terminal_corner(120, true)
local COLOR_STRIPE = Color.terminal_grid_background(60, true)
local STAT_LABEL_FONT_SIZE = 16
local STAT_VALUE_FONT_SIZE = 16
local STAT_ICON_SIZE = 32
local STAT_ICON_GAP = 8
local STAT_VALUE_TOP_OFFSET = 20
local STAT_WRAP_PAD = 6

local SECTION_LEVELS = {
    { height = 36, font_size = 22, rule = true },
    { height = 28, font_size = 19, rule = false },
    { height = 22, font_size = 16, rule = false },
}

local CHAIN_ICON_SIZE = 28
local CHAIN_ICON_SPACING = 6
local CHAIN_ROW_HEIGHT = 34

local GESTALT_ICONS = {
    activate = 'content/ui/materials/icons/weapons/actions/activate',
    ads = 'content/ui/materials/icons/weapons/actions/ads',
    brace = 'content/ui/materials/icons/weapons/actions/brace',
    charge = 'content/ui/materials/icons/weapons/actions/charge',
    defence = 'content/ui/materials/icons/weapons/actions/defence',
    flashlight = 'content/ui/materials/icons/weapons/actions/flashlight',
    hipfire = 'content/ui/materials/icons/weapons/actions/hipfire',
    linesman = 'content/ui/materials/icons/weapons/actions/linesman',
    melee = 'content/ui/materials/icons/weapons/actions/melee',
    melee_hand = 'content/ui/materials/icons/weapons/actions/melee_hand',
    ninja_fencer = 'content/ui/materials/icons/weapons/actions/ninjafencer',
    quick_grenade = 'content/ui/materials/icons/weapons/actions/quick_grenade',
    smiter = 'content/ui/materials/icons/weapons/actions/smiter',
    special_attack = 'content/ui/materials/icons/weapons/actions/special_attack',
    special_bullet = 'content/ui/materials/icons/weapons/actions/special_bullet',
    tank = 'content/ui/materials/icons/weapons/actions/tank',
    vent = 'content/ui/materials/icons/weapons/actions/vent',
}

local SPACER_HEIGHT = {
    group = 10,
    tight = 4,
}

-- Builds the complete pass_template for the damage/ADM table (background, frame,
-- separators, column headers, and all data cells) as one widget sized to its content.
local function _table_passes(width, columns, rows)
    local num_columns = #columns
    local num_rows = #rows
    local cell_area_width = width - TABLE_NAME_WIDTH
    local column_width = num_columns > 0 and math.floor(cell_area_width / num_columns) or 0
    local header_height = TABLE_HEADER_HEIGHT
    local row_height = TABLE_ROW_HEIGHT
    local total_height = header_height + num_rows * row_height
    local passes = {}

    passes[#passes + 1] = {
        pass_type = 'rect',
        style_id = 'background',
        style = {
            color = TABLE_BG_COLOR,
            offset = { 0, 0, 0 },
            size = { width, total_height },
        },
    }
    passes[#passes + 1] = {
        pass_type = 'texture',
        style_id = 'frame',
        value = 'content/ui/materials/frames/frame_tile_2px',
        style = {
            scale_to_material = true,
            color = TABLE_FRAME_COLOR,
            offset = { 0, 0, 3 },
            size = { width, total_height },
        },
    }
    passes[#passes + 1] = {
        pass_type = 'texture',
        style_id = 'corner',
        value = 'content/ui/materials/frames/frame_corner_2px',
        style = {
            scale_to_material = true,
            color = TABLE_CORNER_COLOR,
            offset = { 0, 0, 4 },
            size = { width, total_height },
        },
    }
    passes[#passes + 1] = {
        pass_type = 'rect',
        style_id = 'header_band',
        style = {
            color = TABLE_HEADER_BG_COLOR,
            offset = { 0, 0, 1 },
            size = { width, header_height },
        },
    }
    passes[#passes + 1] = {
        pass_type = 'rect',
        style_id = 'header_separator',
        style = {
            color = TABLE_GRID_COLOR,
            offset = { 0, header_height - 1, 2 },
            size = { width, 2 },
        },
    }
    passes[#passes + 1] = {
        pass_type = 'rect',
        style_id = 'name_separator',
        style = {
            color = TABLE_GRID_COLOR,
            offset = { TABLE_NAME_WIDTH - 1, 0, 2 },
            size = { 2, total_height },
        },
    }
    for col_index = 1, num_columns - 1 do
        local x = TABLE_NAME_WIDTH + col_index * column_width - 1
        passes[#passes + 1] = {
            pass_type = 'rect',
            style_id = 'col_sep_' .. col_index,
            style = {
                color = TABLE_GRID_COLOR,
                offset = { x, 0, 2 },
                size = { 2, total_height },
            },
        }
    end
    for col_index = 1, num_columns do
        local column = columns[col_index]
        local x = TABLE_NAME_WIDTH + (col_index - 1) * column_width
        passes[#passes + 1] = {
            pass_type = 'text',
            style_id = 'col_' .. col_index,
            value_id = 'col_' .. col_index,
            value = column and column.label or '',
            style = {
                font_type = 'proxima_nova_bold',
                font_size = 15,
                text_vertical_alignment = 'center',
                text_horizontal_alignment = 'center',
                text_color = (column and column.color) or COLOR_LABEL,
                offset = { x, 0, 5 },
                size = { column_width, header_height },
                text_overflow_mode = 'truncate',
            },
        }
    end
    for row_index = 1, num_rows do
        local row = rows[row_index]
        local cells = row.cells or {}
        local y = header_height + (row_index - 1) * row_height
        passes[#passes + 1] = {
            pass_type = 'text',
            style_id = 'name_' .. row_index,
            value_id = 'name_' .. row_index,
            value = row.name or '',
            style = {
                font_type = 'proxima_nova_bold',
                font_size = 15,
                text_vertical_alignment = 'center',
                text_horizontal_alignment = 'left',
                text_color = row.name_color or COLOR_LABEL,
                offset = { 6, y, 5 },
                size = { TABLE_NAME_WIDTH - 12, row_height },
                text_overflow_mode = 'truncate',
            },
        }
        for col_index = 1, num_columns do
            local cell = cells[col_index] or {}
            local x = TABLE_NAME_WIDTH + (col_index - 1) * column_width
            passes[#passes + 1] = {
                pass_type = 'text',
                style_id = 'cell_' .. row_index .. '_' .. col_index,
                value_id = 'cell_' .. row_index .. '_' .. col_index,
                value = cell.text or '',
                style = {
                    font_type = 'proxima_nova_bold',
                    font_size = 15,
                    text_vertical_alignment = 'center',
                    text_horizontal_alignment = 'center',
                    text_color = cell.color or COLOR_VALUE,
                    offset = { x, y, 5 },
                    size = { column_width, row_height },
                    text_overflow_mode = 'truncate',
                },
            }
        end
    end
    return passes
end

-- Detail-grid blueprints. Each widget_type maps to a builder record type.
-- The grid drives layout/scroll/mask; blueprints only define visual passes + init.
local function make_blueprints(width)
    local blueprints = {}

    blueprints.spacer = {
        size_function = function(_, config)
            return { width, SPACER_HEIGHT[config.size or 'tight'] or 8 }
        end,
        pass_template = {
            {
                pass_type = 'rect',
                style = { color = { 0, 0, 0, 0 } },
            },
        },
    }

    blueprints.header = {
        size = { width, 42 },
        pass_template = {
            {
                pass_type = 'text',
                style_id = 'text',
                value_id = 'text',
                value = '',
                style = {
                    font_type = 'proxima_nova_bold',
                    font_size = 26,
                    text_vertical_alignment = 'top',
                    text_horizontal_alignment = 'left',
                    text_color = Color.terminal_text_header(255, true),
                    offset = { 0, 0, 2 },
                    size = { width, 38 },
                    text_overflow_mode = 'truncate',
                },
            },
        },
        init = function(_, widget, element)
            widget.content.text = element.text or ''
            if element.color then
                widget.style.text.text_color = element.color
            end
        end,
    }

    blueprints.header_icon = {
        size = { width, 130 },
        pass_template = {
            {
                pass_type = 'texture',
                style_id = 'icon',
                value_id = 'icon',
                value = 'content/ui/materials/base/ui_default_base',
                style = {
                    horizontal_alignment = 'left',
                    vertical_alignment = 'center',
                    size = { 192, 96 },
                    color = Color.terminal_text_body(255, true),
                    offset = { 10, 0, 2 },
                },
                visibility_function = function(content)
                    return content.icon ~= nil
                end,
            },
            {
                pass_type = 'text',
                style_id = 'text',
                value_id = 'text',
                value = '',
                style = {
                    font_type = 'proxima_nova_bold',
                    font_size = 26,
                    text_vertical_alignment = 'bottom',
                    text_horizontal_alignment = 'left',
                    text_color = Color.terminal_text_header(255, true),
                    offset = { 200, 0, 2 },
                    size = { width - 200, 80 },
                    text_overflow_mode = 'truncate',
                },
            },
            {
                pass_type = 'text',
                style_id = 'subtext',
                value_id = 'subtext',
                value = '',
                style = {
                    font_type = 'proxima_nova_bold',
                    font_size = 18,
                    text_vertical_alignment = 'top',
                    text_horizontal_alignment = 'left',
                    text_color = Color.terminal_text_body_sub_header(255, true),
                    offset = { 200, 78, 3 },
                    size = { width - 200, 50 },
                    text_overflow_mode = 'truncate',
                },
            },
        },
        init = function(_, widget, element)
            widget.content.text = element.text or ''
            widget.content.icon = element.icon
            widget.content.subtext = element.subtext or ''
            if element.color then
                widget.style.text.text_color = element.color
            end
        end,
    }

    blueprints.subtext = {
        size = { width, 22 },
        pass_template = {
            {
                pass_type = 'text',
                style_id = 'text',
                value_id = 'text',
                value = '',
                style = {
                    font_type = 'proxima_nova_bold',
                    font_size = 16,
                    text_vertical_alignment = 'top',
                    text_horizontal_alignment = 'left',
                    text_color = Color.terminal_text_body_sub_header(255, true),
                    offset = { 0, 0, 2 },
                    size = { width, 22 },
                    text_overflow_mode = 'truncate',
                },
            },
        },
        init = function(_, widget, element)
            widget.content.text = element.text or ''
            if element.color then
                widget.style.text.text_color = element.color
            end
        end,
    }

    blueprints.section = {
        size_function = function(_, config)
            return { width, SECTION_LEVELS[config.level or 1].height }
        end,
        pass_template_function = function(_, config)
            local level = SECTION_LEVELS[config.level or 1]
            local passes = {
                {
                    pass_type = 'text',
                    style_id = 'text',
                    value_id = 'text',
                    value = '',
                    style = {
                        font_type = 'proxima_nova_bold',
                        font_size = level.font_size,
                        text_vertical_alignment = 'top',
                        text_horizontal_alignment = 'left',
                        offset = { 0, 0, 2 },
                        size = { width, level.height - (level.rule and 6 or 0) },
                    },
                },
            }
            if level.rule then
                passes[#passes + 1] = {
                    pass_type = 'rect',
                    style_id = 'rule',
                    style = {
                        color = COLOR_RULE,
                        offset = { 0, level.height - 6, 1 },
                        size = { width, 2 },
                    },
                }
            end
            return passes
        end,
        init = function(_, widget, element)
            widget.content.text = element.text or ''
            local style = widget.style.text
            if element.color then
                style.text_color = element.color
            end
            style.offset[1] = (element.indent or 0) * INDENT_PX
        end,
    }

    local function _measure_text(ui_renderer, text, font_size, max_width)
        if not ui_renderer or text == '' then
            return 0
        end
        local style = table.clone(UIFontSettings.body)
        style.font_size = font_size
        style.size = { max_width, 1000 }
        style.text_horizontal_alignment = 'left'
        style.text_vertical_alignment = 'top'
        style.offset = { 0, 0, 0 }
        local ok, h = pcall(Text.text_height, ui_renderer, text, style, nil, true)
        return ok and h or 0
    end

    blueprints.stat = {
        size_function = function(_, config, ui_renderer)
            if not config.wrap then
                return { width, STAT_ROW_HEIGHT }
            end
            local content_x = config.icon and (STAT_ICON_SIZE + STAT_ICON_GAP) or 0
            local value_w = width - content_x
            local value_h = _measure_text(ui_renderer, config.value or '', STAT_VALUE_FONT_SIZE, value_w)
            local h = STAT_VALUE_TOP_OFFSET + math.max(STAT_VALUE_FONT_SIZE, value_h) + STAT_WRAP_PAD
            return { width, math.max(STAT_ROW_HEIGHT, h) }
        end,
        pass_template_function = function(_, config)
            local content_x = config.icon and (STAT_ICON_SIZE + STAT_ICON_GAP) or 0
            local value_w = width - content_x
            local passes = {
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
            }
            if config.icon then
                passes[#passes + 1] = {
                    pass_type = 'texture',
                    style_id = 'icon',
                    value = 'content/ui/materials/icons/traits/traits_container',
                    style = {
                        horizontal_alignment = 'left',
                        vertical_alignment = 'top',
                        size = { STAT_ICON_SIZE, STAT_ICON_SIZE },
                        offset = { 0, 0, 3 },
                        color = Color.terminal_icon(255, true),
                        material_values = { icon = 'content/ui/textures/icons/traits/weapon_trait_unknown' },
                    },
                    visibility_function = function(content)
                        return content.has_icon == true
                    end,
                }
            end
            local label_style = table.clone(UIFontSettings.header_3)
            label_style.font_size = STAT_LABEL_FONT_SIZE
            label_style.text_vertical_alignment = 'top'
            label_style.text_horizontal_alignment = 'left'
            label_style.text_color = COLOR_LABEL
            label_style.offset = { content_x, 0, 2 }
            label_style.size = { value_w, STAT_LABEL_FONT_SIZE }
            label_style.text_overflow_mode = 'truncate'
            passes[#passes + 1] = {
                pass_type = 'text',
                style_id = 'label',
                value_id = 'label',
                value = '',
                style = label_style,
            }
            if config.wrap then
                local value_style = table.clone(UIFontSettings.body)
                value_style.font_size = STAT_VALUE_FONT_SIZE
                value_style.text_vertical_alignment = 'top'
                value_style.text_horizontal_alignment = 'left'
                value_style.text_color = COLOR_VALUE
                value_style.offset = { content_x, STAT_VALUE_TOP_OFFSET, 2 }
                value_style.size = { value_w, 1000 }
                value_style.text_overflow_mode = 'wrap'
                passes[#passes + 1] = {
                    pass_type = 'text',
                    style_id = 'value',
                    value_id = 'value',
                    value = '',
                    style = value_style,
                }
            else
                local value_style = table.clone(UIFontSettings.header_3)
                value_style.font_size = STAT_VALUE_FONT_SIZE
                value_style.text_vertical_alignment = 'center'
                value_style.text_horizontal_alignment = 'left'
                value_style.text_color = COLOR_VALUE
                value_style.offset = { width * 0.55, 0, 2 }
                value_style.size = { width * 0.45, STAT_ROW_HEIGHT }
                value_style.text_overflow_mode = 'truncate'
                passes[#passes + 1] = {
                    pass_type = 'text',
                    style_id = 'value',
                    value_id = 'value',
                    value = '',
                    style = value_style,
                }
            end
            return passes
        end,
        init = function(_, widget, element)
            local content = widget.content
            content.label = element.label or ''
            content.value = element.value or ''
            content.stripe = element.stripe == true
            local style = widget.style
            local indent_x = (element.indent or 0) * INDENT_PX
            style.label.offset[1] = indent_x + (element.icon and (STAT_ICON_SIZE + STAT_ICON_GAP) or 0)
            if not element.wrap then
                style.value.offset[1] = indent_x + width * 0.55
            else
                style.value.offset[1] = style.label.offset[1]
            end
            if element.label_color then
                style.label.text_color = element.label_color
            end
            if element.value_color then
                style.value.text_color = element.value_color
            end
            if element.icon then
                content.has_icon = true
                style.icon.material_values.icon = element.icon
                if element.icon_frame then
                    style.icon.material_values.frame = element.icon_frame
                end
            end
        end,
    }

    blueprints.chain = {
        size = { width, CHAIN_ROW_HEIGHT },
        pass_template_function = function(_, config)
            local chain = config.chain or {}
            local passes = {
                {
                    pass_type = 'text',
                    style_id = 'title',
                    value_id = 'title',
                    value = config.title or '',
                    style = {
                        font_type = 'proxima_nova_bold',
                        font_size = 16,
                        text_vertical_alignment = 'center',
                        text_horizontal_alignment = 'left',
                        text_color = COLOR_LABEL,
                        offset = { 0, 0, 2 },
                        size = { width * 0.3, CHAIN_ROW_HEIGHT },
                        text_overflow_mode = 'truncate',
                    },
                },
            }
            local icon_area_x = width * 0.3 + 10
            local step = CHAIN_ICON_SIZE + CHAIN_ICON_SPACING
            for i = 1, #chain do
                local gestalt = chain[i]
                local icon = gestalt and GESTALT_ICONS[gestalt] or nil
                if icon then
                    local x = icon_area_x + (i - 1) * step
                    passes[#passes + 1] = {
                        pass_type = 'texture',
                        style_id = 'icon_' .. i,
                        value = icon,
                        style = {
                            horizontal_alignment = 'left',
                            vertical_alignment = 'center',
                            offset = { x, 0, 2 },
                            size = { CHAIN_ICON_SIZE, CHAIN_ICON_SIZE },
                            color = Color.terminal_text_body(255, true),
                        },
                    }
                end
            end
            return passes
        end,
    }

    blueprints.table = {
        size_function = function(_, config)
            local rows = config.rows or {}
            return { width, TABLE_HEADER_HEIGHT + #rows * TABLE_ROW_HEIGHT }
        end,
        pass_template_function = function(_, config)
            return _table_passes(width, config.columns or {}, config.rows or {})
        end,
    }

    return blueprints
end

return make_blueprints
