local mod = get_mod('SimpleCharging')

local ChargeSources = {}

local MAX_SOURCES = 12
local ACTION_CHARGE = 'action_charge'
local AIM_TIME_PATTERN = 'aim_time'

local function _clamp(value, minimum, maximum)
    if value < minimum then
        return minimum
    elseif value > maximum then
        return maximum
    end

    return value
end

local function _call(object, method_name, ...)
    local method = object and object[method_name]

    if not method then
        return nil
    end

    local ok, value = pcall(method, object, ...)

    return ok and value or nil
end

local function _read_component(extension, component_name)
    local component = _call(extension, 'read_component', component_name)

    if component then
        return component
    end

    local components = extension and extension._components

    return components and components[component_name]
end

local function _extension(unit, extension_name)
    if not unit or not ScriptUnit or not ScriptUnit.has_extension then
        return nil
    end

    local ok, extension = pcall(ScriptUnit.has_extension, unit, extension_name)

    return ok and extension or nil
end

local function _player_context()
    local player_manager = Managers and Managers.player
    local player = player_manager and player_manager:local_player_safe(1)
    local unit = player and player.player_unit
    local weapon_extension = _extension(unit, 'weapon_system')
    local unit_data_extension = _extension(unit, 'unit_data_system')
    local buff_extension = _extension(unit, 'buff_system')
    local inventory = weapon_extension and weapon_extension._inventory_component
    local wielded_slot = inventory and inventory.wielded_slot
    local wielded_weapon

    if weapon_extension and inventory and weapon_extension._wielded_weapon then
        local ok, weapon =
            pcall(weapon_extension._wielded_weapon, weapon_extension, inventory, weapon_extension._weapons)
        wielded_weapon = ok and weapon or nil
    end

    local weapon_template = wielded_weapon and wielded_weapon.weapon_template
    local weapon_action = _read_component(unit_data_extension, 'weapon_action')
    local charge_component = _read_component(unit_data_extension, 'action_module_charge')

    charge_component = charge_component or weapon_extension and weapon_extension._action_module_charge_component

    local inventory_slot_component = wielded_weapon and wielded_weapon.inventory_slot_component
    local kind = wielded_slot == 'slot_primary' and 'melee' or wielded_slot == 'slot_secondary' and 'ranged' or nil

    return {
        player = player,
        unit = unit,
        weapon_extension = weapon_extension,
        unit_data_extension = unit_data_extension,
        buff_extension = buff_extension,
        inventory = inventory,
        wielded_slot = wielded_slot,
        wielded_weapon = wielded_weapon,
        weapon_template = weapon_template,
        weapon_action = weapon_action,
        charge_component = charge_component,
        inventory_slot_component = inventory_slot_component,
        kind = kind,
    }
end

local function _has_charge_trait_name(name)
    if not name then
        return false
    end

    for _, pattern in ipairs(CHARGE_TRAIT_PATTERNS) do
        if string.find(name, pattern, 1, true) then
            return true
        end
    end

    return false
end

local function _is_current_item_buff(buff, context)
    local template_context = buff and buff._template_context
    local item_slot_name = template_context and (template_context.item_slot_name or template_context.item_slot)

    return not item_slot_name or not context.wielded_slot or item_slot_name == context.wielded_slot
end

local function _buff_list(buff_extension)
    if not buff_extension then
        return nil
    end

    return buff_extension._buffs or buff_extension._buffs_by_index
end

