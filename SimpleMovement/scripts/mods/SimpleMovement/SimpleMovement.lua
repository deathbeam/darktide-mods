local mod = get_mod('SimpleMovement')
local constants = require('scripts/settings/player_character/player_character_constants')
local ActionAvailability = require('scripts/extension_systems/weapon/utilities/action_availability')
local ActionHandlerSettings = require('scripts/settings/action/action_handler_settings')
local Sprint = require('scripts/extension_systems/character_state_machine/character_states/utilities/sprint')

-- Global Cache
local CLASS = CLASS
local Managers = Managers
local Vector3 = Vector3

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
local previous_state_name = 'walking'
local current_state_name = 'walking'
local is_action_blocking_sprint = false
local sliding_speed = 0

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

-- Reset movement parameters
local function reset_params()
    previous_state_name = 'walking'
    current_state_name = 'walking'
    is_action_blocking_sprint = false
    sliding_speed = 0
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
end

-- Init Movement Component Cache
local function init_movement_component(playerDataExtension)
    if not playerDataExtension then
        return
    end

    movement_components.movement_state = playerDataExtension:read_component('movement_state')
    movement_components.sprint_character_state = playerDataExtension:read_component('sprint_character_state')
    movement_components.dodge_character_state = playerDataExtension:read_component('dodge_character_state')
    movement_components.locomotion = playerDataExtension:read_component('locomotion')
    movement_components.character_state = playerDataExtension:read_component('character_state')
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
    if not movement_components.sprint_character_state then
        return false
    end

    return movement_components.sprint_character_state.is_sprinting
        or movement_components.sprint_character_state.is_sprint_jumping
end

-- Check if player's move input can dodge (diagonal movement)
local function is_dodge_direction()
    local move = Vector3(move_right - move_left, move_forward - move_backward, 0)
    if move.x == 0 and move.y == 0 then
        return always_dodge
    end

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

-- Check if action allows sprinting (checks if next weapon action allows sprint)
local function can_sprint_with_next_action()
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

    return buff_keyword_allows_action_during_sprint
        or allowed_during_sprint
        or requires_press_to_interrupt
        or no_interruption_for_sprint
end

local function can_hold_dodge_slide()
    if not dodge_hold or not movement_components.character_state or not movement_components.dodge_character_state then
        return false
    end
    local start_time = math.max(movement_components.character_state.entered_t, dodge_hold_start_time)
    local distance_left = movement_components.dodge_character_state.distance_left
    local gameplay_time = Managers.time:time('gameplay')
    return gameplay_time - start_time >= 0.2 or distance_left <= 0.24
end

local function can_keep_dodging()
    local dodge_state = movement_components.dodge_character_state
    if not dodge_state or not playerWeaponExtension or not playerBuffExtension then
        return true
    end

    local weapon_dodge_template = playerWeaponExtension:dodge_template()
    local dr_start = (weapon_dodge_template and weapon_dodge_template.diminishing_return_start or 2)
    local extra = math.round(playerBuffExtension:stat_buffs().extra_consecutive_dodges or 0)
    local consecutive = dodge_state.consecutive_dodges
    if Managers.time:time('gameplay') > dodge_state.consecutive_dodges_cooldown then
        consecutive = 0
    end

    return consecutive < dr_start + extra
end

-- Build abort_sprint table from core game settings
local ALLOWED_INPUTS_IN_SPRINT = {
    combat_ability = true,
    wield = true,
}

local abort_sprint_table = {}
for i = 1, #ActionHandlerSettings.abort_sprint do
    local action_kind = ActionHandlerSettings.abort_sprint[i]
    abort_sprint_table[action_kind] = true
end

local function should_abort_sprint(action_settings)
    -- Check if action explicitly sets abort_sprint
    if action_settings.abort_sprint ~= nil then
        return action_settings.abort_sprint and not action_settings.override_allow_during_sprint
    end

    -- Check if action kind is in core game's abort_sprint table
    local action_kind = action_settings.kind
    return abort_sprint_table[action_kind] and not action_settings.override_allow_during_sprint
end

-- Input action hook, simulate action inputs based on movement states for player
local function input_service_hook(func, self, action_name)
    local result = func(self, action_name)

    if action_name == 'sprint' then
        if result then
            sprint_press = current_state_name ~= 'sprinting'
            is_action_blocking_sprint = false -- Clear block when player presses sprint again
        end
    elseif action_name == 'sprinting' then
        -- Hold sprint button to walk (allows manual stamina regen; blocking also works)
        attempt_sprint = not result
        if not attempt_sprint then
            sprint_press = false
        end

        -- Stop sprint for sprint dodge
        if attempt_sprint_dodge then
            return false
        end

        -- Enable continuous sprint
        -- Blocked if: action is preventing sprint, OR player toggled sprint off
        return attempt_sprint and not is_action_blocking_sprint and (sprint_press or can_sprint_with_next_action())
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
        dodge_hold = func(self, 'dodge_hold')
        if dodge_hold then
            dodge_hold_start_time = dodge_hold_start_time or Managers.time:time('gameplay')
        else
            dodge_hold_start_time = nil
        end

        if current_state_name == 'dodging' then
            -- Dodge slide: hold dodge to slide after 0.2s
            attempt_dodge_slide = attempt_dodge_slide or result
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
            -- Keep dodging: hold dodge key to continuously dodge (stops before diminishing returns)
            if dodge_hold and can_keep_dodging() then
                return true
            end
        end
    elseif action_name == 'crouching' then
        if current_state_name == 'sliding' and dodge_hold and (hold_to_crouch or sliding_speed > 0.5) then
            if previous_state_name == 'dodging' then
                return true
            elseif previous_state_name == 'sprinting' then
                return true
            end
        end
        if hold_to_crouch then
            -- Dodge slide
            if
                current_state_name == 'dodging'
                and (attempt_dodge_slide or can_hold_dodge_slide())
                and can_dodge_slide()
            then
                return true
            end
            -- Sprint slide
            if is_sprint_jumping() and attempt_sprint_slide then
                return true
            end
        end
    elseif action_name == 'crouch' then
        if not hold_to_crouch and movement_components.movement_state then
            local is_crouching = movement_components.movement_state.is_crouching
            -- Dodge slide
            if
                current_state_name == 'dodging'
                and (attempt_dodge_slide or can_hold_dodge_slide())
                and not is_crouching
                and can_dodge_slide()
            then
                return true
            end
            -- Sprint slide
            if is_sprint_jumping() and attempt_sprint_slide and not is_crouching then
                return true
            end
        end
    end
    return result
