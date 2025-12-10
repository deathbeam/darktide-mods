local mod = get_mod('CombatStats')

local BuffTemplates = mod:original_require('scripts/settings/buff/buff_templates')

local function _get_gameplay_time()
    return Managers.time and Managers.time:has_timer('gameplay') and Managers.time:time('gameplay') or 0
end

local function _get_buff_icon(buff_template_name)
    local template = BuffTemplates[buff_template_name]
    if not template then
        return nil
    end

    if template.hide_icon_in_hud then
        return nil
    end

    if template.hud_icon then
        return template.hud_icon
    end

    return nil
end

local function _should_show_buff(buff_template_name, uptime_percent, duration)
    local template = BuffTemplates[buff_template_name]
    if not template then
        return uptime_percent < 99.9 and uptime_percent >= 0
    end

    if not template.hud_icon then
        return false
    end

    if template.hide_icon_in_hud then
        return false
    end

    if template.max_duration or template.duration then
        return uptime_percent >= 0
    end

    if uptime_percent < 99.9 and uptime_percent >= 0 then
        return true
    end

    return false
end

local function _show_complete_stats(stats, duration, buff_uptime)
    local mod = get_mod('CombatStats')
    Imgui.spacing()

    if Imgui.collapsing_header(mod:localize('damage_stats'), true) then
        Imgui.indent()

        local dps = duration > 0 and stats.total_damage / duration or 0
        Imgui.text(string.format('%s: %d', mod:localize('total'), stats.total_damage))
        if duration > 0 then
            Imgui.same_line()
            Imgui.text_colored(0, 255, 0, 255, string.format('(%.1f DPS)', dps))
        end

        Imgui.spacing()

        if stats.melee_damage > 0 then
            local melee_pct = stats.total_damage > 0 and (stats.melee_damage / stats.total_damage * 100) or 0
            Imgui.text(string.format('%s: %d', mod:localize('melee'), stats.melee_damage))
            Imgui.same_line()
            Imgui.progress_bar(melee_pct / 100, 150, 20, string.format('%.1f%%', melee_pct))

            Imgui.indent()
            if stats.melee_crit_damage and stats.melee_crit_damage > 0 then
                local melee_crit_pct = stats.melee_damage > 0 and (stats.melee_crit_damage / stats.melee_damage * 100)
                    or 0
                Imgui.text(
                    string.format('%s: %d (%.1f%%)', mod:localize('crit'), stats.melee_crit_damage, melee_crit_pct)
                )
            end
            if stats.melee_weakspot_damage and stats.melee_weakspot_damage > 0 then
                local melee_ws_pct = stats.melee_damage > 0 and (stats.melee_weakspot_damage / stats.melee_damage * 100)
                    or 0
                Imgui.text(
                    string.format(
                        '%s: %d (%.1f%%)',
                        mod:localize('weakspot'),
                        stats.melee_weakspot_damage,
                        melee_ws_pct
                    )
                )
            end
            Imgui.unindent()
        end

        if stats.ranged_damage > 0 then
            local ranged_pct = stats.total_damage > 0 and (stats.ranged_damage / stats.total_damage * 100) or 0
            Imgui.text(string.format('%s: %d', mod:localize('ranged'), stats.ranged_damage))
            Imgui.same_line()
            Imgui.progress_bar(ranged_pct / 100, 150, 20, string.format('%.1f%%', ranged_pct))

            Imgui.indent()
            if stats.ranged_crit_damage and stats.ranged_crit_damage > 0 then
                local ranged_crit_pct = stats.ranged_damage > 0
                        and (stats.ranged_crit_damage / stats.ranged_damage * 100)
                    or 0
                Imgui.text(
                    string.format('%s: %d (%.1f%%)', mod:localize('crit'), stats.ranged_crit_damage, ranged_crit_pct)
                )
            end
            if stats.ranged_weakspot_damage and stats.ranged_weakspot_damage > 0 then
                local ranged_ws_pct = stats.ranged_damage > 0
                        and (stats.ranged_weakspot_damage / stats.ranged_damage * 100)
                    or 0
                Imgui.text(
                    string.format(
                        '%s: %d (%.1f%%)',
                        mod:localize('weakspot'),
                        stats.ranged_weakspot_damage,
                        ranged_ws_pct
                    )
                )
            end
            Imgui.unindent()
        end

        if stats.buff_damage and stats.buff_damage > 0 then
            local buff_pct = stats.total_damage > 0 and (stats.buff_damage / stats.total_damage * 100) or 0
            Imgui.text(string.format('%s: %d', mod:localize('buff'), stats.buff_damage))
            Imgui.same_line()
            Imgui.progress_bar(buff_pct / 100, 150, 20, string.format('%.1f%%', buff_pct))

            Imgui.indent()
            if stats.bleed_damage > 0 then
                local bleed_pct = stats.buff_damage > 0 and (stats.bleed_damage / stats.buff_damage * 100) or 0
                Imgui.text(string.format('%s: %d (%.1f%%)', mod:localize('bleed'), stats.bleed_damage, bleed_pct))
            end
            if stats.burn_damage > 0 then
                local burn_pct = stats.buff_damage > 0 and (stats.burn_damage / stats.buff_damage * 100) or 0
                Imgui.text(string.format('%s: %d (%.1f%%)', mod:localize('burn'), stats.burn_damage, burn_pct))
            end
            if stats.toxin_damage > 0 then
                local toxin_pct = stats.buff_damage > 0 and (stats.toxin_damage / stats.buff_damage * 100) or 0
                Imgui.text(string.format('%s: %d (%.1f%%)', mod:localize('toxin'), stats.toxin_damage, toxin_pct))
            end
            Imgui.unindent()
        end

        Imgui.unindent()
    end

    Imgui.spacing()

    if Imgui.collapsing_header(mod:localize('hit_stats'), true) then
        Imgui.indent()

        Imgui.text(string.format('%s: %d', mod:localize('total'), stats.total_hits))

        if stats.melee_hits and stats.melee_hits > 0 then
            Imgui.spacing()
            local melee_hit_pct = stats.total_hits > 0 and (stats.melee_hits / stats.total_hits * 100) or 0
            Imgui.text(string.format('%s: %d', mod:localize('melee'), stats.melee_hits))
            Imgui.same_line()
            Imgui.progress_bar(melee_hit_pct / 100, 150, 20, string.format('%.1f%%', melee_hit_pct))

            Imgui.indent()
            if stats.melee_crit_hits and stats.melee_crit_hits > 0 then
                local melee_crit_rate = stats.melee_hits > 0 and (stats.melee_crit_hits / stats.melee_hits * 100) or 0
                Imgui.text(
                    string.format('%s: %d (%.1f%%)', mod:localize('crit'), stats.melee_crit_hits, melee_crit_rate)
                )
            end

            if stats.melee_weakspot_hits and stats.melee_weakspot_hits > 0 then
                local melee_ws_rate = stats.melee_hits > 0 and (stats.melee_weakspot_hits / stats.melee_hits * 100) or 0
                Imgui.text(
                    string.format('%s: %d (%.1f%%)', mod:localize('weakspot'), stats.melee_weakspot_hits, melee_ws_rate)
                )
            end
            Imgui.unindent()
        end

        if stats.ranged_hits and stats.ranged_hits > 0 then
            Imgui.spacing()
            local ranged_hit_pct = stats.total_hits > 0 and (stats.ranged_hits / stats.total_hits * 100) or 0
            Imgui.text(string.format('%s: %d', mod:localize('ranged'), stats.ranged_hits))
            Imgui.same_line()
            Imgui.progress_bar(ranged_hit_pct / 100, 150, 20, string.format('%.1f%%', ranged_hit_pct))

            Imgui.indent()
            if stats.ranged_crit_hits and stats.ranged_crit_hits > 0 then
                local ranged_crit_rate = stats.ranged_hits > 0 and (stats.ranged_crit_hits / stats.ranged_hits * 100)
                    or 0
                Imgui.text(
                    string.format('%s: %d (%.1f%%)', mod:localize('crit'), stats.ranged_crit_hits, ranged_crit_rate)
                )
            end

            if stats.ranged_weakspot_hits and stats.ranged_weakspot_hits > 0 then
                local ranged_ws_rate = stats.ranged_hits > 0 and (stats.ranged_weakspot_hits / stats.ranged_hits * 100)
                    or 0
                Imgui.text(
                    string.format(
                        '%s: %d (%.1f%%)',
                        mod:localize('weakspot'),
                        stats.ranged_weakspot_hits,
                        ranged_ws_rate
                    )
                )
            end
            Imgui.unindent()
        end

        Imgui.unindent()
    end

    if duration > 0 and buff_uptime then
        local sorted_buffs = {}
        for buff_name, uptime in pairs(buff_uptime) do
            local uptime_percent = (uptime / duration) * 100
            if _should_show_buff(buff_name, uptime_percent, duration) then
                local icon = _get_buff_icon(buff_name)
                table.insert(sorted_buffs, {
                    name = buff_name,
                    uptime = uptime,
                    icon = icon,
                })
            end
        end
        table.sort(sorted_buffs, function(a, b)
            return a.uptime > b.uptime
        end)

        if #sorted_buffs > 0 then
            Imgui.spacing()

            if Imgui.collapsing_header(mod:localize('buff_uptime'), true) then
                Imgui.indent()

                for i, buff_data in ipairs(sorted_buffs) do
                    local uptime_percent = (buff_data.uptime / duration) * 100

                    if buff_data.icon then
                        Imgui.image_button(buff_data.icon, 32, 32, 255, 255, 255, 1)
                        Imgui.same_line()
                    end

                    Imgui.text(buff_data.name)
                    Imgui.same_line()
                    Imgui.progress_bar(
                        math.min(uptime_percent / 100, 1.0),
                        200,
                        20,
                        string.format('%.1f%%', uptime_percent)
                    )
                end

                Imgui.unindent()
            end
        end
    end
