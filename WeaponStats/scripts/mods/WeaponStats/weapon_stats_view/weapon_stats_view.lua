local mod = get_mod('WeaponStats')

local UIWidget = mod:original_require('scripts/managers/ui/ui_widget')
local UIWidgetGrid = mod:original_require('scripts/ui/widget_logic/ui_widget_grid')
local UIRenderer = mod:original_require('scripts/managers/ui/ui_renderer')
local ViewElementInputLegend =
    mod:original_require('scripts/ui/view_elements/view_element_input_legend/view_element_input_legend')

local WeaponTemplates = mod:original_require('scripts/settings/equipment/weapon_templates/weapon_templates')
local WeaponTemplate = mod:original_require('scripts/utilities/weapon/weapon_template')
local UIFontSettings = mod:original_require('scripts/managers/ui/ui_font_settings')

local Builder = mod:io_dofile('WeaponStats/scripts/mods/WeaponStats/weapon_stats_builder')
local Utils = mod:io_dofile('WeaponStats/scripts/mods/WeaponStats/weapon_stats_utils')

-- Max stat value a real weapon can roll: items cap at 0.8 (items.lua max_weapon_preview).
local MAX_STAT_VALUE = 0.8

local GRID_SPACING = { 4, 4 }
local DETAIL_GRID_SPACING = { 0, 2 }

-- Detail-pane layout constants
local INDENT_PX = 18
local STAT_ROW_HEIGHT = 21

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
-- Weapon._init_traits / build_stats expect.
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

-- Detail-pane renderer -----------------------------------------------------
-- The builder returns a flat list of typed records; each helper below turns one
-- record into a single grid widget. The pane is just a vertical stack of these,
-- so the layout (spacers, section rules, stat rows, armor bars) lives entirely
-- here, decoupled from the data-extraction logic in the builder.

local COLOR_LABEL = Color.terminal_text_body_sub_header(255, true)
local COLOR_VALUE = Color.terminal_text_body(255, true)
local COLOR_RULE = Color.terminal_corner(120, true)
local COLOR_ARMOR_BONUS = Color.ui_orange_medium(255, true)

