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

local function _should_show_buff(buff_template_name)
    local template = BuffTemplates[buff_template_name]
    if not template then
        return false
    end

    if not template.hud_icon then
        return false
    end

    if template.hide_icon_in_hud then
        return false
    end

    return true
end

local function _process_buff_uptime(buff_uptime, duration)
    if not buff_uptime or not duration or duration <= 0 then
        return {}
    end

    local processed_buffs = {}
    for buff_name, uptime in pairs(buff_uptime) do
        if _should_show_buff(buff_name) then
            processed_buffs[#processed_buffs + 1] = {
                name = buff_name,
                uptime = uptime,
                uptime_percent = (uptime / duration) * 100,
                icon = _get_buff_icon(buff_name),
            }
        end
    end

    -- Sort by uptime descending
    table.sort(processed_buffs, function(a, b)
        return a.uptime > b.uptime
    end)

    return processed_buffs
end

local CombatStatsTracker = class('CombatStatsTracker')

function CombatStatsTracker:init()
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

function CombatStatsTracker:is_enabled(ui_only)
    local game_mode_manager = Managers.state and Managers.state.game_mode
    local gamemode_name = game_mode_manager and game_mode_manager:game_mode_name()

    if not gamemode_name then
        return false
    end

    if gamemode_name == 'hub' or gamemode_name == 'prologue_hub' then
        return ui_only and mod:get('enable_in_hub')
    end

    if gamemode_name ~= 'shooting_range' then
        return mod:get('enable_in_missions')
    end

    return true
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

function CombatStatsTracker:stop()
    self:_end_combat()
    for _, engagement in ipairs(self._active_engagements) do
        self:_finish_enemy_engagement(engagement.unit)
    end
end

function CombatStatsTracker:_get_session_duration()
    local total = self._total_combat_time

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

function CombatStatsTracker:_update_combat()
    if self._is_in_combat then
        local has_active = self:_has_active_engagements()
        if not has_active then
            self:_end_combat()
        end
    end
end

function CombatStatsTracker:_calculate_session_stats()
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

function CombatStatsTracker:_calculate_engagement_stats(engagement)
    local stats = {
        total_damage = engagement.total_damage or 0,
        melee_damage = engagement.melee_damage or 0,
        ranged_damage = engagement.ranged_damage or 0,
        buff_damage = engagement.buff_damage or 0,
        melee_crit_damage = engagement.melee_crit_damage or 0,
        melee_weakspot_damage = engagement.melee_weakspot_damage or 0,
        ranged_crit_damage = engagement.ranged_crit_damage or 0,
        ranged_weakspot_damage = engagement.ranged_weakspot_damage or 0,
        bleed_damage = engagement.bleed_damage or 0,
        burn_damage = engagement.burn_damage or 0,
        toxin_damage = engagement.toxin_damage or 0,
        total_kills = engagement.in_progress and 0 or 1,
        kills = {},
        total_hits = engagement.total_hits or 0,
        melee_hits = engagement.melee_hits or 0,
        ranged_hits = engagement.ranged_hits or 0,
        melee_crit_hits = engagement.melee_crit_hits or 0,
        melee_weakspot_hits = engagement.melee_weakspot_hits or 0,
        ranged_crit_hits = engagement.ranged_crit_hits or 0,
        ranged_weakspot_hits = engagement.ranged_weakspot_hits or 0,
    }

    if not engagement.in_progress and engagement.breed_type then
        stats.kills[engagement.breed_type] = 1
    end

    return stats
end

-- Public API: Get session stats in consistent format
function CombatStatsTracker:get_session_stats()
    local current_time = _get_gameplay_time()
    local duration = self:_get_session_duration()
    local stats = self:_calculate_session_stats()
    local buff_uptime_data = _process_buff_uptime(self._buff_uptime, duration)

    return {
        name = mod:localize('overall_stats'),
        display_name = mod:localize('overall_stats'),
        subtext = string.format('%.1fs', duration),
        start_time = self._session_start_time,
        end_time = current_time,
        duration = duration,
        stats = stats,
        buff_uptime = buff_uptime_data,
        in_progress = self:_has_active_engagements(),
        is_overall = true,
    }
end

-- Public API: Get all engagement stats in consistent format
function CombatStatsTracker:get_engagement_stats()
    local engagements = {}
    local current_time = _get_gameplay_time()

    for i, engagement in ipairs(self._engagements or {}) do
        local duration = (engagement.end_time or current_time) - engagement.start_time
        local stats = self:_calculate_engagement_stats(engagement)
        local buff_uptime_data = _process_buff_uptime(engagement.buffs, duration)

        local subtext
        if engagement.in_progress then
            subtext = mod:localize('in_progress')
        else
            subtext = string.format('%.1fs', duration)
        end

        engagements[i] = {
            name = engagement.breed_name or ('engagement_' .. i),
            display_name = engagement.breed_name or (mod:localize('engagement') .. ' ' .. i),
            subtext = subtext,
            breed_name = engagement.breed_name,
            breed_type = engagement.breed_type,
            start_time = engagement.start_time,
            end_time = engagement.end_time,
            duration = duration,
            stats = stats,
            buff_uptime = buff_uptime_data,
            in_progress = engagement.in_progress or false,
            is_overall = false,
        }
    end

    return engagements
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

function CombatStatsTracker:_update_active_engagements()
    if not self:_has_active_engagements() then
        return
    end

    local current_time = _get_gameplay_time()
    local to_remove = {}

    for i, engagement in ipairs(self._active_engagements) do
        if not ALIVE[engagement.unit] then
            engagement.in_progress = false
            engagement.end_time = current_time
            engagement.duration = current_time - engagement.start_time
            engagement.dps = engagement.duration > 0 and engagement.total_damage / engagement.duration or 0
            table.insert(to_remove, i)
        end
    end

    for i = #to_remove, 1, -1 do
        table.remove(self._active_engagements, to_remove[i])
    end

    if #to_remove > 0 then
        self._session_stats_dirty = true
    end
end

function CombatStatsTracker:_update_enemy_buffs(dt)
    if not self:_has_active_engagements() then
        return
    end

    local current_time = _get_gameplay_time()

    for i, engagement in ipairs(self._active_engagements) do
        engagement.duration = current_time - engagement.start_time
        engagement.dps = engagement.duration > 0 and engagement.total_damage / engagement.duration or 0

        for buff_name, _ in pairs(self._active_buffs) do
            if not engagement.buffs[buff_name] then
                engagement.buffs[buff_name] = 0
            end
            engagement.buffs[buff_name] = engagement.buffs[buff_name] + dt
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
    if not self:is_enabled() then
        return
    end

    self:_update_active_engagements()
    self:_update_buffs(dt)
    self:_update_combat()
end

return CombatStatsTracker
