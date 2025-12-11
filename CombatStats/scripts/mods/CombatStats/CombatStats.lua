local mod = get_mod('CombatStats')

local CombatStatsTracker = mod:io_dofile('CombatStats/scripts/mods/CombatStats/combat_stats_tracker')

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
        init_view_function = function()
            return true
        end,
        class = 'CombatStatsView',
        disable_game_world = false,
        load_always = true,
        load_in_hub = true,
        path = 'CombatStats/scripts/mods/CombatStats/combat_stats_view/combat_stats_view',
        package = 'packages/ui/views/options_view/options_view',
        state_bound = false,
    },
    view_transitions = {},
    view_options = {
        close_all = false,
        close_previous = false,
    },
})

-- Initialize tracker
mod.tracker = CombatStatsTracker:new()

function mod.toggle_view()
    local ui_manager = Managers.ui
    if ui_manager:using_input() then
        return
    end

    if ui_manager:view_active('combat_stats_view') then
        ui_manager:close_view('combat_stats_view')
    elseif mod.tracker:is_enabled(true) then
        ui_manager:open_view('combat_stats_view')
    end
end

function mod.update(dt)
    mod.tracker:update(dt)
end

function mod.on_game_state_changed(status, state_name)
    if (status == 'enter' or status == 'exit') and state_name == 'StateGameplay' then
        mod.tracker:stop()
    end

    -- Preload icon packages
    if status == 'enter' then
        Managers.package:load('packages/ui/views/inventory_view/inventory_view', 'CombatStats', nil, true)
        Managers.package:load(
            'packages/ui/views/inventory_weapons_view/inventory_weapons_view',
            'CombatStats',
            nil,
            true
        )
        Managers.package:load('packages/ui/hud/player_weapon/player_weapon', 'CombatStats', nil, true)
    end
end

mod:hook(CLASS.StateGameplay, 'on_enter', function(func, self, parent, params, creation_context, ...)
    func(self, parent, params, creation_context, ...)

    -- Reset stats when starting new mission
    local mission_name = params.mission_name
    local is_hub = mission_name == 'hub_ship'
    if not is_hub then
        mod.tracker:reset()
    end
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
        if mod.tracker:is_enabled() then
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
                            mod.tracker:_finish_enemy_engagement(attacked_unit)
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

mod:hook_safe('HudElementPlayerBuffs', '_update_buffs', function(self)
    if not mod.tracker:is_enabled() then
        return
    end

    local active_buffs_data = self._active_buffs_data
    local dt = Managers.time and Managers.time:has_timer('gameplay') and Managers.time:delta_time('gameplay') or 0
    mod.tracker:_update_buffs(active_buffs_data, dt)
end)
