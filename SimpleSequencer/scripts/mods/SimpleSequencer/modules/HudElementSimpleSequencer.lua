local mod = get_mod('SimpleSequencer')

local UIWorkspaceSettings = require('scripts/settings/ui/ui_workspace_settings')
local UIWidget = require('scripts/managers/ui/ui_widget')
local UIHudSettings = require('scripts/settings/ui/ui_hud_settings')

local function _display_setting(mode, field)
    local value = mod:get(mode .. '_' .. field)

    if type(value) == 'table' then
        return value[1]
    end

    return value
end

local function _mode_display(mode)
    local mode_number = tonumber(string.sub(mode, 6)) or 1
    local name = _display_setting(mode, 'name')

    if name == nil or name == '' then
        name = 'Mode ' .. tostring(mode_number)
    end

    local color = {
        255,
        tonumber(_display_setting(mode, 'color_r')) or 255,
        tonumber(_display_setting(mode, 'color_g')) or 255,
        tonumber(_display_setting(mode, 'color_b')) or 255,
    }

    return {
        name = tostring(name),
        icon = _display_setting(mode, 'icon') or '',
        color = color,
    }
end

local DEFINITIONS = {
    scenegraph_definition = {
        screen = UIWorkspaceSettings.screen,
        mode_indicator = {
            parent = 'screen',
            vertical_alignment = 'center',
            horizontal_alignment = 'center',
            size = { 500, 48 },
            position = { 0, 0, 10 },
        },
    },
    widget_definitions = {
        mode_indicator = UIWidget.create_definition({
            {
                pass_type = 'texture',
                style_id = 'mode_icon',
                value_id = 'mode_icon',
                value = '',
                style = {
                    size = { 28, 28 },
                    horizontal_alignment = 'left',
                    vertical_alignment = 'center',
                    color = UIHudSettings.color_tint_main_1,
                    offset = { 190, 0, 3 },
                },
                visibility_function = function(content)
                    return content.mode_icon ~= nil and content.mode_icon ~= ''
                end,
            },
            {
                pass_type = 'text',
                style_id = 'mode_text',
                value_id = 'mode_text',
                value = '',
                style = {
                    size = { 250, 48 },
                    font_size = 22,
                    font_type = 'proxima_nova_bold',
                    text_horizontal_alignment = 'left',
                    text_vertical_alignment = 'center',
                    text_color = UIHudSettings.color_tint_main_1,
                    offset = { 218, 0, 2 },
                },
            },
        }, 'mode_indicator'),
    },
}

local HudElementSimpleSequencer = class('HudElementSimpleSequencer', 'HudElementBase')

function HudElementSimpleSequencer:init(parent, draw_layer, start_scale)
    HudElementSimpleSequencer.super.init(self, parent, draw_layer, start_scale, DEFINITIONS)
    self:set_visible(false)
end

function HudElementSimpleSequencer:set_visible(visible, ui_renderer)
    local widget = self._widgets_by_name.mode_indicator

    if widget and ui_renderer then
        UIWidget.set_visible(widget, ui_renderer, visible)
    end
end

function HudElementSimpleSequencer:update(dt, t, ui_renderer, render_settings, input_service)
    HudElementSimpleSequencer.super.update(self, dt, t, ui_renderer, render_settings, input_service)

    local widget = self._widgets_by_name.mode_indicator
    local manager = mod.mode_manager

    if not widget or not manager or not mod.ready or not mod.ready() or not mod:get('hud_enabled') then
        self:set_visible(false, ui_renderer)

        return
    end

    local mode = manager:active()
    local display = _mode_display(mode)
    local position_x = tonumber(mod:get('hud_position_x')) or 0
    local position_y = tonumber(mod:get('hud_position_y')) or 70

    widget.offset[1] = position_x
    widget.offset[2] = position_y
    widget.content.mode_icon = display.icon
    widget.content.mode_text = display.name
    widget.style.mode_icon.color = display.color
    widget.style.mode_text.text_color = display.color
    self:set_visible(true, ui_renderer)
end

function HudElementSimpleSequencer:draw(dt, t, ui_renderer, render_settings, input_service)
    if mod:get('hud_enabled') then
        HudElementSimpleSequencer.super.draw(self, dt, t, ui_renderer, render_settings, input_service)
    end
end

return HudElementSimpleSequencer
