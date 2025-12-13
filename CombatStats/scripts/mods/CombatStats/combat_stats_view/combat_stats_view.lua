local mod = get_mod('CombatStats')

local UIWidget = mod:original_require('scripts/managers/ui/ui_widget')
local UIWidgetGrid = mod:original_require('scripts/ui/widget_logic/ui_widget_grid')
local UIRenderer = mod:original_require('scripts/managers/ui/ui_renderer')
local ViewElementInputLegend =
    mod:original_require('scripts/ui/view_elements/view_element_input_legend/view_element_input_legend')
local Missions = mod:original_require('scripts/settings/mission/mission_templates')
local BuffTemplates = mod:original_require('scripts/settings/buff/buff_templates')

local CombatStatsTracker = mod:io_dofile('CombatStats/scripts/mods/CombatStats/combat_stats_tracker')
local CombatStatsUtils = mod:io_dofile('CombatStats/scripts/mods/CombatStats/combat_stats_utils')
local CombatStatsView = class('CombatStatsView', 'BaseView')

function CombatStatsView:init(settings, context)
    self._definitions =
        mod:io_dofile('CombatStats/scripts/mods/CombatStats/combat_stats_view/combat_stats_view_definitions')
    self._blueprints =
        mod:io_dofile('CombatStats/scripts/mods/CombatStats/combat_stats_view/combat_stats_view_blueprints')
    self._settings = mod:io_dofile('CombatStats/scripts/mods/CombatStats/combat_stats_view/combat_stats_view_settings')

    CombatStatsView.super.init(self, self._definitions, settings)

    self._pass_draw = false
    self._using_cursor_navigation = Managers.ui:using_cursor_navigation()
    self._viewing_history = false
    self._tracker = mod.tracker
end

function CombatStatsView:on_enter()
    CombatStatsView.super.on_enter(self)

    self:_setup_input_legend()
    self:_setup_search()
    self:_setup_entries()
end

function CombatStatsView:_setup_search()
    local search_widget = self._widgets_by_name.combat_stats_search
    if search_widget then
        search_widget.content.input_text = ''
        search_widget.content.placeholder_text = mod:localize('search_placeholder')

        -- Adjust colors to match the view better
        local style = search_widget.style
        if style then
            -- Make background slightly lighter
            style.background.color = { 255, 30, 30, 30 }
            -- Make baseline more subtle
            style.baseline.color = Color.terminal_text_body(100, true)
        end
    end
end

function CombatStatsView:_setup_input_legend()
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

function CombatStatsView:_get_mission_display_name(mission_info)
    if not mission_info or not mission_info.name then
        return nil
    end

    local mission_settings = Missions[mission_info.name]
    if mission_settings and mission_settings.mission_name then
        return Localize(mission_settings.mission_name)
    end

    return mission_info.name
end

