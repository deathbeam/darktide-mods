local mod = get_mod('SimpleMovement')
local constants = require('scripts/settings/player_character/player_character_constants')
local ActionAvailability = require('scripts/extension_systems/weapon/utilities/action_availability')
local Sprint = require('scripts/extension_systems/character_state_machine/character_states/utilities/sprint')

-- Global Cache
local CLASS = CLASS
local ScriptUnit = ScriptUnit
local Managers = Managers
local Vector3 = Vector3

-- Player Cache
local player = nil

-- Extensions Cache
local playerBuffExtension = nil
local playerWeaponExtension = nil
local playerActionInputExtension = nil

-- Movement Component Cache
local movement_components = {}

-- Game Settings
local hold_to_crouch = true
local diagonal_forward_dodge = true
local stationary_dodge = false
local always_dodge = false

-- Mod Status
local mod_enabled = false

-- Player Movement Status
local current_state_name = 'walking'
local is_in_hub = false
local time_in_dodge = 0
local no_sprinting_bug_fix = false
local no_sprinting_stamina = false
local sprint_action_settings = nil
local run_n_gun_need_sprint = false

-- Input Cache
local sprint_press = false
local move_forward = 0
local move_backward = 0
local move_left = 0
local move_right = 0
local dodge_hold = false
local dodge_hold_start_time = nil

-- Fake Input Flag
local attempt_dodge_slide = false
local attempt_sprint_slide = false
local attempt_sprint = false
local attempt_sprint_dodge = false

-- Stamina Management (from DefaultSprint)
local current_slot = 'slot_primary'
local is_attacking = false
local attacking_time = 0.0

-- Sprint-attack whitelist (weapons that can attack while sprinting)
local SPRINT_WEAPONS = {
    'loc_combatknife_p1_m1',
    'loc_combatknife_p1_m2',
    'loc_combatsword_p3_m1',
    'loc_combatsword_p3_m2',
    'loc_combatsword_p3_m3',
    'loc_dual_shivs_p1_m1',
    'loc_dual_shivs_p1_m2',
}

-- Reset movement parameters
local function reset_params()
    current_state_name = 'walking'
    is_in_hub = false
    time_in_dodge = 0
    no_sprinting_bug_fix = false
    no_sprinting_stamina = false
    sprint_action_settings = nil
    run_n_gun_need_sprint = false
    sprint_press = false
    move_forward = 0
    move_backward = 0
    move_left = 0
    move_right = 0
    dodge_hold = false
    dodge_hold_start_time = nil
    attempt_dodge_slide = false
    attempt_sprint_slide = false
    attempt_sprint = false
    attempt_sprint_dodge = false
    current_slot = 'slot_primary'
    is_attacking = false
    attacking_time = 0.0
end

-- Get Extensions
local function get_player_data_extension()
    return player and ScriptUnit.extension(player.player_unit, 'unit_data_system')
end

local function get_player_buff_extension()
    return player and ScriptUnit.extension(player.player_unit, 'buff_system')
end

local function get_player_weapon_extension()
    return player and ScriptUnit.extension(player.player_unit, 'weapon_system')
end

local function get_player_action_input_extension()
    return player and ScriptUnit.extension(player.player_unit, 'action_input_system')
end

-- Init Player Cache
local function init_player()
    local result = Managers.player:local_player_safe(1)
    if result then
        player = result
    end
end

-- Init Extensions Cache
local function init_extensions()
    local result = get_player_buff_extension()
    if result then
        playerBuffExtension = result
    end
    result = get_player_weapon_extension()
    if result then
        playerWeaponExtension = result
    end
    result = get_player_action_input_extension()
    if result then
        playerActionInputExtension = result
    end
end

-- Init Movement Component Cache
local function init_movement_component(playerDataExtension)
    playerDataExtension = playerDataExtension or get_player_data_extension()
    if not playerDataExtension then
        return
    end

    movement_components.movement_state = playerDataExtension:read_component('movement_state')
    movement_components.hub_jog_character_state = playerDataExtension:read_component('hub_jog_character_state')
    movement_components.sprint_character_state = playerDataExtension:read_component('sprint_character_state')
    movement_components.dodge_character_state = playerDataExtension:read_component('dodge_character_state')
    movement_components.locomotion = playerDataExtension:read_component('locomotion')
end

