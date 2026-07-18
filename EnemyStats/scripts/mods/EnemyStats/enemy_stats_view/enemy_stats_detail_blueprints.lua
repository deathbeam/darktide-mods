local mod = get_mod('EnemyStats')

local Shared = mod:io_dofile('EnemyStats/scripts/mods/EnemyStats/shared/shared_detail_blueprints')

local STAT_ROW_HEIGHT = 21

-- Humanoid body diagram: rect passes laid out as a silhouette, each part colored
-- by its zone armor type. Shown beside the hit-zone table for humanoid breeds.
local BODY_W = 180
local BODY_GAP = 10
local BODY_BG = { 80, 18, 18, 18 }
local BODY_FRAME = Color.terminal_frame(100, true)

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
        local color = z and z.armor_color or { 255, 120, 120, 120 }
        local cx, cy, nw, nh = geom[1], geom[2], geom[3], geom[4]
        local w = nw * BODY_W
        local h = nh * canvas_h
        local px = origin_x + half_w + cx * half_w - w / 2
        local py = half_h + cy * half_h - h / 2
        passes[#passes + 1] = {
            pass_type = 'rect',
            style_id = 'part_' .. zone_key,
            style = {
                color = color,
                offset = { px, py, 2 },
                size = { w, h },
            },
        }
    end

    return passes
end

local function make_blueprints(width)
    local blueprints = Shared.make_blueprints(width)

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
                    text_color = Shared.colors.label,
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
                    text_color = Shared.colors.value,
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

    blueprints.table = {
        size_function = function(_, config)
            local rows = config.rows or {}
            local table_h = Shared.table_height(#rows)
            if config.diagram then
                local table_w = (width - BODY_W - BODY_GAP)
                return { BODY_W + BODY_GAP + table_w, table_h }
            end
            return { width, table_h }
        end,
        pass_template_function = function(_, config)
            local rows = config.rows or {}
            local columns = config.columns or {}
            local table_h = Shared.table_height(#rows)
            local table_w = config.diagram and (width - BODY_W - BODY_GAP) or width
            local table_origin = config.diagram and (BODY_W + BODY_GAP) or 0
            local table_passes = Shared.make_table_passes(table_w, columns, rows, {
                name_column_label = config.name_column_label,
                origin_x = table_origin,
            })
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
