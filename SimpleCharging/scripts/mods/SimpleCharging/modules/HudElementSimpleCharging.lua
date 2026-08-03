local mod = get_mod('SimpleCharging')

local ChargeSources = mod.charge_sources
local UIHudSettings = require('scripts/settings/ui/ui_hud_settings')
local UIWidget = require('scripts/managers/ui/ui_widget')

local BAR_WIDTH = 24
local BAR_HEIGHT = 56
local MASK_HEIGHT = BAR_HEIGHT - 4
local DEFAULT_BAR_DISTANCE = 64
local DEFAULT_BAR_SPACING = 28
local TEXTURE_FRAME = 'content/ui/materials/hud/crosshairs/charge_up'
local TEXTURE_MASK = 'content/ui/materials/hud/crosshairs/charge_up_mask'
local MAX_BARS = 12
local NATIVE_CHARGE_LEFT = 'charge_left'
local NATIVE_CHARGE_RIGHT = 'charge_right'

local SOURCE_COLORS = {
    weapon = 'color_tint_main_1',
    blessing = 'color_tint_main_2',
    crit = 'color_tint_secondary_1',
}

local STYLE_IDS = {}

for index = 1, MAX_BARS do
    STYLE_IDS[index] = {
        left = 'simple_charging_left_' .. index,
        right = 'simple_charging_right_' .. index,
        mask_left = 'simple_charging_mask_left_' .. index,
        mask_right = 'simple_charging_mask_right_' .. index,
    }
end

local function _tint()
    local color = UIHudSettings.color_tint_main_1

    return {
        color[1],
        color[2],
        color[3],
        color[4],
    }
end

local function _source_tint(kind)
    local color = UIHudSettings[SOURCE_COLORS[kind]] or UIHudSettings.color_tint_main_1

    return {
        color[1],
        color[2],
        color[3],
        color[4],
    }
end

local function _native_charge_distance(style)
    local left = style[NATIVE_CHARGE_LEFT]
    local right = style[NATIVE_CHARGE_RIGHT]

    if not left or not right or not left.offset or not right.offset then
        return nil
    end

    return math.max(math.abs(left.offset[1] or 0), math.abs(right.offset[1] or 0))
end

local function _bar_passes(index, ids)
    return {
        {
            pass_type = 'texture_uv',
            style_id = ids.left,
            value = TEXTURE_FRAME,
            style = {
                horizontal_alignment = 'center',
                vertical_alignment = 'center',
                visible = false,
                uvs = {
                    { 1, 0 },
                    { 0, 1 },
                },
                offset = { 0, 0, 1 },
                size = { BAR_WIDTH, BAR_HEIGHT },
                color = _tint(),
            },
        },
        {
            pass_type = 'texture',
            style_id = ids.right,
            value = TEXTURE_FRAME,
            style = {
                horizontal_alignment = 'center',
                vertical_alignment = 'center',
                visible = false,
                offset = { 0, 0, 1 },
                size = { BAR_WIDTH, BAR_HEIGHT },
                color = _tint(),
            },
        },
        {
            pass_type = 'texture_uv',
            style_id = ids.mask_left,
            value = TEXTURE_MASK,
            style = {
                horizontal_alignment = 'center',
                vertical_alignment = 'center',
                visible = false,
                uvs = {
                    { 1, 0 },
                    { 0, 1 },
                },
                offset = { 0, 0, 2 },
                size = { BAR_WIDTH, MASK_HEIGHT },
                color = _tint(),
            },
        },
        {
            pass_type = 'texture_uv',
            style_id = ids.mask_right,
            value = TEXTURE_MASK,
            style = {
                horizontal_alignment = 'center',
                vertical_alignment = 'center',
                visible = false,
                uvs = {
                    { 0, 1 },
                    { 1, 0 },
                },
                offset = { 0, 0, 2 },
                size = { BAR_WIDTH, MASK_HEIGHT },
                color = _tint(),
            },
        },
    }