-- Init Cache
local function init_cache()
    init_player()
    init_extensions()
    init_movement_component()
end

local function init_game_settings()
    hold_to_crouch = Managers.save:account_data().input_settings.hold_to_crouch
    diagonal_forward_dodge = Managers.save:account_data().input_settings.diagonal_forward_dodge
    stationary_dodge = Managers.save:account_data().input_settings.stationary_dodge
    always_dodge = Managers.save:account_data().input_settings.always_dodge
end

-- Turn on Hold to Sprint (required for always sprint)
local function enable_hold_to_sprint()
    if not mod_enabled then
        return
    end

    local input_settings = Managers.save:account_data().input_settings
    if not input_settings.hold_to_sprint then
        input_settings.hold_to_sprint = true
    end
end

-- Check if player is in hub
local function check_is_in_hub()
    local gameModeManager = Managers.state.game_mode
    is_in_hub = gameModeManager and (gameModeManager:is_social_hub() or gameModeManager:is_prologue_hub())
end

-- Time for Now
local function main_time()
    return Managers.time:time('main')
end

-- Get equipped weapon name
local function get_equip_weapon()
    if not player or not player._profile then
        return 'unknown'
    end
    local profile = player._profile
    local slot = current_slot or 'slot_primary'
    local weapon = profile.loadout[slot]
    if not weapon then
        return 'unknown'
    end
    return weapon.display_name
end

-- Check if weapon can sprint while attacking
local function is_sprint_weapon(weapon)
    for i = 1, #SPRINT_WEAPONS do
        if weapon == SPRINT_WEAPONS[i] then
            return true
        end
    end
    return false
end

-- Check if action should stop sprint (from DefaultSprint)
local function is_unsprint_action(action_name)
    return action_name:find('melee_start')
        or action_name:find('light')
        or action_name:find('left_heavy')
        or action_name:find('right_heavy')
        or action_name:find('action_heavy')
        or action_name:find('rapid')
        or action_name == 'action_zealot_channel'
        or action_name == 'action_spread_charged'
end

-- Check if slide action is valid
local function can_dodge_slide()
    if not movement_components.locomotion or not movement_components.dodge_character_state then
        return true
    end

    local velocity = movement_components.locomotion.velocity_current
    if not velocity then
        return true
    end

    local started_from_crouch = movement_components.dodge_character_state.started_from_crouch
    local distance_left = movement_components.dodge_character_state.distance_left
    local current_length_sq = Vector3.length_squared(Vector3.flat(velocity))
    local slide_threshold_sq = constants.slide_move_speed_threshold_sq
    return not started_from_crouch and distance_left > 0 and current_length_sq > slide_threshold_sq
end

-- Check if player is sprinting or sprint-jumping
local function is_sprint_jumping()
    if is_in_hub then
        if not movement_components.hub_jog_character_state then
            return false
        end

        return movement_components.hub_jog_character_state.move_state == 'sprint'
    else
        if not movement_components.sprint_character_state then
            return false
        end

        return movement_components.sprint_character_state.is_sprinting
            or movement_components.sprint_character_state.is_sprint_jumping
    end
end

-- Check if player's move input can dodge (diagonal movement)
local function is_dodge_direction()
    local move = Vector3(move_right - move_left, move_forward - move_backward, 0)
    local normalized_move = Vector3.normalize(move)
    local y = normalized_move.y
    local x = normalized_move.x
    return y < 0
        or (y == 0 and x ~= 0)
        or (diagonal_forward_dodge and y > 0 and math.abs(x) > 0.707)
        or (stationary_dodge and y == 0 and x == 0)
        or always_dodge
end

-- Check if jump action is valid
local function can_jump()
    if current_state_name == 'sprinting' then
        return true
    end

    return not is_dodge_direction()
end

-- Check if player has move input
local function has_move_input()
    if is_in_hub then
        return move_forward ~= move_backward or move_right ~= move_left
    else
        return move_forward - move_backward > 0
    end
end