end

local CombatStatsTracker = class('CombatStatsTracker')

function CombatStatsTracker:init()
    self._is_open = false
    self._is_focused = false
    self._active_buffs = {}
    self._buff_uptime = {}
    self._engagements = {}
    self._total_combat_time = 0
    self._is_in_combat = false
    self._last_combat_start = nil

    -- Performance caching and lookup tables
    self._active_engagements = {}
    self._engagements_by_unit = {}
    self._cached_session_stats = nil
    self._session_stats_dirty = true
end

function CombatStatsTracker:is_enabled()
    local game_mode_manager = Managers.state and Managers.state.game_mode
    local gamemode_name = game_mode_manager and game_mode_manager:game_mode_name()

    if not gamemode_name or gamemode_name == 'hub' or gamemode_name == 'prologue_hub' then
        return false
    end

    local only_in_psykanium = mod:get('only_in_psykanium')
    if only_in_psykanium and gamemode_name ~= 'shooting_range' then
        return false
    end

    return true
end

function CombatStatsTracker:open()
    if not self:is_enabled() then
        return
    end

    self._is_open = true
    Imgui.open_imgui()
end

function CombatStatsTracker:close()
    if not self._is_open then
        return
    end

    Imgui.close_imgui()
    self._is_open = false
    self:unfocus()