function CombatStatsView:_setup_entries()
    if self._entry_widgets then
        for i = 1, #self._entry_widgets do
            local widget = self._entry_widgets[i]
            self:_unregister_widget_name(widget.name)
        end
        self._entry_widgets = {}
    end

    local entries = {}

    -- Get search filter
    local search_widget = self._widgets_by_name.combat_stats_search
    local search_text = search_widget and search_widget.content.input_text or ''
    search_text = search_text:lower()

    if self._viewing_history then
        -- Load history entries
        local history_entries = mod.history:get_history_entries()

        for _, history_entry in ipairs(history_entries) do
            local mission_display = self:_get_mission_display_name(history_entry.mission) or history_entry.mission.name
            local display_name = history_entry.date .. ' | ' .. mission_display

            if search_text == '' or display_name:lower():find(search_text, 1, true) then
                entries[#entries + 1] = {
                    widget_type = 'stats_entry',
                    name = display_name,
                    duration = history_entry.duration,
                    stats = history_entry.stats,
                    buffs = history_entry.buffs,
                    is_session = true,
                    is_history = true,
                    history_data = history_entry,
                    pressed_function = function(parent, widget, entry)
                        parent:_load_history_entry(entry)
                    end,
                }
            end
        end
    else
        local tracker = self._tracker
        if not tracker then
            return
        end

        local current_time = Managers.time:time('gameplay')
        local engagements = tracker:get_engagement_stats()
        local session = tracker:get_session_stats()

        -- Add session stats with mission name from tracker
        local session_name = self:_get_mission_display_name(tracker:get_mission()) or mod:localize('overall_stats')

        entries[#entries + 1] = {
            widget_type = 'stats_entry',
            name = session_name,
            start_time = nil,
            end_time = nil,
            duration = session.duration,
            stats = session.stats,
            buffs = session.buffs,
            is_session = true,
            pressed_function = function(parent, widget, entry)
                parent:_select_entry(widget, entry)
            end,
        }

        -- Add all engagements in reverse order (newest first) if they match search
        for i = #engagements, 1, -1 do
            local engagement = engagements[i]
            local duration = (engagement.end_time or current_time) - engagement.start_time
            local breed_name = engagement.name or (mod:localize('enemy') .. ' ' .. i)
            local display_name = CombatStatsUtils.get_breed_display_name(breed_name)

            if
                search_text == ''
                or display_name:lower():find(search_text, 1, true)
                or breed_name:lower():find(search_text, 1, true)
                or engagement.type:lower():find(search_text, 1, true)
            then
                entries[#entries + 1] = {
                    widget_type = 'stats_entry',
                    name = display_name,
                    breed_name = breed_name,
                    type = engagement.type,
                    start_time = engagement.start_time,
                    end_time = engagement.end_time,
                    duration = duration,
                    stats = engagement.stats,
                    buffs = engagement.buffs,
                    is_session = false,
                    pressed_function = function(parent, widget, entry)
                        parent:_select_entry(widget, entry)
                    end,
                }
            end
        end
    end

    local scenegraph_id = 'combat_stats_list_pivot'
    local callback_name = 'cb_on_entry_pressed'

    self._entry_widgets, self._entry_alignment_list = self:_setup_widgets(entries, scenegraph_id, callback_name)

    local grid_scenegraph_id = 'combat_stats_list_background'
    local grid_spacing = self._settings.grid_spacing

    self._entry_grid =
        self:_setup_grid(self._entry_widgets, self._entry_alignment_list, grid_scenegraph_id, grid_spacing)

    local scrollbar_widget = self._widgets_by_name.combat_stats_list_scrollbar
    self._entry_grid:assign_scrollbar(scrollbar_widget, 'combat_stats_list_pivot', grid_scenegraph_id)
    self._entry_grid:set_scrollbar_progress(0)

    -- Select first entry by default
    if #self._entry_widgets > 0 then
        self:_select_entry(self._entry_widgets[1], entries[1])
    end
end

function CombatStatsView:_setup_widgets(content, scenegraph_id, callback_name)
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

function CombatStatsView:_setup_grid(widgets, alignment_list, grid_scenegraph_id, spacing)
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

function CombatStatsView:_select_entry(widget, entry)
    self._selected_entry = entry
    self:_rebuild_detail_widgets(entry)
end

