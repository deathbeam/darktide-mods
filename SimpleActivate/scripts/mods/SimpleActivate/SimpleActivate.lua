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

local ACTIVATION_INPUT_NAMES = {
    grenade_ability_pressed = true,
    wield_3 = true,
    wield_3_gamepad = true,
    wield_4 = true,
    wield_scroll_down = true,
    wield_scroll_up = true,
}

local ACTIONS_THAT_END_WAITING = {
    action_give = true,
    action_place_complete = true,
    action_throw_grenade = true,
    action_use_ally = true,
    action_use_self = true,
}

local SETTING_AUTO_USE_CRATE = 'auto_use_crate'
local SETTING_AUTO_USE_STIMM = 'auto_use_stimm'
local SETTING_AUTO_USE_BLITZ = 'auto_use_blitz'

local current_stage = ACTION_STAGES.NONE
local target_slot
local stage_start_time = 0
local last_check_time = 0
local mod_enabled = false
local activation_input_service
local activation_input_name
local activation_input_was_held = false
local activation_requested = false
local last_wield_input_service
local last_wield_input_name

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
    activation_input_service = nil
    activation_input_name = nil
    activation_input_was_held = false
    activation_requested = false
    last_wield_input_service = nil
    last_wield_input_name = nil
end

-- Wield inputs expose press events only, so release detection reads the bound device.
local function _action_is_held(input_service, action_name)
    if not input_service or not action_name then
        return false
    end

    local ok, alias = pcall(input_service.get_alias_key, input_service, action_name)
    if not ok or not alias then
        return false
    end

    local keys_ok, keys = pcall(input_service.get_keys_from_alias, input_service, alias)
    if not keys_ok then
        return false
    end

    local devices = input_service:devices() or {}

    for _, key_name in ipairs(keys or {}) do
        for _, device in pairs(devices) do
            local index_ok, index = pcall(device.button_index, device, key_name)
            if index_ok and index then
                local held_ok, held = pcall(device.held, device, index)
                if held_ok and held then
                    return true
                end
            end
        end
    end

    return false
end

local function _configure_activation_input()
    if last_wield_input_service and ACTIVATION_INPUT_NAMES[last_wield_input_name] then
        activation_input_service = last_wield_input_service
        activation_input_name = last_wield_input_name
        activation_input_was_held = true
    end

    last_wield_input_service = nil
    last_wield_input_name = nil
end

local function _request_activation()
    if current_stage == ACTION_STAGES.WAITING_FOR_USE then
        activation_requested = true
    end
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

local function _auto_use_enabled(setting_id)
    return mod:get(setting_id) ~= false
end

local function _auto_use_pocketable_enabled(slot_name)
    if slot_name == SLOT_POCKETABLE then
        return _auto_use_enabled(SETTING_AUTO_USE_CRATE)
    end

    return _auto_use_enabled(SETTING_AUTO_USE_STIMM)
end

mod.update = function()
    local game_mode_manager = Managers and Managers.state and Managers.state.game_mode
    local game_mode_name = game_mode_manager and game_mode_manager:game_mode_name()

    if not game_mode_name or game_mode_name == 'hub' then
        _reset_state()

        return
    end

    if activation_input_service and not activation_requested then
        local input_is_held = _action_is_held(activation_input_service, activation_input_name)

        if activation_input_was_held and not input_is_held then
            _request_activation()
        end

        activation_input_was_held = input_is_held
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

    local value = func(self, action_name)
    if value and ACTIVATION_INPUT_NAMES[action_name] then
        last_wield_input_service = self
        last_wield_input_name = action_name
    end

    if action_name == 'action_one_pressed' and activation_requested and self == activation_input_service then
        activation_requested = false

        return true
    end

    return value
end

-- Hooks
mod:hook(CLASS.InputService, '_get', _input_action_hook)
mod:hook(CLASS.InputService, '_get_simulate', _input_action_hook)

mod:hook(CLASS.PlayerUnitWeaponExtension, 'on_slot_wielded', function(func, self, slot_name, t, skip_wield_action)
    if mod_enabled and _get_player_unit() == self._unit then
        local switch_to_waiting = false
        local weapon_template = _grenade_template()

        if
            _auto_use_enabled(SETTING_AUTO_USE_BLITZ)
            and slot_name == SLOT_GRENADE
            and not _is_quick_throw_grenade(weapon_template)
            and _is_auto_throw_eligible(weapon_template)
        then
            switch_to_waiting = true
            skip_wield_action = true
        end

        if
            _auto_use_pocketable_enabled(slot_name)
            and (slot_name == SLOT_POCKETABLE or slot_name == SLOT_POCKETABLE_SMALL)
            and current_stage == ACTION_STAGES.NONE
        then
            switch_to_waiting = true
            skip_wield_action = true
        end

        if switch_to_waiting then
            current_stage = ACTION_STAGES.WAITING_FOR_USE
            target_slot = slot_name
            stage_start_time = _get_gameplay_time()
            _configure_activation_input()
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
        and ACTIONS_THAT_END_WAITING[action_name]
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
