local mod = get_mod('CombatStats')

local SharedUtils = mod:io_dofile('CombatStats/scripts/mods/CombatStats/shared/shared_utils')
local CombatStatsTracker = mod:io_dofile('CombatStats/scripts/mods/CombatStats/combat_stats_tracker')
local make_view = mod:io_dofile('CombatStats/scripts/mods/CombatStats/shared/shared_view_base')
local make_detail_blueprints =
    mod:io_dofile('CombatStats/scripts/mods/CombatStats/combat_stats_view/combat_stats_detail_blueprints')

local COLOR_MELEE = Color.gray(255, true)
local COLOR_RANGED = { 255, 139, 101, 69 }
local COLOR_EXPLOSION = { 255, 255, 100, 0 }
local COLOR_COMPANION = { 255, 100, 149, 237 }
local COLOR_ARC = { 255, 186, 85, 211 }

local ICON_PACKAGES = {
    'packages/ui/hud/player_weapon/player_weapon',
    'packages/ui/hud/player_buffs/player_buffs',
    'packages/ui/hud/wield_info/wield_info',
    'packages/ui/views/talent_builder_view/talent_builder_view',
    'packages/ui/material_sets/circumstances',
}

local CombatStatsView = make_view(mod, {
    class_name = 'CombatStatsView',
    prefix = 'combat_stats',
    shared_utils = SharedUtils,
    icon_packages = ICON_PACKAGES,
    definitions_path = 'CombatStats/scripts/mods/CombatStats/combat_stats_view/combat_stats_view_definitions',
    list_blueprints_path = 'CombatStats/scripts/mods/CombatStats/combat_stats_view/combat_stats_view_blueprints',
})

function CombatStatsView:_on_init(settings, context)
    self._viewing_history = false
    self._viewing_history_entry = false
    self._history_loading = false
    self._history_entry_loading = false
    self._tracker = mod.tracker
end

function CombatStatsView:_format_entry_subtext(entry)
    if entry.is_history then
        local date = entry.history_data and entry.history_data.date
        return date or '', Color.terminal_text_body_sub_header(255, true)
    end

    local dps = 0
    if entry.duration > 0 and entry.stats and entry.stats.total_damage then
        dps = entry.stats.total_damage / entry.duration
    end

    if entry.is_session then
        return string.format('%.1fs | %.0f %s', entry.duration, dps, mod:localize('dps')),
            Color.terminal_text_body_sub_header(255, true)
    else
        local status_color = Color.terminal_text_body(255, true)
        if entry.end_time then
            status_color = Color.ui_green_light(255, true)
        elseif entry.start_time then
            status_color = Color.ui_hud_yellow_light(255, true)
        end

        local enemy_type_label = mod:localize('breed_' .. entry.type)
        return string.format('%s | %.1fs | %.0f %s', enemy_type_label, entry.duration, dps, mod:localize('dps')),
            status_color
    end
end

-- Weapon list ------------------------------------------------------------

