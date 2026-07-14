local mod = get_mod('WeaponStats')

local ViewElementInputLegend =
    mod:original_require('scripts/ui/view_elements/view_element_input_legend/view_element_input_legend')
local ViewElementGrid = mod:original_require('scripts/ui/view_elements/view_element_grid/view_element_grid')

local WeaponTemplates = mod:original_require('scripts/settings/equipment/weapon_templates/weapon_templates')
local WeaponTemplate = mod:original_require('scripts/utilities/weapon/weapon_template')

local Builder = mod:io_dofile('WeaponStats/scripts/mods/WeaponStats/weapon_stats_builder')
local Utils = mod:io_dofile('WeaponStats/scripts/mods/WeaponStats/weapon_stats_utils')
local make_list_blueprints =
    mod:io_dofile('WeaponStats/scripts/mods/WeaponStats/weapon_stats_view/weapon_stats_view_blueprints')
local make_detail_blueprints =
    mod:io_dofile('WeaponStats/scripts/mods/WeaponStats/weapon_stats_view/weapon_stats_detail_blueprints')

local MAX_STAT_VALUE = 0.8

local ICON_PACKAGES = {
    'packages/ui/hud/player_weapon/player_weapon',
}

local function _package_is_available(package_name)
    local application = Application and Application.can_get_resource
    if not application then
        return false
    end
    local ok, exists = pcall(application, 'package', package_name)
    return ok and exists or false
end

