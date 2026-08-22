local mod = get_mod('SimpleCharging')
local ChargeSources = mod:io_dofile('SimpleCharging/scripts/mods/SimpleCharging/SimpleCharging_sources')
local UIWidget = require('scripts/managers/ui/ui_widget')

local BAR_WIDTH = 24
local BAR_HEIGHT = 56
local MASK_HEIGHT = BAR_HEIGHT - 4
local DEFAULT_BAR_DISTANCE = 64
local DEFAULT_BAR_SPACING = 28
local MAX_BARS = 12
local FRAME_TEXTURE = 'content/ui/materials/hud/crosshairs/charge_up'
local MASK_TEXTURE = 'content/ui/materials/hud/crosshairs/charge_up_mask'
local NATIVE_LEFT = 'charge_left'
local NATIVE_RIGHT = 'charge_right'
local NATIVE_MASK_LEFT = 'charge_mask_left'
local NATIVE_MASK_RIGHT = 'charge_mask_right'
local NATIVE_BAR_STYLE_IDS = { NATIVE_LEFT, NATIVE_RIGHT, NATIVE_MASK_LEFT, NATIVE_MASK_RIGHT }
local INJECTED_MARKER = 'simple_charging_frame_left_1'
local DEFAULT_BAR_COLOR = { 255, 216, 229, 207 }

local BAR_PARTS = {
    {
        id = 'frame_left',
        pass_type = 'texture_uv',
        texture = FRAME_TEXTURE,
        layer = 1,
        height = BAR_HEIGHT,
        uvs = { { 1, 0 }, { 0, 1 } },
    },
    {
        id = 'frame_right',
        pass_type = 'texture',
        texture = FRAME_TEXTURE,
        layer = 1,
        height = BAR_HEIGHT,
    },
    {
        id = 'mask_left',
        pass_type = 'texture_uv',
        texture = MASK_TEXTURE,
        layer = 2,
        height = MASK_HEIGHT,
        uvs = { { 1, 0 }, { 0, 1 } },
    },
    {
        id = 'mask_right',
        pass_type = 'texture_uv',
        texture = MASK_TEXTURE,
        layer = 2,
        height = MASK_HEIGHT,
        uvs = { { 0, 1 }, { 1, 0 } },
    },
}

local BAR_IDS = {}

for index = 1, MAX_BARS do
    BAR_IDS[index] = {}

    for _, part in ipairs(BAR_PARTS) do
        BAR_IDS[index][part.id] = 'simple_charging_' .. part.id .. '_' .. index
    end
end

local INJECTED_STYLE_IDS = {}

