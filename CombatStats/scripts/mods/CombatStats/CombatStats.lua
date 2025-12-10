local mod = get_mod('CombatStats')

local CombatStatsTracker = mod:io_dofile('CombatStats/scripts/mods/CombatStats/combat_stats_tracker')

local class_name = 'HudElementCombatStats'
local filename = 'CombatStats/scripts/mods/CombatStats/hud_element_combat_stats/hud_element_combat_stats'

mod:register_hud_element({
    class_name = class_name,
    filename = filename,
    use_hud_scale = true,
    visibility_groups = {
        'alive',
    },
})

mod.tracker = CombatStatsTracker:new()

function mod.update(dt)
    mod.tracker:update(dt)
    mod.tracker:draw()
end

function mod.toggle_window()
    if mod.tracker._is_open then
        mod.tracker:close()
    else
        mod.tracker:open()
    end
end

function mod.toggle_window_focus()
    if not mod.tracker._is_open then
        mod.tracker:open()
    end

    if mod.tracker._is_focused then
        mod.tracker:unfocus()
    else
        mod.tracker:focus()
    end
end

function mod.on_game_state_changed(status, state_name)
    if (status == 'enter' or status == 'exit') and state_name == 'StateGameplay' then
        mod.tracker:close()
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
        mod.tracker:reset_stats()
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

mod:hook('UIManager', 'using_input', function(func, ...)
    return mod.tracker._is_focused or func(...)
end)