end

function CombatStatsTracker:focus()
    if not self._is_open or not self:is_enabled() then
        return
    end

    self._is_focused = true
    local input_manager = Managers.input
    local name = self.__class_name
    if not input_manager:cursor_active() then
        input_manager:push_cursor(name)
    end
end

function CombatStatsTracker:unfocus()
    if not self._is_focused then
        return
    end

    local input_manager = Managers.input
    local name = self.__class_name
    if input_manager:cursor_active() then
        input_manager:pop_cursor(name)
    end
    self._is_focused = false
end

function CombatStatsTracker:reset_stats()
    self._active_buffs = {}
    self._buff_uptime = {}
    self._engagements = {}
    self._active_engagements = {}
    self._engagements_by_unit = {}
    self._total_combat_time = 0
    self._is_in_combat = false
    self._last_combat_start = nil
    self._cached_session_stats = nil
    self._session_stats_dirty = true
end

function CombatStatsTracker:_get_session_duration()
    local total = self._total_combat_time

    -- Add current active combat time if in combat
    if self._is_in_combat and self._last_combat_start then
        local current_time = _get_gameplay_time()
        total = total + (current_time - self._last_combat_start)
    end

    return total
end

function CombatStatsTracker:_has_active_engagements()
    return #self._active_engagements > 0
end

function CombatStatsTracker:_start_combat()
    if not self._is_in_combat then
        self._is_in_combat = true
        self._last_combat_start = _get_gameplay_time()
    end
end

function CombatStatsTracker:_end_combat()
    if self._is_in_combat then
        local current_time = _get_gameplay_time()
        if self._last_combat_start then
            self._total_combat_time = self._total_combat_time + (current_time - self._last_combat_start)
        end
        self._is_in_combat = false
        self._last_combat_start = nil
    end
end

function CombatStatsTracker:_update_combat_time(dt)
    if self._is_in_combat then
        local has_active = self:_has_active_engagements()
        if not has_active then
            self:_end_combat()
        end
    end
end

