-- Common detail-grid blueprints shared across the stats mods: spacer, header,
-- subtext, section, and the framed table pass builder. Each mod merges these
-- with its own blueprints (stat, chain, header_icon, body diagram, etc.).
-- `colors` is the unified palette; mods use it for their unique blueprints too.

local INDENT_PX = 18

local colors = {
    label = Color.terminal_text_body(255, true),
    value = Color.terminal_text_header(255, true),
    header = Color.terminal_text_header(255, true),
    subtext = Color.terminal_text_body_sub_header(255, true),
    rule = Color.terminal_corner(120, true),
    table_bg = Color.terminal_grid_background(90, true),
    table_frame = Color.terminal_frame(180, true),
    table_corner = Color.terminal_corner(180, true),
    table_header_bg = Color.terminal_grid_background(160, true),
    table_grid = Color.terminal_frame(50, true),
}

local SPACER_HEIGHT = {
    group = 10,
    tight = 4,
}

local SECTION_LEVELS = {
    { height = 36, font_size = 22, rule = true },
    { height = 28, font_size = 19, rule = false },
    { height = 22, font_size = 16, rule = false },
}

local TABLE_NAME_WIDTH = 150
local TABLE_HEADER_HEIGHT = 26
local TABLE_ROW_HEIGHT = 22

local function make_table_passes(width, columns, rows, config)
    config = config or {}
    local name_column_label = config.name_column_label
    local origin_x = config.origin_x or 0

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
            color = colors.table_bg,
            offset = { origin_x, 0, 0 },
            size = { width, total_height },
        },
    }
    passes[#passes + 1] = {
        pass_type = 'texture',
        style_id = 'frame',
        value = 'content/ui/materials/frames/frame_tile_2px',
        style = {
            scale_to_material = true,
            color = colors.table_frame,
            offset = { origin_x, 0, 3 },
            size = { width, total_height },
        },
    }
    passes[#passes + 1] = {
        pass_type = 'texture',
        style_id = 'corner',
        value = 'content/ui/materials/frames/frame_corner_2px',
        style = {
            scale_to_material = true,
            color = colors.table_corner,
            offset = { origin_x, 0, 4 },
            size = { width, total_height },
        },
    }
    passes[#passes + 1] = {
        pass_type = 'rect',
        style_id = 'header_band',
        style = {
            color = colors.table_header_bg,
            offset = { origin_x, 0, 1 },
            size = { width, header_height },
        },
    }
    passes[#passes + 1] = {
        pass_type = 'rect',
        style_id = 'header_separator',
        style = {
            color = colors.table_grid,
            offset = { origin_x, header_height - 1, 2 },
            size = { width, 2 },
        },
    }
    passes[#passes + 1] = {
        pass_type = 'rect',
        style_id = 'name_separator',
        style = {
            color = colors.table_grid,
            offset = { origin_x + TABLE_NAME_WIDTH - 1, 0, 2 },
            size = { 2, total_height },
        },
    }
    for col_index = 1, num_columns - 1 do
        local x = TABLE_NAME_WIDTH + col_index * column_width - 1
        passes[#passes + 1] = {
            pass_type = 'rect',
            style_id = 'col_sep_' .. col_index,
            style = {
                color = colors.table_grid,
                offset = { origin_x + x, 0, 2 },
                size = { 2, total_height },
            },
        }
    end

    if name_column_label ~= nil then
        passes[#passes + 1] = {
            pass_type = 'text',
            style_id = 'col_name',
            value_id = 'col_name',
            value = name_column_label,
            style = {
                font_type = 'proxima_nova_bold',
                font_size = 15,
                text_vertical_alignment = 'center',
                text_horizontal_alignment = 'left',
                text_color = colors.label,
                offset = { origin_x + 6, 0, 5 },
                size = { TABLE_NAME_WIDTH - 12, header_height },
                text_overflow_mode = 'truncate',
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
                text_color = (column and column.color) or colors.label,
                offset = { origin_x + x, 0, 5 },
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
                text_color = row.name_color or colors.label,
                offset = { origin_x + 6, y, 5 },
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
                    text_color = cell.color or colors.value,
                    offset = { origin_x + x, y, 5 },
                    size = { column_width, row_height },
                    text_overflow_mode = 'truncate',
                },
            }
        end
    end
    return passes
end

-- Total widget height for a table with `num_rows` data rows (header + rows).

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

    blueprints.header_icon = {
        size = { width, 96 },
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
                    text_color = colors.header,
                    offset = { 200, 0, 2 },
                    size = { width - 200, 60 },
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
                    text_color = colors.subtext,
                    offset = { 200, 58, 3 },
                    size = { width - 200, 30 },
                    text_overflow_mode = 'truncate',
                },
            },
        },
        init = function(_, widget, element)
            widget.content.text = element.text or ''
            widget.content.icon = element.icon
            widget.content.subtext = element.subtext or ''

            local icon_size = element.icon_size or { 192, 96 }
            local icon_margin = 10

            widget.style.icon.size = icon_size

            if element.icon then
                local text_x = icon_size[1] + icon_margin
                widget.style.text.offset[1] = text_x
                widget.style.text.size[1] = width - text_x
                widget.style.subtext.offset[1] = text_x
                widget.style.subtext.size[1] = width - text_x
            else
                widget.style.text.offset[1] = icon_margin
                widget.style.text.size[1] = width - icon_margin
                widget.style.subtext.offset[1] = icon_margin
                widget.style.subtext.size[1] = width - icon_margin
            end

            if element.color then
                widget.style.text.text_color = element.color
            end
            if element.subtext_color then
                widget.style.subtext.text_color = element.subtext_color
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
                        text_color = colors.header,
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
                        color = colors.rule,
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

    return blueprints
end

local function table_height(num_rows)
    return TABLE_HEADER_HEIGHT + num_rows * TABLE_ROW_HEIGHT
end

return {
    make_blueprints = make_blueprints,
    make_table_passes = make_table_passes,
    table_height = table_height,
    colors = colors,
}
