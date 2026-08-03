local mod = get_mod('SimpleMovement')

local constants = require('scripts/settings/player_character/player_character_constants')
local ActionAvailability = require('scripts/extension_systems/weapon/utilities/action_availability')
local ActionHandlerSettings = require('scripts/settings/action/action_handler_settings')
local Sprint = require('scripts/extension_systems/character_state_machine/character_states/utilities/sprint')

local CLASS = CLASS
local Managers = Managers
local Vector3 = Vector3

local movement_components = {}
local player_buff_extension
local player_weapon_extension
local player_action_input_extension

local hold_to_crouch = true
local diagonal_forward_dodge = true
local stationary_dodge = false
local always_dodge = false
local original_hold_to_sprint

local mod_enabled = false
local previous_state_name = 'walking'
local current_state_name = 'walking'
local is_action_blocking_sprint = false
local sliding_speed = 0

local sprint_press = false
local move_forward = 0
local move_backward = 0
local move_left = 0
local move_right = 0
local dodge_hold = false
local dodge_hold_start_time

local attempt_dodge_slide = false
local attempt_sprint_slide = false
local attempt_sprint = false
local attempt_sprint_dodge = false

local ALLOWED_INPUTS_IN_SPRINT = {
    combat_ability = true,
    wield = true,
}

local function _is_local_player(player)
    return player and player.viewport_name == 'player1'
end

local function _reset_state()
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

local function _init_movement_components(unit_data_extension)
    if not unit_data_extension then
        return
    end

    movement_components.movement_state = unit_data_extension:read_component('movement_state')
    movement_components.sprint_character_state = unit_data_extension:read_component('sprint_character_state')
    movement_components.dodge_character_state = unit_data_extension:read_component('dodge_character_state')
    movement_components.locomotion = unit_data_extension:read_component('locomotion')
    movement_components.character_state = unit_data_extension:read_component('character_state')
end

local function _init_game_settings()
    local save_manager = Managers.save
    local account_data = save_manager and save_manager:account_data()
    local input_settings = account_data and account_data.input_settings

    if not input_settings then
        return
    end

    hold_to_crouch = input_settings.hold_to_crouch
    diagonal_forward_dodge = input_settings.diagonal_forward_dodge
    stationary_dodge = input_settings.stationary_dodge
    always_dodge = input_settings.always_dodge
end

local function _enable_hold_to_sprint()
    if not mod_enabled then
        return
    end

    local save_manager = Managers.save
    local account_data = save_manager and save_manager:account_data()
    local input_settings = account_data and account_data.input_settings

    if not input_settings or input_settings.hold_to_sprint then
        return
    end

    original_hold_to_sprint = input_settings.hold_to_sprint
    input_settings.hold_to_sprint = true
end

local function _restore_hold_to_sprint()
    if original_hold_to_sprint == nil then
        return
    end

    local save_manager = Managers.save
    local account_data = save_manager and save_manager:account_data()
    local input_settings = account_data and account_data.input_settings

    if input_settings then
        input_settings.hold_to_sprint = original_hold_to_sprint
    end

    original_hold_to_sprint = nil
end

local function _can_dodge_slide()
    local locomotion = movement_components.locomotion
    local dodge_state = movement_components.dodge_character_state

    if not locomotion or not dodge_state or not locomotion.velocity_current then
        return true
    end

    local velocity = locomotion.velocity_current
    local current_length_sq = Vector3.length_squared(Vector3.flat(velocity))
    local slide_threshold_sq = constants.slide_move_speed_threshold_sq

    return not dodge_state.started_from_crouch
        and dodge_state.distance_left > 0
        and current_length_sq > slide_threshold_sq
end

local function _is_sprint_jumping()
    local sprint_state = movement_components.sprint_character_state

    return sprint_state and (sprint_state.is_sprinting or sprint_state.is_sprint_jumping) or false
end

