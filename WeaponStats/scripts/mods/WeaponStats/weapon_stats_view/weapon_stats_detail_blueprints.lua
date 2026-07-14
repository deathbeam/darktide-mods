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
local COLOR_STRIPE = { 120, 49, 56, 49 }
local STRIPE_BLEED_LEFT = 20
local STRIPE_BLEED_RIGHT = 30

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
        size = { width, 36 },
        pass_template = {
            {
                pass_type = 'text',
                style_id = 'text',
                value_id = 'text',
                value = '',
                style = {
                    font_type = 'proxima_nova_bold',
                    font_size = 22,
                    text_vertical_alignment = 'top',
                    text_horizontal_alignment = 'left',
                    offset = { 0, 0, 2 },
                    size = { width, 30 },
                },
            },
            {
                pass_type = 'rect',
                style_id = 'rule',
                style = {
                    color = COLOR_RULE,
                    offset = { 0, 30, 1 },
                    size = { width, 2 },
                },
            },
        },
        init = function(_, widget, element)
            widget.content.text = element.text or ''
            local style = widget.style.text
            if element.color then
                style.text_color = element.color
            end
        end,
    }

    blueprints.attack = {
        size = { width, 28 },
        pass_template = {
            {
                pass_type = 'text',
                style_id = 'text',
                value_id = 'text',
                value = '',
                style = {
                    font_type = 'proxima_nova_bold',
                    font_size = 19,
                    text_vertical_alignment = 'top',
                    text_horizontal_alignment = 'left',
                    offset = { 0, 0, 2 },
                    size = { width, 26 },
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

    blueprints.subheader = {
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
                    offset = { 0, 0, 2 },
                    size = { width, 22 },
                },
            },
        },
        init = function(_, widget, element)
            widget.content.text = element.text or ''
            local style = widget.style.text
            if element.color then
                style.text_color = element.color
            end
            style.offset[1] = (element.indent or 0) * INDENT_PX
        end,
    }

    blueprints.stat = {
        size = { width, STAT_ROW_HEIGHT },
        pass_template = {
            {
                pass_type = 'rect',
                style_id = 'stripe',
                style = {
                    color = COLOR_STRIPE,
                    offset = { -STRIPE_BLEED_LEFT, 0, 0 },
                    size = { width + STRIPE_BLEED_LEFT + STRIPE_BLEED_RIGHT, STAT_ROW_HEIGHT },
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
                style = {
                    font_type = 'proxima_nova_bold',
                    font_size = 16,
                    text_vertical_alignment = 'center',
                    text_horizontal_alignment = 'left',
                    text_color = COLOR_LABEL,
                    offset = { 0, 0, 2 },
                    size = { width * 0.55, STAT_ROW_HEIGHT },
                    text_overflow_mode = 'truncate',
                },
            },
            {
                pass_type = 'text',
                style_id = 'value',
                value_id = 'value',
                value = '',
                style = {
                    font_type = 'proxima_nova_bold',
                    font_size = 16,
                    text_vertical_alignment = 'center',
                    text_horizontal_alignment = 'left',
                    text_color = COLOR_VALUE,
                    offset = { width * 0.55, 0, 2 },
                    size = { width * 0.45, STAT_ROW_HEIGHT },
                    text_overflow_mode = 'truncate',
                },
            },
        },
        init = function(_, widget, element)
            local content = widget.content
            content.label = element.label or ''
            content.value = element.value or ''
            content.stripe = element.stripe == true
            local style = widget.style
            style.label.offset[1] = (element.indent or 0) * INDENT_PX
            if element.label_color then
                style.label.text_color = element.label_color
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
            local rows = config.record.rows or {}
            return { width, TABLE_HEADER_HEIGHT + #rows * TABLE_ROW_HEIGHT }
        end,
        pass_template_function = function(_, config)
            local record = config.record
            return _table_passes(width, record.columns or {}, record.rows or {})
        end,
    }

    return blueprints
end

return make_blueprints