function CombatStatsTracker:_calculate_session_stats()
    -- Return cached stats if not dirty
    if not self._session_stats_dirty and self._cached_session_stats then
        return self._cached_session_stats
    end

    local stats = {
        total_damage = 0,
        melee_damage = 0,
        ranged_damage = 0,
        buff_damage = 0,
        melee_crit_damage = 0,
        melee_weakspot_damage = 0,
        ranged_crit_damage = 0,
        ranged_weakspot_damage = 0,
        bleed_damage = 0,
        burn_damage = 0,
        toxin_damage = 0,
        total_kills = 0,
        kills = {},
        total_hits = 0,
        melee_hits = 0,
        ranged_hits = 0,
        melee_crit_hits = 0,
        melee_weakspot_hits = 0,
        ranged_crit_hits = 0,
        ranged_weakspot_hits = 0,
    }

    for _, engagement in ipairs(self._engagements) do
        stats.total_damage = stats.total_damage + engagement.total_damage
        stats.total_hits = stats.total_hits + engagement.total_hits
        stats.melee_hits = stats.melee_hits + (engagement.melee_hits or 0)
        stats.ranged_hits = stats.ranged_hits + (engagement.ranged_hits or 0)
        stats.melee_crit_hits = stats.melee_crit_hits + (engagement.melee_crit_hits or 0)
        stats.melee_weakspot_hits = stats.melee_weakspot_hits + (engagement.melee_weakspot_hits or 0)
        stats.ranged_crit_hits = stats.ranged_crit_hits + (engagement.ranged_crit_hits or 0)
        stats.ranged_weakspot_hits = stats.ranged_weakspot_hits + (engagement.ranged_weakspot_hits or 0)

        if not engagement.in_progress then
            stats.total_kills = stats.total_kills + 1
        end

        if engagement.melee_damage then
            stats.melee_damage = stats.melee_damage + engagement.melee_damage
        end
        if engagement.ranged_damage then
            stats.ranged_damage = stats.ranged_damage + engagement.ranged_damage
        end
        if engagement.buff_damage then
            stats.buff_damage = stats.buff_damage + engagement.buff_damage
        end
        if engagement.melee_crit_damage then
            stats.melee_crit_damage = stats.melee_crit_damage + engagement.melee_crit_damage
        end
        if engagement.melee_weakspot_damage then
            stats.melee_weakspot_damage = stats.melee_weakspot_damage + engagement.melee_weakspot_damage
        end
        if engagement.ranged_crit_damage then
            stats.ranged_crit_damage = stats.ranged_crit_damage + engagement.ranged_crit_damage
        end
        if engagement.ranged_weakspot_damage then
            stats.ranged_weakspot_damage = stats.ranged_weakspot_damage + engagement.ranged_weakspot_damage
        end
        if engagement.bleed_damage then
            stats.bleed_damage = stats.bleed_damage + engagement.bleed_damage
        end
        if engagement.burn_damage then
            stats.burn_damage = stats.burn_damage + engagement.burn_damage
        end
        if engagement.toxin_damage then
            stats.toxin_damage = stats.toxin_damage + engagement.toxin_damage
        end

        if not engagement.in_progress then
            stats.kills[engagement.breed_type] = (stats.kills[engagement.breed_type] or 0) + 1
        end
    end

    -- Cache the result
    self._cached_session_stats = stats
    self._session_stats_dirty = false

    return stats
end

function CombatStatsTracker:_start_enemy_engagement(unit, breed)
    local engagement = self:_find_engagement(unit)
    if engagement and engagement.in_progress then
        return
    end

    local breed_name = breed.name
    local breed_type = 'unknown'
    if breed.tags then
        if breed.tags.monster or breed.tags.captain or breed.tags.cultist_captain then
            breed_type = 'monster'
        elseif breed.tags.ritualist then
            breed_type = 'ritualist'
        elseif breed.tags.special then
            breed_type = 'special'
        elseif breed.tags.elite then
            breed_type = 'elite'
        elseif breed.tags.horde or breed.tags.roamer then
            breed_type = 'horde'
        end
    end

    local current_time = _get_gameplay_time()
    local engagement = {
        unit = unit,
        breed_name = breed_name,
        breed_type = breed_type,
        start_time = current_time,
        end_time = nil,
        duration = 0,
        in_progress = true,
        total_damage = 0,
        melee_damage = 0,
        ranged_damage = 0,
        buff_damage = 0,
        melee_crit_damage = 0,
        melee_weakspot_damage = 0,
        ranged_crit_damage = 0,
        ranged_weakspot_damage = 0,
        bleed_damage = 0,
        burn_damage = 0,
        toxin_damage = 0,
        total_hits = 0,
        melee_hits = 0,
        ranged_hits = 0,
        melee_crit_hits = 0,
        melee_weakspot_hits = 0,
        ranged_crit_hits = 0,
        ranged_weakspot_hits = 0,
        dps = 0,
        buffs = {},
    }

    for buff_name, _ in pairs(self._active_buffs) do
        engagement.buffs[buff_name] = 0
    end

    table.insert(self._engagements, engagement)
    table.insert(self._active_engagements, engagement)
    self._engagements_by_unit[unit] = engagement
    self._session_stats_dirty = true

    self:_start_combat()
