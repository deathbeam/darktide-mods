local mod = get_mod('SimpleMinimap')

local UIWidget = require('scripts/managers/ui/ui_widget')
local UIHudSettings = require('scripts/settings/ui/ui_hud_settings')

local HudElementSimpleMinimap = class('HudElementSimpleMinimap', 'HudElementBase')

-- Scenegraph
local scenegraph_definition = {
    screen = {
        scale = 'fit',
        size = { 1920, 1080 },
        position = { 0, 0, 0 },
    },
    minimap = {
        parent = 'screen',
        vertical_alignment = 'bottom',
        horizontal_alignment = 'center',
        size = { 200, 200 },
        position = { 0, -30, 1 },
    },
}

-- Base widgets (background, FOV, player)
local function _create_widgets(size)
    return {
        background = UIWidget.create_definition({
            {
                pass_type = 'circle',
                style_id = 'circle',
                style = {
                    vertical_alignment = 'center',
                    horizontal_alignment = 'center',
                    color = { 128, 40, 40, 40 },
                    offset = { 0, 0, 0 },
                    size = { size, size },
                },
            },
        }, 'minimap'),
        fov_indicator = UIWidget.create_definition({
            {
                pass_type = 'triangle',
                style_id = 'left',
                style = {
                    vertical_alignment = 'center',
                    horizontal_alignment = 'center',
                    color = { 64, 200, 200, 200 },
                    offset = { 8, 7, 1 },
                    size = { 16, 16 },
                    triangle_corners = {
                        { 0, 0 },
                        { -size / 4, -size / 2 },
                        { 0, -size / 2 },
                    },
                },
            },
            {
                pass_type = 'triangle',
                style_id = 'right',
                style = {
                    vertical_alignment = 'center',
                    horizontal_alignment = 'center',
                    color = { 64, 200, 200, 200 },
                    offset = { 8, 7, 1 },
                    size = { 16, 16 },
                    triangle_corners = {
                        { 0, 0 },
                        { 0, -size / 2 },
                        { size / 4, -size / 2 },
                    },
                },
            },
        }, 'minimap'),
        player = UIWidget.create_definition({
            {
                pass_type = 'triangle',
                style_id = 'triangle',
                style = {
                    vertical_alignment = 'center',
                    horizontal_alignment = 'center',
                    color = Color.ui_terminal(255, true),
                    offset = { 8, 7, 2 },
                    size = { 16, 16 },
                    triangle_corners = {
                        { -8, 8 },
                        { 8, 8 },
                        { 0, -8 },
                    },
                },
            },
        }, 'minimap'),
    }
end

function HudElementSimpleMinimap:init(parent, draw_layer, start_scale)
    local size = mod.settings.size or 200

    HudElementSimpleMinimap.super.init(self, parent, draw_layer, start_scale, {
        widget_definitions = _create_widgets(size),
        scenegraph_definition = scenegraph_definition,
    })

    self._world_markers_list = nil

    -- Performance: throttle marker updates
    self._update_interval = 0.2 -- Update markers 5 times per second
    self._last_update_time = 0
    self._cached_marker_data = {}

    -- Register marker types (each handles both collection and rendering)
    self._markers = {}
    self:_register_marker('teammates', mod:io_dofile('SimpleMinimap/scripts/mods/SimpleMinimap/markers/teammates'))
    self:_register_marker('objectives', mod:io_dofile('SimpleMinimap/scripts/mods/SimpleMinimap/markers/objectives'))
    self:_register_marker('pings', mod:io_dofile('SimpleMinimap/scripts/mods/SimpleMinimap/markers/pings'))
    self:_register_marker('enemies', mod:io_dofile('SimpleMinimap/scripts/mods/SimpleMinimap/markers/enemies'))
end

function HudElementSimpleMinimap:_register_marker(name, marker_module)
    self._markers[name] = marker_module
    if marker_module.init then
        marker_module.init(self)
    end
end

function HudElementSimpleMinimap:update(dt, t, ui_renderer, render_settings, input_service)
    HudElementSimpleMinimap.super.update(self, dt, t, ui_renderer, render_settings, input_service)

    -- Request world markers list
    if not self._world_markers_list then
        Managers.event:trigger('request_world_markers_list', callback(self, '_on_world_markers'))
    end
end

function HudElementSimpleMinimap:_on_world_markers(markers)
    self._world_markers_list = markers
end

-- Calculate marker position on minimap from world position
function HudElementSimpleMinimap:world_to_minimap(world_position)
    local camera = self._parent:player_camera()
    if not camera then
        return nil
    end

    local ScriptCamera = require('scripts/foundation/utilities/script_camera')
    local camera_position = ScriptCamera.position(camera)
    local camera_forward = Quaternion.forward(ScriptCamera.rotation(camera))

    local diff = world_position - camera_position
    local vertical_distance = math.abs(diff.z)
    diff.z = 0

    local azimuth = Vector3.flat_angle(camera_forward, diff)
    local range = Vector3.length(diff)

    local max_range = mod.settings.max_range or 50
    local minimap_radius = (mod.settings.size or 200) / 2

    local radius = (range / max_range) * minimap_radius
    local clamped = false

    if radius > minimap_radius then
        radius = minimap_radius * 0.95
        clamped = true
    end

    return {
        x = radius * -math.sin(azimuth),
        y = radius * -math.cos(azimuth),
        range = range,
        vertical_distance = vertical_distance,
        clamped = clamped,
    }
end

function HudElementSimpleMinimap:_draw_widgets(dt, t, input_service, ui_renderer)
    HudElementSimpleMinimap.super._draw_widgets(self, dt, t, input_service, ui_renderer)

    -- Update background opacity
    local bg = self._widgets_by_name.background
    if bg then
        bg.style.circle.color[1] = mod.settings.background_opacity or 128
    end

    -- Performance: throttle data collection, but draw every frame for smooth positioning
    local should_update = (t - self._last_update_time) >= self._update_interval
    if should_update then
        self._last_update_time = t

        -- Collect marker data (expensive operations)
        for name, marker_module in pairs(self._markers) do
            if marker_module.collect then
                local new_data = marker_module.collect(self, dt, t)
                if new_data then
                    self._cached_marker_data[name] = new_data
                end
            end
        end
    end

    -- Draw markers every frame using cached data
    for name, marker_module in pairs(self._markers) do
        if marker_module.draw then
            local cached_data = self._cached_marker_data[name]
            marker_module.draw(self, ui_renderer, dt, t, cached_data)
        end
    end
end

return HudElementSimpleMinimap
