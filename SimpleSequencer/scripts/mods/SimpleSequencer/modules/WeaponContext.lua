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

local function _chain_action_at(chain_actions, index)
    if chain_actions[1] then
        return chain_actions[index]
    end

    return index == 1 and chain_actions or nil
end

local function _chain_actions_for_input(settings, chain_name)
    local allowed_chain_actions = settings and settings.allowed_chain_actions
    local resolved_chain_name = chain_name
    local chain_actions = allowed_chain_actions and allowed_chain_actions[resolved_chain_name]

    if not chain_actions and chain_name == 'heavy_attack' and allowed_chain_actions then
        if allowed_chain_actions.special_action_heavy then
            resolved_chain_name = 'special_action_heavy'
        elseif allowed_chain_actions.heavy_attack_special then
            resolved_chain_name = 'heavy_attack_special'
        end

        chain_actions = allowed_chain_actions[resolved_chain_name]
    end

    return resolved_chain_name, chain_actions
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

local function _game_chain_ready(context, chain_name, current_time)
    local extension = context and context.extension
    local validator = extension and extension.action_input_is_currently_valid

    if not validator then
        return false
    end

    local ok, valid = pcall(validator, extension, 'weapon_action', chain_name, nil, current_time)

    return ok and valid == true
end

local function _calibration_allows(settings, start_t, chain_actions, context, current_time)
    local weapon_overrides = context and CHAIN_TIME_OVERRIDES[context.name]

    if not weapon_overrides then
        return true
    end

    local action_component = context and context.extension and context.extension._weapon_action_component
    local time_scale = action_component and action_component.time_scale or 1

    if time_scale <= 0 then
        return false
    end

    local time_in_action = current_time - start_t
    local action_kind = settings and settings.kind
    local has_override = false

    for index = 1, chain_actions[1] and #chain_actions or 1 do
        local chain_action = _chain_action_at(chain_actions, index)
        local action_override = chain_action and weapon_overrides[chain_action.action_name]
        local corrected_chain_time = action_override and action_override[chain_action.chain_time]

        if corrected_chain_time then
            has_override = true

            local chain_time = _scaled_chain_time(corrected_chain_time, time_scale, action_kind)
            local chain_until = _scaled_chain_time(chain_action.chain_until, time_scale, action_kind)

            if chain_time <= time_in_action or chain_until and time_in_action <= chain_until then
                return true
            end
        end
    end

    return not has_override
end

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
        extension = extension,
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

function WeaponContext.can_chain(settings, start_t, chain_name, context)
    local resolved_chain_name, chain_actions = _chain_actions_for_input(settings, chain_name)

    if not chain_actions or not start_t then
        return false
    end

    local extension = context and context.extension
    local current_time = extension and extension._last_fixed_t
        or Managers and Managers.time and Managers.time:time('gameplay')

    if not current_time or not _game_chain_ready(context, resolved_chain_name, current_time) then
        return false
    end

    return _calibration_allows(settings, start_t, chain_actions, context, current_time)
end

function WeaponContext.charge_state(context)
    local extension = context and context.extension
    local charge_component = extension and extension._action_module_charge_component
    local max_charge = charge_component and charge_component.max_charge

    return charge_component and charge_component.charge_level or 0,
        max_charge and max_charge > 0 and max_charge or nil,
        charge_component and charge_component.charge_start_time or nil
end

function WeaponContext.can_buffer_input(settings, start_t, chain_name, context)
    local template = context and context.template
    local input = template and template.action_inputs and template.action_inputs[chain_name]
    local buffer_time = input and input.buffer_time
    local resolved_chain_name, chain_actions = _chain_actions_for_input(settings, chain_name)
    local extension = context and context.extension
    local current_time = extension and extension._last_fixed_t
        or Managers and Managers.time and Managers.time:time('gameplay')
    local action_component = extension and extension._weapon_action_component
    local time_scale = action_component and action_component.time_scale or 1

    if
        not buffer_time
        or buffer_time <= 0
        or not chain_actions
        or not start_t
        or not current_time
        or time_scale <= 0
    then
        return false
    end

    if not _game_chain_ready(context, resolved_chain_name, current_time + buffer_time) then
        return false
    end

    local time_in_action = current_time - start_t
    local action_kind = settings and settings.kind
    local weapon_overrides = context and CHAIN_TIME_OVERRIDES[context.name]

    for index = 1, chain_actions[1] and #chain_actions or 1 do
        local chain_action = _chain_action_at(chain_actions, index)
        local action_override = weapon_overrides and chain_action and weapon_overrides[chain_action.action_name]
        local configured_chain_time = action_override and action_override[chain_action.chain_time]
            or chain_action and chain_action.chain_time
        local chain_time = _scaled_chain_time(configured_chain_time or 0, time_scale, action_kind)
        local queue_start_t = math.max(0, chain_time - buffer_time)

        if queue_start_t <= time_in_action then
            return true
        end
    end

    return false
end

return WeaponContext
