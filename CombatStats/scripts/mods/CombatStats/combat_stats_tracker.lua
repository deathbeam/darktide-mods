local mod = get_mod('CombatStats')

local CombatStatsTracker = class('CombatStatsTracker')

function CombatStatsTracker:init()
    self._tracking = false
    self._mission_name = nil
    self._class_name = nil

    self:reset()
end

function CombatStatsTracker:reset()
    -- Do not reset mission_name/class_name and tracking for in mission resets
    self._buffs = {}
    self._engagements = {}
    self._total_combat_time = 0
    self._last_combat_start = nil
    self._session_stats = nil
    self._active_engagements_by_unit = {}
    self._engagements_by_unit = {}
end

function CombatStatsTracker:get_time()
    return Managers.time and Managers.time:has_timer('gameplay') and Managers.time:time('gameplay') or 0
end

function CombatStatsTracker:is_tracking()
    return self._tracking
end

function CombatStatsTracker:get_mission_name()
    return self._mission_name or 'unknown'
end

function CombatStatsTracker:get_class_name()
    return self._class_name or 'unknown'
end

function CombatStatsTracker:load_from_history(history_data)
    self:stop()
    self:reset()

    self._total_combat_time = history_data.duration or 0
    self._mission_name = history_data.mission_name
    self._class_name = history_data.class_name
    self._buffs = history_data.buffs or {}

    for _, eng_data in ipairs(history_data.engagements or {}) do
        local engagement = {
            name = eng_data.name,
            type = eng_data.type,
            start_time = eng_data.start_time,
            end_time = eng_data.end_time,
            killed = eng_data.killed ~= nil and eng_data.killed or true,

            buffs = eng_data.buffs or {},
            stats = eng_data.stats or {},
        }
        table.insert(self._engagements, engagement)
    end

    self._session_stats = nil
end

function CombatStatsTracker:start(mission_name, class_name)
    self:reset()
    self._tracking = true
    self._mission_name = mission_name
    self._class_name = class_name
    self._session_id = Managers and Managers.connection and Managers.connection:session_id() or nil
end

function CombatStatsTracker:stop()
    self:_end_combat()
    self._tracking = false

    local current_time = self:get_time()
    for _, engagement in pairs(self._active_engagements_by_unit) do
        if not engagement.end_time then
            engagement.end_time = current_time
        end
    end

    self._active_engagements_by_unit = {}
    self._session_stats = nil
end

-- Get session stats
function CombatStatsTracker:get_session_stats()
    local total = self._total_combat_time
    if self._last_combat_start then
        total = total + (self:get_time() - self._last_combat_start)
    end

    if not self._session_stats then
        local stats = {
            total_damage = 0,
            overkill_damage = 0,

            melee_damage = 0,
            melee_crit_damage = 0,
            melee_weakspot_damage = 0,
            melee_overkill_damage = 0,

            ranged_damage = 0,
            ranged_crit_damage = 0,
            ranged_weakspot_damage = 0,
            ranged_overkill_damage = 0,

            explosion_damage = 0,
            companion_damage = 0,

            buff_damage = 0,
            bleed_damage = 0,
            burn_damage = 0,
            toxin_damage = 0,

            total_hits = 0,

            melee_hits = 0,
            melee_crit_hits = 0,
            melee_weakspot_hits = 0,

            ranged_hits = 0,
            ranged_crit_hits = 0,
            ranged_weakspot_hits = 0,

            total_kills = 0,
            kills_by_type = {},
            damage_by_type = {},
        }

        for _, engagement in ipairs(self._engagements) do
            stats.total_damage = stats.total_damage + (engagement.stats.total_damage or 0)
            stats.overkill_damage = stats.overkill_damage + (engagement.stats.overkill_damage or 0)

            stats.melee_damage = stats.melee_damage + (engagement.stats.melee_damage or 0)
            stats.melee_crit_damage = stats.melee_crit_damage + (engagement.stats.melee_crit_damage or 0)
            stats.melee_weakspot_damage = stats.melee_weakspot_damage + (engagement.stats.melee_weakspot_damage or 0)
            stats.melee_overkill_damage = stats.melee_overkill_damage + (engagement.stats.melee_overkill_damage or 0)

            stats.ranged_damage = stats.ranged_damage + (engagement.stats.ranged_damage or 0)
            stats.ranged_crit_damage = stats.ranged_crit_damage + (engagement.stats.ranged_crit_damage or 0)
            stats.ranged_weakspot_damage = stats.ranged_weakspot_damage + (engagement.stats.ranged_weakspot_damage or 0)
            stats.ranged_overkill_damage = stats.ranged_overkill_damage + (engagement.stats.ranged_overkill_damage or 0)

            stats.explosion_damage = stats.explosion_damage + (engagement.stats.explosion_damage or 0)
            stats.companion_damage = stats.companion_damage + (engagement.stats.companion_damage or 0)

            stats.buff_damage = stats.buff_damage + (engagement.stats.buff_damage or 0)
            stats.bleed_damage = stats.bleed_damage + (engagement.stats.bleed_damage or 0)
            stats.burn_damage = stats.burn_damage + (engagement.stats.burn_damage or 0)
            stats.toxin_damage = stats.toxin_damage + (engagement.stats.toxin_damage or 0)

            stats.total_hits = stats.total_hits + (engagement.stats.total_hits or 0)

            stats.melee_hits = stats.melee_hits + (engagement.stats.melee_hits or 0)
            stats.melee_crit_hits = stats.melee_crit_hits + (engagement.stats.melee_crit_hits or 0)
            stats.melee_weakspot_hits = stats.melee_weakspot_hits + (engagement.stats.melee_weakspot_hits or 0)

            stats.ranged_hits = stats.ranged_hits + (engagement.stats.ranged_hits or 0)
            stats.ranged_crit_hits = stats.ranged_crit_hits + (engagement.stats.ranged_crit_hits or 0)
            stats.ranged_weakspot_hits = stats.ranged_weakspot_hits + (engagement.stats.ranged_weakspot_hits or 0)

            if engagement.killed then
                stats.total_kills = stats.total_kills + 1
                stats.kills_by_type[engagement.type] = (stats.kills_by_type[engagement.type] or 0) + 1
            end

            stats.damage_by_type[engagement.type] = (stats.damage_by_type[engagement.type] or 0)
                + (engagement.stats.total_damage or 0)
        end

        self._session_stats = stats
    end

    return {
        duration = total,
        buffs = self._buffs,
        stats = self._session_stats,
    }
