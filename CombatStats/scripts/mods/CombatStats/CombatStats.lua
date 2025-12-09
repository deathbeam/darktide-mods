local mod = get_mod('CombatStats')

local Breed = mod:original_require('scripts/utilities/breed')
local BuffTemplates = mod:original_require('scripts/settings/buff/buff_templates')

local function _get_gameplay_time()
    return Managers.time and Managers.time:has_timer('gameplay') and Managers.time:time('gameplay') or 0
end

local function _is_enabled()
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

local function _show_damage_stats(stats, prefix)
    prefix = prefix or ''

    Imgui.text(string.format('%sTotal Damage: %d', prefix, stats.total_damage))
    Imgui.same_line()
    if stats.total_hits > 0 then
        Imgui.text(string.format('(Avg: %.0f per hit)', stats.total_damage / stats.total_hits))
    end

    if stats.melee_damage > 0 or stats.ranged_damage > 0 then
        Imgui.indent()
        if stats.melee_damage > 0 then
            Imgui.text(
                string.format(
                    '%sMelee: %d (%.1f%%)',
                    prefix,
                    stats.melee_damage,
                    stats.total_damage > 0 and (stats.melee_damage / stats.total_damage * 100) or 0
                )
            )
        end
        if stats.ranged_damage > 0 then
            Imgui.text(
                string.format(
                    '%sRanged: %d (%.1f%%)',
                    prefix,
                    stats.ranged_damage,
                    stats.total_damage > 0 and (stats.ranged_damage / stats.total_damage * 100) or 0
                )
            )
        end
        Imgui.unindent()
    end

    if stats.crit_damage > 0 then
        Imgui.text(
            string.format(
                '%sCrit Damage: %d (%.1f%% of total)',
                prefix,
                stats.crit_damage,
                stats.total_damage > 0 and (stats.crit_damage / stats.total_damage * 100) or 0
            )
        )
    end

    if stats.weakspot_damage > 0 then
        Imgui.text(
            string.format(
                '%sWeakspot Damage: %d (%.1f%% of total)',
                prefix,
                stats.weakspot_damage,
                stats.total_damage > 0 and (stats.weakspot_damage / stats.total_damage * 100) or 0
            )
        )
    end

    local dot_damage = stats.bleed_damage + stats.burn_damage + stats.toxin_damage
    if dot_damage > 0 then
        Imgui.text(
            string.format(
                '%sDOT Damage: %d (%.1f%% of total)',
                prefix,
                dot_damage,
                stats.total_damage > 0 and (dot_damage / stats.total_damage * 100) or 0
            )
        )
        Imgui.indent()
        if stats.bleed_damage > 0 then
            Imgui.text(string.format('%sBleed: %d', prefix, stats.bleed_damage))
        end
        if stats.burn_damage > 0 then
            Imgui.text(string.format('%sBurn: %d', prefix, stats.burn_damage))
        end
        if stats.toxin_damage > 0 then
            Imgui.text(string.format('%sToxin: %d', prefix, stats.toxin_damage))
        end
        Imgui.unindent()
    end
end

local function _show_hit_stats(stats, prefix)
    prefix = prefix or ''

    Imgui.text(string.format('%sTotal Hits: %d', prefix, stats.total_hits))

    if stats.crit_hits > 0 then
        Imgui.text(
            string.format(
                '%sCrit Hits: %d (%.1f%%)',
                prefix,
                stats.crit_hits,
                stats.total_hits > 0 and (stats.crit_hits / stats.total_hits * 100) or 0
            )
        )
    end

    if stats.weakspot_hits > 0 then
        Imgui.text(
            string.format(
                '%sWeakspot Hits: %d (%.1f%%)',
                prefix,
                stats.weakspot_hits,
                stats.total_hits > 0 and (stats.weakspot_hits / stats.total_hits * 100) or 0
            )
        )
    end
end