local function _load_icon_packages()
    local loaded = {}
    for _, pkg in ipairs(ICON_PACKAGES) do
        if _package_is_available(pkg) and mod:package_status(pkg) ~= 'loaded' then
            mod:load_package(pkg, nil, true)
            loaded[#loaded + 1] = pkg
        end
    end
    return loaded
end

local function _release_icon_packages(loaded)
    for i = 1, #loaded do
        if mod:package_status(loaded[i]) == 'loaded' then
            mod:unload_package(loaded[i])
        end
    end
end

local WeaponStatsView = class('WeaponStatsView', 'BaseView')

-- Cached on the class so re-opening the view is instant.
function WeaponStatsView:_build_weapon_list()
    if WeaponStatsView._weapon_list then
        return WeaponStatsView._weapon_list
    end

    local list = {}
    for name, weapon_template in pairs(WeaponTemplates) do
        if weapon_template.base_stats ~= nil then
            local is_ranged = WeaponTemplate.is_ranged(weapon_template)
            local display_name, sub_name = Utils.weapon_display_name(name)
            list[#list + 1] = {
                name = display_name or Utils.friendly_action_label(name),
                sub_display_name = sub_name,
                weapon_template = weapon_template,
                is_ranged = is_ranged,
            }
        end
    end

    table.sort(list, function(a, b)
        if a.is_ranged ~= b.is_ranged then
            return not a.is_ranged -- melee first
        end
        return a.name:lower() < b.name:lower()
    end)

    WeaponStatsView._weapon_list = list
    return list
end

-- Placeholder item with every stat trait maxed (0.8), in the shape build_stats expects.
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

function WeaponStatsView:ui_renderer()
    return self._ui_renderer
end

function WeaponStatsView:init(settings, context)
    self._definitions =
        mod:io_dofile('WeaponStats/scripts/mods/WeaponStats/weapon_stats_view/weapon_stats_view_definitions')

    WeaponStatsView.super.init(self, self._definitions, settings)

    self._pass_draw = false
    self._weapon_list = self:_build_weapon_list()
    self._last_search_text = ''
    self._initial_weapon_template = context and context.weapon_template_name or nil
end

function WeaponStatsView:on_enter()
    WeaponStatsView.super.on_enter(self)

    self._loaded_icon_packages = _load_icon_packages()

    self:_setup_input_legend()
    self:_setup_search()
    self:_setup_list_grid()
    self:_setup_detail_grid()
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

-- Grid elements ----------------------------------------------------------

function WeaponStatsView:_setup_list_grid()
    if self._list_grid then
        self._list_grid = nil
        self:_remove_element('list_grid')
    end

    local grid_settings = self._definitions.list_grid_settings
    self._list_grid = self:_add_element(ViewElementGrid, 'list_grid', 10, grid_settings)
    self:_update_list_grid_position()
end

function WeaponStatsView:_setup_detail_grid()
    if self._detail_grid then
        self._detail_grid = nil
        self:_remove_element('detail_grid')
    end

    local grid_settings = self._definitions.detail_grid_settings
    self._detail_grid = self:_add_element(ViewElementGrid, 'detail_grid', 10, grid_settings)
    self:_update_detail_grid_position()
end

function WeaponStatsView:_update_list_grid_position()
    if not self._list_grid then
        return
    end

    local position = self:_scenegraph_world_position('weapon_stats_list_content')
    if position then
        self._list_grid:set_pivot_offset(position[1], position[2])
    end
end

function WeaponStatsView:_update_detail_grid_position()
    if not self._detail_grid then
        return
    end

    local position = self:_scenegraph_world_position('weapon_stats_detail_content')
    if position then
        self._detail_grid:set_pivot_offset(position[1], position[2])
    end
end

function WeaponStatsView:_list_width()
    local grid_settings = self._definitions.list_grid_settings
    return grid_settings and grid_settings.grid_size[1] or 480
end

function WeaponStatsView:_detail_width()
    local grid_settings = self._definitions.detail_grid_settings
    return grid_settings and grid_settings.grid_size[1] or 600
end

-- Matches the in-game card: title = family, subtext = kind + pattern • mark.
function WeaponStatsView:_format_entry_subtext(entry)
    local kind = entry.is_ranged and mod:localize('kind_ranged') or mod:localize('kind_melee')
    if entry.sub_display_name and entry.sub_display_name ~= '' then
        return kind .. ' • ' .. entry.sub_display_name, Color.terminal_text_body_sub_header(255, true)
    end
    return kind, Color.terminal_text_body_sub_header(255, true)
end

-- Weapon list ------------------------------------------------------------

function WeaponStatsView:_setup_entries()
    local search_widget = self._widgets_by_name.weapon_stats_search
    local search_text = search_widget and search_widget.content.input_text or ''
    search_text = search_text:lower()

    local entries = {}
    for i = 1, #self._weapon_list do
        local weapon = self._weapon_list[i]
        local name = weapon.name
        local sub_name = weapon.sub_display_name or ''
        local match = search_text == ''
            or name:lower():find(search_text, 1, true)
            or sub_name:lower():find(search_text, 1, true)
            or weapon.name:lower():find(search_text, 1, true)
        if match then
            local entry = {
                widget_type = 'weapon_entry',
                name = weapon.name,
                sub_display_name = weapon.sub_display_name,
                weapon = weapon,
                is_ranged = weapon.is_ranged,
            }
            entry.subtext, entry.subtext_color = self:_format_entry_subtext(entry)
            entries[#entries + 1] = entry
        end
    end

    self._filtered_list = entries
    self._selected_entry = nil

    local blueprints = make_list_blueprints(self:_list_width())
    local left_click_callback = callback(self, 'cb_on_list_entry_left_pressed')
    local on_present_callback = callback(self, '_cb_on_list_presented')
    local display_name = nil
    local grow_direction = 'down'

    self._list_grid:present_grid_layout(
        entries,
        blueprints,
        left_click_callback,
        nil,
        display_name,
        grow_direction,
        on_present_callback
    )
end

function WeaponStatsView:_cb_on_list_presented()
    local entries = self._filtered_list
    if not entries or #entries == 0 then
        self:_present_detail(nil)
        return
    end

    local initial_template = self._initial_weapon_template
    local match_index = nil
    if initial_template then
        for i = 1, #entries do
            if entries[i].weapon.name == initial_template then
                match_index = i
                break
            end
        end
    end
    match_index = match_index or 1
    self._list_grid:select_grid_index(match_index)
    self:_select_entry(entries[match_index])
    self._initial_weapon_template = nil
end

function WeaponStatsView:cb_on_list_entry_left_pressed(widget, element)
    self:_select_entry(element)
end

function WeaponStatsView:_select_entry(entry)
    self._selected_entry = entry
    if entry then
        local index = self._list_grid:index_by_element(entry)
        if index then
            self._list_grid:select_grid_index(index)
        end
    end
    self:_present_detail(entry)
end

-- Detail panel -----------------------------------------------------------

function WeaponStatsView:_present_detail(entry)
    if not self._detail_grid then
        return
    end

    local width = self:_detail_width()
    local blueprints = make_detail_blueprints(width)

    local layout = {}
    if entry then
        layout[#layout + 1] = {
            widget_type = 'header',
            text = entry.name,
            color = Color.terminal_text_header(255, true),
        }
        if entry.subtext then
            layout[#layout + 1] = {
                widget_type = 'subtext',
                text = entry.subtext,
                color = entry.subtext_color,
            }
        end
        layout[#layout + 1] = { widget_type = 'spacer', size = 'group' }

        local weapon = entry.weapon
        local item = WeaponStatsView._placeholder_item(weapon.weapon_template)
        local records = Builder.build_stats(item)

        local stripe_count = 0
        for i = 1, #records do
            local record = records[i]
            local rtype = record.type
            if rtype == 'stat' then
                local grid_entry = {
                    widget_type = 'stat',
                    label = record.label,
                    value = record.value,
                    label_color = record.label_color,
                    indent = record.indent or 0,
                    stripe = stripe_count % 2 == 1,
                }
                layout[#layout + 1] = grid_entry
                stripe_count = stripe_count + 1
            elseif rtype == 'table' then
                layout[#layout + 1] = { widget_type = 'spacer', size = 'tight' }
                layout[#layout + 1] = { widget_type = 'table', record = record }
                stripe_count = 0
            elseif rtype == 'chain' then
                layout[#layout + 1] = {
                    widget_type = 'chain',
                    title = record.title,
                    chain = record.chain,
                }
                stripe_count = 0
            else
                layout[#layout + 1] = {
                    widget_type = rtype,
                    text = record.text,
                    color = record.color,
                    size = record.size,
                    indent = record.indent,
                }
            end
        end
    end

    local left_click_callback = callback(self, 'cb_on_detail_entry_left_pressed')
    self._detail_grid:present_grid_layout(layout, blueprints, left_click_callback)
end

function WeaponStatsView:cb_on_detail_entry_left_pressed(widget, element)
    -- Non-interactive detail grid; left clicks are absorbed but do nothing.
    return
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

    return WeaponStatsView.super.update(self, dt, t, input_service)
end

function WeaponStatsView:on_exit()
    if self._input_legend_element then
        self._input_legend_element = nil
        self:_remove_element('input_legend')
    end

    if self._list_grid then
        self._list_grid = nil
        self:_remove_element('list_grid')
    end

    if self._detail_grid then
        self._detail_grid = nil
        self:_remove_element('detail_grid')
    end

    _release_icon_packages(self._loaded_icon_packages)
    self._loaded_icon_packages = nil

    WeaponStatsView.super.on_exit(self)
end

return WeaponStatsView