local function _make_text_widget(self, text, font_size, color, width, height, offset_x)
    local h = height or (font_size + 6)
    local widget_def = UIWidget.create_definition({
        {
            pass_type = 'text',
            value_id = 'text',
            value = text,
            style = {
                font_type = 'proxima_nova_bold',
                font_size = font_size,
                text_vertical_alignment = 'top',
                text_horizontal_alignment = 'left',
                text_color = color or COLOR_VALUE,
                offset = { offset_x or 0, 0, 2 },
                size = { width, h },
            },
        },
    }, 'weapon_stats_detail_pivot', nil, { width, h })

    local widget = self:_create_widget('detail_' .. #self._detail_widgets, widget_def)
    self._detail_widgets[#self._detail_widgets + 1] = widget
    return widget
end

-- A full-width divider line. Sits just below the baseline of the section header.
local function _make_rule(self, width)
    local h = 2
    local widget_def = UIWidget.create_definition({
        {
            pass_type = 'rect',
            style = {
                color = COLOR_RULE,
                offset = { 0, 0, 1 },
                size = { width, h },
            },
        },
    }, 'weapon_stats_detail_pivot', nil, { width, h })

    local widget = self:_create_widget('detail_rule_' .. #self._detail_widgets, widget_def)
    self._detail_widgets[#self._detail_widgets + 1] = widget
end

local function _make_spacer(self, height, width)
    local h = height or 8
    local widget_def = UIWidget.create_definition({
        {
            pass_type = 'rect',
            style = {
                color = { 0, 0, 0, 0 },
            },
        },
    }, 'weapon_stats_detail_pivot', nil, { width, h })

    local widget = self:_create_widget('detail_spacer_' .. #self._detail_widgets, widget_def)
    self._detail_widgets[#self._detail_widgets + 1] = widget
end

-- Two-column row: muted label left, colored value right-aligned.
local function _make_stat_row(self, label, value, value_color, width, indent)
    local h = STAT_ROW_HEIGHT
    local x = (indent or 0) * INDENT_PX
    local label_w = width * 0.55
    local value_w = width - label_w
    local widget_def = UIWidget.create_definition({
        {
            pass_type = 'text',
            value_id = 'label',
            value = label,
            style = {
                font_type = 'proxima_nova_bold',
                font_size = 16,
                text_vertical_alignment = 'center',
                text_horizontal_alignment = 'left',
                text_color = COLOR_LABEL,
                offset = { x, 0, 2 },
                size = { label_w - x, h },
                text_overflow_mode = 'truncate',
            },
        },
        {
            pass_type = 'text',
            value_id = 'value',
            value = value,
            style = {
                font_type = 'proxima_nova_bold',
                font_size = 16,
                text_vertical_alignment = 'center',
                text_horizontal_alignment = 'left',
                text_color = value_color or COLOR_VALUE,
                offset = { label_w, 0, 2 },
                size = { value_w, h },
                text_overflow_mode = 'truncate',
            },
        },
    }, 'weapon_stats_detail_pivot', nil, { width, h })

    local widget = self:_create_widget('detail_stat_' .. #self._detail_widgets, widget_def)
    self._detail_widgets[#self._detail_widgets + 1] = widget
end

-- Armor row as a stat row: "Name" left, "100% (C: 90%)" right.
-- Color only highlights bonuses (>100%) in orange; penalties and baseline stay muted.
-- Most ADM is <100%, so coloring every penalty red drowns the real signal (bonuses).
local function _armor_value_color(value)
    if value > 1.005 then
        return COLOR_ARMOR_BONUS
    end
    return COLOR_VALUE
end

-- Format one ADM figure, appending " (C: X%)" when crit differs from normal.
local function _armor_value_text(normal, crit, has_crit)
    local text = string.format('%.0f%%', normal * 100)
    if has_crit then
        text = text .. string.format(' (C: %.0f%%)', crit * 100)
    end
    return text
end

local function _make_armor_row(self, row, width)
    local color = _armor_value_color(row.normal)
    if row.has_far then
        -- Ranged: "Near% → Far%" with crit riding the near figure.
        local value = _armor_value_text(row.normal, row.crit, row.has_crit)
            .. ' → '
            .. _armor_value_text(row.normal_far, row.crit_far, row.has_crit)
        _make_stat_row(self, row.name, value, color, width, 1)
    else
        _make_stat_row(self, row.name, _armor_value_text(row.normal, row.crit, row.has_crit), color, width, 1)
    end
end

-- Dispatch a single builder record to the matching widget helper.
local function _render_record(self, record, width)
    local rtype = record.type
    if rtype == 'spacer' then
        _make_spacer(self, record.height, width)
    elseif rtype == 'section' then
        _make_text_widget(self, record.text, 22, record.color, width, 30)
        _make_rule(self, width)
        _make_spacer(self, 4, width)
    elseif rtype == 'attack' then
        _make_spacer(self, 2, width)
        _make_text_widget(self, record.text, 19, record.color, width, 26)
    elseif rtype == 'subheader' then
        _make_text_widget(self, record.text, 16, record.color, width, 22, (record.indent or 0) * INDENT_PX)
    elseif rtype == 'stat' then
        _make_stat_row(self, record.label, record.value, record.value_color, width, record.indent or 0)
    elseif rtype == 'armor' then
        _make_spacer(self, 2, width)
        _make_text_widget(self, record.header, 16, record.color, width, 22)
        for _, row in ipairs(record.rows) do
            _make_armor_row(self, row, width)
        end
    end
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
    local detail_width = detail_scenegraph and detail_scenegraph.size[1] or 600

    -- Header: weapon name (bold, terminal orange) + kind subtext.
    _make_text_widget(self, entry.name, 26, Color.terminal_text_header(255, true), detail_width, 34)
    if entry.subtext then
        _make_text_widget(self, entry.subtext, 16, entry.subtext_color or COLOR_LABEL, detail_width, 22)
    end
    _make_spacer(self, 8, detail_width)

    local weapon = entry.weapon
    local item = WeaponStatsView._placeholder_item(weapon.weapon_template)
    local records = Builder.build_stats(item)

    for i = 1, #records do
        _render_record(self, records[i], detail_width)
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
