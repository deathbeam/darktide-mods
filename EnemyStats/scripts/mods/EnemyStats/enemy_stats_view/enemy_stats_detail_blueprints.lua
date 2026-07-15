local STAT_ROW_HEIGHT = 21
local TABLE_HEADER_HEIGHT = 26
local TABLE_ROW_HEIGHT = 22
local TABLE_NAME_WIDTH = 150
local TABLE_FRAME_COLOR = Color.terminal_frame(180, true)
local TABLE_CORNER_COLOR = Color.terminal_frame(180, true)
local TABLE_BG_COLOR = Color.terminal_grid_background(90, true)
local TABLE_HEADER_BG_COLOR = Color.terminal_grid_background(160, true)
local TABLE_GRID_COLOR = Color.terminal_frame(50, true)
local COLOR_LABEL = Color.terminal_text_body(255, true)
local COLOR_VALUE = Color.terminal_text_header(255, true)
local COLOR_RULE = Color.terminal_frame(120, true)

local SPACER_HEIGHT = {
    group = 10,
    tight = 4,
}

-- Humanoid body diagram: rect passes laid out as a silhouette, each part colored
-- by its zone armor type. Shown beside the hit-zone table for humanoid breeds.
local BODY_W = 180
local BODY_GAP = 10
local BODY_BG = { 80, 18, 18, 18 }
local BODY_FRAME = Color.terminal_frame(100, true)
local PART_BORDER = { 120, 0, 0, 0 }

-- Zone key to { cx, cy, w, h }: center coordinates relative to the canvas center,
-- scaled to a -1..1 range so the silhouette stretches to the diagram height.
local BODY_PARTS = {
    head = { 0, -0.82, 0.19, 0.12 },
    torso = { 0, -0.46, 0.33, 0.18 },
    center_mass = { 0, -0.46, 0.33, 0.08 },
    upper_left_arm = { -0.47, -0.44, 0.10, 0.18 },
    lower_left_arm = { -0.47, -0.06, 0.09, 0.16 },
    upper_right_arm = { 0.47, -0.44, 0.10, 0.18 },
    lower_right_arm = { 0.47, -0.06, 0.09, 0.16 },
    upper_left_leg = { -0.18, 0.0, 0.16, 0.18 },
    lower_left_leg = { -0.18, 0.36, 0.14, 0.18 },
    upper_right_leg = { 0.18, 0.0, 0.16, 0.18 },
    lower_right_leg = { 0.18, 0.36, 0.14, 0.18 },
}

-- Generic 3-column table: name + 2 value columns, sized to its content.
local function _stat_table_passes(width, columns, rows, difficulty_header)
    local num_value_cols = #columns
    local cell_area_width = width - TABLE_NAME_WIDTH
    local col_width = num_value_cols > 0 and math.floor(cell_area_width / num_value_cols) or 0
    local header_height = TABLE_HEADER_HEIGHT
    local row_height = TABLE_ROW_HEIGHT
    local total_height = header_height + #rows * row_height
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
    for col_index = 1, num_value_cols - 1 do
        local x = TABLE_NAME_WIDTH + col_index * col_width - 1
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

    -- Difficulty label header for the first column.
    passes[#passes + 1] = {
        pass_type = 'text',
        style_id = 'col_difficulty',
        value_id = 'col_difficulty',
        value = difficulty_header or 'Difficulty',
        style = {
            font_type = 'proxima_nova_bold',
            font_size = 15,
            text_vertical_alignment = 'center',
            text_horizontal_alignment = 'left',
            text_color = COLOR_LABEL,
            offset = { 6, 0, 5 },
            size = { TABLE_NAME_WIDTH - 12, header_height },
            text_overflow_mode = 'truncate',
        },
    }
    for col_index = 1, num_value_cols do
        local column = columns[col_index]
        local x = TABLE_NAME_WIDTH + (col_index - 1) * col_width
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
                text_color = COLOR_LABEL,
                offset = { x, 0, 5 },
                size = { col_width, header_height },
                text_overflow_mode = 'truncate',
            },
        }
    end

    for row_index = 1, #rows do
        local row = rows[row_index]
        local y = header_height + (row_index - 1) * row_height
        passes[#passes + 1] = {
            pass_type = 'text',
            style_id = 'name_' .. row_index,
            value_id = 'name_' .. row_index,
            value = row.difficulty or '',
            style = {
                font_type = 'proxima_nova_bold',
                font_size = 15,
                text_vertical_alignment = 'center',
                text_horizontal_alignment = 'left',
                text_color = row.is_havoc and COLOR_LABEL or COLOR_LABEL,
                offset = { 6, y, 5 },
                size = { TABLE_NAME_WIDTH - 12, row_height },
                text_overflow_mode = 'truncate',
            },
        }
        local cells = { row.health, row.hit_mass }
        for col_index = 1, num_value_cols do
            local x = TABLE_NAME_WIDTH + (col_index - 1) * col_width
            passes[#passes + 1] = {
                pass_type = 'text',
                style_id = 'cell_' .. row_index .. '_' .. col_index,
                value_id = 'cell_' .. row_index .. '_' .. col_index,
                value = cells[col_index] or '',
                style = {
                    font_type = 'proxima_nova_bold',
                    font_size = 15,
                    text_vertical_alignment = 'center',
                    text_horizontal_alignment = 'center',
                    text_color = COLOR_VALUE,
                    offset = { x, y, 5 },
                    size = { col_width, row_height },
                    text_overflow_mode = 'truncate',
                },
            }
        end
    end
    return passes