local function _is_dodge_direction()
    local move = Vector3(move_right - move_left, move_forward - move_backward, 0)

    if move.x == 0 and move.y == 0 then
        return always_dodge
    end

    local normalized_move = Vector3.normalize(move)
    local x = normalized_move.x
    local y = normalized_move.y

    return y < 0
        or y == 0 and x ~= 0
        or diagonal_forward_dodge and y > 0 and math.abs(x) > 0.707
        or stationary_dodge and y == 0 and x == 0
        or always_dodge
end

local function _can_jump()
    if current_state_name == 'sprinting' then
        return true
    end

    return not _is_dodge_direction()
end

local function _can_sprint_with_next_action()
    if not player_buff_extension or not player_weapon_extension or not player_action_input_extension then
        return true
    end

    local weapon_action_input = player_action_input_extension:peek_next_input('weapon_action')
    if not weapon_action_input then
        return true
    end

    local action_settings = player_weapon_extension:action_settings_from_action_input(weapon_action_input)
    if not action_settings then
        return true
    end

    local allowed_during_sprint, buff_allows_action =
        ActionAvailability.available_in_sprint(action_settings, player_buff_extension)
    local requires_press_to_interrupt = Sprint.requires_press_to_interrupt(action_settings)
    local no_interruption_for_sprint = Sprint.no_interruption_for_sprint(action_settings)

    return buff_allows_action or allowed_during_sprint or requires_press_to_interrupt or no_interruption_for_sprint
end

local abort_sprint_by_kind = {}
for i = 1, #ActionHandlerSettings.abort_sprint do
    local action_kind = ActionHandlerSettings.abort_sprint[i]
    abort_sprint_by_kind[action_kind] = true
end

local function _should_abort_sprint(action_settings)
    if not action_settings then
        return false
    end

    if action_settings.abort_sprint ~= nil then
        return action_settings.abort_sprint and not action_settings.override_allow_during_sprint
    end

    return abort_sprint_by_kind[action_settings.kind] and not action_settings.override_allow_during_sprint or false
end

local function _can_hold_dodge_slide()
    local character_state = movement_components.character_state
    local dodge_state = movement_components.dodge_character_state

    if not dodge_hold or not character_state or not dodge_state then
        return false
    end

    local start_time = math.max(character_state.entered_t, dodge_hold_start_time)
    local distance_left = dodge_state.distance_left
    local gameplay_time = Managers.time:time('gameplay')

    return gameplay_time - start_time >= 0.2 or distance_left <= 0.24
end

local function _can_keep_dodging()
    local dodge_state = movement_components.dodge_character_state

    if not dodge_state or not player_weapon_extension or not player_buff_extension then
        return true
    end

    local dodge_template = player_weapon_extension:dodge_template()
    local diminishing_return_start = dodge_template and dodge_template.diminishing_return_start or 2
    local extra_dodges = math.round(player_buff_extension:stat_buffs().extra_consecutive_dodges or 0)
    local consecutive_dodges = dodge_state.consecutive_dodges

    if Managers.time:time('gameplay') > dodge_state.consecutive_dodges_cooldown then
        consecutive_dodges = 0
    end

    return consecutive_dodges < diminishing_return_start + extra_dodges
end

