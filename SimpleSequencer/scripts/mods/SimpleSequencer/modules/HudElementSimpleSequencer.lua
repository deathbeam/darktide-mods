local mod = get_mod('SimpleSequencer')

local UIWorkspaceSettings = require('scripts/settings/ui/ui_workspace_settings')
local UIWidget = require('scripts/managers/ui/ui_widget')
local UIHudSettings = require('scripts/settings/ui/ui_hud_settings')

local HUB_GAME_MODES = {
    hub = true,
    prologue_hub = true,
    hub_singleplay = true,
}

local HUD_DISPLAY_DISABLED = 'disabled'
local ACTIVE_ALPHA = 128
local DISPLAY_MODES = {
    [HUD_DISPLAY_DISABLED] = {
        show_icon = false,
        show_name = false,
    },
    icon = {
        show_icon = true,
        show_name = false,
        icon_offset_x = 236,
        text_offset_x = 0,
    },
    name = {
        show_icon = false,
        show_name = true,
        icon_offset_x = 0,
        text_offset_x = 125,
    },
    icon_and_name = {
        show_icon = true,
        show_name = true,
        icon_offset_x = 190,
        text_offset_x = 218,
    },
}

local function _is_in_mission()
    local game_mode_manager = Managers.state and Managers.state.game_mode
    local game_mode_name = game_mode_manager and game_mode_manager:game_mode_name()

    return game_mode_name and not HUB_GAME_MODES[game_mode_name] or false
end

local function _display_mode()
    local display_mode = mod:get('hud_display_mode')

    return DISPLAY_MODES[display_mode] and display_mode or HUD_DISPLAY_DISABLED
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
                visibility_function = function(content)
                    return content.mode_text ~= nil and content.mode_text ~= ''
                end,
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
    local display_mode = _display_mode()

    if
        not widget
        or not manager
        or not mod.ready
        or not mod.ready()
        or not _is_in_mission()
        or display_mode == HUD_DISPLAY_DISABLED
    then
        self:set_visible(false, ui_renderer)

        return
    end

    local layout = DISPLAY_MODES[display_mode]
    local display = manager:display()
    local controller = mod.controller
    local sequencer_active = controller and controller:is_active() or false
    display.color[1] = sequencer_active and ACTIVE_ALPHA or 255
    local position_x = tonumber(mod:get('hud_position_x')) or 0
    local position_y = tonumber(mod:get('hud_position_y')) or 70

    widget.offset[1] = position_x
    widget.offset[2] = position_y
    widget.style.mode_icon.offset[1] = layout.icon_offset_x
    widget.style.mode_text.offset[1] = layout.text_offset_x
    widget.content.mode_icon = layout.show_icon and display.icon or ''
    widget.content.mode_text = layout.show_name and display.name or ''
    widget.style.mode_icon.color = display.color
    widget.style.mode_text.text_color = display.color
    self:set_visible(true, ui_renderer)
end

function HudElementSimpleSequencer:draw(dt, t, ui_renderer, render_settings, input_service)
    if _display_mode() ~= HUD_DISPLAY_DISABLED and _is_in_mission() then
        HudElementSimpleSequencer.super.draw(self, dt, t, ui_renderer, render_settings, input_service)
    end
end

return HudElementSimpleSequencer
