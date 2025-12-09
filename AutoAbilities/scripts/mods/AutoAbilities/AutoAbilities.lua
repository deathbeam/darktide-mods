local mod = get_mod('AutoAbilities')

local PlayerUnitVisualLoadout = require('scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout')

-- ┌────────────────────────────┐
-- │       STATE & CONFIG       │
-- └────────────────────────────┘

local ACTION_STAGES = {
    NONE = 0,
    SWITCH_TO = 1,
    WAITING_FOR_USE = 2,
}

local CHECK_INTERVAL = 0.5
local DEPLOY_TIMEOUT = 5.0
local SLOT_POCKETABLE = 'slot_pocketable'
local SLOT_POCKETABLE_SMALL = 'slot_pocketable_small'
local SLOT_GRENADE = 'slot_grenade_ability'

local current_stage = ACTION_STAGES.NONE
local target_slot = nil
local stage_start_time = 0
local current_wield_slot = nil
local last_check_time = 0

local chemical_autostim_enabled = false
local quick_deploy_enabled = false
local auto_blitz_enabled = false

local function _get_player_unit()
    local player = Managers.player and Managers.player:local_player_safe(1)
    return player and player.player_unit
end

local function _get_gameplay_time()
    return Managers.time and Managers.time:has_timer('gameplay') and Managers.time:time('gameplay') or 0
end

local function _get_current_wielded_slot()
    local player_unit = _get_player_unit()
    if not player_unit then
        return nil
    end

    local unit_data_ext = ScriptUnit.has_extension(player_unit, 'unit_data_system')
    if not unit_data_ext then
        return nil
    end

    local inventory_component = unit_data_ext:read_component('inventory')
    if not inventory_component then
        return nil
    end

    return inventory_component.wielded_slot
end

local function _is_weapon_switching()
    local player_unit = _get_player_unit()
    if not player_unit then
        return false
    end

    local unit_data_ext = ScriptUnit.has_extension(player_unit, 'unit_data_system')
    if not unit_data_ext then
        return false
    end

    local weapon_action_comp = unit_data_ext:read_component('weapon_action')
    if not weapon_action_comp then
        return false
    end

    local current_action = weapon_action_comp.current_action_name
    return current_action == 'action_wield'
        or current_action == 'action_unwield'
        or current_action == 'action_unwield_to_previous'
        or current_action == 'action_unwield_to_specific'
end

local function _is_weapon_template_valid(slot_name)
    if not slot_name then
        return false
    end

    local player_unit = _get_player_unit()
    if not player_unit then
        return false
    end

    local visual_loadout_ext = ScriptUnit.has_extension(player_unit, 'visual_loadout_system')
    if not visual_loadout_ext then
        return false
    end

    local success, weapon_template = pcall(function()
        return visual_loadout_ext:weapon_template_from_slot(slot_name)
    end)

    return success and weapon_template ~= nil
end

local function _can_use_ability(ability_name)
    local player_unit = _get_player_unit()
    if not player_unit then
        return false
    end

    local ability_ext = ScriptUnit.has_extension(player_unit, 'ability_system')
    if not ability_ext then
        return false
    end

    return ability_ext:can_use_ability(ability_name or 'pocketable_ability')
end

local function _reset_state()
    current_stage = ACTION_STAGES.NONE
    target_slot = nil
    stage_start_time = 0
end

local function _has_chemical_dependency()
    local player_unit = _get_player_unit()
    if not player_unit then
        return false
    end

    local buff_ext = ScriptUnit.has_extension(player_unit, 'buff_system')
    if not buff_ext then
        return false
    end

    return buff_ext:has_buff_using_buff_template('broker_keystone_chemical_dependency')
end

local function _get_chem_dep_stacks()
    local player_unit = _get_player_unit()
    if not player_unit then
        return 0, 3
    end

    local buff_ext = ScriptUnit.has_extension(player_unit, 'buff_system')
    if not buff_ext or not buff_ext._stacking_buffs then
        return 0, 3
    end

    local buff_instance = buff_ext._stacking_buffs['broker_keystone_chemical_dependency_stack']
    if not buff_instance then
        return 0, 3
    end

    return buff_instance:stack_count(), buff_instance:max_stacks() or 3
end

local function _has_broker_stim()
    local player_unit = _get_player_unit()
    if not player_unit then
        return false
    end

    local visual_loadout_ext = ScriptUnit.has_extension(player_unit, 'visual_loadout_system')
    if not visual_loadout_ext then
        return false
    end

    return PlayerUnitVisualLoadout.has_weapon_keyword_from_slot(
        visual_loadout_ext,
        SLOT_POCKETABLE_SMALL,
        'pocketable_broker_syringe'
    )
end