end

-- Hit-zone table: zone name + armor label (color-coded) + weakspot tag.
-- origin_x shifts the table right so it can sit beside the body diagram.
local function _zone_table_passes(width, rows, zone_header, armor_header, weakspot_header, origin_x)
    origin_x = origin_x or 0
    local num_rows = #rows
    local col_width = (width - TABLE_NAME_WIDTH) / 2
    local header_height = TABLE_HEADER_HEIGHT
    local row_height = TABLE_ROW_HEIGHT
    local total_height = header_height + num_rows * row_height
    local passes = {}

    passes[#passes + 1] = {
        pass_type = 'rect',
        style_id = 'background',
        style = {
            color = TABLE_BG_COLOR,
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
            color = TABLE_FRAME_COLOR,
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
            color = TABLE_CORNER_COLOR,
            offset = { origin_x, 0, 4 },
            size = { width, total_height },
        },
    }
    passes[#passes + 1] = {
        pass_type = 'rect',
        style_id = 'header_band',
        style = {
            color = TABLE_HEADER_BG_COLOR,
            offset = { origin_x, 0, 1 },
            size = { width, header_height },
        },
    }
    passes[#passes + 1] = {
        pass_type = 'rect',
        style_id = 'header_separator',
        style = {
            color = TABLE_GRID_COLOR,
            offset = { origin_x, header_height - 1, 2 },
            size = { width, 2 },
        },
    }
    passes[#passes + 1] = {
        pass_type = 'rect',
        style_id = 'name_separator',
        style = {
            color = TABLE_GRID_COLOR,
            offset = { origin_x + TABLE_NAME_WIDTH - 1, 0, 2 },
            size = { 2, total_height },
        },
    }

    local header_labels = {
        zone_header or 'Zone',
        armor_header or 'Armor',
        weakspot_header or 'Weakspot',
    }
    local header_aligns = { 'left', 'center', 'center' }
    local header_x = { 6, TABLE_NAME_WIDTH, TABLE_NAME_WIDTH + col_width }
    for col_index = 1, 3 do
        passes[#passes + 1] = {
            pass_type = 'text',
            style_id = 'hcol_' .. col_index,
            value_id = 'hcol_' .. col_index,
            value = header_labels[col_index],
            style = {
                font_type = 'proxima_nova_bold',
                font_size = 15,
                text_vertical_alignment = 'center',
                text_horizontal_alignment = header_aligns[col_index],
                text_color = COLOR_LABEL,
                offset = { origin_x + header_x[col_index], 0, 5 },
                size = { col_width, header_height },
                text_overflow_mode = 'truncate',
            },
        }
    end
    for col_index = 1, 2 do
        local x = TABLE_NAME_WIDTH + col_index * col_width - 1
        passes[#passes + 1] = {
            pass_type = 'rect',
            style_id = 'col_sep_' .. col_index,
            style = {
                color = TABLE_GRID_COLOR,
                offset = { origin_x + x, 0, 2 },
                size = { 2, total_height },
            },
        }
    end

    for row_index = 1, num_rows do
        local row = rows[row_index]
        local y = header_height + (row_index - 1) * row_height
        passes[#passes + 1] = {
            pass_type = 'text',
            style_id = 'name_' .. row_index,
            value_id = 'name_' .. row_index,
            value = row.label or '',
            style = {
                font_type = 'proxima_nova_bold',
                font_size = 15,
                text_vertical_alignment = 'center',
                text_horizontal_alignment = 'left',
                text_color = COLOR_LABEL,
                offset = { origin_x + 6, y, 5 },
                size = { TABLE_NAME_WIDTH - 12, row_height },
                text_overflow_mode = 'truncate',
            },
        }
        passes[#passes + 1] = {
            pass_type = 'text',
            style_id = 'armor_' .. row_index,
            value_id = 'armor_' .. row_index,
            value = row.armor_label or '',
            style = {
                font_type = 'proxima_nova_bold',
                font_size = 15,
                text_vertical_alignment = 'center',
                text_horizontal_alignment = 'center',
                text_color = { 255, row.armor_color[1], row.armor_color[2], row.armor_color[3] },
                offset = { origin_x + TABLE_NAME_WIDTH, y, 5 },
                size = { col_width, row_height },
                text_overflow_mode = 'truncate',
            },
        }
        passes[#passes + 1] = {
            pass_type = 'text',
            style_id = 'weak_' .. row_index,
            value_id = 'weak_' .. row_index,
            value = row.weakspot_label or '',
            style = {
                font_type = 'proxima_nova_bold',
                font_size = 15,
                text_vertical_alignment = 'center',
                text_horizontal_alignment = 'center',
                text_color = row.weakspot and Color.ui_terminal(255, true) or COLOR_VALUE,
                offset = { origin_x + TABLE_NAME_WIDTH + col_width, y, 5 },
                size = { col_width, row_height },
                text_overflow_mode = 'truncate',
            },
        }
    end
    return passes
