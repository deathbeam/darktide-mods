local mod = get_mod('CombatStats')

local SharedUtils = mod:io_dofile('CombatStats/scripts/mods/CombatStats/shared/shared_utils')
local _loc = mod:io_dofile('CombatStats/scripts/mods/CombatStats/CombatStats_localization')
SharedUtils.apply_loc_settings(mod, _loc)

local Breed = mod:original_require('scripts/utilities/breed')

local CombatStatsTracker = mod:io_dofile('CombatStats/scripts/mods/CombatStats/combat_stats_tracker')
local CombatStatsHistory = mod:io_dofile('CombatStats/scripts/mods/CombatStats/combat_stats_history')
local CombatStatsUtils = mod:io_dofile('CombatStats/scripts/mods/CombatStats/combat_stats_utils')

-- Register Combat HUD element
mod:register_hud_element({
    class_name = 'HudElementCombatStats',
    filename = 'CombatStats/scripts/mods/CombatStats/hud_element_combat_stats/hud_element_combat_stats',
    use_hud_scale = true,
    visibility_groups = {
        'alive',
    },
})

-- Register Combat Stats View (and its ESC-menu button)
SharedUtils.register_stats_view(
    mod,
    'combat_stats_view',
    'CombatStatsView',
    'CombatStats/scripts/mods/CombatStats/combat_stats_view/combat_stats_view',
    'loc_combat_stats_menu_button'
)

-- Initialize tracker and history
mod.tracker = CombatStatsTracker:new()
mod.history = CombatStatsHistory:new()
mod.utils = CombatStatsUtils:new()

function mod.update(dt)
    if mod.tracker:is_tracking() then
        mod.tracker:update(dt)
    end
end

function mod.on_all_mods_loaded()
    -- Warm the history index so the stats view opens instantly
    if mod.history then
        mod.history:load_index()
    end
end

mod:hook(CLASS.StateGameplay, 'on_enter', function(func, self, parent, params, ...)
    -- Start tracking
    local mission_name = params.mission_name
    if mission_name ~= 'hub_ship' then
        if
            not mod:get('only_in_psykhanium')
            or (mission_name == 'tg_shooting_range' or mission_name == 'tg_training_grounds')
        then
            local player = Managers.player and Managers.player:local_player_safe(1)
            local class_name = player and player:archetype_name()
            mod.tracker:start(mission_name, class_name)
        end
    end

    -- Call original function
    func(self, parent, params, ...)
end)

mod:hook(CLASS.StateGameplay, 'on_exit', function(func, self, ...)
    if mod.tracker:is_tracking() then
        mod.tracker:stop()

        local mission_name = mod.tracker:get_mission_name()
        if
            mission_name ~= 'tg_shooting_range'
            and mission_name ~= 'tg_training_grounds'
            and mod:get('save_history')
        then
            local class_name = mod.tracker:get_class_name()
            local session = mod.tracker:get_session_stats()
            local engagements = mod.tracker:get_engagement_stats()

            local tracker_data = {
                duration = session.duration,
                buffs = session.buffs,
                engagements = engagements,
            }

            mod.history:save_history_entry(tracker_data, mission_name, class_name)
        end
    end

    -- Call original function
    func(self, ...)
end)

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
        if mod.tracker:is_tracking() then
            local player = Managers.player and Managers.player:local_player_safe(1)
            if player then
                local player_unit = player.player_unit
                local player_unit_spawn_manager = Managers.state and Managers.state.player_unit_spawn
                local attacker_owner = attacking_unit
                    and player_unit_spawn_manager
                    and player_unit_spawn_manager:owner(attacking_unit)

                local attacked_breed = ALIVE[attacked_unit]
                        and ScriptUnit.has_extension(attacked_unit, 'unit_data_system')
                    or nil
                attacked_breed = attacked_breed and attacked_breed:breed()

                -- Update the HP ledger for any player hit so teammate damage is reflected.
                local actual_damage, overkill_damage = damage, 0
                if attacker_owner and Breed.is_minion(attacked_breed) then
                    actual_damage, overkill_damage =
                        mod.tracker:update_enemy_health(attacked_unit, damage, attack_result)
                end

                if player_unit and attacking_unit == player_unit and attacked_breed then
                    mod.tracker:start_enemy_engagement(attacked_unit, attacked_breed)

                    local damage_profile_name = damage_profile and damage_profile.name
                    local effective_attack_type = damage_profile_name
                            and damage_profile_name:find('companion')
                            and 'companion'
                        or attack_type

                    mod.tracker:track_enemy_damage(
                        attacked_unit,
                        actual_damage,
                        overkill_damage,
                        effective_attack_type,
                        is_critical_strike,
                        hit_weakspot,
                        damage_profile_name
                    )

                    if attack_result == 'died' then
                        mod.tracker:finish_enemy_engagement(attacked_unit, true)
                    end
                elseif
                    player_unit
                    and attacked_unit == player_unit
                    and ALIVE[attacking_unit]
                    and mod:get('track_incoming_attacks')
                then
                    local unit_data_extension = ScriptUnit.has_extension(attacking_unit, 'unit_data_system')
                    local breed = unit_data_extension and unit_data_extension:breed()
                    if breed then
                        mod.tracker:start_enemy_engagement(attacking_unit, breed)
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

-- Seed at full max_health on spawn; the husk damage field is racy on clients.
mod:hook_safe(CLASS.HuskHealthExtension, 'init', function(self, extension_init_context, unit, ...)
    if not mod.tracker:is_tracking() then
        return
    end
    mod.tracker:register_enemy_health(unit, self)
end)

mod:hook_safe('HudElementPlayerBuffs', '_update_buffs', function(self)
    if not mod.tracker:is_tracking() then
        return
    end

    local dt = Managers.time and Managers.time:has_timer('gameplay') and Managers.time:delta_time('gameplay') or 0

    local active_buffs_data = self._active_buffs_data
    local hidden_buffs_data = nil
    local player = self._player
    if player then
        local player_unit = player.player_unit
        if player_unit then
            local buff_extension = ScriptUnit.has_extension(player_unit, 'buff_system')
            if buff_extension then
                hidden_buffs_data = buff_extension:buffs()
            end
        end
    end

    mod.tracker:update_buffs(active_buffs_data, hidden_buffs_data, dt)
end)

function mod.on_setting_changed(setting_id)
    if setting_id == 'hud_pos_x' or setting_id == 'hud_pos_y' then
        local hud = Managers.ui and Managers.ui:get_hud()
        local element = hud and hud:element('HudElementCombatStats')
        if element and element._update_position then
            element:_update_position()
        end
    end
end