local function _start_chemical_autostim()
    if not _has_chemical_dependency() then
        return false
    end
    local current_stacks, max_stacks = _get_chem_dep_stacks()
    if current_stacks >= max_stacks then
        return false
    end
    if not _has_broker_stim() then
        return false
    end
    if not _can_use_ability('pocketable_ability') then
        return false
    end
    if _is_weapon_switching() then
        return false
    end
    if not current_wield_slot then
        current_wield_slot = _get_current_wielded_slot()
    end
    if not _is_weapon_template_valid(current_wield_slot) then
        return false
    end

    if current_wield_slot == SLOT_POCKETABLE_SMALL then
        current_stage = ACTION_STAGES.WAITING_FOR_USE
    else
        current_stage = ACTION_STAGES.SWITCH_TO
    end

    target_slot = SLOT_POCKETABLE_SMALL
    stage_start_time = _get_gameplay_time()
    return true
end

local function _is_quick_throw_grenade()
    local player_unit = _get_player_unit()
    if not player_unit then
        return false
    end
    local weapon_extension = ScriptUnit.has_extension(player_unit, 'weapon_system')
    local weapons = weapon_extension and weapon_extension._weapons
    local weapon = weapons and weapons.slot_grenade_ability
    local weapon_template = weapon and weapon.weapon_template
    if not weapon_template then
        return false
    end
    local grenade = weapon_template.name
    if grenade == 'zealot_throwing_knives' or grenade == 'quick_flash_grenade' then
        return true
    end
    return false
end

mod.update = function(dt)
    local game_mode_manager = Managers.state and Managers.state.game_mode
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

    -- Deploy timeout check
    if target_slot and current_stage ~= ACTION_STAGES.NONE then
        if current_time - stage_start_time > DEPLOY_TIMEOUT then
            _reset_state()
        end
    end

    -- Chemical AutoStim check
    if chemical_autostim_enabled and current_stage == ACTION_STAGES.NONE then
        if stage_start_time > 0 then
            local time_since_last = current_time - stage_start_time
            if time_since_last < 1.0 then
                return
            end
        end

        _start_chemical_autostim()
    end
end

local _input_action_hook = function(func, self, action_name)
    -- Switch to target slot
    if current_stage == ACTION_STAGES.SWITCH_TO and target_slot then
        if target_slot == SLOT_POCKETABLE_SMALL and action_name == 'wield_4' then
            return true
        elseif target_slot == SLOT_POCKETABLE and (action_name == 'wield_3' or action_name == 'wield_3_gamepad') then
            return true
        end
    end

    -- Auto use when wielded
    if current_stage == ACTION_STAGES.WAITING_FOR_USE and action_name == 'action_one_pressed' then
        _reset_state()
        return true
    end

    return func(self, action_name)
end
mod:hook(CLASS.InputService, '_get', _input_action_hook)
mod:hook(CLASS.InputService, '_get_simulate', _input_action_hook)

mod:hook(CLASS.PlayerUnitWeaponExtension, 'on_slot_wielded', function(func, self, slot_name, t, skip_wield_action)
    if _get_player_unit() == self._unit then
        current_wield_slot = slot_name
        local switch_to_waiting = false

        -- Proceed to use after switching to target slot
        if current_stage == ACTION_STAGES.SWITCH_TO and slot_name == target_slot then
            switch_to_waiting = true
        end

        -- Start auto throw for grenades if enabled
        if auto_blitz_enabled and slot_name == SLOT_GRENADE and not _is_quick_throw_grenade() then
            switch_to_waiting = true
            skip_wield_action = true
        end

        -- Start auto use for pocketables if enabled
        if
            quick_deploy_enabled
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
        end

        -- Reset if we switch away from what we're trying to use (check AFTER setting up new actions)
        if current_stage == ACTION_STAGES.WAITING_FOR_USE and slot_name ~= target_slot then
            _reset_state()
        end
    end

    return func(self, slot_name, t, skip_wield_action)
end)

mod:hook_safe(
    CLASS.ActionHandler,
    'start_action',
    function(self, id, action_objects, action_name, action_params, action_settings, used_input)
        if _get_player_unit() == self._unit then
            if
                current_stage == ACTION_STAGES.WAITING_FOR_USE
                and (
                    action_name == 'action_use_self'
                    or action_name == 'action_place_complete'
                    or action_name == 'action_throw_grenade'
                )
            then
                _reset_state()
            end
        end
    end
)

mod.on_setting_changed = function(id)
    if id == 'auto_blitz_enabled' then
        auto_blitz_enabled = mod:get('auto_blitz_enabled')
    elseif id == 'quick_deploy_enabled' then
        quick_deploy_enabled = mod:get('quick_deploy_enabled')
    elseif id == 'chemical_autostim_enabled' then
        chemical_autostim_enabled = mod:get('chemical_autostim_enabled')
    end
end

mod.on_all_mods_loaded = function()
    auto_blitz_enabled = mod:get('auto_blitz_enabled')
    quick_deploy_enabled = mod:get('quick_deploy_enabled')
    chemical_autostim_enabled = mod:get('chemical_autostim_enabled')
end

mod.on_game_state_changed = function(status, state_name)
    if state_name == 'StateLoading' or state_name == 'StateGameplay' then
        last_check_time = 0
        current_wield_slot = nil
        _reset_state()
    end
end