end

local function _inject_passes(element)
    local definitions = element._crosshair_widget_definitions

    if not definitions then
        return
    end

    for _, definition in pairs(definitions) do
        if definition then
            local has_passes = definition.style and definition.style[STYLE_IDS[1].left]

            if not has_passes then
                for index = 1, MAX_BARS do
                    local passes = _bar_passes(index, STYLE_IDS[index])

                    for pass_index = 1, #passes do
                        UIWidget.add_definition_pass(definition, passes[pass_index])
                    end
                end
            end
        end
    end

    element._simple_charging_injected = true
    mod._element = element
end

local function _hide_all(element)
    local widget = element and element._widget
    local style = widget and widget.style

    if not style then
        return
    end

    for index = 1, MAX_BARS do
        local ids = STYLE_IDS[index]
        local left = style[ids.left]
        local right = style[ids.right]
        local mask_left = style[ids.mask_left]
        local mask_right = style[ids.mask_right]

        if left then
            left.visible = false
            right.visible = false
            mask_left.visible = false
            mask_right.visible = false
        end
    end
end

local function _update_bar(style, ids, source, distance)
    local left = style[ids.left]
    local right = style[ids.right]
    local mask_left = style[ids.mask_left]
    local mask_right = style[ids.mask_right]

    if not left or not source then
        return
    end

    local fraction = source.fraction or 0
    local filled_height = MASK_HEIGHT * fraction
    local filled_offset = MASK_HEIGHT * (1 - fraction) * 0.5
    local color = _source_tint(source.kind)

    left.color = color
    right.color = color
    mask_left.color = color
    mask_right.color = color

    left.visible = true
    left.offset[1] = -distance

    right.visible = true
    right.offset[1] = distance

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

local function _update_bars(element)
    local widget = element._widget
    local style = widget and widget.style

    if not style then
        return
    end

    local sources = ChargeSources.collect()
    local distance = tonumber(mod:get('bar_distance')) or DEFAULT_BAR_DISTANCE
    local spacing = tonumber(mod:get('bar_spacing')) or DEFAULT_BAR_SPACING

    local native_distance = _native_charge_distance(style)
    if native_distance then
        distance = math.max(distance, native_distance + spacing)
    end

    for index = 1, MAX_BARS do
        local source = sources[index]
        local ids = STYLE_IDS[index]

        if source then
            _update_bar(style, ids, source, distance + spacing * (index - 1))
        else
            local left = style[ids.left]

            if left then
                left.visible = false
                style[ids.right].visible = false
                style[ids.mask_left].visible = false
                style[ids.mask_right].visible = false
            end
        end
    end
end

local function _rebuild_current_widget(element)
    local crosshair_type = element._crosshair_type

    if element._widget and crosshair_type then
        element:_unregister_widget_name(crosshair_type)
        element._widget = nil
    end

    element._crosshair_type = nil
end

local hooks_installed = false

local function _install_hooks()
    if hooks_installed then
        return
    end

    pcall(require, 'scripts/ui/hud/elements/crosshair/hud_element_crosshair')

    local element_class = CLASS and CLASS.HudElementCrosshair

    if not element_class then
        return
    end

    mod:hook_safe(element_class, 'init', function(self)
        _inject_passes(self)
    end)

    mod:hook_safe(element_class, 'destroy', function(self)
        if mod._element == self then
            mod._element = nil
        end
    end)

    mod:hook_safe(element_class, 'update', function(self)
        if not self._simple_charging_injected then
            _inject_passes(self)
            _rebuild_current_widget(self)

            return
        end

        _update_bars(self)
    end)

    hooks_installed = true
end

_install_hooks()

mod.on_enabled = function()
    _install_hooks()
end

mod.on_game_state_changed = function()
    _install_hooks()
end

mod.on_disabled = function()
    _hide_all(mod._element)
end

return {
    install = _install_hooks,
}
