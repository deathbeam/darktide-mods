local mod = get_mod('CombatStats')

local function _get_gameplay_time()
    return Managers.time and Managers.time:has_timer('gameplay') and Managers.time:time('gameplay') or 0
end

local CombatStatsTracker = class('CombatStatsTracker')

function CombatStatsTracker:init()
    self._tracked_buffs = {}
    self._engagements = {}
    self._total_combat_time = 0
    self._is_in_combat = false
    self._last_combat_start = nil
    self._mission_name = nil
    self._class_name = nil

    -- Performance caching and lookup tables
    self._active_engagements_by_unit = {}
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

function CombatStatsTracker:reset()
    self._tracked_buffs = {}
    self._engagements = {}
    self._total_combat_time = 0
    self._is_in_combat = false
    self._last_combat_start = nil
    self._mission_name = nil
    self._class_name = nil

    self._active_engagements_by_unit = {}
    self._engagements_by_unit = {}
    self._cached_session_stats = nil
    self._session_stats_dirty = true
end

function CombatStatsTracker:set_mission(mission_name, class_name)
    self._mission_name = mission_name
    self._class_name = class_name
end

function CombatStatsTracker:get_mission_name()
    return self._mission_name or 'unknown'
end

function CombatStatsTracker:get_class_name()
    return self._class_name or 'unknown'
end

function CombatStatsTracker:load_from_history(history_data)
    self:reset()

    self._tracked_buffs = history_data.buffs or {}
    self._total_combat_time = history_data.duration or 0
    self._mission_name = history_data.mission_name
    self._class_name = history_data.class_name

    -- Reconstruct engagements from history
    for _, eng_data in ipairs(history_data.engagements or {}) do
        local engagement = {
            unit = nil,
            name = eng_data.name,
            type = eng_data.type,
            start_time = eng_data.start_time,
            end_time = eng_data.end_time,
            killed = true,
            total_damage = eng_data.stats.total_damage or 0,
            melee_damage = eng_data.stats.melee_damage or 0,
            ranged_damage = eng_data.stats.ranged_damage or 0,
            explosion_damage = eng_data.stats.explosion_damage or 0,
            companion_damage = eng_data.stats.companion_damage or 0,
            buff_damage = eng_data.stats.buff_damage or 0,
            melee_crit_damage = eng_data.stats.melee_crit_damage or 0,
            melee_weakspot_damage = eng_data.stats.melee_weakspot_damage or 0,
            ranged_crit_damage = eng_data.stats.ranged_crit_damage or 0,
            ranged_weakspot_damage = eng_data.stats.ranged_weakspot_damage or 0,
            bleed_damage = eng_data.stats.bleed_damage or 0,
            burn_damage = eng_data.stats.burn_damage or 0,
            toxin_damage = eng_data.stats.toxin_damage or 0,
            total_hits = eng_data.stats.total_hits or 0,
            melee_hits = eng_data.stats.melee_hits or 0,
            ranged_hits = eng_data.stats.ranged_hits or 0,
            melee_crit_hits = eng_data.stats.melee_crit_hits or 0,
            melee_weakspot_hits = eng_data.stats.melee_weakspot_hits or 0,
            ranged_crit_hits = eng_data.stats.ranged_crit_hits or 0,
            ranged_weakspot_hits = eng_data.stats.ranged_weakspot_hits or 0,
            buffs = eng_data.buffs or {},
        }
        table.insert(self._engagements, engagement)
    end

    self._session_stats_dirty = true
end

function CombatStatsTracker:stop()
    self:_end_combat()

    local current_time = _get_gameplay_time()
    for _, engagement in pairs(self._active_engagements_by_unit) do
        if not engagement.end_time then
            engagement.end_time = current_time
        end
    end

    self._active_engagements_by_unit = {}
    self._session_stats_dirty = true
end

-- Get session stats
function CombatStatsTracker:get_session_stats()
    local stats = self:_calculate_session_stats()

    return {
        duration = self:_get_session_duration(),
        stats = stats,
        buffs = self._tracked_buffs,
    }
end