end

-- Get all engagement stats
function CombatStatsTracker:get_engagement_stats()
    local engagements = {}

    for _, engagement in ipairs(self._engagements or {}) do
        engagements[#engagements + 1] = {
            name = engagement.name,
            type = engagement.type,
            start_time = engagement.start_time,
            end_time = engagement.end_time,
            killed = engagement.killed,

            buffs = engagement.buffs,

            stats = {
                total_damage = engagement.stats.total_damage or 0,
                overkill_damage = engagement.stats.overkill_damage or 0,

                melee_damage = engagement.stats.melee_damage or 0,
                melee_crit_damage = engagement.stats.melee_crit_damage or 0,
                melee_weakspot_damage = engagement.stats.melee_weakspot_damage or 0,
                melee_overkill_damage = engagement.stats.melee_overkill_damage or 0,

                ranged_damage = engagement.stats.ranged_damage or 0,
                ranged_crit_damage = engagement.stats.ranged_crit_damage or 0,
                ranged_weakspot_damage = engagement.stats.ranged_weakspot_damage or 0,
                ranged_overkill_damage = engagement.stats.ranged_overkill_damage or 0,

                explosion_damage = engagement.stats.explosion_damage or 0,
                companion_damage = engagement.stats.companion_damage or 0,

                buff_damage = engagement.stats.buff_damage or 0,
                bleed_damage = engagement.stats.bleed_damage or 0,
                burn_damage = engagement.stats.burn_damage or 0,
                toxin_damage = engagement.stats.toxin_damage or 0,

                total_hits = engagement.stats.total_hits or 0,

                melee_hits = engagement.stats.melee_hits or 0,
                melee_crit_hits = engagement.stats.melee_crit_hits or 0,
                melee_weakspot_hits = engagement.stats.melee_weakspot_hits or 0,

                ranged_hits = engagement.stats.ranged_hits or 0,
                ranged_crit_hits = engagement.stats.ranged_crit_hits or 0,
                ranged_weakspot_hits = engagement.stats.ranged_weakspot_hits or 0,
            },
        }
    end

    return engagements
end

function CombatStatsTracker:_has_active_engagements()
    return next(self._active_engagements_by_unit) ~= nil
end

function CombatStatsTracker:_start_combat()
    if not self._last_combat_start then
        self._last_combat_start = self:get_time()
    end
end

function CombatStatsTracker:_end_combat()
    if self._last_combat_start then
        self._total_combat_time = self._total_combat_time + (self:get_time() - self._last_combat_start)
        self._last_combat_start = nil
    end
end

function CombatStatsTracker:_update_combat()
    if self._last_combat_start then
        local has_active = self:_has_active_engagements()
        if not has_active then
            self:_end_combat()
        end
    end
end

function CombatStatsTracker:_track_engagement(unit, engagement)
    local current_time = self:get_time()
    self._active_engagements_by_unit[unit] = engagement
    engagement.end_time = nil
    engagement.last_damage_time = current_time
    self:_start_combat()
    self._session_stats = nil
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
        last_damage_time = nil,

        name = breed_name,
        type = breed_type,
        start_time = self:get_time(),
        end_time = nil,
        killed = false,

        buffs = {},
        stats = {},
    }

    for buff_name, _ in pairs(self._buffs) do
        engagement.buffs[buff_name] = 0
    end

    table.insert(self._engagements, engagement)
    self._engagements_by_unit[unit] = engagement
    self:_track_engagement(unit, engagement)