local function _show_complete_stats(stats, duration, buff_uptime, title_prefix)
    title_prefix = title_prefix or ''

    Imgui.spacing()

    if Imgui.collapsing_header(title_prefix .. 'Damage Stats', 'default_open') then
        Imgui.indent()

        local dps = duration > 0 and stats.total_damage / duration or 0
        Imgui.text(string.format('Total Damage: %d', stats.total_damage))
        if duration > 0 then
            Imgui.same_line()
            Imgui.text_colored(0, 255, 0, 255, string.format('(%.1f DPS)', dps))
        end

        Imgui.spacing()

        if stats.melee_damage > 0 then
            local melee_pct = stats.total_damage > 0 and (stats.melee_damage / stats.total_damage * 100) or 0
            Imgui.text(string.format('Melee: %d', stats.melee_damage))
            Imgui.same_line()
            Imgui.progress_bar(melee_pct / 100, 150, 20, string.format('%.1f%%', melee_pct))

            Imgui.indent()
            if stats.melee_crit_damage and stats.melee_crit_damage > 0 then
                local melee_crit_pct = stats.melee_damage > 0 and (stats.melee_crit_damage / stats.melee_damage * 100)
                    or 0
                Imgui.text(string.format('Crit: %d (%.1f%%)', stats.melee_crit_damage, melee_crit_pct))
            end
            if stats.melee_weakspot_damage and stats.melee_weakspot_damage > 0 then
                local melee_ws_pct = stats.melee_damage > 0 and (stats.melee_weakspot_damage / stats.melee_damage * 100)
                    or 0
                Imgui.text(string.format('Weakspot: %d (%.1f%%)', stats.melee_weakspot_damage, melee_ws_pct))
            end
            Imgui.unindent()
        end

        if stats.ranged_damage > 0 then
            local ranged_pct = stats.total_damage > 0 and (stats.ranged_damage / stats.total_damage * 100) or 0
            Imgui.text(string.format('Ranged: %d', stats.ranged_damage))
            Imgui.same_line()
            Imgui.progress_bar(ranged_pct / 100, 150, 20, string.format('%.1f%%', ranged_pct))

            Imgui.indent()
            if stats.ranged_crit_damage and stats.ranged_crit_damage > 0 then
                local ranged_crit_pct = stats.ranged_damage > 0
                        and (stats.ranged_crit_damage / stats.ranged_damage * 100)
                    or 0
                Imgui.text(string.format('Crit: %d (%.1f%%)', stats.ranged_crit_damage, ranged_crit_pct))
            end
            if stats.ranged_weakspot_damage and stats.ranged_weakspot_damage > 0 then
                local ranged_ws_pct = stats.ranged_damage > 0
                        and (stats.ranged_weakspot_damage / stats.ranged_damage * 100)
                    or 0
                Imgui.text(string.format('Weakspot: %d (%.1f%%)', stats.ranged_weakspot_damage, ranged_ws_pct))
            end
            Imgui.unindent()
        end

        if stats.buff_damage and stats.buff_damage > 0 then
            local buff_pct = stats.total_damage > 0 and (stats.buff_damage / stats.total_damage * 100) or 0
            Imgui.text(string.format('Buff: %d', stats.buff_damage))
            Imgui.same_line()
            Imgui.progress_bar(buff_pct / 100, 150, 20, string.format('%.1f%%', buff_pct))

            Imgui.indent()
            if stats.bleed_damage > 0 then
                local bleed_pct = stats.buff_damage > 0 and (stats.bleed_damage / stats.buff_damage * 100) or 0
                Imgui.text(string.format('Bleed: %d (%.1f%%)', stats.bleed_damage, bleed_pct))
            end
            if stats.burn_damage > 0 then
                local burn_pct = stats.buff_damage > 0 and (stats.burn_damage / stats.buff_damage * 100) or 0
                Imgui.text(string.format('Burn: %d (%.1f%%)', stats.burn_damage, burn_pct))
            end
            if stats.toxin_damage > 0 then
                local toxin_pct = stats.buff_damage > 0 and (stats.toxin_damage / stats.buff_damage * 100) or 0
                Imgui.text(string.format('Toxin: %d (%.1f%%)', stats.toxin_damage, toxin_pct))
            end
            Imgui.unindent()
        end

        Imgui.unindent()
    end

    Imgui.spacing()

    if Imgui.collapsing_header(title_prefix .. 'Hit Stats') then
        Imgui.indent()

        Imgui.text(string.format('Total Hits: %d', stats.total_hits))

        if stats.melee_hits and stats.melee_hits > 0 then
            Imgui.spacing()
            local melee_hit_pct = stats.total_hits > 0 and (stats.melee_hits / stats.total_hits * 100) or 0
            Imgui.text(string.format('Melee Hits: %d', stats.melee_hits))
            Imgui.same_line()
            Imgui.progress_bar(melee_hit_pct / 100, 150, 20, string.format('%.1f%%', melee_hit_pct))

            Imgui.indent()
            if stats.melee_crit_hits and stats.melee_crit_hits > 0 then
                local melee_crit_rate = stats.melee_hits > 0 and (stats.melee_crit_hits / stats.melee_hits * 100) or 0
                Imgui.text(string.format('Crit: %d (%.1f%%)', stats.melee_crit_hits, melee_crit_rate))
            end

            if stats.melee_weakspot_hits and stats.melee_weakspot_hits > 0 then
                local melee_ws_rate = stats.melee_hits > 0 and (stats.melee_weakspot_hits / stats.melee_hits * 100) or 0
                Imgui.text(string.format('Weakspot: %d (%.1f%%)', stats.melee_weakspot_hits, melee_ws_rate))
            end
            Imgui.unindent()
        end

        if stats.ranged_hits and stats.ranged_hits > 0 then
            Imgui.spacing()
            local ranged_hit_pct = stats.total_hits > 0 and (stats.ranged_hits / stats.total_hits * 100) or 0
            Imgui.text(string.format('Ranged Hits: %d', stats.ranged_hits))
            Imgui.same_line()
            Imgui.progress_bar(ranged_hit_pct / 100, 150, 20, string.format('%.1f%%', ranged_hit_pct))

            Imgui.indent()
            if stats.ranged_crit_hits and stats.ranged_crit_hits > 0 then
                local ranged_crit_rate = stats.ranged_hits > 0 and (stats.ranged_crit_hits / stats.ranged_hits * 100)
                    or 0
                Imgui.text(string.format('Crit: %d (%.1f%%)', stats.ranged_crit_hits, ranged_crit_rate))
            end

            if stats.ranged_weakspot_hits and stats.ranged_weakspot_hits > 0 then
                local ranged_ws_rate = stats.ranged_hits > 0 and (stats.ranged_weakspot_hits / stats.ranged_hits * 100)
                    or 0
                Imgui.text(string.format('Weakspot: %d (%.1f%%)', stats.ranged_weakspot_hits, ranged_ws_rate))
            end
            Imgui.unindent()
        end

        Imgui.unindent()
    end

    if duration > 0 and buff_uptime then
        Imgui.spacing()

        if Imgui.collapsing_header(title_prefix .. 'Buff Uptime') then
            Imgui.indent()

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
            else
                Imgui.text('No buffs tracked (permanent buffs hidden)')
            end

            Imgui.unindent()
        end
    end