-- Get all engagement stats
function CombatStatsTracker:get_engagement_stats()
    local engagements = {}

    for i, engagement in ipairs(self._engagements or {}) do
        -- Only return killed enemies or currently active engagements
        local is_active = not engagement.end_time
        local is_killed = engagement.killed

        if is_active or is_killed then
            local stats = self:_calculate_engagement_stats(engagement)

            engagements[#engagements + 1] = {
                name = engagement.name,
                type = engagement.type,
                start_time = engagement.start_time,
                end_time = engagement.end_time,
                stats = stats,
                buffs = engagement.buffs,
            }
        end
    end

    return engagements
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
    return next(self._active_engagements_by_unit) ~= nil
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
        explosion_damage = 0,
        companion_damage = 0,
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
        damage_by_type = {},
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

        if engagement.killed then
            stats.total_kills = stats.total_kills + 1
        end

        if engagement.melee_damage then
            stats.melee_damage = stats.melee_damage + engagement.melee_damage
        end
        if engagement.ranged_damage then
            stats.ranged_damage = stats.ranged_damage + engagement.ranged_damage
        end
        if engagement.explosion_damage then
            stats.explosion_damage = stats.explosion_damage + engagement.explosion_damage
        end
        if engagement.companion_damage then
            stats.companion_damage = stats.companion_damage + engagement.companion_damage
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

        if engagement.killed then
            stats.kills[engagement.type] = (stats.kills[engagement.type] or 0) + 1
        end

        -- Track damage by breed type
        if engagement.total_damage and engagement.total_damage > 0 then
            stats.damage_by_type[engagement.type] = (stats.damage_by_type[engagement.type] or 0)
                + engagement.total_damage
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
        explosion_damage = engagement.explosion_damage or 0,
        companion_damage = engagement.companion_damage or 0,
        buff_damage = engagement.buff_damage or 0,
        melee_crit_damage = engagement.melee_crit_damage or 0,
        melee_weakspot_damage = engagement.melee_weakspot_damage or 0,
        ranged_crit_damage = engagement.ranged_crit_damage or 0,
        ranged_weakspot_damage = engagement.ranged_weakspot_damage or 0,
        bleed_damage = engagement.bleed_damage or 0,
        burn_damage = engagement.burn_damage or 0,
        toxin_damage = engagement.toxin_damage or 0,
        total_kills = engagement.killed and 1 or 0,
        kills = {},
        total_hits = engagement.total_hits or 0,
        melee_hits = engagement.melee_hits or 0,
        ranged_hits = engagement.ranged_hits or 0,
        melee_crit_hits = engagement.melee_crit_hits or 0,
        melee_weakspot_hits = engagement.melee_weakspot_hits or 0,
        ranged_crit_hits = engagement.ranged_crit_hits or 0,
        ranged_weakspot_hits = engagement.ranged_weakspot_hits or 0,
    }

    if engagement.killed and engagement.type then
        stats.kills[engagement.type] = 1
    end

    return stats
end

function CombatStatsTracker:_track_engagement(unit, engagement)
    local current_time = _get_gameplay_time()
    self._active_engagements_by_unit[unit] = engagement
    engagement.end_time = nil
    engagement.last_damage_time = current_time
    self:_start_combat()
    self._session_stats_dirty = true
end

function CombatStatsTracker:_start_enemy_engagement(unit, breed)
    local engagement = self:_find_engagement(unit)
    if engagement then
        self:_track_engagement(unit, engagement)
        return
    end

    local breed_name = breed.name
    local breed_type = 'unknown'
    if breed.tags then
        if breed.tags.monster or breed.tags.captain or breed.tags.cultist_captain then
            breed_type = 'monster'
        elseif breed.tags.ritualist then
            breed_type = 'ritualist'
        elseif breed.tags.disabler then
            breed_type = 'disabler'
        elseif breed.tags.special then
            breed_type = 'special'
        elseif breed.tags.elite then
            breed_type = 'elite'
        elseif breed.tags.horde or breed.tags.roamer then
            breed_type = 'horde'
        end
    end

    if not mod:get('breed_' .. breed_type) then
        return
    end

    engagement = {
        unit = unit,
        name = breed_name,
        type = breed_type,
        start_time = _get_gameplay_time(),
        end_time = nil,
        last_damage_time = nil,
        total_damage = 0,
        melee_damage = 0,
        ranged_damage = 0,
        explosion_damage = 0,
        companion_damage = 0,
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
        killed = false,
        buffs = {},
    }

    for buff_name, _ in pairs(self._tracked_buffs) do
        engagement.buffs[buff_name] = 0
    end

    table.insert(self._engagements, engagement)
    self._engagements_by_unit[unit] = engagement
    self:_track_engagement(unit, engagement)