end

function CombatStatsTracker:_find_engagement(unit)
    local engagement = self._engagements_by_unit[unit]
    if engagement and engagement.in_progress then
        return engagement
    end
    return nil
end

function CombatStatsTracker:_track_enemy_damage(unit, damage, attack_type, is_critical, is_weakspot, damage_profile)
    local engagement = self:_find_engagement(unit)
    if not engagement then
        return
    end

    local damage_type = nil
    if damage_profile then
        if string.find(damage_profile:lower(), 'bleed') then
            damage_type = 'bleed'
        elseif
            string.find(damage_profile:lower(), 'burn')
            or string.find(damage_profile:lower(), 'fire')
            or string.find(damage_profile:lower(), 'flame')
        then
            damage_type = 'burn'
        elseif string.find(damage_profile:lower(), 'toxin') then
            damage_type = 'toxin'
        end
    end

    engagement.total_damage = engagement.total_damage + damage

    if attack_type == 'melee' then
        engagement.melee_damage = engagement.melee_damage + damage
        engagement.melee_hits = engagement.melee_hits + 1
        engagement.total_hits = engagement.total_hits + 1

        if is_critical then
            engagement.melee_crit_damage = engagement.melee_crit_damage + damage
            engagement.melee_crit_hits = engagement.melee_crit_hits + 1
        end

        if is_weakspot then
            engagement.melee_weakspot_damage = engagement.melee_weakspot_damage + damage
            engagement.melee_weakspot_hits = engagement.melee_weakspot_hits + 1
        end
    elseif attack_type == 'ranged' then
        engagement.ranged_damage = engagement.ranged_damage + damage
        engagement.ranged_hits = engagement.ranged_hits + 1
        engagement.total_hits = engagement.total_hits + 1

        if is_critical then
            engagement.ranged_crit_damage = engagement.ranged_crit_damage + damage
            engagement.ranged_crit_hits = engagement.ranged_crit_hits + 1
        end

        if is_weakspot then
            engagement.ranged_weakspot_damage = engagement.ranged_weakspot_damage + damage
            engagement.ranged_weakspot_hits = engagement.ranged_weakspot_hits + 1
        end
    elseif attack_type == 'buff' then
        engagement.buff_damage = engagement.buff_damage + damage
    end

    if damage_type == 'bleed' then
        engagement.bleed_damage = engagement.bleed_damage + damage
    elseif damage_type == 'burn' then
        engagement.burn_damage = engagement.burn_damage + damage
    elseif damage_type == 'toxin' then
        engagement.toxin_damage = engagement.toxin_damage + damage
    end

    self._session_stats_dirty = true
end

function CombatStatsTracker:_finish_enemy_engagement(unit)
    local engagement = self:_find_engagement(unit)
    if not engagement then
        return
    end

    local current_time = _get_gameplay_time()
    engagement.end_time = current_time
    engagement.duration = current_time - engagement.start_time
    engagement.in_progress = false
    engagement.dps = engagement.duration > 0 and engagement.total_damage / engagement.duration or 0

    -- Remove from active engagements
    for i, active_engagement in ipairs(self._active_engagements) do
        if active_engagement == engagement then
            table.remove(self._active_engagements, i)
            break
        end
    end

    self._session_stats_dirty = true
end

function CombatStatsTracker:_update_enemy_buffs(dt)
    if not self:_has_active_engagements() then
        return
    end

    local current_time = _get_gameplay_time()
    local to_remove = {}

    for i, engagement in ipairs(self._active_engagements) do
        if ALIVE[engagement.unit] then
            engagement.duration = current_time - engagement.start_time
            engagement.dps = engagement.duration > 0 and engagement.total_damage / engagement.duration or 0

            for buff_name, _ in pairs(self._active_buffs) do
                if not engagement.buffs[buff_name] then
                    engagement.buffs[buff_name] = 0
                end
                engagement.buffs[buff_name] = engagement.buffs[buff_name] + dt
            end
        else
            -- Enemy died, mark for removal
            engagement.in_progress = false
            engagement.end_time = current_time
            engagement.duration = current_time - engagement.start_time
            engagement.dps = engagement.duration > 0 and engagement.total_damage / engagement.duration or 0
            table.insert(to_remove, i)
        end
    end

    -- Remove dead engagements (iterate backwards to avoid index issues)
    for i = #to_remove, 1, -1 do
        table.remove(self._active_engagements, to_remove[i])
    end

    if #to_remove > 0 then
        self._session_stats_dirty = true
    end