local function _input_service_hook(func, self, action_name)
    local result = func(self, action_name)

    if not mod_enabled then
        return result
    end

    if action_name == 'sprint' then
        if result then
            sprint_press = current_state_name ~= 'sprinting'
            is_action_blocking_sprint = false
        end
    elseif action_name == 'sprinting' then
        attempt_sprint = not result
        if not attempt_sprint then
            sprint_press = false
        end

        if attempt_sprint_dodge then
            return false
        end

        return attempt_sprint and not is_action_blocking_sprint and (sprint_press or _can_sprint_with_next_action())
    elseif action_name == 'move_forward' then
        move_forward = result
    elseif action_name == 'move_backward' then
        move_backward = result
    elseif action_name == 'move_left' then
        move_left = result
    elseif action_name == 'move_right' then
        move_right = result
    elseif action_name == 'jump' then
        if current_state_name == 'dodging' then
            return false
        elseif (current_state_name == 'walking' or current_state_name == 'sprinting') and not _can_jump() then
            return false
        end
    elseif action_name == 'jump_held' then
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
            attempt_dodge_slide = attempt_dodge_slide or result
        elseif _is_sprint_jumping() and current_state_name == 'sprinting' then
            if _is_dodge_direction() then
                attempt_sprint_dodge = attempt_sprint_dodge or result or dodge_hold
            else
                attempt_sprint_slide = attempt_sprint_slide or result or dodge_hold
            end
        elseif current_state_name == 'walking' then
            if attempt_sprint_dodge then
                if _is_dodge_direction() then
                    return true
                end

                attempt_sprint_dodge = false
            end

            if dodge_hold and _can_keep_dodging() then
                return true
            end
        end
    elseif action_name == 'crouching' then
        if current_state_name == 'sliding' and dodge_hold and (hold_to_crouch or sliding_speed > 0.5) then
            if previous_state_name == 'dodging' or previous_state_name == 'sprinting' then
                return true
            end
        end

        if hold_to_crouch then
            if
                current_state_name == 'dodging'
                and (attempt_dodge_slide or _can_hold_dodge_slide())
                and _can_dodge_slide()
            then
                return true
            end

            if _is_sprint_jumping() and attempt_sprint_slide then
                return true
            end
        end
    elseif action_name == 'crouch' and not hold_to_crouch then
        local movement_state = movement_components.movement_state
        if movement_state then
            local is_crouching = movement_state.is_crouching

            if
                current_state_name == 'dodging'
                and (attempt_dodge_slide or _can_hold_dodge_slide())
                and not is_crouching
                and _can_dodge_slide()
            then
                return true
            end

            if _is_sprint_jumping() and attempt_sprint_slide and not is_crouching then
                return true
            end
        end
    end

    return result
end

local function _on_state_change()
    if current_state_name == 'sprinting' then
        sprint_press = false
    end

    if not _is_sprint_jumping() then
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

-- State transitions reset input intent so a held key cannot leak between states.
mod:hook_safe(CLASS.CharacterStateMachine, '_change_state', function(self, unit, dt, t, next_state)
    local unit_data_extension = self._unit_data_extension
    if not mod_enabled or not _is_local_player(unit_data_extension and unit_data_extension._player) then
        return
    end

    previous_state_name = current_state_name
    current_state_name = next_state
    _on_state_change()
end)

mod:hook_safe(CLASS.CharacterStateMachine, 'server_correction_occurred', function(self, unit)
    local unit_data_extension = self._unit_data_extension
    if not mod_enabled or not _is_local_player(unit_data_extension and unit_data_extension._player) then
        return
    end

    local state_name = self:current_state_name()
    if state_name ~= current_state_name then
        previous_state_name = current_state_name
        current_state_name = state_name
        _on_state_change()
    end
end)

mod:hook_safe(
    CLASS.PlayerCharacterStateSliding,
    '_check_transition',
    function(self, unit, dt, t, next_state_params, input_source, commit_period_over, max_mass_hit, current_speed)
        if mod_enabled and _is_local_player(self._player) then
            sliding_speed = current_speed
        end
    end
)

mod:hook_safe(
    CLASS.ActionHandler,
    'start_action',
    function(self, id, action_objects, action_name, action_params, action_settings)
        local unit_data_extension = self._unit_data_extension
        if not mod_enabled or not _is_local_player(unit_data_extension and unit_data_extension._player) then
            return
        end

        local allowed_during_sprint = ActionAvailability.available_in_sprint(action_settings, self._buff_extension)
        local requires_press_to_interrupt = Sprint.requires_press_to_interrupt(action_settings)
        local no_interruption_for_sprint = Sprint.no_interruption_for_sprint(action_settings)
        local can_do_while_sprinting = allowed_during_sprint
            or requires_press_to_interrupt
            or no_interruption_for_sprint

        if not can_do_while_sprinting then
            is_action_blocking_sprint = true
        end

        local registered_component = self._registered_components and self._registered_components[id]
        local running_action = registered_component and registered_component.running_action
        local weapon_template = running_action and running_action._weapon_template
        local allowed_inputs = weapon_template and weapon_template.allowed_inputs_in_sprint or ALLOWED_INPUTS_IN_SPRINT
        local start_input = action_settings and action_settings.start_input
        local is_allowed_input = allowed_inputs[start_input]

        if not allowed_during_sprint and not is_allowed_input or _should_abort_sprint(action_settings) then
            attempt_sprint = false
        end
    end
)