-- Check if sprinting is valid
local function is_sprinting_valid()
    if not playerBuffExtension or not playerWeaponExtension or not playerActionInputExtension then
        return true
    end

    local weapon_action_input = playerActionInputExtension:peek_next_input('weapon_action')
    if not weapon_action_input then
        return true
    end

    local action_settings = playerWeaponExtension:action_settings_from_action_input(weapon_action_input)
    if not action_settings then
        return true
    end

    local allowed_during_sprint, buff_keyword_allows_action_during_sprint =
        ActionAvailability.available_in_sprint(action_settings, playerBuffExtension)
    local requires_press_to_interrupt = Sprint.requires_press_to_interrupt(action_settings)
    local no_interruption_for_sprint = Sprint.no_interruption_for_sprint(action_settings)
    if
        buff_keyword_allows_action_during_sprint
        or allowed_during_sprint
        or requires_press_to_interrupt
        or no_interruption_for_sprint
    then
        return true
    end

    return false
end

-- Input action hook, simulate action inputs based on movement states for player
local function input_service_hook(func, self, action_name)
    local result = func(self, action_name)

    if action_name == 'sprint' then
        -- Always sprint mode: set attempt_sprint on any sprint press
        if result then
            sprint_press = current_state_name ~= 'sprinting'
            no_sprinting_bug_fix = false
            no_sprinting_stamina = false
        end
        if run_n_gun_need_sprint and attempt_sprint and not is_sprint_jumping() and has_move_input() then
            return true
        end
    elseif action_name == 'sprinting' then
        -- Hold sprint button to walk (allows manual stamina regen; blocking also works)
        attempt_sprint = not result
        if not attempt_sprint then
            sprint_press = false
        end

        -- Auto-stop sprint during attacks for stamina regen
        -- Exception: sprint-attack weapons (combat knives, dual shivs, combat swords)
        if is_attacking then
            local weapon_name = get_equip_weapon()
            if not is_sprint_weapon(weapon_name) then
                return false
            end
        end

        -- Stop sprint for sprint dodge
        if attempt_sprint_dodge then
            return false
        end

        -- Enable continuous sprint
        return attempt_sprint
            and not no_sprinting_bug_fix
            and not no_sprinting_stamina
            and (sprint_press or is_sprinting_valid())
    elseif action_name == 'move_forward' then
        move_forward = result
    elseif action_name == 'move_backward' then
        move_backward = result
    elseif action_name == 'move_left' then
        move_left = result
    elseif action_name == 'move_right' then
        move_right = result
    elseif action_name == 'jump' then
        -- Prevent accidental jump when dodging
        if current_state_name == 'dodging' then
            return false
        elseif (current_state_name == 'walking' or current_state_name == 'sprinting') and not can_jump() then
            return false
        end
    elseif action_name == 'jump_held' then
        -- Auto vault when airborne
        if current_state_name == 'jumping' or current_state_name == 'falling' then
            return true
        end
    elseif action_name == 'dodge' then
        if result then
            dodge_hold = true
            dodge_hold_start_time = main_time()
        end
        if not func(self, 'dodge_hold') then
            dodge_hold = false
            dodge_hold_start_time = nil
        end

        if current_state_name == 'dodging' then
            -- Dodge slide: hold dodge to slide after 0.2s
            attempt_dodge_slide = attempt_dodge_slide or dodge_hold and time_in_dodge > 0.2
        elseif is_sprint_jumping() and current_state_name == 'sprinting' then
            -- Check if moving diagonally or straight forward
            if not is_dodge_direction() then
                -- Straight forward sprint: trigger sprint slide
                attempt_sprint_slide = attempt_sprint_slide or result
            else
                -- Diagonal sprint: allow sprint dodge (with keep dodging)
                attempt_sprint_dodge = attempt_sprint_dodge or result or dodge_hold
            end
        elseif current_state_name == 'walking' then
            if attempt_sprint_dodge then
                if is_dodge_direction() then
                    return true
                else
                    attempt_sprint_dodge = false
                end
            end
            -- Keep dodging: hold dodge key to continuously dodge
            if dodge_hold then
                return true
            end
        end
    elseif action_name == 'crouching' then
        if hold_to_crouch then
            -- Dodge slide
            if current_state_name == 'dodging' and attempt_dodge_slide and can_dodge_slide() then
                return true
            end
            -- Sprint slide
            if is_sprint_jumping() and attempt_sprint_slide then
                return true
            end
        end
    elseif action_name == 'crouch' then
        if not hold_to_crouch then
            -- Dodge slide
            if
                current_state_name == 'dodging'
                and attempt_dodge_slide
                and not movement_components.movement_state.is_crouching
                and can_dodge_slide()
            then
                return true
            end
            -- Sprint slide
            if is_sprint_jumping() and attempt_sprint_slide and not movement_components.movement_state.is_crouching then
                return true
            end
        end
    end
    return result
