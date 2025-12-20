local mod = get_mod('CombatStats')

local CombatStatsTracker = mod:io_dofile('CombatStats/scripts/mods/CombatStats/combat_stats_tracker')
local CombatStatsHistory = mod:io_dofile('CombatStats/scripts/mods/CombatStats/combat_stats_history')

-- Register Combat HUD element
mod:register_hud_element({
    class_name = 'HudElementCombatStats',
    filename = 'CombatStats/scripts/mods/CombatStats/hud_element_combat_stats/hud_element_combat_stats',
    use_hud_scale = true,
    visibility_groups = {
        'alive',
    },
})

-- Register Combat Stats View
mod:add_require_path('CombatStats/scripts/mods/CombatStats/combat_stats_view/combat_stats_view')
mod:register_view({
    view_name = 'combat_stats_view',
    view_settings = {
        init_view_function = function(ingame_ui_context)
            return true
        end,
        class = 'CombatStatsView',
        disable_game_world = false,
        game_world_blur = 0,
        load_always = true,
        load_in_hub = true,
        path = 'CombatStats/scripts/mods/CombatStats/combat_stats_view/combat_stats_view',
        package = 'packages/ui/views/options_view/options_view',
        state_bound = false,
        enter_sound_events = {
            'wwise/events/ui/play_ui_enter_short',
        },
        exit_sound_events = {
            'wwise/events/ui/play_ui_back_short',
        },
        wwise_states = {
            options = 'ingame_menu',
        },
    },
    view_transitions = {},
    view_options = {
        close_all = false,
        close_previous = false,
        close_transition_time = nil,
        transition_time = nil,
    },
})

-- Initialize tracker and history
mod.tracker = CombatStatsTracker:new()
mod.history = CombatStatsHistory:new()

function mod.update(dt)
    if not mod.tracker:is_tracking() then
        return
    end

    mod.tracker:update(dt)
end

mod:hook(CLASS.StateGameplay, 'on_enter', function(func, self, parent, params, ...)
    -- Start tracking
    local mission_name = params.mission_name
    if mission_name ~= 'hub_ship' then
        if
            not mod:get('only_in_psykhanium')
            or (mission_name == 'tg_shooting_range' or mission_name == 'tg_training_grounds')
        then
            local player = Managers.player:local_player(1)
            local class_name = player and player:archetype_name()
            mod.tracker:start(mission_name, class_name)
        end
    end

    -- Preload icon packages
    Managers.package:load('packages/ui/views/inventory_view/inventory_view', 'CombatStats', nil, true)
    Managers.package:load('packages/ui/views/inventory_weapons_view/inventory_weapons_view', 'CombatStats', nil, true)
    Managers.package:load('packages/ui/hud/player_weapon/player_weapon', 'CombatStats', nil, true)

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
                stats = session.stats,
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
            local player = Managers.player:local_player_safe(1)
            if player then
                local player_unit = player.player_unit
                if player_unit and attacking_unit == player_unit then
                    local unit_data_extension = ScriptUnit.has_extension(attacked_unit, 'unit_data_system')
                    local breed = unit_data_extension and unit_data_extension:breed()
                    if breed then
                        mod.tracker:_start_enemy_engagement(attacked_unit, breed)

                        mod.tracker:_track_enemy_damage(
                            attacked_unit,
                            damage,
                            attack_type,
                            is_critical_strike,
                            hit_weakspot,
                            damage_profile and damage_profile.name
                        )

                        if attack_result == 'died' then
                            mod.tracker:_finish_enemy_engagement(attacked_unit, true)
                        end
                    end
                elseif player_unit and attacked_unit == player_unit and mod:get('track_incoming_attacks') then
                    local unit_data_extension = ScriptUnit.has_extension(attacking_unit, 'unit_data_system')
                    local breed = unit_data_extension and unit_data_extension:breed()
                    if breed then
                        mod.tracker:_start_enemy_engagement(attacking_unit, breed)
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

    mod.tracker:_update_buffs(active_buffs_data, hidden_buffs_data, dt)
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
