local mod = get_mod('WeaponStats')

local UIWidget = mod:original_require('scripts/managers/ui/ui_widget')
local UIWidgetGrid = mod:original_require('scripts/ui/widget_logic/ui_widget_grid')
local UIRenderer = mod:original_require('scripts/managers/ui/ui_renderer')
local ViewElementInputLegend =
    mod:original_require('scripts/ui/view_elements/view_element_input_legend/view_element_input_legend')

local WeaponTemplates = mod:original_require('scripts/settings/equipment/weapon_templates/weapon_templates')
local WeaponTemplate = mod:original_require('scripts/utilities/weapon/weapon_template')
local TextUtilities = mod:original_require('scripts/utilities/ui/text')

local Builder = mod:io_dofile('WeaponStats/scripts/mods/WeaponStats/weapon_stats_builder')
local Utils = mod:io_dofile('WeaponStats/scripts/mods/WeaponStats/weapon_stats_utils')

-- Max stat value a real weapon can roll: items cap at 0.8 (items.lua max_weapon_preview).
local MAX_STAT_VALUE = 0.8

local GRID_SPACING = { 4, 4 }
local DETAIL_GRID_SPACING = { 0, 0 }
local FONT_SIZE = 16
local LINE_H = 19.5

local WeaponStatsView = class('WeaponStatsView', 'BaseView')

-- Build the full weapon list once. Cached on the class so re-opening the view is instant.
function WeaponStatsView:_build_weapon_list()
    if WeaponStatsView._weapon_list then
        return WeaponStatsView._weapon_list
    end

    local list = {}
    for name, weapon_template in pairs(WeaponTemplates) do
        local has_stats = weapon_template.base_stats ~= nil
        if has_stats then
            local is_ranged = WeaponTemplate.is_ranged(weapon_template)
            list[#list + 1] = {
                name = name,
                display_name = Utils.friendly_action_label(name),
                weapon_template = weapon_template,
                is_ranged = is_ranged,
            }
        end
    end

    table.sort(list, function(a, b)
        if a.is_ranged ~= b.is_ranged then
            return not a.is_ranged -- melee first
        end
        return a.display_name:lower() < b.display_name:lower()
    end)

    WeaponStatsView._weapon_list = list
    return list
end

-- Construct a placeholder item with every stat trait maxed (0.8), in the shape
-- Weapon._init_traits / build_stats_text expect.
function WeaponStatsView._placeholder_item(weapon_template)
    local template_name = weapon_template.name
    local stats = {}
    for stat_name, stat_definition in pairs(weapon_template.base_stats or {}) do
        if stat_definition.is_stat_trait == true then
            stats[#stats + 1] = {
                name = stat_name,
                value = MAX_STAT_VALUE,
            }
        end
    end
    return {
        weapon_template = template_name,
        base_stats = stats,
        perks = {},
        traits = {},
        overclocks = {},
    }
end

function WeaponStatsView:init(settings, context)
    self._definitions =
        mod:io_dofile('WeaponStats/scripts/mods/WeaponStats/weapon_stats_view/weapon_stats_view_definitions')
    self._blueprints =
        mod:io_dofile('WeaponStats/scripts/mods/WeaponStats/weapon_stats_view/weapon_stats_view_blueprints')

    WeaponStatsView.super.init(self, self._definitions, settings)

    self._pass_draw = false
    self._using_cursor_navigation = Managers.ui:using_cursor_navigation()
    self._weapon_list = self:_build_weapon_list()
    self._filtered_list = self._weapon_list
    self._selected_weapon = nil
    self._last_search_text = ''
end

function WeaponStatsView:on_enter()
    WeaponStatsView.super.on_enter(self)

    self:_setup_input_legend()
    self:_setup_search()
    self:_setup_entries()
end

function WeaponStatsView:_setup_search()
    local search_widget = self._widgets_by_name.weapon_stats_search
    if search_widget then
        search_widget.content.input_text = ''
        search_widget.content.placeholder_text = mod:localize('search_placeholder')

        local style = search_widget.style
        if style then
            style.background.color = { 255, 30, 30, 30 }
            style.baseline.color = Color.terminal_text_body(100, true)
        end
    end