end

function CombatStatsTracker:_update_buffs(dt)
    local player = Managers.player:local_player_safe(1)
    if not player then
        return
    end

    local unit = player.player_unit
    if not unit then
        return
    end

    local buff_extension = ScriptUnit.has_extension(unit, 'buff_system')
    if not buff_extension then
        return
    end

    local current_buffs = {}
    local buffs = buff_extension:buffs()
    for i = 1, #buffs do
        local buff = buffs[i]
        if buff then
            local buff_name = buff:template_name()
            if buff_name then
                current_buffs[buff_name] = true
                if not self._buff_uptime[buff_name] then
                    self._buff_uptime[buff_name] = 0
                end
            end
        end
    end

    for buff_name, _ in pairs(current_buffs) do
        self._buff_uptime[buff_name] = self._buff_uptime[buff_name] + dt
    end

    for buff_name, _ in pairs(self._active_buffs) do
        if not current_buffs[buff_name] then
            self._active_buffs[buff_name] = nil
        end
    end

    self._active_buffs = current_buffs

    self:_update_enemy_buffs(dt)
end

function CombatStatsTracker:update(dt)
    local current_time = _get_gameplay_time()
    if current_time == 0 then
        return
    end

    self:_update_buffs(dt)
    self:_update_combat_time(dt)

    if not self._is_open then
        return
    end

    local _, closed = Imgui.begin_window(mod:localize('mod_name'), 'always_auto_resize')

    if closed then
        self:close()
    end

    local duration = self:_get_session_duration()
    local stats = self:_calculate_session_stats()

    Imgui.text(string.format('%s: %.1f %s', mod:localize('time'), duration, mod:localize('seconds')))
    Imgui.same_line()
    if Imgui.button(mod:localize('reset_stats')) then
        self:reset_stats()
    end

    local kill_text = mod:localize('kills') .. ': ' .. stats.total_kills
    if next(stats.kills) then
        local kill_details = {}
        for breed_type, count in pairs(stats.kills) do
            local localized_breed = mod:localize('breed_' .. breed_type)
            table.insert(kill_details, string.format('%s: %d', localized_breed, count))
        end
        kill_text = kill_text .. ' (' .. table.concat(kill_details, ', ') .. ')'
    end

    Imgui.text(kill_text)

    if duration > 0 and stats.total_damage > 0 then
        Imgui.text_colored(
            0,
            255,
            0,
            255,
            string.format('%s: %.0f', mod:localize('dps'), stats.total_damage / duration)
        )
    end

    _show_complete_stats(stats, duration, self._buff_uptime)

    if #self._engagements > 0 then
        Imgui.spacing()

        if Imgui.collapsing_header(mod:localize('engagements'), true) then
            Imgui.indent()

            local max_display = mod:get('max_kill_history') or 10
            local displayed = 0

            for i = #self._engagements, 1, -1 do
                if displayed >= max_display then
                    break
                end

                local engagement = self._engagements[i]

                local status = engagement.in_progress and mod:localize('in_progress') or mod:localize('killed')
                local breed_type_str = mod:localize('breed_' .. (engagement.breed_type or 'unknown'))
                local header_text = string.format(
                    '#%d: %s [%s] (%s) - %.1fs - %d dmg (%.0f DPS)##%d',
                    i,
                    engagement.breed_name,
                    status,
                    breed_type_str,
                    engagement.duration,
                    engagement.total_damage,
                    engagement.dps,
                    i
                )

                if Imgui.tree_node(header_text) then
                    _show_complete_stats(engagement, engagement.duration, engagement.buffs, '')
                    Imgui.tree_pop()
                end

                displayed = displayed + 1
            end

            if #self._engagements > max_display then
                Imgui.text(string.format('%d ' .. mod:localize('and_more'), #self._engagements - max_display))
            end

            Imgui.unindent()
        end
    end

    Imgui.end_window()
end

return CombatStatsTracker