end

local function _body_diagram_passes(origin_x, canvas_h, zones)
    local zone_by_key = {}
    for i = 1, #zones do
        zone_by_key[zones[i].zone] = zones[i]
    end

    local passes = {
        {
            pass_type = 'rect',
            style_id = 'diagram_bg',
            style = {
                color = BODY_BG,
                offset = { origin_x, 0, 0 },
                size = { BODY_W, canvas_h },
            },
        },
        {
            pass_type = 'rect',
            style_id = 'diagram_frame',
            style = {
                color = BODY_FRAME,
                offset = { origin_x, 0, 1 },
                size = { BODY_W, canvas_h },
            },
        },
    }

    -- Normalized coords (-1..1) scaled to the canvas.
    local half_w = BODY_W / 2
    local half_h = canvas_h / 2
    for zone_key, geom in pairs(BODY_PARTS) do
        local z = zone_by_key[zone_key]
        local rgb = z and z.armor_color or { 120, 120, 120 }
        local cx, cy, nw, nh = geom[1], geom[2], geom[3], geom[4]
        local w = nw * BODY_W
        local h = nh * canvas_h
        local px = origin_x + half_w + cx * half_w - w / 2
        local py = half_h + cy * half_h - h / 2
        passes[#passes + 1] = {
            pass_type = 'rect',
            style_id = 'part_' .. zone_key,
            style = {
                color = { 255, rgb[1], rgb[2], rgb[3] },
                offset = { px, py, 2 },
                size = { w, h },
            },
        }
    end

    return passes
end

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

    blueprints.stat = {
        size = { width, STAT_ROW_HEIGHT },
        pass_template = {
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
            widget.content.label = element.label or ''
            widget.content.value = element.value or ''
            if element.label_color then
                widget.style.label.text_color = element.label_color
            end
            if element.value_color then
                widget.style.value.text_color = element.value_color
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
                    text_color = Color.terminal_text_header(255, true),
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

    blueprints.stat_table = {
        size_function = function(_, config)
            local rows = config.rows or {}
            return { width, TABLE_HEADER_HEIGHT + #rows * TABLE_ROW_HEIGHT }
        end,
        pass_template_function = function(_, config)
            return _stat_table_passes(width, config.columns or {}, config.rows or {}, config.difficulty_header)
        end,
    }

    blueprints.zone_table = {
        size_function = function(_, config)
            local rows = config.rows or {}
            local table_h = TABLE_HEADER_HEIGHT + #rows * TABLE_ROW_HEIGHT
            if config.diagram then
                local table_w = width - BODY_W - BODY_GAP
                return { BODY_W + BODY_GAP + table_w, table_h }
            end
            return { width, table_h }
        end,
        pass_template_function = function(_, config)
            local rows = config.rows or {}
            local table_h = TABLE_HEADER_HEIGHT + #rows * TABLE_ROW_HEIGHT
            local table_w = config.diagram and (width - BODY_W - BODY_GAP) or width
            local table_origin = config.diagram and (BODY_W + BODY_GAP) or 0
            local table_passes = _zone_table_passes(
                table_w,
                rows,
                config.zone_header,
                config.armor_header,
                config.weakspot_header,
                table_origin
            )
            if config.diagram then
                local diagram_passes = _body_diagram_passes(0, table_h, rows)
                for i = 1, #diagram_passes do
                    table_passes[#table_passes + 1] = diagram_passes[i]
                end
            end
            return table_passes
        end,
    }
    return blueprints
end

return make_blueprints