function CombatStatsView:_rebuild_detail_widgets(entry)
    -- Clear existing detail widgets
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

    local stats = entry.stats
    local duration = entry.duration
    local buffs = entry.buffs or {}

    local detail_scenegraph = self._ui_scenegraph.combat_stats_detail_content
    local detail_content_width = detail_scenegraph.size[1]

    local bar_height = 20
    local text_width = detail_content_width

    -- Helper to create text widget
    local function create_text(text, color, font_size)
        font_size = font_size or 18
        -- Calculate height based on font size with some padding
        local height = font_size + 10

        local widget_def = UIWidget.create_definition({
            {
                pass_type = 'text',
                value_id = 'text',
                value = text,
                style = {
                    font_type = 'proxima_nova_bold',
                    font_size = font_size,
                    text_horizontal_alignment = 'left',
                    text_vertical_alignment = 'top',
                    text_color = color or Color.terminal_text_body(255, true),
                    offset = { 0, 0, 2 },
                    size = { text_width, height },
                },
            },
        }, 'combat_stats_detail_pivot', nil, { text_width, height })

        local widget = self:_create_widget('detail_text_' .. #self._detail_widgets, widget_def)
        self._detail_widgets[#self._detail_widgets + 1] = widget
        return widget
    end

    -- Helper to create progress bar with optional icon
    local function create_progress_bar(label, value, max_value, color, icon, gradient_map)
        local pct = max_value > 0 and (value / max_value) or 0
        pct = math.min(pct, 1.0)

        -- Layout: [icon] label | bar
        local icon_size = icon and 24 or 0
        local icon_spacing = icon and 5 or 0
        local label_width = text_width * 0.5 - icon_size - icon_spacing
        local bar_width = text_width * 0.5 - 20
        local widget_height = bar_height + 10 -- Increased padding to prevent overlap

        local passes = {}

        -- Icon pass (if icon exists)
        if icon then
            passes[#passes + 1] = {
                pass_type = 'texture',
                style_id = 'icon',
                value = 'content/ui/materials/icons/buffs/hud/buff_container_with_background',
                style = {
                    horizontal_alignment = 'left',
                    vertical_alignment = 'center',
                    offset = { 0, 0, 2 },
                    size = { icon_size, icon_size },
                    color = Color.white(255, true),
                    material_values = {
                        talent_icon = icon,
                        gradient_map = gradient_map,
                    },
                },
            }
        end

        -- Label pass
        passes[#passes + 1] = {
            pass_type = 'text',
            value_id = 'label',
            value = label,
            style = {
                font_type = 'proxima_nova_bold',
                font_size = 16,
                text_horizontal_alignment = 'left',
                text_vertical_alignment = 'center',
                text_color = Color.terminal_text_body(255, true),
                offset = { icon_size + icon_spacing, 0, 2 },
                size = { label_width, bar_height },
                text_overflow_mode = 'truncate',
            },
        }

        -- Background bar
        passes[#passes + 1] = {
            pass_type = 'rect',
            style = {
                offset = { text_width * 0.5 + 10, 0, 1 },
                size = { bar_width, bar_height },
                color = { 100, 50, 50, 50 },
            },
        }

        -- Progress bar
        passes[#passes + 1] = {
            pass_type = 'rect',
            style_id = 'bar',
            style = {
                offset = { text_width * 0.5 + 10, 0, 2 },
                size = { bar_width * pct, bar_height },
                color = color or Color.ui_terminal(255, true),
            },
        }

        -- Percentage text
        passes[#passes + 1] = {
            pass_type = 'text',
            value_id = 'percentage',
            value = string.format('%.1f%%', pct * 100),
            style = {
                font_type = 'proxima_nova_bold',
                font_size = 14,
                text_horizontal_alignment = 'center',
                text_vertical_alignment = 'center',
                text_color = Color.white(255, true),
                offset = { text_width * 0.5 + 10, 0, 3 },
                size = { bar_width, bar_height },
            },
        }

        local widget_def =
            UIWidget.create_definition(passes, 'combat_stats_detail_pivot', nil, { text_width, widget_height })

        local widget = self:_create_widget('detail_bar_' .. #self._detail_widgets, widget_def)
        self._detail_widgets[#self._detail_widgets + 1] = widget
        return widget
    end

    -- Helper to create spacer widget
    local function create_spacer(height)
        local widget_def = UIWidget.create_definition({
            {
                pass_type = 'rect',
                style = {
                    color = { 0, 0, 0, 0 }, -- Invisible
                },
            },
        }, 'combat_stats_detail_pivot', nil, { text_width, height })

        local widget = self:_create_widget('detail_spacer_' .. #self._detail_widgets, widget_def)
        self._detail_widgets[#self._detail_widgets + 1] = widget
        return widget
    end

    -- Add top padding
    create_spacer(15)

    -- Title
    create_text(entry.name, Color.terminal_text_header(255, true), 26)

    if not entry.is_session then
        -- Enemy stats
        local dps = 0
        if duration > 0 and stats.total_damage > 0 then
            dps = stats.total_damage / duration
        end

        local status_color = Color.terminal_text_body(255, true)
        if entry.end_time then
            status_color = Color.ui_green_light(255, true)
        elseif entry.start_time then
            status_color = Color.ui_hud_yellow_light(255, true)
        end

        local enemy_type_label = mod:localize('breed_' .. entry.type)
        create_text(
            string.format('%s | %.1fs | %.0f %s', enemy_type_label, duration, dps, mod:localize('dps')),
            status_color,
            18
        )
    else
        -- Session stats
        local dps = 0
        if duration > 0 and stats.total_damage > 0 then
            dps = stats.total_damage / duration
        end
        create_text(
            string.format('%.1fs | %.0f %s', duration, dps, mod:localize('dps')),
            Color.terminal_text_body(255, true),
            18
        )
    end

    -- Enemy Stats (only for session stats)
    if entry.is_session and stats.damage_by_type and next(stats.damage_by_type) then
        create_spacer(10)
        create_text(mod:localize('enemy_stats'), Color.terminal_text_header(255, true), 20)

        -- Sort by damage (highest first)
        local sorted_types = {}
        for breed_type, damage in pairs(stats.damage_by_type) do
            local kills = stats.kills[breed_type] or 0
            table.insert(sorted_types, { type = breed_type, damage = damage, kills = kills })
        end
        table.sort(sorted_types, function(a, b)
            return a.damage > b.damage
        end)

        for _, type_data in ipairs(sorted_types) do
            local breed_type = type_data.type
            local damage = type_data.damage
            local kills = type_data.kills
            local pct = (damage / stats.total_damage * 100)

            -- Color coding by enemy type
            local color = Color.white(255, true)
            if breed_type == 'monster' then
                color = Color.ui_red_medium(255, true)
            elseif breed_type == 'disabler' or breed_type == 'special' then
                color = { 255, 255, 165, 0 } -- Orange
            elseif breed_type == 'elite' then
                color = Color.ui_hud_yellow_medium(255, true)
            end

            create_progress_bar(
                string.format(
                    '%s: %d kills | %d dmg (%.1f%%)',
                    mod:localize('breed_' .. breed_type),
                    kills,
                    damage,
                    pct
                ),
                damage,
                stats.total_damage,
                color
            )
        end
    end

    -- Damage Stats Header
    if stats.total_damage > 0 then
        create_spacer(10)
        create_text(mod:localize('damage_stats'), Color.terminal_text_header(255, true), 20)
        create_text(string.format('%s: %d', mod:localize('total'), stats.total_damage))

        -- Melee damage
        if stats.melee_damage and stats.melee_damage > 0 then
            create_progress_bar(
                string.format('%s: %d', mod:localize('melee'), stats.melee_damage),
                stats.melee_damage,
                stats.total_damage,
                Color.gray(255, true)
            )

            if stats.melee_crit_damage and stats.melee_crit_damage > 0 then
                local pct = (stats.melee_crit_damage / stats.melee_damage * 100)
                create_text(string.format('  %s: %d (%.1f%%)', mod:localize('crit'), stats.melee_crit_damage, pct))
            end
            if stats.melee_weakspot_damage and stats.melee_weakspot_damage > 0 then
                local pct = (stats.melee_weakspot_damage / stats.melee_damage * 100)
                create_text(
                    string.format('  %s: %d (%.1f%%)', mod:localize('weakspot'), stats.melee_weakspot_damage, pct)
                )
            end
        end

        -- Ranged damage
        if stats.ranged_damage and stats.ranged_damage > 0 then
            create_progress_bar(
                string.format('%s: %d', mod:localize('ranged'), stats.ranged_damage),
                stats.ranged_damage,
                stats.total_damage,
                { 255, 139, 101, 69 }
            )

            if stats.ranged_crit_damage and stats.ranged_crit_damage > 0 then
                local pct = (stats.ranged_crit_damage / stats.ranged_damage * 100)
                create_text(string.format('  %s: %d (%.1f%%)', mod:localize('crit'), stats.ranged_crit_damage, pct))
            end
            if stats.ranged_weakspot_damage and stats.ranged_weakspot_damage > 0 then
                local pct = (stats.ranged_weakspot_damage / stats.ranged_damage * 100)
                create_text(
                    string.format('  %s: %d (%.1f%%)', mod:localize('weakspot'), stats.ranged_weakspot_damage, pct)
                )
            end
        end

        -- Explosion damage
        if stats.explosion_damage and stats.explosion_damage > 0 then
            create_progress_bar(
                string.format('%s: %d', mod:localize('explosion'), stats.explosion_damage),
                stats.explosion_damage,
                stats.total_damage,
                { 255, 255, 100, 0 }
            )
        end

        -- Companion damage
        if stats.companion_damage and stats.companion_damage > 0 then
            create_progress_bar(
                string.format('%s: %d', mod:localize('companion'), stats.companion_damage),
                stats.companion_damage,
                stats.total_damage,
                { 255, 100, 149, 237 }
            )
        end

        -- Buff damage
        if stats.buff_damage and stats.buff_damage > 0 then
            create_progress_bar(
                string.format('%s: %d', mod:localize('buff'), stats.buff_damage),
                stats.buff_damage,
                stats.total_damage,
                Color.ui_hud_green_light(255, true)
            )

            if stats.bleed_damage and stats.bleed_damage > 0 then
                local pct = (stats.bleed_damage / stats.buff_damage * 100)
                create_text(string.format('  %s: %d (%.1f%%)', mod:localize('bleed'), stats.bleed_damage, pct))
            end
            if stats.burn_damage and stats.burn_damage > 0 then
                local pct = (stats.burn_damage / stats.buff_damage * 100)
                create_text(string.format('  %s: %d (%.1f%%)', mod:localize('burn'), stats.burn_damage, pct))
            end
            if stats.toxin_damage and stats.toxin_damage > 0 then
                local pct = (stats.toxin_damage / stats.buff_damage * 100)
                create_text(string.format('  %s: %d (%.1f%%)', mod:localize('toxin'), stats.toxin_damage, pct))
            end
        end
    end

    -- Hit Stats Header
    if stats.total_hits > 0 then
        create_spacer(10)
        create_text(mod:localize('hit_stats'), Color.terminal_text_header(255, true), 20)
        create_text(string.format('%s: %d', mod:localize('total'), stats.total_hits))

        -- Melee hits
        if stats.melee_hits and stats.melee_hits > 0 then
            create_progress_bar(
                string.format('%s: %d', mod:localize('melee'), stats.melee_hits),
                stats.melee_hits,
                stats.total_hits,
                Color.gray(255, true)
            )

            if stats.melee_crit_hits and stats.melee_crit_hits > 0 then
                local pct = (stats.melee_crit_hits / stats.melee_hits * 100)
                create_text(string.format('  %s: %d (%.1f%%)', mod:localize('crit'), stats.melee_crit_hits, pct))
            end
            if stats.melee_weakspot_hits and stats.melee_weakspot_hits > 0 then
                local pct = (stats.melee_weakspot_hits / stats.melee_hits * 100)
                create_text(
                    string.format('  %s: %d (%.1f%%)', mod:localize('weakspot'), stats.melee_weakspot_hits, pct)
                )
            end
        end

        -- Ranged hits
        if stats.ranged_hits and stats.ranged_hits > 0 then
            create_progress_bar(
                string.format('%s: %d', mod:localize('ranged'), stats.ranged_hits),
                stats.ranged_hits,
                stats.total_hits,
                { 255, 139, 101, 69 }
            )

            if stats.ranged_crit_hits and stats.ranged_crit_hits > 0 then
                local pct = (stats.ranged_crit_hits / stats.ranged_hits * 100)
                create_text(string.format('  %s: %d (%.1f%%)', mod:localize('crit'), stats.ranged_crit_hits, pct))
            end
            if stats.ranged_weakspot_hits and stats.ranged_weakspot_hits > 0 then
                local pct = (stats.ranged_weakspot_hits / stats.ranged_hits * 100)
                create_text(
                    string.format('  %s: %d (%.1f%%)', mod:localize('weakspot'), stats.ranged_weakspot_hits, pct)
                )
            end
        end
    end

    -- Buff Uptime
    if duration > 0 and buffs then
        -- Convert raw buff data to sorted array for display
        local buff_array = {}
        for buff_template_name, uptime in pairs(buffs) do
            local display_name = CombatStatsUtils.get_buff_display_name(buff_template_name)
            local icon, gradient_map = CombatStatsUtils.get_buff_icon(buff_template_name)

            buff_array[#buff_array + 1] = {
                name = display_name,
                uptime = uptime,
                icon = icon,
                gradient_map = gradient_map,
            }
        end

        -- Sort by uptime descending
        table.sort(buff_array, function(a, b)
            -- Safety check: ensure uptimes are numbers
            local a_uptime = type(a.uptime) == 'number' and a.uptime or 0
            local b_uptime = type(b.uptime) == 'number' and b.uptime or 0
            return a_uptime > b_uptime
        end)

        if #buff_array > 0 then
            create_spacer(10)
            create_text(mod:localize('buff_uptime'), Color.terminal_text_header(255, true), 20)

            for i = 1, #buff_array do
                local buff = buff_array[i]
                create_progress_bar(
                    buff.name,
                    buff.uptime,
                    duration,
                    Color.ui_terminal(255, true),
                    buff.icon,
                    buff.gradient_map
                )
            end
        end
    end

    -- Setup detail grid for scrolling
    if #self._detail_widgets > 0 then
        local detail_grid_scenegraph_id = 'combat_stats_detail_content'
        local detail_grid_spacing = { 0, 0 }

        self._detail_grid =
            self:_setup_grid(self._detail_widgets, self._detail_widgets, detail_grid_scenegraph_id, detail_grid_spacing)

        local detail_scrollbar_widget = self._widgets_by_name.combat_stats_detail_scrollbar
        if detail_scrollbar_widget then
            self._detail_grid:assign_scrollbar(
                detail_scrollbar_widget,
                'combat_stats_detail_pivot',
                detail_grid_scenegraph_id
            )
            self._detail_grid:set_scrollbar_progress(0)
        end
    end
end

function CombatStatsView:cb_on_entry_pressed(widget, entry)
    local pressed_function = entry.pressed_function
    if pressed_function then
        pressed_function(self, widget, entry)
    end
end

function CombatStatsView:cb_on_close_pressed()
    Managers.ui:close_view(self.view_name)
end

function CombatStatsView:cb_on_reset_pressed()
    -- Don't reset if typing in search
    local search_widget = self._widgets_by_name.combat_stats_search
    if search_widget and search_widget.content.is_writing then
        return
    end

    if mod.tracker then
        mod.tracker:reset()
        self:_setup_entries()
    end
end

function CombatStatsView:cb_on_history_pressed()
    self._viewing_history = true
    self._selected_entry = nil
    self:_setup_entries()
end

function CombatStatsView:cb_on_back_to_current_pressed()
    self._viewing_history = false
    self._selected_entry = nil
    self._tracker = mod.tracker

    self:_setup_entries()
end

function CombatStatsView:_load_history_entry(entry)
    if not entry.history_data then
        return
    end

    -- Create a temporary tracker for history viewing
    self._tracker = CombatStatsTracker:new()
    self._tracker:load_from_history(entry.history_data)

    -- Switch back to normal view (not history list view) and clear selection
    self._viewing_history = false
    self._selected_entry = nil

    -- Refresh entries - will now show the loaded history data
    self:_setup_entries()
end

function CombatStatsView:update(dt, t, input_service)
    -- Check if search text changed
    local search_widget = self._widgets_by_name.combat_stats_search
    if search_widget then
        local current_search = search_widget.content.input_text or ''
        if current_search ~= self._last_search_text then
            self._last_search_text = current_search
            self:_setup_entries()
        end
    end

    -- Update grids with proper input handling
    local widgets_by_name = self._widgets_by_name

    if self._entry_grid and widgets_by_name.combat_stats_list_interaction then
        local list_interaction = widgets_by_name.combat_stats_list_interaction
        local is_list_hovered = not self._using_cursor_navigation or list_interaction.content.hotspot.is_hover or false
        local list_input_service = is_list_hovered and input_service or input_service:null_service()
        self._entry_grid:update(dt, t, list_input_service)
    end

    if self._detail_grid and widgets_by_name.combat_stats_detail_interaction then
        local detail_interaction = widgets_by_name.combat_stats_detail_interaction
        local is_detail_hovered = not self._using_cursor_navigation
            or detail_interaction.content.hotspot.is_hover
            or false
        local detail_input_service = is_detail_hovered and input_service or input_service:null_service()
        self._detail_grid:update(dt, t, detail_input_service)
    end

    return CombatStatsView.super.update(self, dt, t, input_service)
end

function CombatStatsView:_draw_grid(grid, widgets, interaction_widget, ui_renderer, is_grid_hovered)
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

function CombatStatsView:_draw_widgets(dt, t, input_service, ui_renderer)
    CombatStatsView.super._draw_widgets(self, dt, t, input_service, ui_renderer)

    local ui_scenegraph = self._ui_scenegraph
    local render_settings = self._render_settings
    local widgets_by_name = self._widgets_by_name

    -- Update scrollbar visibility
    if self._entry_grid then
        local list_scrollbar = widgets_by_name.combat_stats_list_scrollbar
        if list_scrollbar then
            list_scrollbar.content.visible = self._entry_grid:can_scroll()
        end
    end

    if self._detail_grid then
        local detail_scrollbar = widgets_by_name.combat_stats_detail_scrollbar
        if detail_scrollbar then
            detail_scrollbar.content.visible = self._detail_grid:can_scroll()
        end
    end

    UIRenderer.begin_pass(ui_renderer, ui_scenegraph, input_service, dt, render_settings)

    -- Draw entry grid
    local grid_interaction_widget = widgets_by_name.combat_stats_list_interaction
    local is_list_hovered = not self._using_cursor_navigation
        or grid_interaction_widget.content.hotspot.is_hover
        or false
    self:_draw_grid(self._entry_grid, self._entry_widgets, grid_interaction_widget, ui_renderer, is_list_hovered)

    -- Draw detail grid
    local detail_interaction_widget = widgets_by_name.combat_stats_detail_interaction
    local is_detail_hovered = not self._using_cursor_navigation
        or detail_interaction_widget.content.hotspot.is_hover
        or false
    self:_draw_grid(self._detail_grid, self._detail_widgets, detail_interaction_widget, ui_renderer, is_detail_hovered)

    UIRenderer.end_pass(ui_renderer)
end

function CombatStatsView:on_exit()
    if self._input_legend_element then
        self._input_legend_element = nil
        self:_remove_element('input_legend')
    end

    CombatStatsView.super.on_exit(self)
end

return CombatStatsView