end

-- Update attacking timer
mod.update = function(dt)
    if attacking_time > 0 then
        is_attacking = true
        attacking_time = attacking_time - dt
    else
        attacking_time = 0
        is_attacking = false
    end
end

-- Mod Enabled
mod.on_enabled = function()
    mod_enabled = true
    init_cache()
    init_game_settings()
    enable_hold_to_sprint()
    check_is_in_hub()
end

-- Mod Disabled
mod.on_disabled = function()
    mod_enabled = false
    reset_params()
end

mod.on_all_mods_loaded = function()
    init_cache()
    init_game_settings()
    enable_hold_to_sprint()
    check_is_in_hub()
end

mod.on_game_state_changed = function(status, state_name)
    if state_name == 'GameplayStateRun' then
        if status == 'enter' then
            init_game_settings()
            enable_hold_to_sprint()
            check_is_in_hub()
        elseif status == 'exit' then
            reset_params()
        end
    end
end

-- HOOKS
local function on_state_change()
    if current_state_name == 'sprinting' then
        sprint_press = false
    else
        attempt_sprint_slide = false
    end

    if current_state_name ~= 'dodging' then
        attempt_dodge_slide = false
        time_in_dodge = 0
    end

    if current_state_name == 'sliding' then
        attempt_sprint_slide = false
        attempt_dodge_slide = false
    end

    if current_state_name ~= 'walking' then
        attempt_sprint_dodge = false
    end
end

-- Hook CharacterStateMachine for Movement State
mod:hook_safe(CLASS.CharacterStateMachine, '_change_state', function(self, unit, dt, t, next_state, params)
    if self._unit_data_extension._player.viewport_name == 'player1' then
        current_state_name = next_state
        on_state_change()
    end
end)

mod:hook_safe(CLASS.CharacterStateMachine, 'server_correction_occurred', function(self, unit)
    if self._unit_data_extension._player.viewport_name == 'player1' then
        current_state_name = self:current_state_name()
        on_state_change()
    end
end)

-- Calculate time in dodge
mod:hook_safe(
    CLASS.PlayerCharacterStateDodging,
    'fixed_update',
    function(self, unit, dt, t, next_state_params, fixed_frame)
        if self._player.viewport_name == 'player1' then
            time_in_dodge = t - self._character_state_component.entered_t
        end
    end
)

local function on_action_change(self, id, running_action)
    local action_settings = running_action:action_settings()
    local allowed_during_sprint, buff_keyword_allows_action_during_sprint =
        ActionAvailability.available_in_sprint(action_settings, self._buff_extension)
    if id == 'weapon_action' then
        local requires_press_to_interrupt = Sprint.requires_press_to_interrupt(action_settings)
        local no_interruption_for_sprint = Sprint.no_interruption_for_sprint(action_settings)
        if
            not allowed_during_sprint
            and not buff_keyword_allows_action_during_sprint
            and not requires_press_to_interrupt
            and not no_interruption_for_sprint
        then
            no_sprinting_bug_fix = true
        end

        if sprint_action_settings == action_settings then
            no_sprinting_stamina = true
        end
        sprint_action_settings = nil

        if buff_keyword_allows_action_during_sprint and requires_press_to_interrupt then
            run_n_gun_need_sprint = true
        end
    end
end

mod:hook_safe(
    CLASS.ActionHandler,
    'start_action',
    function(
        self,
        id,
        action_objects,
        action_name,
        action_params,
        action_settings,
        used_input,
        t,
        transition_type,
        condition_func_params,
        automatic_input,
        reset_combo_override
    )
        if self._unit_data_extension._player.viewport_name ~= 'player1' then
            return
        end

        local handler_data = self._registered_components[id]
        local running_action = handler_data.running_action
        on_action_change(self, id, running_action)

        -- Attack detection for stamina management
        -- Sprint attacks: if action has "sprint" in name, don't stop sprinting
        if action_name:find('sprint') then
            is_attacking = false
            attacking_time = 0
            return
        end

        -- Check if this is an action that should stop sprinting
        if is_unsprint_action(action_name) then
            local action_time = self:_calculate_action_total_time(
                action_settings,
                action_params,
                self:_calculate_time_scale(action_settings)
            )

            -- Action only needs about 1/2 time to finish, unless it's a start action
            if not action_name:find('start') then
                action_time = action_time / 2
            end

            -- Minimum action time to prevent interruption
            if action_time < 0.5 then
                action_time = 0.5
            end

            attacking_time = action_time
            is_attacking = true
            return
        end

        -- Reset attacking state for other actions
        is_attacking = false
        attacking_time = 0
    end
)

