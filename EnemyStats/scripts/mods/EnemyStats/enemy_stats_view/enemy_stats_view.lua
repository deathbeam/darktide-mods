local mod = get_mod('EnemyStats')

local ViewElementInputLegend =
    mod:original_require('scripts/ui/view_elements/view_element_input_legend/view_element_input_legend')
local ViewElementGrid = mod:original_require('scripts/ui/view_elements/view_element_grid/view_element_grid')

local Data = mod:io_dofile('EnemyStats/scripts/mods/EnemyStats/enemy_stats_data')
local make_list_blueprints =
    mod:io_dofile('EnemyStats/scripts/mods/EnemyStats/enemy_stats_view/enemy_stats_view_blueprints')
local make_detail_blueprints =
    mod:io_dofile('EnemyStats/scripts/mods/EnemyStats/enemy_stats_view/enemy_stats_detail_blueprints')

local EnemyStatsView = class('EnemyStatsView', 'BaseView')

function EnemyStatsView:init(settings, context)
    self._definitions =
        mod:io_dofile('EnemyStats/scripts/mods/EnemyStats/enemy_stats_view/enemy_stats_view_definitions')

    EnemyStatsView.super.init(self, self._definitions, settings)

    self._pass_draw = false
    self._enemy_groups = Data.build_enemy_list()
    self._flat_list = {}
    for _, cat in ipairs(Data.category_order()) do
        local group = self._enemy_groups[cat] or {}
        for i = 1, #group do
            self._flat_list[#self._flat_list + 1] = group[i]
        end
    end
    self._last_search_text = ''
    self._initial_breed = context and context.breed_name or nil
end

function EnemyStatsView:on_enter()
    EnemyStatsView.super.on_enter(self)

    self:_setup_input_legend()
    self:_setup_search()
    self:_setup_list_grid()
    self:_setup_detail_grid()
    self:_setup_entries()
end

function EnemyStatsView:_setup_search()
    local search_widget = self._widgets_by_name.enemy_stats_search
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

function EnemyStatsView:_setup_input_legend()
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

function EnemyStatsView:_setup_list_grid()
    if self._list_grid then
        self._list_grid = nil
        self:_remove_element('list_grid')
    end

    local grid_settings = self._definitions.list_grid_settings
    self._list_grid = self:_add_element(ViewElementGrid, 'list_grid', 10, grid_settings)
    self:_update_list_grid_position()
end

function EnemyStatsView:_setup_detail_grid()
    if self._detail_grid then
        self._detail_grid = nil
        self:_remove_element('detail_grid')
    end

    local grid_settings = self._definitions.detail_grid_settings
    self._detail_grid = self:_add_element(ViewElementGrid, 'detail_grid', 10, grid_settings)
    self:_update_detail_grid_position()
end

function EnemyStatsView:_update_list_grid_position()
    if not self._list_grid then
        return
    end

    local position = self:_scenegraph_world_position('enemy_stats_list_content')
    if position then
        self._list_grid:set_pivot_offset(position[1], position[2])
    end
end

function EnemyStatsView:_update_detail_grid_position()
    if not self._detail_grid then
        return
    end

    local position = self:_scenegraph_world_position('enemy_stats_detail_content')
    if position then
        self._detail_grid:set_pivot_offset(position[1], position[2])
    end
end

function EnemyStatsView:_list_width()
    local grid_settings = self._definitions.list_grid_settings
    return grid_settings and grid_settings.grid_size[1] or 480
end

function EnemyStatsView:_detail_width()
    local grid_settings = self._definitions.detail_grid_settings
    return grid_settings and grid_settings.grid_size[1] or 600
end

-- Enemy list ------------------------------------------------------------

function EnemyStatsView:_setup_entries()
    local search_widget = self._widgets_by_name.enemy_stats_search
    local search_text = search_widget and search_widget.content.input_text or ''
    search_text = search_text:lower()

    local entries = {}
    for _, cat in ipairs(Data.category_order()) do
        local group = self._enemy_groups[cat] or {}
        for i = 1, #group do
            local entry = group[i]
            local label = entry.label
            local match = search_text == ''
                or label:lower():find(search_text, 1, true)
                or entry.breed_name:lower():find(search_text, 1, true)
            if match then
                entries[#entries + 1] = {
                    widget_type = 'enemy_entry',
                    name = label,
                    subtext = self:_format_list_subtext(entry),
                    subtext_color = Color.terminal_text_body_sub_header(255, true),
                    breed_name = entry.breed_name,
                    category = cat,
                    size = entry.size,
                    is_ranged = entry.is_ranged,
                    faction = entry.faction,
                }
            end
        end
    end

    self._filtered_list = entries

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

function EnemyStatsView:_format_list_subtext(entry)
    local size_label = mod:localize('size_' .. entry.size)
    local role_label = mod:localize(entry.is_ranged and 'role_ranged' or 'role_melee')
    local faction_label = mod:localize('faction_' .. entry.faction)
    return string.format('%s | %s | %s', size_label, role_label, faction_label)
end

function EnemyStatsView:_cb_on_list_presented()
    local entries = self._filtered_list
    if not entries or #entries == 0 then
        self:_present_detail(nil)
        return
    end

    local initial_breed = self._initial_breed
    local match_index = nil
    if initial_breed then
        for i = 1, #entries do
            if entries[i].breed_name == initial_breed then
                match_index = i
                break
            end
        end
    end
    match_index = match_index or 1
    self._list_grid:select_grid_index(match_index)
    self._list_grid:scroll_to_grid_index(match_index)
    self:_select_entry(entries[match_index])
    self._initial_breed = nil
end

function EnemyStatsView:cb_on_list_entry_left_pressed(widget, element)
    self:_select_entry(element)
end

function EnemyStatsView:_select_entry(entry)
    if entry then
        local index = self._list_grid:index_by_element(entry)
        if index then
            self._list_grid:select_grid_index(index)
        end
    end
    self:_present_detail(entry)
end

-- Detail panel -----------------------------------------------------------

function EnemyStatsView:_present_detail(entry)
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

        local info = Data.breed_info(entry.breed_name)
        if info then
            layout[#layout + 1] = { widget_type = 'section', text = mod:localize('header_info') }
            layout[#layout + 1] = {
                widget_type = 'stat',
                label = mod:localize('stat_category'),
                value = mod:localize('kind_' .. info.category),
            }
            layout[#layout + 1] = {
                widget_type = 'stat',
                label = mod:localize('stat_size'),
                value = mod:localize('size_' .. info.size),
            }
            local role_key = info.is_ranged and 'role_ranged' or 'role_melee'
            layout[#layout + 1] = {
                widget_type = 'stat',
                label = mod:localize('stat_role'),
                value = mod:localize(role_key),
            }
            layout[#layout + 1] = {
                widget_type = 'stat',
                label = mod:localize('stat_faction'),
                value = mod:localize('faction_' .. info.faction),
            }
            if info.challenge_rating then
                layout[#layout + 1] = {
                    widget_type = 'stat',
                    label = mod:localize('stat_challenge'),
                    value = tostring(info.challenge_rating),
                }
            end
            if info.stagger_resistance then
                layout[#layout + 1] = {
                    widget_type = 'stat',
                    label = mod:localize('stat_stagger_resist'),
                    value = tostring(info.stagger_resistance),
                }
            end
            if info.stagger_reduction then
                layout[#layout + 1] = {
                    widget_type = 'stat',
                    label = mod:localize('stat_stagger_reduction'),
                    value = tostring(info.stagger_reduction),
                }
            end
            if info.run_speed then
                layout[#layout + 1] = {
                    widget_type = 'stat',
                    label = mod:localize('stat_run_speed'),
                    value = string.format('%.1f', info.run_speed),
                }
            end
            layout[#layout + 1] = { widget_type = 'spacer', size = 'group' }
        end

        local diff_rows = Data.difficulty_table(entry.breed_name)
        if diff_rows and #diff_rows > 0 then
            layout[#layout + 1] = {
                widget_type = 'section',
                text = mod:localize('header_health'),
            }
            layout[#layout + 1] = {
                widget_type = 'stat_table',
                difficulty_header = mod:localize('stat_difficulty'),
                columns = {
                    { label = mod:localize('stat_health'), width = 0.0 },
                    { label = mod:localize('stat_hit_mass'), width = 0.0 },
                },
                rows = diff_rows,
            }
            layout[#layout + 1] = { widget_type = 'spacer', size = 'tight' }
        end

        local zones = Data.hit_zones(entry.breed_name)
        if zones and #zones > 0 then
            layout[#layout + 1] = {
                widget_type = 'section',
                text = mod:localize('header_hit_zones'),
            }
            layout[#layout + 1] = {
                widget_type = 'zone_table',
                zone_header = mod:localize('stat_zone'),
                armor_header = mod:localize('stat_armor'),
                weakspot_header = mod:localize('stat_weakspots'),
                rows = zones,
            }
        end
    end

    local left_click_callback = callback(self, 'cb_on_detail_entry_left_pressed')
    self._detail_grid:present_grid_layout(layout, blueprints, left_click_callback)
end

function EnemyStatsView:cb_on_detail_entry_left_pressed(widget, element)
    return
end

function EnemyStatsView:cb_on_close_pressed()
    Managers.ui:close_view(self.view_name)
end

function EnemyStatsView:update(dt, t, input_service)
    local search_widget = self._widgets_by_name.enemy_stats_search
    if search_widget then
        local current_search = search_widget.content.input_text or ''
        if current_search ~= self._last_search_text then
            self._last_search_text = current_search
            self:_setup_entries()
        end
    end

    return EnemyStatsView.super.update(self, dt, t, input_service)
end

function EnemyStatsView:on_exit()
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

    EnemyStatsView.super.on_exit(self)
end

return EnemyStatsView