end

function CombatStatsTracker:_find_engagement(unit)
    return self._engagements_by_unit[unit]
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
    elseif attack_type == 'explosion' then
        engagement.explosion_damage = engagement.explosion_damage + damage
    elseif attack_type == 'companion_dog' then
        engagement.companion_damage = engagement.companion_damage + damage
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

function CombatStatsTracker:_finish_enemy_engagement(unit, killed)
    local engagement = self:_find_engagement(unit)
    if not engagement then
        return
    end

    local current_time = _get_gameplay_time()
    engagement.end_time = current_time
    engagement.killed = killed or false
    self._active_engagements_by_unit[unit] = nil

    self._session_stats_dirty = true
end

function CombatStatsTracker:_update_active_engagements()
    if not self:_has_active_engagements() then
        return
    end

    local current_time = _get_gameplay_time()
    local removed_any = false

    for unit, engagement in pairs(self._active_engagements_by_unit) do
        local should_end = false

        if not ALIVE[unit] or not HEALTH_ALIVE[unit] then
            should_end = true
        elseif engagement.last_damage_time then
            local time_since_damage = current_time - engagement.last_damage_time
            if time_since_damage >= mod:get('engagement_timeout') then
                should_end = true
            end
        end

        if should_end then
            removed_any = true
            engagement.end_time = current_time
            self._active_engagements_by_unit[unit] = nil
        end
    end

    if removed_any then
        self._session_stats_dirty = true
    end
end

function CombatStatsTracker:_update_buffs(active_buffs_data, hidden_buff_data, dt)
    if not active_buffs_data and not hidden_buff_data then
        return
    end

    local templates = {}

    if active_buffs_data then
        for i = 1, #active_buffs_data do
            local buff_data = active_buffs_data[i]
            local buff_instance = buff_data.buff_instance

            if not buff_data.remove and buff_instance and buff_data.show then
                local buff_template_name = buff_instance:template_name()
                if buff_template_name then
                    templates[buff_template_name] = true
                end
            end
        end
    end

    if hidden_buff_data then
        for i = 1, #hidden_buff_data do
            local buff_instance = hidden_buff_data[i]
            if buff_instance then
                local buff_template_name = buff_instance:template_name()

                if buff_template_name and not templates[buff_template_name] then
                    local buff_template = buff_instance:template()
                    local has_duration = buff_template.duration or buff_template.active_duration
                    local is_proc_buff = buff_instance.is_proc_active ~= nil
                    local should_track = not is_proc_buff or (is_proc_buff and buff_instance:is_proc_active())
                    if has_duration and should_track then
                        templates[buff_template_name] = true
                    end
                end
            end
        end
    end

    for buff_template_name, _ in pairs(templates) do
        -- Update tracked buffs
        if not self._tracked_buffs[buff_template_name] then
            self._tracked_buffs[buff_template_name] = 0
        end
        self._tracked_buffs[buff_template_name] = self._tracked_buffs[buff_template_name] + dt

        -- Update active engagements
        for _, engagement in pairs(self._active_engagements_by_unit) do
            if not engagement.buffs[buff_template_name] then
                engagement.buffs[buff_template_name] = 0
            end
            engagement.buffs[buff_template_name] = engagement.buffs[buff_template_name] + dt
        end
    end
end

function CombatStatsTracker:update()
    if not self:is_enabled() then
        return
    end

    self:_update_active_engagements()
    self:_update_combat()
end

return CombatStatsTracker