end

-- Mod Enabled
mod.on_enabled = function()
    mod_enabled = true
    init_game_settings()
    enable_hold_to_sprint()
end

-- Mod Disabled
mod.on_disabled = function()
    mod_enabled = false
    reset_params()
end

mod.on_all_mods_loaded = function()
    init_game_settings()
    enable_hold_to_sprint()
end

mod.on_game_state_changed = function(status, state_name)
    if state_name == 'GameplayStateRun' then
        if status == 'enter' then
            init_game_settings()
            enable_hold_to_sprint()
        elseif status == 'exit' then
            reset_params()
        end
    end
end

-- HOOKS
local function on_state_change()
    if current_state_name == 'sprinting' then
        sprint_press = false
    end

    if not is_sprint_jumping() then
        attempt_sprint_slide = false
    end

    if current_state_name ~= 'dodging' then
        attempt_dodge_slide = false
    end

    if current_state_name == 'sliding' then
        attempt_sprint_slide = false
        attempt_dodge_slide = false
    else
        sliding_speed = 0
    end

    if current_state_name ~= 'walking' then
        attempt_sprint_dodge = false
    end
end

-- Hook CharacterStateMachine for Movement State
mod:hook_safe(CLASS.CharacterStateMachine, '_change_state', function(self, unit, dt, t, next_state, params)
    if self._unit_data_extension._player.viewport_name == 'player1' then
        previous_state_name = current_state_name
        current_state_name = next_state
        on_state_change()
    end
end)

mod:hook_safe(CLASS.CharacterStateMachine, 'server_correction_occurred', function(self, unit)
    if
        self._unit_data_extension._player.viewport_name == 'player1'
        and current_state_name ~= self:current_state_name()
    then
        previous_state_name = current_state_name
        current_state_name = self:current_state_name()
        on_state_change()
    end
end)

-- Hook Sliding State for Current Speed
mod:hook_safe(
    CLASS.PlayerCharacterStateSliding,
    '_check_transition',
    function(
        self,
        unit,
        t,
        next_state_params,
        input_source,
        is_crouching,
        commit_period_over,
        max_mass_hit,
        current_speed
    )
        if self._player.viewport_name == 'player1' then
            sliding_speed = current_speed
        end
    end
)

-- Track when actions prevent sprinting (two different mechanisms):
-- 1. is_action_blocking_sprint: Temporary block while action is running (auto-clears when action ends)
-- 2. attempt_sprint: Player's sprint intent (only cleared when player releases sprint or action aborts sprint)
mod:hook_safe(
    CLASS.ActionHandler,
    'start_action',
    function(self, id, action_objects, action_name, action_params, action_settings)
        if self._unit_data_extension._player.viewport_name ~= 'player1' then
            return
        end

        local allowed_during_sprint = ActionAvailability.available_in_sprint(action_settings, self._buff_extension)
        local requires_press_to_interrupt = Sprint.requires_press_to_interrupt(action_settings)
        local no_interruption_for_sprint = Sprint.no_interruption_for_sprint(action_settings)

        -- Check if this action can be performed while sprinting
        local can_do_while_sprinting = allowed_during_sprint
            or requires_press_to_interrupt
            or no_interruption_for_sprint

        -- MECHANISM 1: Temporary sprint block while action is running
        -- This prevents sprint input flickering during incompatible actions
        if not can_do_while_sprinting then
            is_action_blocking_sprint = true
        end

        -- MECHANISM 2: Permanent sprint disable (until player presses sprint again)
        -- Check if action should abort sprint based on core game settings
        local running_action = self._registered_components[id].running_action
        local weapon_template = running_action._weapon_template
        local is_allowed_input = (
            weapon_template and weapon_template.allowed_inputs_in_sprint or ALLOWED_INPUTS_IN_SPRINT
        )[action_settings.start_input]
        local is_abort_sprint = should_abort_sprint(action_settings)

        if not allowed_during_sprint and not is_allowed_input or is_abort_sprint then
            attempt_sprint = false
        end
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

        -- Clear temporary sprint block when no action is running
        if current_action_name == 'none' then
            is_action_blocking_sprint = false
        end
    end
)

mod:hook_safe(CLASS.ActionHandler, '_finish_action', function(self, handler_data)
    if self._unit_data_extension._player.viewport_name ~= 'player1' then
        return
    end

    -- Clear temporary sprint block when action finishes
    is_action_blocking_sprint = false
end)

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