function CombatStatsView:_setup_entries()
    local entries = {}

    local search_widget = self._widgets_by_name.combat_stats_search
    local search_text = search_widget and search_widget.content.input_text or ''
    search_text = search_text:lower()

    if self._viewing_history then
        local history_entries = mod.history:get_history_entries()

        if #history_entries == 0 then
            local label = self._history_loading and 'Loading history...' or 'No history entries'
            local placeholder = {
                widget_type = 'stats_entry',
                name = label,
                duration = 0,
                stats = {},
                buffs = {},
                is_session = true,
                is_history = true,
                disabled = true,
            }
            placeholder.subtext, placeholder.subtext_color = self:_format_entry_subtext(placeholder)
            entries[#entries + 1] = placeholder
        end

        for _, history_entry in ipairs(history_entries) do
            local mission_display = mod.utils:get_mission_display_name(history_entry.mission_name)
            local class_display = mod.utils:get_archetype_display_name(history_entry.class_name)
            local display_name = class_display .. ' | ' .. mission_display

            if
                search_text == ''
                or display_name:lower():find(search_text, 1, true)
                or history_entry.date:lower():find(search_text, 1, true)
            then
                local entry = {
                    widget_type = 'stats_entry',
                    name = display_name,
                    duration = 0,
                    stats = {},
                    buffs = {},
                    is_session = true,
                    is_history = true,
                    history_data = history_entry,
                }
                entry.subtext, entry.subtext_color = self:_format_entry_subtext(entry)
                entries[#entries + 1] = entry
            end
        end
    else
        if self._history_entry_loading then
            local placeholder = {
                widget_type = 'stats_entry',
                name = 'Loading entry...',
                duration = 0,
                stats = {},
                buffs = {},
                is_session = true,
                disabled = true,
            }
            placeholder.subtext, placeholder.subtext_color = self:_format_entry_subtext(placeholder)
            entries[#entries + 1] = placeholder

            self._filtered_list = entries
            self:_present_list(entries)
            return
        end

        local tracker = self._tracker
        if not tracker then
            self._filtered_list = entries
            self:_present_list(entries)
            return
        end

        local current_time = tracker:get_time()
        local engagements = tracker:get_engagement_stats()
        local session = tracker:get_session_stats()

        local mission_display = mod.utils:get_mission_display_name(tracker:get_mission_name())
        local class_display = mod.utils:get_archetype_display_name(tracker:get_class_name())
        local session_name = class_display .. ' | ' .. mission_display

        local session_entry = {
            widget_type = 'stats_entry',
            name = session_name,
            start_time = nil,
            end_time = nil,
            duration = session.duration,
            stats = session.stats,
            buffs = session.buffs,
            is_session = true,
        }
        session_entry.subtext, session_entry.subtext_color = self:_format_entry_subtext(session_entry)
        entries[#entries + 1] = session_entry

        for i = #engagements, 1, -1 do
            local engagement = engagements[i]
            if engagement.stats.total_damage ~= 0 or engagement.stats.total_hits ~= 0 then
                local duration = (engagement.end_time or current_time) - engagement.start_time
                local breed_name = engagement.name or (mod:localize('enemy') .. ' ' .. i)
                local display_name = mod.utils:get_breed_display_name(breed_name)

                if
                    search_text == ''
                    or display_name:lower():find(search_text, 1, true)
                    or breed_name:lower():find(search_text, 1, true)
                    or engagement.type:lower():find(search_text, 1, true)
                then
                    local enemy_entry = {
                        widget_type = 'stats_entry',
                        name = display_name,
                        type = engagement.type,
                        icon = SharedUtils.category_icon(engagement.type),
                        start_time = engagement.start_time,
                        end_time = engagement.end_time,
                        duration = duration,
                        stats = engagement.stats,
                        buffs = engagement.buffs,
                        is_session = false,
                    }
                    enemy_entry.subtext, enemy_entry.subtext_color = self:_format_entry_subtext(enemy_entry)
                    entries[#entries + 1] = enemy_entry
                end
            end
        end
    end

    self._filtered_list = entries
    self:_present_list(entries)
end

function CombatStatsView:_cb_on_list_presented()
    local entries = self._filtered_list
    if not entries or #entries == 0 then
        self:_present_detail(nil)
        return
    end

    if not self._viewing_history then
        self._list_grid:select_grid_index(1)
        self:_select_entry(entries[1])
    else
        self:_present_detail(nil)
    end
end

function CombatStatsView:cb_on_list_entry_left_pressed(widget, element)
    local entry = element
    if entry and entry.is_history and entry.history_data then
        -- Defer to next frame: present_grid_layout mutates _grid_widgets while
        -- the grid is mid-update inside this click callback, leaving nil holes.
        self._pending_history_entry = entry
    elseif entry then
        self:_select_entry(entry)
    end
end

-- Detail panel -----------------------------------------------------------

function CombatStatsView:_present_detail(entry)
    if not self._detail_grid then
        return
    end

    local width = self:_detail_width()
    local blueprints = make_detail_blueprints(width)

    local layout = {}
    if entry and not entry.disabled then
        layout[#layout + 1] = { widget_type = 'spacer', size = 'group' }
        layout[#layout + 1] = {
            widget_type = 'header_icon',
            text = entry.name,
            icon = entry.icon,
            icon_size = { 80, 80 },
            subtext = entry.subtext,
            subtext_color = entry.subtext_color,
            color = Color.terminal_text_header(255, true),
        }

        local stats = entry.stats
        local duration = entry.duration
        local buffs = entry.buffs or {}

        -- Enemy Stats (session only)
        if entry.is_session and stats.damage_by_type and next(stats.damage_by_type) then
            layout[#layout + 1] = { widget_type = 'spacer', size = 'group' }
            layout[#layout + 1] = { widget_type = 'section', text = mod:localize('enemy_stats') }

            local sorted_types = {}
            for breed_type, damage in pairs(stats.damage_by_type) do
                local kills = stats.kills_by_type[breed_type] or 0
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

                local color = Color.white(255, true)
                if breed_type == 'monster' then
                    color = Color.ui_red_medium(255, true)
                elseif breed_type == 'disabler' or breed_type == 'special' then
                    color = { 255, 255, 165, 0 }
                elseif breed_type == 'elite' then
                    color = Color.ui_hud_yellow_medium(255, true)
                end

                layout[#layout + 1] = {
                    widget_type = 'progress_bar',
                    label = string.format(
                        '%s: %d kills | %d dmg (%.1f%%)',
                        mod:localize('breed_' .. breed_type),
                        kills,
                        damage,
                        pct
                    ),
                    value = damage,
                    max_value = stats.total_damage,
                    color = color,
                }
            end
        end

        -- Damage Stats
        if stats.total_damage > 0 then
            layout[#layout + 1] = { widget_type = 'spacer', size = 'group' }
            layout[#layout + 1] = { widget_type = 'section', text = mod:localize('damage_stats') }

            layout[#layout + 1] = {
                widget_type = 'text',
                text = string.format('%s: %d', mod:localize('total'), stats.total_damage),
            }

            if stats.overkill_damage > 0 then
                layout[#layout + 1] = {
                    widget_type = 'text',
                    text = string.format('%s: %d', mod:localize('overkill'), stats.overkill_damage),
                }
            end

            if stats.melee_damage and stats.melee_damage > 0 then
                layout[#layout + 1] = {
                    widget_type = 'progress_bar',
                    label = string.format('%s: %d', mod:localize('melee'), stats.melee_damage),
                    value = stats.melee_damage,
                    max_value = stats.total_damage,
                    color = COLOR_MELEE,
                }
                self:_add_substats(layout, stats.melee_damage, {
                    { key = 'crit', value = stats.melee_crit_damage },
                    { key = 'weakspot', value = stats.melee_weakspot_damage },
                })
            end

            if stats.ranged_damage and stats.ranged_damage > 0 then
                layout[#layout + 1] = {
                    widget_type = 'progress_bar',
                    label = string.format('%s: %d', mod:localize('ranged'), stats.ranged_damage),
                    value = stats.ranged_damage,
                    max_value = stats.total_damage,
                    color = COLOR_RANGED,
                }
                self:_add_substats(layout, stats.ranged_damage, {
                    { key = 'crit', value = stats.ranged_crit_damage },
                    { key = 'weakspot', value = stats.ranged_weakspot_damage },
                })
            end

            if stats.buff_damage and stats.buff_damage > 0 then
                layout[#layout + 1] = {
                    widget_type = 'progress_bar',
                    label = string.format('%s: %d', mod:localize('buff'), stats.buff_damage),
                    value = stats.buff_damage,
                    max_value = stats.total_damage,
                    color = Color.ui_hud_green_light(255, true),
                }
                self:_add_substats(layout, stats.buff_damage, {
                    { key = 'bleed', value = stats.bleed_damage },
                    { key = 'burn', value = stats.burn_damage },
                    { key = 'toxin', value = stats.toxin_damage },
                })
            end

            if stats.explosion_damage and stats.explosion_damage > 0 then
                layout[#layout + 1] = {
                    widget_type = 'progress_bar',
                    label = string.format('%s: %d', mod:localize('explosion'), stats.explosion_damage),
                    value = stats.explosion_damage,
                    max_value = stats.total_damage,
                    color = COLOR_EXPLOSION,
                }
            end

            if stats.companion_damage and stats.companion_damage > 0 then
                layout[#layout + 1] = {
                    widget_type = 'progress_bar',
                    label = string.format('%s: %d', mod:localize('companion'), stats.companion_damage),
                    value = stats.companion_damage,
                    max_value = stats.total_damage,
                    color = COLOR_COMPANION,
                }
            end

            if stats.arc_damage and stats.arc_damage > 0 then
                layout[#layout + 1] = {
                    widget_type = 'progress_bar',
                    label = string.format('%s: %d', mod:localize('arc'), stats.arc_damage),
                    value = stats.arc_damage,
                    max_value = stats.total_damage,
                    color = COLOR_ARC,
                }
            end
        end

        -- Hit Stats
        if stats.total_hits > 0 then
            layout[#layout + 1] = { widget_type = 'spacer', size = 'group' }
            layout[#layout + 1] = { widget_type = 'section', text = mod:localize('hit_stats') }
            layout[#layout + 1] = {
                widget_type = 'text',
                text = string.format('%s: %d', mod:localize('total'), stats.total_hits),
            }

            if stats.melee_hits and stats.melee_hits > 0 then
                layout[#layout + 1] = {
                    widget_type = 'progress_bar',
                    label = string.format('%s: %d', mod:localize('melee'), stats.melee_hits),
                    value = stats.melee_hits,
                    max_value = stats.total_hits,
                    color = COLOR_MELEE,
                }
                self:_add_substats(layout, stats.melee_hits, {
                    { key = 'crit', value = stats.melee_crit_hits },
                    { key = 'weakspot', value = stats.melee_weakspot_hits },
                })
            end

            if stats.ranged_hits and stats.ranged_hits > 0 then
                layout[#layout + 1] = {
                    widget_type = 'progress_bar',
                    label = string.format('%s: %d', mod:localize('ranged'), stats.ranged_hits),
                    value = stats.ranged_hits,
                    max_value = stats.total_hits,
                    color = COLOR_RANGED,
                }
                self:_add_substats(layout, stats.ranged_hits, {
                    { key = 'crit', value = stats.ranged_crit_hits },
                    { key = 'weakspot', value = stats.ranged_weakspot_hits },
                })
            end

            if stats.explosion_hits and stats.explosion_hits > 0 then
                layout[#layout + 1] = {
                    widget_type = 'progress_bar',
                    label = string.format('%s: %d', mod:localize('explosion'), stats.explosion_hits),
                    value = stats.explosion_hits,
                    max_value = stats.total_hits,
                    color = COLOR_EXPLOSION,
                }
            end

            if stats.companion_hits and stats.companion_hits > 0 then
                layout[#layout + 1] = {
                    widget_type = 'progress_bar',
                    label = string.format('%s: %d', mod:localize('companion'), stats.companion_hits),
                    value = stats.companion_hits,
                    max_value = stats.total_hits,
                    color = COLOR_COMPANION,
                }
            end

            if stats.arc_hits and stats.arc_hits > 0 then
                layout[#layout + 1] = {
                    widget_type = 'progress_bar',
                    label = string.format('%s: %d', mod:localize('arc'), stats.arc_hits),
                    value = stats.arc_hits,
                    max_value = stats.total_hits,
                    color = COLOR_ARC,
                }
            end
        end

        -- Buff Uptime
        if duration > 0 and buffs then
            local buff_array = {}
            for buff_template_name, uptime in pairs(buffs) do
                local display_name = mod.utils:get_buff_display_name(buff_template_name)
                local icon, gradient_map = mod.utils:get_buff_icon(buff_template_name)

                buff_array[#buff_array + 1] = {
                    name = display_name,
                    uptime = uptime,
                    icon = icon,
                    gradient_map = gradient_map,
                }
            end

            table.sort(buff_array, function(a, b)
                local a_uptime = type(a.uptime) == 'number' and a.uptime or 0
                local b_uptime = type(b.uptime) == 'number' and b.uptime or 0
                return a_uptime > b_uptime
            end)

            if #buff_array > 0 then
                layout[#layout + 1] = { widget_type = 'spacer', size = 'group' }
                layout[#layout + 1] = { widget_type = 'section', text = mod:localize('buff_uptime') }

                for i = 1, #buff_array do
                    local buff = buff_array[i]
                    layout[#layout + 1] = {
                        widget_type = 'progress_bar',
                        label = buff.name,
                        value = buff.uptime,
                        max_value = duration,
                        color = Color.ui_terminal(255, true),
                        icon = buff.icon,
                        gradient_map = buff.gradient_map,
                    }
                end
            end
        end
    end

    self._detail_grid:present_grid_layout(layout, blueprints)
end

function CombatStatsView:_add_substats(layout, total, substats)
    for _, substat in ipairs(substats) do
        if substat.value and substat.value > 0 then
            local pct = (substat.value / total * 100)
            layout[#layout + 1] = {
                widget_type = 'substat',
                text = string.format('%s: %d (%.1f%%)', mod:localize(substat.key), substat.value, pct),
            }
        end
    end
end

-- Callbacks --------------------------------------------------------------

function CombatStatsView:cb_on_reset_pressed()
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
    local search_widget = self._widgets_by_name.combat_stats_search
    if search_widget and search_widget.content.is_writing then
        return
    end

    if self._viewing_history then
        self:cb_on_back_to_current_pressed()
    else
        self._viewing_history = true
        self._viewing_history_entry = false
        self._history_loading = true
        self:_setup_entries()

        mod.history:load_index(function()
            if self._destroyed then
                return
            end
            self._history_loading = false
            if self._viewing_history and not self._viewing_history_entry then
                self:_setup_entries()
            end
        end)
    end
end

function CombatStatsView:cb_on_back_to_current_pressed()
    local search_widget = self._widgets_by_name.combat_stats_search
    if search_widget and search_widget.content.is_writing then
        return
    end

    if self._viewing_history_entry then
        self._viewing_history = true
        self._viewing_history_entry = false
        self._history_entry_loading = false
        self._history_loading = false
        self._current_history_file = nil
        self._tracker = mod.tracker
        self:_setup_entries()
    else
        self._viewing_history = false
        self._viewing_history_entry = false
        self._history_entry_loading = false
        self._history_loading = false
        self._current_history_file = nil
        self._tracker = mod.tracker
        self:_setup_entries()
    end
end

function CombatStatsView:cb_on_delete_entry_pressed()
    if not self._viewing_history_entry or not self._current_history_file then
        return
    end

    local search_widget = self._widgets_by_name.combat_stats_search
    if search_widget and search_widget.content.is_writing then
        return
    end

    if mod.history:delete_history_entry(self._current_history_file) then
        self._current_history_file = nil
        self:cb_on_back_to_current_pressed()
    end
end

function CombatStatsView:_load_history_entry(entry)
    if not entry.history_data then
        return
    end

    local file_name = entry.history_data.file
    self._current_history_file = file_name
    self._history_entry_loading = true

    self._tracker = nil
    self._viewing_history = false
    self._viewing_history_entry = true
    self:_setup_entries()

    mod.history:load_history_entry(file_name, function(full_data)
        if self._destroyed then
            return
        end
        self._history_entry_loading = false

        if self._current_history_file ~= file_name then
            return
        end

        if not full_data then
            self:cb_on_back_to_current_pressed()
            return
        end

        self._tracker = CombatStatsTracker:new()
        self._tracker:load_from_history(full_data)

        self:_setup_entries()
    end)
end

function CombatStatsView:_on_update(dt, t, input_service)
    if self._pending_history_entry then
        local entry = self._pending_history_entry
        self._pending_history_entry = nil
        self:_load_history_entry(entry)
    end
end

return CombatStatsView