end

function WeaponStatsView:_setup_input_legend()
    self._input_legend_element = self:_add_element(ViewElementInputLegend, 'input_legend', 10)
    local legend_inputs = self._definitions.legend_inputs

    for i = 1, #legend_inputs do
        local legend_input = legend_inputs[i]
        local on_pressed_callback = legend_input.on_pressed_callback
            and callback(self, legend_input.on_pressed_callback)

        self._input_legend_element:add_entry(
            legend_input.display_name,
            legend_input.input_action,
            legend_input.visibility_function,
            on_pressed_callback,
            legend_input.alignment
        )
    end
end

function WeaponStatsView:_format_entry_subtext(entry)
    local kind = entry.is_ranged and mod:localize('kind_ranged') or mod:localize('kind_melee')
    return kind, Color.terminal_text_body_sub_header(255, true)
end

function WeaponStatsView:_setup_entries()
    if self._entry_widgets then
        for i = 1, #self._entry_widgets do
            local widget = self._entry_widgets[i]
            self:_unregister_widget_name(widget.name)
        end
        self._entry_widgets = {}
    end

    local search_widget = self._widgets_by_name.weapon_stats_search
    local search_text = search_widget and search_widget.content.input_text or ''
    search_text = search_text:lower()

    local entries = {}
    for i = 1, #self._weapon_list do
        local weapon = self._weapon_list[i]
        local name = weapon.display_name
        local match = search_text == ''
            or name:lower():find(search_text, 1, true)
            or weapon.name:lower():find(search_text, 1, true)
        if match then
            local entry = {
                widget_type = 'weapon_entry',
                name = name,
                weapon = weapon,
                is_ranged = weapon.is_ranged,
                pressed_function = function(parent, widget, entry)
                    parent:_select_entry(widget, entry)
                end,
            }
            entry.subtext, entry.subtext_color = self:_format_entry_subtext(entry)
            entries[#entries + 1] = entry
        end
    end
    self._filtered_list = entries

    local scenegraph_id = 'weapon_stats_list_pivot'
    local callback_name = 'cb_on_entry_pressed'
    self._entry_widgets, self._entry_alignment_list = self:_setup_widgets(entries, scenegraph_id, callback_name)

    local grid_scenegraph_id = 'weapon_stats_list_background'
    self._entry_grid =
        self:_setup_grid(self._entry_widgets, self._entry_alignment_list, grid_scenegraph_id, GRID_SPACING)

    local scrollbar_widget = self._widgets_by_name.weapon_stats_list_scrollbar
    self._entry_grid:assign_scrollbar(scrollbar_widget, 'weapon_stats_list_pivot', grid_scenegraph_id)
    self._entry_grid:set_scrollbar_progress(0)

    if #self._entry_widgets > 0 then
        self:_select_entry(self._entry_widgets[1], entries[1])
    else
        self:_rebuild_detail_widgets(nil)
    end
end

function WeaponStatsView:_setup_widgets(content, scenegraph_id, callback_name)
    local widget_definitions = {}
    local widgets = {}
    local alignment_list = {}

    for i = 1, #content do
        local entry = content[i]
        local widget_type = entry.widget_type
        local template = self._blueprints[widget_type]
        local size = template.size
        local pass_template = template.pass_template

        if pass_template and not widget_definitions[widget_type] then
            widget_definitions[widget_type] = UIWidget.create_definition(pass_template, scenegraph_id, nil, size)
        end

        local widget_definition = widget_definitions[widget_type]
        local widget = nil

        if widget_definition then
            local name = scenegraph_id .. '_widget_' .. i
            widget = self:_create_widget(name, widget_definition)

            local init = template.init
            if init then
                init(self, widget, entry, callback_name)
            end

            widgets[#widgets + 1] = widget
        end

        alignment_list[#alignment_list + 1] = widget
    end

    return widgets, alignment_list
end

function WeaponStatsView:_setup_grid(widgets, alignment_list, grid_scenegraph_id, spacing)
    local ui_scenegraph = self._ui_scenegraph
    local direction = 'down'

    local grid = UIWidgetGrid:new(
        widgets,
        alignment_list,
        ui_scenegraph,
        grid_scenegraph_id,
        direction,
        spacing,
        nil, -- fill_section_spacing
        true -- use_is_focused_for_navigation
    )
    local render_scale = self._render_scale

    grid:set_render_scale(render_scale)
    return grid
end

function WeaponStatsView:_select_entry(widget, entry)
    self._selected_entry = entry
    self:_rebuild_detail_widgets(entry)
end

-- Measure the wrapped height of a single stats line at the detail pane width.
local function measure_line_height(renderer, line, text_width)
    if not renderer then
        return LINE_H
    end
    local Text = TextUtilities
    local stripped = line:gsub('{#[^}]*}', '')
    local ok, w = pcall(Text.text_width, renderer, stripped, {
        font_type = 'proxima_nova_bold',
        font_size = FONT_SIZE,
    }, { 9999, 9999 })
    if ok and w and w > text_width then
        return math.min(8, math.ceil(w / text_width)) * LINE_H
    end
    return LINE_H
end

function WeaponStatsView:_rebuild_detail_widgets(entry)
    if self._detail_widgets then
        for i = 1, #self._detail_widgets do
            local widget = self._detail_widgets[i]
            self:_unregister_widget_name(widget.name)
        end
    end
    self._detail_widgets = {}

    if not entry then
        return
    end

    local detail_scenegraph = self._ui_scenegraph.weapon_stats_detail_content
    local detail_content_width = detail_scenegraph and detail_scenegraph.size[1] or 600
    local text_width = detail_content_width

    local weapon = entry.weapon
    local item = WeaponStatsView._placeholder_item(weapon.weapon_template)
    local stats_text = Builder.build_stats_text(item)

    -- Split into lines, one text widget per line so the grid can scroll them.
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

    local lines = split_lines(stats_text)
    local renderer = self._ui_renderer

    -- Header (weapon name + kind) then the stats lines, each with its own font size/color/height.
    local records = {}
    records[#records + 1] = {
        text = entry.name,
        font_size = 26,
        color = Color.terminal_text_header(255, true),
        height = 34,
    }
    if entry.subtext then
        records[#records + 1] = {
            text = entry.subtext,
            font_size = 18,
            color = entry.subtext_color or Color.terminal_text_body_sub_header(255, true),
            height = 24,
        }
    end
    records[#records + 1] = { text = '', font_size = FONT_SIZE, color = nil, height = 10 }

    for idx = 1, #lines do
        local line = lines[idx]
        records[#records + 1] = {
            text = line,
            font_size = FONT_SIZE,
            color = Color.terminal_text_body(255, true),
            height = measure_line_height(renderer, line, text_width),
        }
    end

    for idx = 1, #records do
        local rec = records[idx]
        local h = rec.height

        local widget_def = UIWidget.create_definition({
            {
                pass_type = 'text',
                value_id = 'text',
                value = rec.text,
                style = {
                    font_type = 'proxima_nova_bold',
                    font_size = rec.font_size,
                    text_vertical_alignment = 'top',
                    text_horizontal_alignment = 'left',
                    text_color = rec.color or Color.terminal_text_body(255, true),
                    offset = { 0, 0, 2 },
                    size = { text_width, h },
                },
            },
        }, 'weapon_stats_detail_pivot', nil, { text_width, h })

        local widget = self:_create_widget('detail_line_' .. idx, widget_def)
        self._detail_widgets[#self._detail_widgets + 1] = widget
    end

    local detail_grid_scenegraph_id = 'weapon_stats_detail_content'
    self._detail_grid =
        self:_setup_grid(self._detail_widgets, self._detail_widgets, detail_grid_scenegraph_id, DETAIL_GRID_SPACING)

    local detail_scrollbar_widget = self._widgets_by_name.weapon_stats_detail_scrollbar
    self._detail_grid:assign_scrollbar(detail_scrollbar_widget, 'weapon_stats_detail_pivot', detail_grid_scenegraph_id)
    self._detail_grid:set_scrollbar_progress(0)
end

function WeaponStatsView:cb_on_entry_pressed(widget, entry)
    local pressed_function = entry.pressed_function
    if pressed_function then
        pressed_function(self, widget, entry)
    end
end

function WeaponStatsView:cb_on_close_pressed()
    Managers.ui:close_view(self.view_name)
end

function WeaponStatsView:update(dt, t, input_service)
    local search_widget = self._widgets_by_name.weapon_stats_search
    if search_widget then
        local current_search = search_widget.content.input_text or ''
        if current_search ~= self._last_search_text then
            self._last_search_text = current_search
            self:_setup_entries()
        end
    end

    local widgets_by_name = self._widgets_by_name

    if self._entry_grid and widgets_by_name.weapon_stats_list_interaction then
        local list_interaction = widgets_by_name.weapon_stats_list_interaction
        local is_list_hovered = not self._using_cursor_navigation or list_interaction.content.hotspot.is_hover or false
        local list_input_service = is_list_hovered and input_service or input_service:null_service()
        self._entry_grid:update(dt, t, list_input_service)
    end

    if self._detail_grid and widgets_by_name.weapon_stats_detail_interaction then
        local detail_interaction = widgets_by_name.weapon_stats_detail_interaction
        local is_detail_hovered = not self._using_cursor_navigation
            or detail_interaction.content.hotspot.is_hover
            or false
        local detail_input_service = is_detail_hovered and input_service or input_service:null_service()
        self._detail_grid:update(dt, t, detail_input_service)
    end

    return WeaponStatsView.super.update(self, dt, t, input_service)
end

function WeaponStatsView:_draw_grid(grid, widgets, interaction_widget, ui_renderer, is_grid_hovered)
    if not grid or not widgets then
        return
    end

    for i = 1, #widgets do
        local widget = widgets[i]
        if widget and grid:is_widget_visible(widget) then
            local hotspot = widget.content.hotspot
            if hotspot then
                hotspot.force_disabled = not is_grid_hovered
            end
            UIWidget.draw(widget, ui_renderer)
        end
    end
end

function WeaponStatsView:_draw_widgets(dt, t, input_service, ui_renderer)
    WeaponStatsView.super._draw_widgets(self, dt, t, input_service, ui_renderer)

    local ui_scenegraph = self._ui_scenegraph
    local render_settings = self._render_settings
    local widgets_by_name = self._widgets_by_name

    if self._entry_grid then
        local list_scrollbar = widgets_by_name.weapon_stats_list_scrollbar
        if list_scrollbar then
            list_scrollbar.content.visible = self._entry_grid:can_scroll()
        end
    end

    if self._detail_grid then
        local detail_scrollbar = widgets_by_name.weapon_stats_detail_scrollbar
        if detail_scrollbar then
            detail_scrollbar.content.visible = self._detail_grid:can_scroll()
        end
    end

    UIRenderer.begin_pass(ui_renderer, ui_scenegraph, input_service, dt, render_settings)

    local grid_interaction_widget = widgets_by_name.weapon_stats_list_interaction
    local is_list_hovered = not self._using_cursor_navigation
        or grid_interaction_widget.content.hotspot.is_hover
        or false
    self:_draw_grid(self._entry_grid, self._entry_widgets, grid_interaction_widget, ui_renderer, is_list_hovered)

    local detail_interaction_widget = widgets_by_name.weapon_stats_detail_interaction
    local is_detail_hovered = not self._using_cursor_navigation
        or detail_interaction_widget.content.hotspot.is_hover
        or false
    self:_draw_grid(self._detail_grid, self._detail_widgets, detail_interaction_widget, ui_renderer, is_detail_hovered)

    UIRenderer.end_pass(ui_renderer)
end

function WeaponStatsView:on_exit()
    if self._input_legend_element then
        self._input_legend_element = nil
        self:_remove_element('input_legend')
    end

    WeaponStatsView.super.on_exit(self)
end

return WeaponStatsView