end

function CombatStatsTracker:_find_engagement(unit)
    return self._engagements_by_unit[unit]
end

function CombatStatsTracker:_track_enemy_damage(
    unit,
    damage,
    attack_type,
    is_critical,
    is_weakspot,
    damage_profile,
    attack_result
)
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

    local actual_damage = damage
    local overkill_damage = 0
    if attack_result == 'died' then
        local unit_health_extension = ScriptUnit.has_extension(unit, 'health_system')
        if unit_health_extension then
            local health_damage = unit_health_extension:max_health() - unit_health_extension:damage_taken()
            local is_local_session = not self._session_id
            if is_local_session then
                health_damage = health_damage + damage
            end
            overkill_damage = math.max(0, damage - health_damage)
        end
    end

    engagement.stats.total_damage = (engagement.stats.total_damage or 0) + actual_damage
    engagement.stats.overkill_damage = (engagement.stats.overkill_damage or 0) + overkill_damage

    if attack_type == 'melee' then
        engagement.stats.melee_damage = (engagement.stats.melee_damage or 0) + actual_damage
        engagement.stats.melee_overkill_damage = (engagement.stats.melee_overkill_damage or 0) + overkill_damage
        engagement.stats.melee_hits = (engagement.stats.melee_hits or 0) + 1
        engagement.stats.total_hits = (engagement.stats.total_hits or 0) + 1

        if is_critical then
            engagement.stats.melee_crit_damage = (engagement.stats.melee_crit_damage or 0) + actual_damage
            engagement.stats.melee_crit_hits = (engagement.stats.melee_crit_hits or 0) + 1
        end

        if is_weakspot then
            engagement.stats.melee_weakspot_damage = (engagement.stats.melee_weakspot_damage or 0) + actual_damage
            engagement.stats.melee_weakspot_hits = (engagement.stats.melee_weakspot_hits or 0) + 1
        end
    elseif attack_type == 'ranged' then
        engagement.stats.ranged_damage = (engagement.stats.ranged_damage or 0) + actual_damage
        engagement.stats.ranged_overkill_damage = (engagement.stats.ranged_overkill_damage or 0) + overkill_damage
        engagement.stats.ranged_hits = (engagement.stats.ranged_hits or 0) + 1
        engagement.stats.total_hits = (engagement.stats.total_hits or 0) + 1

        if is_critical then
            engagement.stats.ranged_crit_damage = (engagement.stats.ranged_crit_damage or 0) + actual_damage
            engagement.stats.ranged_crit_hits = (engagement.stats.ranged_crit_hits or 0) + 1
        end

        if is_weakspot then
            engagement.stats.ranged_weakspot_damage = (engagement.stats.ranged_weakspot_damage or 0) + actual_damage
            engagement.stats.ranged_weakspot_hits = (engagement.stats.ranged_weakspot_hits or 0) + 1
        end
    elseif attack_type == 'explosion' then
        engagement.stats.explosion_damage = (engagement.stats.explosion_damage or 0) + actual_damage
    elseif attack_type == 'companion_dog' then
        engagement.stats.companion_damage = (engagement.stats.companion_damage or 0) + actual_damage
    elseif attack_type == 'buff' then
        engagement.stats.buff_damage = (engagement.stats.buff_damage or 0) + actual_damage
    end

    if damage_type == 'bleed' then
        engagement.stats.bleed_damage = (engagement.stats.bleed_damage or 0) + actual_damage
    elseif damage_type == 'burn' then
        engagement.stats.burn_damage = (engagement.stats.burn_damage or 0) + actual_damage
    elseif damage_type == 'toxin' then
        engagement.stats.toxin_damage = (engagement.stats.toxin_damage or 0) + actual_damage
    end

    self._session_stats = nil
end

function CombatStatsTracker:_finish_enemy_engagement(unit, killed)
    local engagement = self:_find_engagement(unit)
    if not engagement then
        return
    end

    local current_time = self:get_time()
    engagement.end_time = current_time
    engagement.killed = killed or false
    self._active_engagements_by_unit[unit] = nil
    self._session_stats = nil
end

function CombatStatsTracker:_update_active_engagements()
    if not self:_has_active_engagements() then
        return
    end

    local current_time = self:get_time()
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
        self._session_stats = nil
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
        if not self._buffs[buff_template_name] then
            self._buffs[buff_template_name] = 0
        end
        self._buffs[buff_template_name] = self._buffs[buff_template_name] + dt

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
    self:_update_active_engagements()
    self:_update_combat()
end

return CombatStatsTracker
