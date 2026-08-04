local mod = get_mod('SimpleActivate')

local ACTION_STAGES = {
    NONE = 0,
    WAITING_FOR_USE = 1,
}

local CHECK_INTERVAL = 0.5
local DEPLOY_TIMEOUT = 5.0

local SLOT_POCKETABLE = 'slot_pocketable'
local SLOT_POCKETABLE_SMALL = 'slot_pocketable_small'
local SLOT_GRENADE = 'slot_grenade_ability'

local current_stage = ACTION_STAGES.NONE
local target_slot
local stage_start_time = 0
local last_check_time = 0
local mod_enabled = false

local function _get_player_unit()
    local player_manager = Managers and Managers.player
    local player = player_manager and player_manager:local_player_safe(1)

    return player and player.player_unit
end

local function _get_gameplay_time()
    local time_manager = Managers and Managers.time

    return time_manager and time_manager:has_timer('gameplay') and time_manager:time('gameplay') or 0
end

local function _reset_state()
    current_stage = ACTION_STAGES.NONE
    target_slot = nil
    stage_start_time = 0
end

local function _grenade_template()
    local player_unit = _get_player_unit()
    local has_extension = ScriptUnit and ScriptUnit.has_extension

    if not player_unit or not has_extension then
        return nil
    end

    local ok, weapon_extension = pcall(has_extension, player_unit, 'weapon_system')
    local weapons = ok and weapon_extension and weapon_extension._weapons
    local weapon = weapons and weapons[SLOT_GRENADE]

    return weapon and weapon.weapon_template
end

local function _is_quick_throw_grenade(weapon_template)
    local grenade_name = weapon_template and weapon_template.name

    return grenade_name == 'zealot_throwing_knives' or grenade_name == 'quick_flash_grenade'
end

local function _sequence_contains_primary_input(sequence)
    for _, step in ipairs(sequence or {}) do
        if step.input == 'action_one_pressed' then
            return true
        end

        for _, nested_step in ipairs(step.inputs or {}) do
            if nested_step.input == 'action_one_pressed' then
                return true
            end
        end
    end

    return false
end

local function _is_auto_throw_eligible(weapon_template)
    for _, input_definition in pairs(weapon_template and weapon_template.action_inputs or {}) do
        if _sequence_contains_primary_input(input_definition.input_sequence) then
            return true
        end
    end

    return false
end

mod.update = function()
    local game_mode_manager = Managers and Managers.state and Managers.state.game_mode
    local game_mode_name = game_mode_manager and game_mode_manager:game_mode_name()

    if not game_mode_name or game_mode_name == 'hub' then
        _reset_state()

        return
    end

    local current_time = _get_gameplay_time()
    if current_time - last_check_time < CHECK_INTERVAL then
        return
    end

    last_check_time = current_time

    if target_slot and current_stage ~= ACTION_STAGES.NONE and current_time - stage_start_time > DEPLOY_TIMEOUT then
        _reset_state()
    end
end

local function _input_action_hook(func, self, action_name)
    if not mod_enabled then
        return func(self, action_name)
    end

    if current_stage == ACTION_STAGES.WAITING_FOR_USE and action_name == 'action_one_pressed' then
        _reset_state()

        return true
    end

    return func(self, action_name)
end

-- Hooks
mod:hook(CLASS.InputService, '_get', _input_action_hook)
mod:hook(CLASS.InputService, '_get_simulate', _input_action_hook)

mod:hook(CLASS.PlayerUnitWeaponExtension, 'on_slot_wielded', function(func, self, slot_name, t, skip_wield_action)
    if mod_enabled and _get_player_unit() == self._unit then
        local switch_to_waiting = false
        local weapon_template = _grenade_template()

        if
            slot_name == SLOT_GRENADE
            and not _is_quick_throw_grenade(weapon_template)
            and _is_auto_throw_eligible(weapon_template)
        then
            switch_to_waiting = true
            skip_wield_action = true
        end

        if
            (slot_name == SLOT_POCKETABLE or slot_name == SLOT_POCKETABLE_SMALL)
            and current_stage == ACTION_STAGES.NONE
        then
            switch_to_waiting = true
            skip_wield_action = true
        end

        if switch_to_waiting then
            current_stage = ACTION_STAGES.WAITING_FOR_USE
            target_slot = slot_name
            stage_start_time = _get_gameplay_time()
        end

        if current_stage == ACTION_STAGES.WAITING_FOR_USE and slot_name ~= target_slot then
            _reset_state()
        end
    end

    return func(self, slot_name, t, skip_wield_action)
end)

mod:hook_safe(CLASS.ActionHandler, 'start_action', function(self, id, action_objects, action_name)
    if
        mod_enabled
        and _get_player_unit() == self._unit
        and current_stage == ACTION_STAGES.WAITING_FOR_USE
        and (
            action_name == 'action_use_self'
            or action_name == 'action_place_complete'
            or action_name == 'action_throw_grenade'
        )
    then
        _reset_state()
    end
end)

-- Lifecycle
mod.on_enabled = function()
    mod_enabled = true
    _reset_state()
end

mod.on_disabled = function()
    mod_enabled = false
    _reset_state()
end

mod.on_game_state_changed = function(status, state_name)
    if state_name == 'StateLoading' or state_name == 'StateGameplay' then
        last_check_time = 0
        _reset_state()
    end
end
