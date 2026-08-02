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

local MELEE_WHILE_NOT_AIMING = {
    ogryn_gauntlet_p1_m1 = true,
}

local function _is_aiming_action(action_name)
    return action_name
        and (
                string.find(action_name, 'zoom', 1, true)
                or string.find(action_name, 'brace', 1, true)
                or string.find(action_name, 'aim', 1, true)
            )
            ~= nil
end

local function _player_unit()
    local player_manager = Managers and Managers.player
    local player = player_manager and player_manager:local_player_safe(1)

    return player and player.player_unit
end

local function _wielded_weapon(extension, inventory)
    if not extension or not inventory or not extension._wielded_weapon then
        return nil
    end

    local ok, weapon = pcall(extension._wielded_weapon, extension, inventory, extension._weapons)

    return ok and weapon or nil
end

function WeaponContext.read()
    local unit = _player_unit()
    local extension = unit and ScriptUnit.has_extension(unit, 'weapon_system')
    local inventory = extension and extension._inventory_component
    local weapon = _wielded_weapon(extension, inventory)
    local template = weapon and weapon.weapon_template
    local name = template and template.name
    local slot = inventory and inventory.wielded_slot
    local kind

    if slot == 'slot_primary' then
        kind = 'MELEE'
    elseif slot == 'slot_secondary' or slot == 'slot_grenade_ability' then
        local action_name = WeaponContext.action({ extension = extension })

        kind = MELEE_WHILE_NOT_AIMING[name] and not _is_aiming_action(action_name) and 'MELEE' or 'RANGED'
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

local function _chain_ready(settings, start_t, chain_name, weapon_name)
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

function WeaponContext.can_chain_start_attack(settings, start_t)
    return _chain_ready(settings, start_t, 'start_attack')
end

function WeaponContext.can_chain_shoot(settings, start_t, weapon_name)
    local chain_name = settings and settings.start_input or 'shoot_pressed'
    return _chain_ready(settings, start_t, chain_name, weapon_name)
end

function WeaponContext.can_chain_heavy_attack(settings, start_t, weapon_name)
    return _chain_ready(settings, start_t, 'heavy_attack', weapon_name)
end

function WeaponContext.charge_level(context)
    local extension = context and context.extension
    local charge_component = extension and extension._action_module_charge_component

    return charge_component and charge_component.charge_level or 0
end

function WeaponContext.charge_start_time(context)
    local extension = context and context.extension
    local charge_component = extension and extension._action_module_charge_component

    return charge_component and charge_component.charge_start_time or nil
end

return WeaponContext