local function _buff_entries(buff_list)
    local entries = {}

    if not buff_list then
        return entries
    end

    if #buff_list > 0 then
        for i = 1, #buff_list do
            entries[#entries + 1] = buff_list[i]
        end
    else
        for _, buff in pairs(buff_list) do
            entries[#entries + 1] = buff
        end
    end

    return entries
end

local function _trait_label(name)
    local label = name or 'Trait Progress'
    label = string.gsub(label, '^weapon_trait_', '')
    label = string.gsub(label, '_', ' ')

    return label
end

local function _find_buff_template(buff_entries, name)
    for _, buff in ipairs(buff_entries) do
        local template = buff and buff._template
        if template and template.name == name then
            return template
        end
    end
end

local function _step_maximum(buff, template, buff_entries)
    if template.min_max_step_func then
        local ok, minimum, maximum = pcall(template.min_max_step_func, buff._template_data, buff._template_context)

        if ok and type(maximum) == 'number' then
            return maximum
        end
    end

    if template.max_stacks then
        return template.max_stacks
    end

    local child_template = template.child_buff_template
        and _find_buff_template(buff_entries, template.child_buff_template)

    return child_template and child_template.max_stacks
end

local function _visual_stack_count(buff)
    if buff and buff.visual_stack_count then
        local ok, count = pcall(buff.visual_stack_count, buff)

        if ok and type(count) == 'number' then
            return count
        end
    end

    local template_context = buff and buff._template_context

    return template_context and template_context.stack_count or 0
end

local function _weapon_kind(context)
    if context.kind then
        return context.kind
    end

    local keywords = context.weapon_template and context.weapon_template.keywords

    if keywords then
        for _, keyword in ipairs(keywords) do
            if keyword == 'melee' then
                return 'melee'
            elseif keyword == 'ranged' then
                return 'ranged'
            end
        end
    end

    return nil
end

local function _weapon_critical_chance(context)
    local player = context.player
    local buff_extension = context.buff_extension
    local profile = player and _call(player, 'profile')
    local archetype = profile and profile.archetype
    local stat_buffs = buff_extension and _call(buff_extension, 'stat_buffs')

    if not archetype or not stat_buffs then
        return nil
    end

    local chance = archetype.base_critical_strike_chance or 0
    chance = chance + (stat_buffs.critical_strike_chance or 0)

    local kind = _weapon_kind(context)

    if kind == 'melee' then
        chance = chance + (stat_buffs.melee_critical_strike_chance or 0)
    elseif kind == 'ranged' then
        chance = chance + (stat_buffs.ranged_critical_strike_chance or 0)
    end

    local handling_template = context.weapon_extension and _call(context.weapon_extension, 'weapon_handling_template')
    local critical_strike = handling_template and handling_template.critical_strike

    if critical_strike and critical_strike.chance_modifier then
        chance = chance + critical_strike.chance_modifier
    end

    return _clamp(chance, 0, 1)
end

local function _add_source(sources, source)
    if not source or not source.maximum or source.maximum <= 0 then
        return
    end

    source.value = _clamp(source.value or 0, 0, source.maximum)
    source.fraction = source.value / source.maximum

    if source.value > 0 then
        sources[#sources + 1] = source
    end
end

local function _collect_weapon_sources(sources, context, settings)
    local charge_component = context.charge_component
    local charge_level = charge_component and charge_component.charge_level or 0
    local max_charge = charge_component and charge_component.max_charge or 0
    local action_name = context.weapon_action and context.weapon_action.current_action_name
    local charging = action_name == ACTION_CHARGE or action_name and string.find(action_name, 'charge', 1, true)

    if settings.show_weapon_charge and max_charge > 0 and (charging or charge_level > 0) then
        _add_source(sources, {
            id = 'weapon_charge',
            order = 1,
            label = 'Weapon Charge',
            kind = 'weapon',
            value = charge_level,
            maximum = max_charge,
        })
    end
end

local function _collect_buff_sources(sources, context, settings)
    local buff_entries = _buff_entries(_buff_list(context.buff_extension))
    local seen = {}

    for _, buff in ipairs(buff_entries) do
        local template = buff and buff._template
        local name = template and template.name
        local class_name = template and template.class_name

        if
            name
            and string.sub(name, 1, 13) == 'weapon_trait_'
            and _is_current_item_buff(buff, context)
            and not seen[name]
        then
            local is_stepped = class_name == 'stepped_stat_buff'
            local is_parent = string.find(class_name or '', 'weapon_trait_', 1, true) == 1
            local maximum = _step_maximum(buff, template, buff_entries)

            if (is_stepped or is_parent) and maximum and maximum > 0 then
                local value = _visual_stack_count(buff)
                local is_aim_time_crit = string.find(name, 'crit', 1, true)
                    and string.find(name, AIM_TIME_PATTERN, 1, true)

                if is_aim_time_crit then
                    local critical_chance = _weapon_critical_chance(context)

                    if critical_chance then
                        value = critical_chance
                        maximum = 1
                    end
                end

                _add_source(sources, {
                    id = name,
                    order = 10,
                    label = _trait_label(name),
                    kind = is_aim_time_crit and 'crit' or 'blessing',
                    value = value,
                    maximum = maximum,
                })
                seen[name] = true
            end
        end
    end
end

function ChargeSources.context()
    return _player_context()
end

function ChargeSources.collect(context, settings)
    context = context or _player_context()
    settings = settings or {}

    local resolved_settings = {
        show_weapon_charge = settings.show_weapon_charge ~= false and (mod:get('show_weapon_charge') ~= false),
    }
    local sources = {}

    _collect_weapon_sources(sources, context, resolved_settings)
    _collect_buff_sources(sources, context, resolved_settings)

    table.sort(sources, function(left, right)
        if left.order ~= right.order then
            return left.order < right.order
        end

        return left.id < right.id
    end)

    while #sources > MAX_SOURCES do
        sources[#sources] = nil
    end

    return sources
end

return ChargeSources