mod:hook_safe(CLASS.ActionHandler, 'server_correction_occurred', function(self, id)
    local unit_data_extension = self._unit_data_extension
    if not mod_enabled or not _is_local_player(unit_data_extension and unit_data_extension._player) then
        return
    end

    local handler = self._registered_components and self._registered_components[id]
    local action_component = handler and handler.component
    if action_component and action_component.current_action_name == 'none' then
        is_action_blocking_sprint = false
    end
end)

mod:hook_safe(CLASS.ActionHandler, '_finish_action', function(self, handler_data)
    local unit_data_extension = self._unit_data_extension
    if mod_enabled and _is_local_player(unit_data_extension and unit_data_extension._player) then
        is_action_blocking_sprint = false
    end
end)

mod:hook_safe(CLASS.EventManager, 'trigger', function(self, event_name)
    if mod_enabled and event_name == 'event_on_input_settings_changed' then
        _init_game_settings()
        _enable_hold_to_sprint()
    end
end)

mod:hook_require('scripts/settings/input/default_ingame_input_settings', function(instance)
    instance.settings.dodge_hold = {
        key_alias = 'dodge',
        type = 'held',
    }
end)

mod:hook_safe(CLASS.PlayerUnitBuffExtension, 'init', function(self)
    if _is_local_player(self._player) then
        player_buff_extension = self
    end
end)

mod:hook_safe(CLASS.PlayerUnitBuffExtension, 'delete', function(self)
    if _is_local_player(self._player) then
        player_buff_extension = nil
    end
end)

mod:hook_safe(CLASS.PlayerUnitWeaponExtension, 'init', function(self)
    if _is_local_player(self._player) then
        player_weapon_extension = self
    end
end)

mod:hook_safe(CLASS.PlayerUnitWeaponExtension, 'delete', function(self)
    if _is_local_player(self._player) then
        player_weapon_extension = nil
    end
end)

mod:hook_safe(CLASS.PlayerUnitActionInputExtension, 'init', function(self, _, unit)
    local player_manager = Managers and Managers.player
    local player = player_manager and player_manager:local_player_safe(1)

    if player and player.player_unit == unit then
        player_action_input_extension = self
    end
end)

mod:hook_safe(CLASS.PlayerUnitActionInputExtension, 'delete', function(self)
    if self == player_action_input_extension then
        player_action_input_extension = nil
    end
end)

mod:hook_safe(CLASS.PlayerUnitDataExtension, 'init', function(self)
    if _is_local_player(self._player) then
        _init_movement_components(self)
    end
end)

mod:hook_safe(CLASS.PlayerUnitDataExtension, 'destroy', function(self)
    if _is_local_player(self._player) then
        movement_components = {}
    end
end)

mod:hook(CLASS.InputService, '_get', _input_service_hook)
mod:hook(CLASS.InputService, '_get_simulate', _input_service_hook)

mod.on_enabled = function()
    mod_enabled = true
    _init_game_settings()
    _enable_hold_to_sprint()
end

mod.on_disabled = function()
    mod_enabled = false
    _restore_hold_to_sprint()
    _reset_state()
end

mod.on_all_mods_loaded = function()
    _init_game_settings()
    _enable_hold_to_sprint()
end

mod.on_game_state_changed = function(status, state_name)
    if state_name ~= 'GameplayStateRun' then
        return
    end

    if status == 'enter' then
        _init_game_settings()
        _enable_hold_to_sprint()
    elseif status == 'exit' then
        _reset_state()
    end
end
