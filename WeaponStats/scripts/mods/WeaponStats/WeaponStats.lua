local mod = get_mod('WeaponStats')
local UIWidget = require('scripts/managers/ui/ui_widget')
local Text = require('scripts/utilities/ui/text')

local Builder = mod:io_dofile('WeaponStats/scripts/mods/WeaponStats/weapon_stats_builder')

-- Layout
local PANEL_X, PANEL_Y = 1350, -100
local PANEL_W, PANEL_H = 370, 650
local TEXT_PAD = 20
local TEXT_W = 325
local VIEWPORT_H = PANEL_H - 2 * TEXT_PAD
local SCROLLBAR_X = TEXT_PAD + TEXT_W
local SCROLLBAR_W = 8
local FONT_SIZE = 16
local SCROLL_STEP = 60
local LINE_H = 19.5

-- State
local stats_lines = {}
local line_heights = {}
local total_height = 0
local scroll_offset = 0

local MEASURE_STYLE = {
    font_type = 'proxima_nova_bold',
    font_size = FONT_SIZE,
}

-- Split a string on newlines, preserving empty lines.
local function split_lines(str)
    local lines = {}
    local i = 1
    while true do
        local j = string.find(str, '\n', i, true)
        if not j then
            lines[#lines + 1] = string.sub(str, i)
            break
        end
        lines[#lines + 1] = string.sub(str, i, j - 1)
        i = j + 1
    end
    return lines
end

-- Strip inline colour tags ({#color(...)} / {#reset()}) so a width probe measures the
-- visible text, not the markup.
local function strip_tags(s)
    return (s:gsub('{#[^}]*}', ''))
end

local function max_scroll()
    return math.max(0, total_height - VIEWPORT_H)
end

-- Height of each line: one row by default, more if the visible text wraps past TEXT_W.
local function measure_line(renderer, line)
    if not renderer then
        return LINE_H
    end
    local ok, w = pcall(Text.text_width, renderer, strip_tags(line), MEASURE_STYLE, { 9999, 9999 })
    if ok and w and w > TEXT_W then
        return math.min(8, math.ceil(w / TEXT_W)) * LINE_H
    end
    return LINE_H
end

local function measure_content(self, full_text)
    stats_lines = split_lines(full_text)
    line_heights = {}
    total_height = 0
    local renderer = self._ui_renderer
    for i, line in ipairs(stats_lines) do
        local h = measure_line(renderer, line)
        line_heights[i] = h
        total_height = total_height + h
    end
end

-- Put the lines intersecting the current scroll window into the text widget and shift the
-- text up by the sub-line offset so partial lines at the top/bottom are hidden by the covers.
local function render_visible(widget, renderer)
    if #stats_lines == 0 then
        return
    end

    local ms = max_scroll()
    local offset = math.clamp(scroll_offset, 0, ms)

    -- Find the first line whose bottom is below the window top, and the last whose top is
    -- above the window bottom. These bracket every line that touches the viewport.
    local cum = 0
    local start, ends, cum_start = nil, #stats_lines, 0
    for i = 1, #stats_lines do
        if not start and cum + line_heights[i] > offset then
            start = i
            cum_start = cum
        end
        if cum < offset + VIEWPORT_H then
            ends = i
        else
            break
        end
        cum = cum + line_heights[i]
    end
    if not start then
        start = #stats_lines
        cum_start = cum - (line_heights[#stats_lines] or 0)
    end

    local visible = {}
    for i = start, ends do
        visible[#visible + 1] = stats_lines[i]
    end
    widget.content.stats_text = table.concat(visible, '\n')

    -- Shift the text up so the start line's top sits at (viewport top - sub-line offset).
    -- When scrolled mid-line this puts the start line partly above the viewport, where the
    -- top cover hides it; the last line likewise spills into the bottom cover.
    local text_style = widget.style.stats_text
    text_style.offset[2] = TEXT_PAD - (offset - cum_start)
    widget.dirty = true
end

-- Position the scrollbar thumb (and hide it) to reflect the current scroll progress.
local function render_scrollbar(widget)
    local thumb_style = widget.style and widget.style.scrollbar_thumb
    local track_style = widget.style and widget.style.scrollbar_track
    if not thumb_style then
        return
    end

    local ms = max_scroll()
    local show = ms > 0

    if track_style and track_style.color then
        track_style.color[4] = show and 255 or 0
    end
    if not show then
        thumb_style.size[2] = 0
        return
    end

    local thumb_h = math.max(24, (VIEWPORT_H / total_height) * VIEWPORT_H)
    local progress = scroll_offset / ms
    thumb_style.size[2] = thumb_h
    thumb_style.offset[2] = TEXT_PAD + progress * (VIEWPORT_H - thumb_h)
    if thumb_style.color then
        thumb_style.color[4] = 255
    end
    widget.dirty = true
end

local function refresh(self)
    local widget = self._widgets_by_name.weapon_damage_stats
    if not widget then
        return
    end
    render_visible(widget, self._ui_renderer)
    render_scrollbar(widget)
end

-- Register the stats panel (text + covers + scrollbar) with the inventory weapons view.
mod:hook_require('scripts/ui/views/inventory_weapons_view/inventory_weapons_view_definitions', function(defs)
    defs.scenegraph_definition.weapon_damage_stats = {
        parent = 'canvas',
        vertical_alignment = 'bottom',
        horizontal_alignment = 'left',
        size = { PANEL_W, PANEL_H },
        position = { PANEL_X, PANEL_Y, 50 },
    }

    defs.widget_definitions.weapon_damage_stats = UIWidget.create_definition({
        {
            pass_type = 'hotspot',
            content_id = 'hotspot',
        },
        {
            pass_type = 'texture',
            value = 'content/ui/materials/backgrounds/terminal_basic',
            style = {
                color = Color.terminal_background(200, true),
                scale_to_material = true,
                vertical_alignment = 'center',
                horizontal_alignment = 'center',
            },
        },
        {
            pass_type = 'text',
            value_id = 'stats_text',
            value = 'Select a weapon to view damage profiles',
            style_id = 'stats_text',
            style = {
                font_type = 'proxima_nova_bold',
                font_size = FONT_SIZE,
                text_vertical_alignment = 'top',
                text_horizontal_alignment = 'left',
                text_color = Color.terminal_text_body(255, true),
                offset = { TEXT_PAD, TEXT_PAD, 1 },
                size = { TEXT_W, VIEWPORT_H },
            },
        },
        {
            pass_type = 'rect',
            style_id = 'scrollbar_track',
            style = {
                color = { 255, 45, 45, 50 },
                size = { SCROLLBAR_W, VIEWPORT_H },
                offset = { SCROLLBAR_X, TEXT_PAD, 2 },
            },
        },
        {
            pass_type = 'rect',
            style_id = 'scrollbar_thumb',
            style = {
                color = { 255, 190, 165, 95 },
                size = { SCROLLBAR_W, 24 },
                offset = { SCROLLBAR_X, TEXT_PAD, 3 },
            },
        },
    }, 'weapon_damage_stats')

    return defs
end)

-- Build stats when a weapon is selected.
mod:hook_safe(CLASS.InventoryWeaponsView, '_preview_item', function(self, item)
    local widget = self._widgets_by_name.weapon_damage_stats
    if not widget then
        return
    end

    scroll_offset = 0
    measure_content(self, Builder.build_stats_text(item))
    refresh(self)
end)

mod:hook_safe(CLASS.InventoryWeaponsView, 'on_enter', function(self)
    local widget = self._widgets_by_name.weapon_damage_stats
    if widget then
        widget.visible = true
    end
    scroll_offset = 0
    refresh(self)
end)

-- Wheel scrolling over the panel.
mod:hook(CLASS.InventoryWeaponsView, 'update', function(func, self, dt, t, input_service)
    func(self, dt, t, input_service)

    local widget = self._widgets_by_name.weapon_damage_stats
    if not (widget and widget.visible and widget.content and widget.content.hotspot) then
        return
    end

    if widget.content.hotspot.is_hover then
        local scroll_axis = input_service:get('scroll_axis')
        if scroll_axis and scroll_axis[2] and scroll_axis[2] ~= 0 then
            scroll_offset = math.clamp(scroll_offset - (scroll_axis[2] * SCROLL_STEP), 0, max_scroll())
            refresh(self)
        end
    end
end)

-- Reset state when the mod is disabled so stale line data doesn't linger.
mod.on_disabled = function()
    stats_lines = {}
    line_heights = {}
    total_height = 0
    scroll_offset = 0
end
