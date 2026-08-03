local WeaponContext = {}

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

local SPECIAL_ACTION_INPUTS = {
    'special_action',
    'special_action_hold',
    'special_action_light',
    'special_action_heavy',
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

function WeaponContext.has_special(context)
    context = context or WeaponContext.read()
    local action_inputs = context.template and context.template.action_inputs

    for _, input_name in ipairs(SPECIAL_ACTION_INPUTS) do
        if action_inputs and action_inputs[input_name] ~= nil then
            return true
        end
    end

    return false
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

function WeaponContext.can_chain(settings, start_t, chain_name, weapon_name)
    local allowed_chain_actions = settings and settings.allowed_chain_actions
    local chain_action = allowed_chain_actions and allowed_chain_actions[chain_name]

    if not chain_action and chain_name == 'heavy_attack' then
        chain_action = allowed_chain_actions
            and (allowed_chain_actions.special_action_heavy or allowed_chain_actions.heavy_attack_special)
    end

    if not chain_action or not start_t or not Managers or not Managers.time then
        return false
    end

    local chain_time = chain_action.chain_time

    if not chain_time and chain_action[1] then
        chain_time = chain_action[1].chain_time
    end

    if not chain_time then
        return false
    end

    local weapon_overrides = CHAIN_TIME_OVERRIDES[weapon_name]
    local action_override = weapon_overrides and weapon_overrides[chain_action.action_name]
    chain_time = action_override and action_override[chain_time] or chain_time

    local current_time = Managers.time:time('gameplay')

    return current_time and current_time - start_t > chain_time
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