end

local CombatStatsTracker = class('CombatStatsTracker')

function CombatStatsTracker:init()
    self._is_open = false
    self._active_buffs = {}
    self._buff_uptime = {}
    self._engagements = {}
    self._engagements_by_unit = {}
end

function CombatStatsTracker:open()
    local input_manager = Managers.input
    local name = self.__class_name

    if not input_manager:cursor_active() then
        input_manager:push_cursor(name)
    end

    self._is_open = true
    Imgui.open_imgui()
end

function CombatStatsTracker:close()
    if not self._is_open then
        return
    end

    local input_manager = Managers.input
    local name = self.__class_name

    if input_manager:cursor_active() then
        input_manager:pop_cursor(name)
    end

    self._is_open = false
    Imgui.close_imgui()
end

function CombatStatsTracker:reset_stats()
    self._active_buffs = {}
    self._buff_uptime = {}
    self._engagements = {}
    self._engagements_by_unit = {}
end

function CombatStatsTracker:_get_session_duration()
    if #self._engagements == 0 then
        return 0
    end

    local first_start = self._engagements[1].start_time
    local last_end = _get_gameplay_time()
    return last_end - first_start
end

function CombatStatsTracker:_calculate_session_stats()
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
    self._engagements_by_unit[unit] = engagement
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
end