mod:hook_safe(
    CLASS.ActionHandler,
    'server_correction_occurred',
    function(self, id, action_objects, action_params, actions)
        if self._unit_data_extension._player.viewport_name ~= 'player1' then
            return
        end

        local handler_data = self._registered_components[id]
        local current_action_name = handler_data.component.current_action_name
        if current_action_name ~= 'none' then
            local running_action = handler_data.running_action
            on_action_change(self, id, running_action)
        elseif id == 'weapon_action' then
            no_sprinting_bug_fix = false
            no_sprinting_stamina = false
            run_n_gun_need_sprint = false
        end
    end
)

mod:hook_safe(
    CLASS.ActionHandler,
    '_finish_action',
    function(self, handler_data, reason, data, t, next_action_params, condition_func_params)
        if self._unit_data_extension._player.viewport_name ~= 'player1' then
            return
        end

        if handler_data.id == 'weapon_action' then
            no_sprinting_bug_fix = false
            run_n_gun_need_sprint = false
            if reason ~= 'new_interrupting_action' then
                no_sprinting_stamina = false
            end
        end
    end
)

-- Update settings when input settings changed
mod:hook_safe(CLASS.EventManager, 'trigger', function(self, event_name, ...)
    if event_name == 'event_on_input_settings_changed' then
        init_game_settings()
        enable_hold_to_sprint()
    end
end)

-- Add dodge held input detection
mod:hook_require('scripts/settings/input/default_ingame_input_settings', function(instance)
    instance.settings.dodge_hold = {
        key_alias = 'dodge',
        type = 'held',
    }
end)

-- Player Cache Hook
mod:hook_safe(CLASS.HumanPlayer, 'init', function(self, ...)
    if self.viewport_name == 'player1' then
        player = self
    end
end)

mod:hook_safe(CLASS.HumanPlayer, 'destroy', function(self, ...)
    if self.viewport_name == 'player1' then
        player = nil
    end
end)

-- Extensions Hook
mod:hook_safe(CLASS.PlayerUnitBuffExtension, 'init', function(self, ...)
    if self._player.viewport_name == 'player1' then
        playerBuffExtension = self
    end
end)

mod:hook_safe(CLASS.PlayerUnitBuffExtension, 'delete', function(self, ...)
    if self._player.viewport_name == 'player1' then
        playerBuffExtension = nil
    end
end)

mod:hook_safe(CLASS.PlayerUnitWeaponExtension, 'init', function(self, ...)
    if self._player.viewport_name == 'player1' then
        playerWeaponExtension = self
    end
end)

mod:hook_safe(CLASS.PlayerUnitWeaponExtension, 'delete', function(self, ...)
    if self._player.viewport_name == 'player1' then
        playerWeaponExtension = nil
    end
end)

-- Track weapon slot changes
mod:hook_safe(CLASS.PlayerUnitWeaponExtension, 'on_slot_wielded', function(self, slot_name, t, skip_wield_action)
    if self._player.viewport_name == 'player1' then
        current_slot = slot_name
    end
end)

mod:hook_safe(CLASS.PlayerUnitActionInputExtension, 'init', function(self, ...)
    playerActionInputExtension = self
end)

mod:hook_safe(CLASS.PlayerUnitActionInputExtension, 'delete', function(self, ...)
    playerActionInputExtension = nil
end)

-- Player Unit Data Hook
mod:hook_safe(CLASS.PlayerUnitDataExtension, 'init', function(self, ...)
    if self._player.viewport_name == 'player1' then
        init_movement_component(self)
    end
end)

mod:hook_safe(CLASS.PlayerUnitDataExtension, 'destroy', function(self, ...)
    if self._player.viewport_name == 'player1' then
        movement_components = {}
    end
end)

-- Input Service Hook for fake input
mod:hook(CLASS.InputService, '_get', input_service_hook)
mod:hook(CLASS.InputService, '_get_simulate', input_service_hook)
