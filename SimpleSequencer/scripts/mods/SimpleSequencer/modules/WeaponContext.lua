local WeaponContext = {}

-- The calibration data below is adapted from Skitarius (GPL-3.0-only).
-- See SimpleSequencer/NOTICE and SimpleSequencer/LICENSE.
local CHAIN_TIME_OVERRIDES = {
    ogryn_powermaul_slabshield_p1_m1 = {
        action_right_heavy = { [0.35] = 0.5, [0.4] = 0.45 },
    },
    ogryn_club_p2_m3 = {
        action_right_heavy = { [0.5] = 0.55 },
    },
    combataxe_p2_m3 = {
        action_left_heavy = { [0.25] = 0.3 },
    },
    powermaul_2h_p1_m1 = {
        action_right_heavy = { [0.35] = 0.45 },
    },
    combataxe_p2_m1 = {
        action_left_heavy = { [0.25] = 0.3 },
    },
    combatknife_p1_m1 = {
        action_left_heavy = { [0.3] = 0.35 },
    },
    combatknife_p1_m2 = {
        action_left_heavy = { [0.3] = 0.35 },
    },
}

local INVERTED_TIME_SCALE_KINDS = {
    overload_charge = true,
    overload_charge_position_finder = true,
    overload_charge_target_finder = true,
    overload_charge_weapon_special = true,
    overload_target_finder = true,
}

function WeaponContext.read()
    local player_manager = Managers and Managers.player
    local player = player_manager and player_manager:local_player_safe(1)
    local unit = player and player.player_unit
    local extension = unit and ScriptUnit.has_extension(unit, 'weapon_system')
    local inventory = extension and extension._inventory_component
    local weapon
    if extension and inventory and extension._wielded_weapon then
        local ok, wielded_weapon = pcall(extension._wielded_weapon, extension, inventory, extension._weapons)
        weapon = ok and wielded_weapon or nil
    end
    local template = weapon and weapon.weapon_template
    local name = template and template.name
    local slot = inventory and inventory.wielded_slot
    local kind

    if slot == 'slot_primary' then
        kind = 'MELEE'
    elseif slot == 'slot_secondary' or slot == 'slot_grenade_ability' then
        local action_name, _, action_settings = WeaponContext.action({ extension = extension })
        local primary_attack = template and template.displayed_attacks and template.displayed_attacks.primary
        local primary_is_melee = primary_attack and primary_attack.type == 'melee'
        local is_aiming = action_settings and action_settings.start_input == 'brace'

        if not is_aiming and action_name then
            is_aiming = string.find(action_name, 'zoom', 1, true) ~= nil
                or string.find(action_name, 'brace', 1, true) ~= nil
                or string.find(action_name, 'aim', 1, true) ~= nil
        end

        kind = primary_is_melee and not is_aiming and 'MELEE' or 'RANGED'
    elseif template and template.keywords then
        for _, keyword in ipairs(template.keywords) do
            if keyword == 'melee' then
                kind = 'MELEE'
                break
            elseif keyword == 'ranged' then
                kind = 'RANGED'
                break
            end
        end
    end

    return {
        unit = unit,
        extension = extension,
        inventory = inventory,
        weapon = weapon,
        template = template,
        name = name or 'none',
        kind = kind or 'none',
    }
end

function WeaponContext.equipped(kind)
    local context = WeaponContext.read()
    local extension = context.extension
    local weapons = extension and extension._weapons
    local slot = kind == 'MELEE' and 'slot_primary' or kind == 'RANGED' and 'slot_secondary'
    local weapon = slot and weapons and weapons[slot]
    local template = weapon and weapon.weapon_template

    return template and template.name or nil
end

function WeaponContext.action(context)
    context = context or WeaponContext.read()

    local extension = context.extension

    if not extension then
        return 'idle', nil, nil
    end

    local settings

    if extension.running_action_settings then
        local ok, result = pcall(extension.running_action_settings, extension)
        settings = ok and result or nil
    end

    if not settings then
        local handler = extension._action_handler
        local handler_data = handler and handler._registered_components and handler._registered_components.weapon_action
        local running_action = handler_data and handler_data.running_action

        if running_action then
            local ok, result = pcall(running_action.action_settings, running_action)
            settings = ok and result or nil
        end
    end

    local component = extension._weapon_action_component
    local action_name = component and component.current_action_name

    if not action_name or action_name == 'none' then
        return 'idle', nil, settings
    end

    local start_t = component and component.start_t
    local template = context.weapon and context.weapon.weapon_template
    local template_settings = template and template.actions and template.actions[action_name]

    if template_settings and (not settings or not settings.allowed_chain_actions) then
        settings = template_settings
    end

    return action_name, start_t, settings