function CombatStatsTracker:_update_enemy_buffs(dt)
    local current_time = _get_gameplay_time()

    for _, engagement in ipairs(self._engagements) do
        if engagement.in_progress then
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
                engagement.in_progress = false
                engagement.end_time = current_time
                engagement.duration = current_time - engagement.start_time
                engagement.dps = engagement.duration > 0 and engagement.total_damage / engagement.duration or 0
            end
        end
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

    if not self._is_open then
        return
    end

    local _, closed = Imgui.begin_window('Combat Stats Tracker')

    if closed then
        self:close()
    end

    local duration = self:_get_session_duration()
    local stats = self:_calculate_session_stats()

    Imgui.text(string.format('Session Duration: %.1f seconds', duration))
    Imgui.same_line()
    if Imgui.button('Reset Stats') then
        self:reset_stats()
    end

    local kill_text = 'Kills: ' .. stats.total_kills
    if next(stats.kills) then
        local kill_details = {}
        for breed_type, count in pairs(stats.kills) do
            table.insert(kill_details, string.format('%s: %d', breed_type, count))
        end
        kill_text = kill_text .. ' (' .. table.concat(kill_details, ', ') .. ')'
    end

    Imgui.text(kill_text)

    if duration > 0 and stats.total_damage > 0 then
        Imgui.text_colored(0, 255, 0, 255, string.format('Session DPS: %.0f', stats.total_damage / duration))
    end

    Imgui.spacing()
    Imgui.separator()

    _show_complete_stats(stats, duration, self._buff_uptime, 'Session ')

    if #self._engagements > 0 then
        Imgui.spacing()

        if Imgui.collapsing_header('Engagements') then
            Imgui.indent()

            local max_display = mod:get('max_kill_history') or 10
            local displayed = 0

            for i = #self._engagements, 1, -1 do
                if displayed >= max_display then
                    break
                end

                local engagement = self._engagements[i]

                local status = engagement.in_progress and 'IN PROGRESS' or 'KILLED'
                local breed_type_str = engagement.breed_type or 'unknown'
                local header_text = string.format(
                    '#%d: %s [%s] (%s) - %.1fs - %d dmg (%.0f DPS)',
                    i,
                    engagement.breed_name,
                    status,
                    breed_type_str,
                    engagement.duration,
                    engagement.total_damage,
                    engagement.dps
                )

                if Imgui.tree_node(header_text) then
                    _show_complete_stats(engagement, engagement.duration, engagement.buffs, '')
                    Imgui.tree_pop()
                end

                displayed = displayed + 1
            end

            if #self._engagements > max_display then
                Imgui.text(string.format('... and %d more engagements', #self._engagements - max_display))
            end

            Imgui.unindent()
        end
    end

    Imgui.end_window()
end

local tracker = CombatStatsTracker:new()

function mod.update(dt)
    if not _is_enabled() then
        return
    end

    tracker:update(dt)
end

function mod.toggle_kill_stats()
    if tracker._is_open or not _is_enabled() then
        tracker:close()
    else
        tracker:open()
    end
end

function mod.on_game_state_changed(status, state_name)
    if status == 'enter' and state_name == 'StateGameplay' then
        tracker:reset_stats()
    elseif status == 'exit' and state_name == 'StateGameplay' then
        tracker:close()
    end
end

mod:hook(
    CLASS.AttackReportManager,
    'add_attack_result',
    function(
        func,
        self,
        damage_profile,
        attacked_unit,
        attacking_unit,
        attack_direction,
        hit_world_position,
        hit_weakspot,
        damage,
        attack_result,
        attack_type,
        damage_efficiency,
        is_critical_strike,
        ...
    )
        if _is_enabled() then
            local player = Managers.player:local_player_safe(1)
            if player then
                local player_unit = player.player_unit
                if player_unit and attacking_unit == player_unit then
                    local unit_data_extension = ScriptUnit.has_extension(attacked_unit, 'unit_data_system')
                    local breed = unit_data_extension and unit_data_extension:breed()
                    if breed then
                        tracker:_start_enemy_engagement(attacked_unit, breed)

                        tracker:_track_enemy_damage(
                            attacked_unit,
                            damage,
                            attack_type,
                            is_critical_strike,
                            hit_weakspot,
                            damage_profile and damage_profile.name
                        )

                        if attack_result == 'died' then
                            tracker:_finish_enemy_engagement(attacked_unit)
                        end
                    end
                end
            end
        end

        return func(
            self,
            damage_profile,
            attacked_unit,
            attacking_unit,
            attack_direction,
            hit_world_position,
            hit_weakspot,
            damage,
            attack_result,
            attack_type,
            damage_efficiency,
            is_critical_strike,
            ...
        )
    end
)

mod:hook('UIManager', 'using_input', function(func, ...)
    return tracker._is_open or func(...)
end)
