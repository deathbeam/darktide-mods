local mod = get_mod('CombatStats')

local SESSION_STAT_KEYS = {
    'total_damage',
    'overkill_damage',
    'melee_damage',
    'melee_crit_damage',
    'melee_weakspot_damage',
    'ranged_damage',
    'ranged_crit_damage',
    'ranged_weakspot_damage',
    'explosion_damage',
    'companion_damage',
    'arc_damage',
    'buff_damage',
    'bleed_damage',
    'burn_damage',
    'toxin_damage',
    'total_hits',
    'melee_hits',
    'melee_crit_hits',
    'melee_weakspot_hits',
    'ranged_hits',
    'ranged_crit_hits',
    'ranged_weakspot_hits',
}

local function new_stats(base)
    local stats = base or {}

    for i = 1, #SESSION_STAT_KEYS do
        stats[SESSION_STAT_KEYS[i]] = 0
    end

    return stats
end

-- Apply one damage event to a stats table (an engagement's, or the session cache).
local function add_damage(stats, actual_damage, overkill_damage, attack_type, is_critical, is_weakspot, damage_type)
    stats.total_damage = stats.total_damage + actual_damage
    stats.overkill_damage = stats.overkill_damage + overkill_damage

    if attack_type == 'melee' then
        stats.total_hits = stats.total_hits + 1
        stats.melee_damage = stats.melee_damage + actual_damage
        stats.melee_hits = stats.melee_hits + 1
        if is_critical then
            stats.melee_crit_damage = stats.melee_crit_damage + actual_damage
            stats.melee_crit_hits = stats.melee_crit_hits + 1
        end
        if is_weakspot then
            stats.melee_weakspot_damage = stats.melee_weakspot_damage + actual_damage
            stats.melee_weakspot_hits = stats.melee_weakspot_hits + 1
        end
    elseif attack_type == 'ranged' then
        stats.total_hits = stats.total_hits + 1
        stats.ranged_damage = stats.ranged_damage + actual_damage
        stats.ranged_hits = stats.ranged_hits + 1
        if is_critical then
            stats.ranged_crit_damage = stats.ranged_crit_damage + actual_damage
            stats.ranged_crit_hits = stats.ranged_crit_hits + 1
        end
        if is_weakspot then
            stats.ranged_weakspot_damage = stats.ranged_weakspot_damage + actual_damage
            stats.ranged_weakspot_hits = stats.ranged_weakspot_hits + 1
        end
    elseif attack_type == 'explosion' then
        stats.explosion_damage = stats.explosion_damage + actual_damage
    elseif attack_type == 'companion_dog' then
        stats.companion_damage = stats.companion_damage + actual_damage
    elseif attack_type == 'arc' then
        stats.arc_damage = stats.arc_damage + actual_damage
    elseif attack_type == 'buff' then
        stats.buff_damage = stats.buff_damage + actual_damage
    end

    if damage_type == 'bleed' then
        stats.bleed_damage = stats.bleed_damage + actual_damage
    elseif damage_type == 'burn' then
        stats.burn_damage = stats.burn_damage + actual_damage
    elseif damage_type == 'toxin' then
        stats.toxin_damage = stats.toxin_damage + actual_damage
    end
end

-- Walk a stats table adding each field into the running session totals.
local function accumulate(dst, src)
    for i = 1, #SESSION_STAT_KEYS do
        local key = SESSION_STAT_KEYS[i]
        dst[key] = dst[key] + (src[key] or 0)
    end
end

local CombatStatsTracker = class('CombatStatsTracker')

function CombatStatsTracker:init()
    self._tracking = false
    self._mission_name = nil
    self._class_name = nil

    self:reset()
end

function CombatStatsTracker:reset()
    self._buffs = {}
    self._engagements = {}
    self._total_combat_time = 0
    self._last_combat_start = nil
    self._session_stats = new_stats({
        total_kills = 0,
        kills_by_type = {},
        damage_by_type = {},
    })
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
        table.insert(self._engagements, {
            name = eng_data.name,
            type = eng_data.type,
            start_time = eng_data.start_time,
            end_time = eng_data.end_time,
            killed = eng_data.killed ~= nil and eng_data.killed or true,

            buffs = eng_data.buffs or {},
            stats = eng_data.stats or new_stats(),
        })
    end

    for _, engagement in ipairs(self._engagements) do
        accumulate(self._session_stats, engagement.stats or {})
        if engagement.killed then
            local breed_type = engagement.type or 'unknown'
            self._session_stats.total_kills = self._session_stats.total_kills + 1
            self._session_stats.kills_by_type[breed_type] = (self._session_stats.kills_by_type[breed_type] or 0) + 1
            self._session_stats.damage_by_type[breed_type] = (self._session_stats.damage_by_type[breed_type] or 0)
                + (engagement.stats.total_damage or 0)
        end
    end
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
end

function CombatStatsTracker:get_session_stats()
    local total = self._total_combat_time
    if self._last_combat_start then
        total = total + (self:get_time() - self._last_combat_start)
    end

    return {
        duration = total,
        buffs = self._buffs,
        stats = self._session_stats,
    }
end

function CombatStatsTracker:get_engagement_stats()
    local engagements = {}

    for _, engagement in ipairs(self._engagements or {}) do
        local stats = new_stats()
        accumulate(stats, engagement.stats or {})

        engagements[#engagements + 1] = {
            name = engagement.name,
            type = engagement.type,
            start_time = engagement.start_time,
            end_time = engagement.end_time,
            killed = engagement.killed,
            buffs = engagement.buffs,
            stats = stats,
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
        stats = new_stats(),
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
        local profile_lower = damage_profile:lower()
        if string.find(profile_lower, 'bleed') then
            damage_type = 'bleed'
        elseif
            string.find(profile_lower, 'burn')
            or string.find(profile_lower, 'fire')
            or string.find(profile_lower, 'flame')
        then
            damage_type = 'burn'
        elseif string.find(profile_lower, 'toxin') then
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

    -- Update the engagement and the session cache with the same event so the view stays in sync.
    add_damage(engagement.stats, actual_damage, overkill_damage, attack_type, is_critical, is_weakspot, damage_type)
    add_damage(self._session_stats, actual_damage, overkill_damage, attack_type, is_critical, is_weakspot, damage_type)

    local breed_type = engagement.type or 'unknown'
    self._session_stats.damage_by_type[breed_type] = (self._session_stats.damage_by_type[breed_type] or 0)
        + actual_damage
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

    if killed then
        local breed_type = engagement.type or 'unknown'
        local session_stats = self._session_stats
        session_stats.total_kills = session_stats.total_kills + 1
        session_stats.kills_by_type[breed_type] = (session_stats.kills_by_type[breed_type] or 0) + 1
    end
end

function CombatStatsTracker:_update_active_engagements()
    if not self:_has_active_engagements() then
        return
    end

    local current_time = self:get_time()

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
            engagement.end_time = current_time
            self._active_engagements_by_unit[unit] = nil
        end
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