end

local function _chain_action_at(chain_actions, index)
    if chain_actions[1] then
        return chain_actions[index]
    end
    return index == 1 and chain_actions or nil
end

local function _scaled_chain_time(value, time_scale, action_kind)
    if not value then
        return nil
    end
    if time_scale < 1 and INVERTED_TIME_SCALE_KINDS[action_kind] then
        return value * time_scale
    end
    return value / time_scale
end

local function _target_action_is_valid(context, chain_action, current_time, time_in_action)
    local target_name = chain_action.action_name
    local template = context and context.template
    local target_settings = target_name and template and template.actions and template.actions[target_name]
    local condition = target_settings and target_settings.action_condition_func
    local handler = context and context.extension and context.extension._action_handler
    local condition_params = handler and handler._action_context

    if not condition or not condition_params then
        return true
    end

    local ok, valid = pcall(condition, target_settings, condition_params, nil, current_time, time_in_action)
    return not ok or valid ~= false
end

local function _running_action_state(context, current_time, time_in_action)
    local handler = context and context.extension and context.extension._action_handler
    local handler_data = handler and handler._registered_components and handler._registered_components.weapon_action
    local running_action = handler_data and handler_data.running_action

    if not running_action or not running_action.running_action_state then
        return nil
    end

    local ok, state = pcall(running_action.running_action_state, running_action, current_time, time_in_action)
    return ok and state or nil
end

function WeaponContext.can_chain(settings, start_t, chain_name, weapon_name, context)
    local allowed_chain_actions = settings and settings.allowed_chain_actions
    local chain_actions = allowed_chain_actions and allowed_chain_actions[chain_name]
    local current_kind = settings and settings.kind

    if not chain_actions and chain_name == 'heavy_attack' then
        chain_actions = allowed_chain_actions
            and (allowed_chain_actions.special_action_heavy or allowed_chain_actions.heavy_attack_special)
    end

    if not chain_actions or not start_t or not Managers or not Managers.time then
        return false
    end

    local current_time = Managers.time:time('gameplay')
    local time_in_action = current_time and current_time - start_t
    local action_component = context and context.extension and context.extension._weapon_action_component
    local time_scale = action_component and action_component.time_scale or 1

    if not current_time or not time_in_action or time_scale <= 0 then
        return false
    end

    for index = 1, chain_actions[1] and #chain_actions or 1 do
        local chain_action = _chain_action_at(chain_actions, index)
        local chain_time = chain_action and chain_action.chain_time
        local chain_until = chain_action and chain_action.chain_until
        local weapon_overrides = CHAIN_TIME_OVERRIDES[weapon_name]
        local action_override = weapon_overrides and chain_action and weapon_overrides[chain_action.action_name]

        chain_time = action_override and action_override[chain_time] or chain_time

        local scaled_chain_time = _scaled_chain_time(chain_time, time_scale, current_kind)
        local scaled_chain_until = _scaled_chain_time(chain_until, time_scale, current_kind)
        local chain_ready = not chain_time
            or scaled_chain_time <= time_in_action
            or scaled_chain_until and time_in_action <= scaled_chain_until

        local running_action_state_requirement = chain_action and chain_action.running_action_state_requirement
        local running_action_state = running_action_state_requirement
            and _running_action_state(context, current_time, time_in_action)
        local state_ready = not running_action_state_requirement
            or running_action_state and running_action_state_requirement[running_action_state]

        if
            chain_action
            and chain_ready
            and state_ready
            and _target_action_is_valid(context, chain_action, current_time, time_in_action)
        then
            return true
        end
    end

    return false
end

function WeaponContext.charge_state(context)
    local extension = context and context.extension
    local charge_component = extension and extension._action_module_charge_component
    local max_charge = charge_component and charge_component.max_charge

    return charge_component and charge_component.charge_level or 0,
        max_charge and max_charge > 0 and max_charge or nil,
        charge_component and charge_component.charge_start_time or nil
end

return WeaponContext
