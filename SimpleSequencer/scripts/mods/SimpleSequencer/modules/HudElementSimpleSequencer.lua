local mod = get_mod('SimpleSequencer')

local UIWorkspaceSettings = require('scripts/settings/ui/ui_workspace_settings')
local UIWidget = require('scripts/managers/ui/ui_widget')
local UIHudSettings = require('scripts/settings/ui/ui_hud_settings')

local DEFINITIONS = {
    scenegraph_definition = {
        screen = UIWorkspaceSettings.screen,
        mode_indicator = {
            parent = 'screen',
            vertical_alignment = 'top',
            horizontal_alignment = 'right',
            size = { 260, 42 },
            position = { -340, 80, 10 },
        },
    },
    widget_definitions = {
        mode_indicator = UIWidget.create_definition({
            {
                pass_type = 'text',
                style_id = 'mode_text',
                value_id = 'mode_text',
                value = '',
                style = {
                    font_size = 22,
                    font_type = 'proxima_nova_bold',
                    text_horizontal_alignment = 'right',
                    text_vertical_alignment = 'center',
                    text_color = UIHudSettings.color_tint_main_1,
                    offset = { 0, 0, 2 },
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

function HudElementSimpleSequencer:set_visible(visible)
    local widget = self._widgets_by_name.mode_indicator

    if widget then
        widget.style.mode_text.visible = visible
    end
end

function HudElementSimpleSequencer:update(dt, t, ui_renderer, render_settings, input_service)
    HudElementSimpleSequencer.super.update(self, dt, t, ui_renderer, render_settings, input_service)

    local widget = self._widgets_by_name.mode_indicator
    local manager = mod.mode_manager

    if not widget or not manager or not mod.ready or not mod.ready() or not mod:get('hud_enabled') then
        self:set_visible(false)

        return
    end

    local mode = manager:active()
    local number = tonumber(string.match(mode or '', '%d+')) or 1
    local name = 'Mode ' .. number

    widget.content.mode_text = string.format('[%d] %s', number, name)
    widget.style.mode_text.text_color = mod.engine and mod.engine.primary_down and Color.ui_hud_green_light(255, true)
        or UIHudSettings.color_tint_main_1
    self:set_visible(true)
end

function HudElementSimpleSequencer:draw(dt, t, ui_renderer, render_settings, input_service)
    if mod:get('hud_enabled') then
        HudElementSimpleSequencer.super.draw(self, dt, t, ui_renderer, render_settings, input_service)
    end
end

return HudElementSimpleSequencer