for index = 1, MAX_BARS do
    for _, part in ipairs(BAR_PARTS) do
        INJECTED_STYLE_IDS[#INJECTED_STYLE_IDS + 1] = BAR_IDS[index][part.id]
    end
end

local current_element
local hooked_element_class

local function _bar_color()
    local color = mod:get('bar_color')
    if type(color) == 'table' and #color >= 4 then
        return color
    end

    return DEFAULT_BAR_COLOR
end

local function _apply_color(style, style_ids, color)
    if not style then
        return
    end

    for _, style_id in ipairs(style_ids) do
        local pass_style = style[style_id]

        if pass_style then
            pass_style.color = { color[1], color[2], color[3], color[4] }
        end
    end
end

local function _apply_definition_colors(definition)
    local styles = definition and definition.style
    local color = _bar_color()

    _apply_color(styles, NATIVE_BAR_STYLE_IDS, color)
    _apply_color(styles, INJECTED_STYLE_IDS, color)
end

local function _native_bar_distance(style)
    local left = style[NATIVE_LEFT]
    local right = style[NATIVE_RIGHT]

    if not left or not right or not left.offset or not right.offset then
        return nil
    end

    return math.max(math.abs(left.offset[1] or 0), math.abs(right.offset[1] or 0))
end

local function _part_style(part)
    local style = {
        horizontal_alignment = 'center',
        vertical_alignment = 'center',
        visible = false,
        offset = { 0, 0, part.layer },
        size = { BAR_WIDTH, part.height },
        color = _bar_color(),
    }

    if part.uvs then
        style.uvs = { { part.uvs[1][1], part.uvs[1][2] }, { part.uvs[2][1], part.uvs[2][2] } }
    end

    return style
end

local function _bar_passes(index)
    local ids = BAR_IDS[index]
    local passes = {}

    for _, part in ipairs(BAR_PARTS) do
        passes[#passes + 1] = {
            pass_type = part.pass_type,
            style_id = ids[part.id],
            value = part.texture,
            style = _part_style(part),
        }
    end

    return passes
end

local function _attach_bars(element)
    local definitions = element._crosshair_widget_definitions

    if not definitions then
        return
    end

    for _, definition in pairs(definitions) do
        local styles = definition and definition.style
        _apply_definition_colors(definition)

        if definition and not (styles and styles[INJECTED_MARKER]) then
            for index = 1, MAX_BARS do
                for _, pass in ipairs(_bar_passes(index)) do
                    UIWidget.add_definition_pass(definition, pass)
                end
            end
        end
    end

    current_element = element
end

local function _needs_bar_injection(element)
    local crosshair_type = element and element._crosshair_type
    local definitions = element and element._crosshair_widget_definitions
    local definition = definitions and crosshair_type and definitions[crosshair_type]
    local styles = definition and definition.style

    return definition and not (styles and styles[INJECTED_MARKER])
end

local function _set_bar_visible(style, ids, visible)
    for _, part in ipairs(BAR_PARTS) do
        local pass_style = style[ids[part.id]]

        if pass_style then
            pass_style.visible = visible
        end
    end
end

local function _hide_bars(element)
    local widget = element and element._widget
    local style = widget and widget.style

    if not style then
        return
    end

    for index = 1, MAX_BARS do
        _set_bar_visible(style, BAR_IDS[index], false)
    end
end

local function _paint_bar(style, ids, source, distance)
    local frame_left = style[ids.frame_left]
    local frame_right = style[ids.frame_right]
    local mask_left = style[ids.mask_left]
    local mask_right = style[ids.mask_right]

    if not frame_left or not frame_right or not mask_left or not mask_right or not source then
        return
    end

    local fraction = source.fraction or 0
    local filled_height = MASK_HEIGHT * fraction
    local filled_offset = MASK_HEIGHT * (1 - fraction) * 0.5
    local color = _bar_color()

    frame_left.color = color
    frame_right.color = color
    mask_left.color = color
    mask_right.color = color

    frame_left.visible = true
    frame_left.offset[1] = -distance
    frame_right.visible = true
    frame_right.offset[1] = distance

    mask_left.visible = true
    mask_left.size[2] = filled_height
    mask_left.offset[1] = -distance
    mask_left.offset[2] = filled_offset
    mask_left.uvs[1][2] = 1 - fraction

    mask_right.visible = true
    mask_right.size[2] = filled_height
    mask_right.offset[1] = distance
    mask_right.offset[2] = filled_offset
    mask_right.uvs[1][2] = fraction
end

local function _paint_native_bars(style)
    if not style or not style[NATIVE_LEFT] and not style[NATIVE_RIGHT] then
        return
    end

    _apply_color(style, NATIVE_BAR_STYLE_IDS, _bar_color())
end

local function _render_bars(element)
    local widget = element._widget
    local style = widget and widget.style

    if not style then
        return
    end

    _paint_native_bars(style)
    local sources = ChargeSources.collect()
    local spacing = DEFAULT_BAR_SPACING
    local distance = DEFAULT_BAR_DISTANCE
    local native_distance = _native_bar_distance(style)

    if native_distance then
        distance = math.max(distance, native_distance + spacing)
    end

    for index = 1, MAX_BARS do
        local source = sources[index]
        local bar_distance = distance + spacing * (index - 1)

        if source then
            _paint_bar(style, BAR_IDS[index], source, bar_distance)
        else
            _set_bar_visible(style, BAR_IDS[index], false)
        end
    end

    widget.dirty = true
end

local function _discard_widget(element)
    local crosshair_type = element._crosshair_type

    if element._widget and crosshair_type and element._unregister_widget_name then
        pcall(element._unregister_widget_name, element, crosshair_type)
        element._widget = nil
    end

    element._crosshair_type = nil
end

mod:hook_require('scripts/ui/hud/elements/crosshair/hud_element_crosshair', function(element_class)
    if not element_class or hooked_element_class == element_class then
        return
    end

    hooked_element_class = element_class
    mod:hook_safe(element_class, 'init', function(self)
        _attach_bars(self)
    end)

    mod:hook_safe(element_class, 'destroy', function(self)
        if current_element == self then
            current_element = nil
        end
    end)

    mod:hook_safe(element_class, 'update', function(self)
        if _needs_bar_injection(self) then
            _attach_bars(self)
            _discard_widget(self)
            return
        end

        _render_bars(self)
    end)
end)

mod.on_setting_changed = function(setting_id)
    if setting_id ~= 'bar_color' then
        return
    end

    _attach_bars(current_element)
    _render_bars(current_element)
end

mod.on_disabled = function()
    _hide_bars(current_element)
end
