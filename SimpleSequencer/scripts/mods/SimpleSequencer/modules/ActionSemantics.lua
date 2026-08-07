local ActionSemantics = {}

local QUICK_SWAP_CANCEL = 'quick_swap_cancel'

-- Canonical action states
local IDENTIFIER_STATES = {
    start_attack = 'start_attack',
    light_attack = 'light_attack',
    heavy_attack = 'heavy_attack',
    block = 'block',
    push = 'push',
    push_follow_up = 'push_follow_up',
    shoot = 'shoot',
    shoot_pressed = 'shoot',
    shoot_hold = 'shoot',
    charge = 'charge',
    charge_heavy = 'charge',
    charge_power = 'charge',
    special_action = 'special_action',
    weapon_special = 'special_action',
    zoom_weapon_special = 'special_action',
    special_action_hold = 'special_start_attack',
    special_action_light = 'special_light_attack',
    special_action_heavy = 'special_heavy_execute',
    special_action_pistol_whip = 'special_light_attack',
    special_action_push = 'special_light_attack',
    special_action_start = 'special_start_attack',
    special_action_execute = 'special_heavy_execute',
    shoot_charged = 'shoot',
    shoot_charge = 'charge',
    shoot_light_pressed = 'shoot',
    trigger_explosion = 'shoot',
    action_attack_special_2 = 'light_attack',
}

local ACTION_KIND_STATES = {
    activate_special = 'special_action',
    charge_ammo = 'charge',
    ranged_wield = 'quick_wield',
    reload_shotgun = 'weapon_reload',
    reload_state = 'weapon_reload',
    toggle_special = 'special_action',
    toggle_special_with_block = 'special_action',
    trigger_explosion = 'shoot',
    unwield = 'quick_wield',
    unwield_to_previous = 'quick_wield',
    unwield_to_specific = 'quick_wield',
    vent_overheat = 'weapon_reload',
    vent_warp_charge = 'weapon_reload',
    wield = 'quick_wield',
}

local MELEE_START_COMMANDS = {
    heavy_attack = true,
    light_attack = true,
    start_attack = true,
}

local SWEEP_COMMANDS = {
    heavy_attack = true,
    light_attack = true,
    push_follow_up = true,
    special_heavy_execute = true,
    special_light_attack = true,
}

local SPECIAL_SWEEP_COMMANDS = {
    special_heavy_execute = true,
    special_light_attack = true,
}

local SHOOT_ACTION_KINDS = {
    chain_lightning = true,
    damage_target = true,
}

local PRIMARY_CHARGE_CACHE = setmetatable({}, { __mode = 'k' })

local COMMAND_TARGETS = {
    light_attack = { 'light_attack' },
    heavy_attack = { 'heavy_attack' },
    special_action = { 'special_action', 'weapon_special', 'zoom_weapon_special' },
    block = { 'block' },
    push = { 'push' },
    push_attack = { 'push_follow_up' },
    standard = {
        'shoot_pressed',
        'shoot',
        'shoot_hold',
        'shoot_light_pressed',
        'shoot_charge',
        'shoot_heavy_hold',
        'trigger_explosion',
    },
    charged = {
        'charge_heavy',
        'charge_power',
        'shoot_charged',
        'shoot_charge',
        'shoot_heavy_hold',
        'shoot_pressed',
        'shoot',
        'shoot_hold',
        'trigger_explosion',
    },
    special = { 'special_action_light', 'special_action_pistol_whip', 'special_action_push' },
    special_charged = { 'special_action_heavy', 'special_action_execute' },
    special_standard = { 'special_action', 'weapon_special', 'zoom_weapon_special' },
}

-- Runtime action classification
local function _contains(value, fragment)
    return value and string.find(value, fragment, 1, true) ~= nil or false
end

local function _classify_identifier(identifier)
    if not identifier then
        return nil
    end

    local state = IDENTIFIER_STATES[identifier]

    if state then
        return state
    end

    if _contains(identifier, 'reload') or _contains(identifier, 'vent') then
        return 'weapon_reload'
    elseif _contains(identifier, 'pushfollow') or _contains(identifier, 'push_follow') then
        return 'push_follow_up'
    elseif _contains(identifier, 'push') or _contains(identifier, 'fling') then
        return 'push'
    elseif _contains(identifier, 'block') then
        return 'block'
    elseif _contains(identifier, 'shoot') or _contains(identifier, 'trigger') or identifier == 'rapid_left' then
        return 'shoot'
    elseif _contains(identifier, 'charge') then
        return 'charge'
    elseif _contains(identifier, 'bash') or _contains(identifier, 'stab') then
        if _contains(identifier, 'start') then
            return 'special_start_attack'
        elseif _contains(identifier, 'heavy') then
            return 'special_heavy_execute'
        end

        return 'special_light_attack'
    end

    local explicit_special = string.sub(identifier, 1, 14) == 'action_special'

    if explicit_special then
        if _contains(identifier, 'start') then
            return 'special_start_attack'
        elseif _contains(identifier, 'execute') or _contains(identifier, 'heavy') then
            return 'special_heavy_execute'
        elseif _contains(identifier, 'light') then
            return 'special_light_attack'
        end

        return 'special_action'
    elseif
        _contains(identifier, 'activate_special')
        or _contains(identifier, 'toggle_special')
        or _contains(identifier, 'weapon_special')
        or _contains(identifier, 'flashlight')
    then
        return 'special_action'
    elseif _contains(identifier, 'start') then
        return 'start_attack'
    elseif _contains(identifier, 'light') or _contains(identifier, 'swing') then
        return 'light_attack'
    elseif _contains(identifier, 'heavy') then
        return 'heavy_attack'
    elseif _contains(identifier, 'special') then
        return _contains(identifier, 'execute') and 'special_heavy_execute' or 'special_action'
    elseif _contains(identifier, 'wield') then
        return 'quick_wield'
    end

    return nil
end

function ActionSemantics.classify_current(action_name, action_settings, expected_command)
    if not action_name or action_name == 'idle' then
        return 'idle'
    end

    local kind = action_settings and action_settings.kind
    local kind_state = ACTION_KIND_STATES[kind]

    if kind_state then
        return kind_state
    end

    local input_state = _classify_identifier(action_settings and action_settings.start_input)

    if input_state then
        return input_state
    end

    local name_state = _classify_identifier(action_name)

    if
        MELEE_START_COMMANDS[expected_command]
        and _contains(action_name, 'start')
        and _contains(action_name, 'special')
    then
        return 'start_attack'
    elseif expected_command == 'special_start_attack' and (kind == 'windup' or _contains(action_name, 'start')) then
        return 'special_start_attack'
    elseif
        kind == 'sweep'
        and SWEEP_COMMANDS[expected_command]
        and (not name_state or name_state == 'special_action' and SPECIAL_SWEEP_COMMANDS[expected_command])
    then
        return expected_command
    elseif expected_command == 'shoot' and SHOOT_ACTION_KINDS[kind] then
        return 'shoot'
    end

    return name_state or 'idle'
end

local function _input_starts_with(template, input_name, raw_input)
    local input = template and template.action_inputs and template.action_inputs[input_name]
    local first = input and input.input_sequence and input.input_sequence[1]

    if not first then
        return false
    end

    if first.input == raw_input then
        return true
    end

    for _, candidate in ipairs(first.inputs or {}) do
        if candidate.input == raw_input then
            return true
        end
    end

    return false
end

local function _template_uses_primary_charge(template)
    if not template then
        return false
    end

    local cached = PRIMARY_CHARGE_CACHE[template]

    if cached ~= nil then
        return cached
    end

    for _, settings in pairs(template.actions or {}) do
        if
            type(settings) == 'table'
            and _contains(settings.kind, 'charge')
            and _input_starts_with(template, settings.start_input, 'action_one_hold')
        then
            PRIMARY_CHARGE_CACHE[template] = true
            return true
        end
    end

    PRIMARY_CHARGE_CACHE[template] = false
    return false
end

function ActionSemantics.uses_primary_charge(context, action_settings)
    local template = context and context.template
    local start_input = action_settings and action_settings.start_input

    if start_input then
        return _input_starts_with(template, start_input, 'action_one_hold')
    end

    return _template_uses_primary_charge(template)
end

-- Runtime plan derivation
local function _append(values, additions)
    for i = 1, #additions do
        values[#values + 1] = additions[i]
    end
end

local function _path_to_input(entries, target, path, visited)
    if type(entries) ~= 'table' then
        return nil
    end

    for _, entry in ipairs(entries) do
        local input = entry and entry.input

        if input and not visited[input] then
            local next_path = {}
            _append(next_path, path)
            next_path[#next_path + 1] = input

            if input == target then
                return next_path
            end

            visited[input] = true
            local result = _path_to_input(entry.transition, target, next_path, visited)
            visited[input] = nil

            if result then
                return result
            end
        end
    end

    return nil
end

local function _find_path(template, candidates)
    local hierarchy = template and template.action_input_hierarchy

    if type(hierarchy) ~= 'table' then
        return nil
    end

    -- Top-level inputs are valid from idle; nested occurrences are chain transitions.
    for i = 1, #candidates do
        local target = candidates[i]

        for _, entry in ipairs(hierarchy or {}) do
            if entry and entry.input == target then
                return { target }
            end
        end
    end

    for i = 1, #candidates do
        local path = _path_to_input(hierarchy, candidates[i], {}, {})

        if path then
            return path
        end
    end

    return nil
end

local function _charge_action(template, input)
    for _, settings in pairs(template.actions or {}) do
        if type(settings) == 'table' then
            local kind = settings.start_input == input and settings.kind

            if type(kind) == 'string' and string.find(kind, 'charge', 1, true) then
                return settings
            end
        end
    end

    return nil
end

local function _charged_release_input(template, input)
    local charge_action = _charge_action(template, input)

    if not charge_action then
        return nil
    end

    for input_name, chain_action in pairs(charge_action.allowed_chain_actions or {}) do
        local action_name = type(chain_action) == 'table' and chain_action.action_name
        local action = action_name and template.actions and template.actions[action_name]
        local kind = action and action.kind
        local is_shoot_action = action
            and (
                action.use_charge
                or type(kind) == 'string'
                    and (string.find(kind, 'shoot', 1, true) or string.find(action_name, 'shoot', 1, true))
            )

        if is_shoot_action then
            return input_name
        end
    end

    local action_end = charge_action.conditional_state_to_action_input
        and charge_action.conditional_state_to_action_input.action_end

    return action_end and action_end.input_name
end

local function _state_for_input(template, input, command, is_first)
    if command == 'charged' and is_first and _charge_action(template, input) then
        return 'charge'
    end

    local state = _classify_identifier(input)

    if command == 'standard' and state == 'charge' and string.find(input, 'shoot', 1, true) then
        return 'shoot'
    end

    return state
end

local function _has_state(states, expected)
    for i = 1, #states do
        if states[i] == expected then
            return true
        end
    end

    return false
end

local function _expand_command(context, command)
    if command == QUICK_SWAP_CANCEL then
        local slot = context.slot

        return (slot == 'slot_primary' or slot == 'slot_secondary') and { command } or nil
    end

    local template = context.template

    local candidates = COMMAND_TARGETS[command]

    if not candidates then
        return nil
    end

    local path = _find_path(template, candidates)

    if not path and (command == 'special' or command == 'special_charged') then
        return _expand_command(context, 'special_action')
    end

    if not path then
        return nil
    end

    local states = {}

    for i = 1, #path do
        local state = _state_for_input(template, path[i], command, i == 1)

        if not state then
            return nil
        end

        if states[#states] ~= state then
            states[#states + 1] = state
        end
    end

    if command == 'charged' then
        local release_input = _charged_release_input(template, path[1])
        local release_state = release_input and _state_for_input(template, release_input, 'standard', false)

        if release_state and not _has_state(states, release_state) then
            states[#states + 1] = release_state
        end

        if not _has_state(states, 'shoot') then
            states[#states + 1] = 'shoot'
        end
    elseif command == 'special_standard' and not _has_state(states, 'shoot') then
        states[#states + 1] = 'shoot'
    end

    if #states > 0 and command ~= 'push_attack' then
        states[#states + 1] = 'idle'
    end

    return states
end

-- Sequence compilation
function ActionSemantics.compile(sequence, context)
    local plan = {
        commands = {},
        cycle_index = 0,
        repeating = false,
        unresolved_steps = {},
    }

    if not sequence or not context or not context.template then
        return plan
    end

    local commands = plan.commands
    local expansion_lengths = {}
    local unresolved_steps = plan.unresolved_steps
    local steps = sequence.steps or {}

    for i = 1, #steps do
        local command = steps[i]
        local expansion = _expand_command(context, command)

        expansion_lengths[i] = expansion and #expansion or 0

        if expansion then
            _append(commands, expansion)
        else
            unresolved_steps[#unresolved_steps + 1] = {
                command = command,
                step = i,
            }
        end
    end

    if #commands == 0 then
        return plan
    end

    local cycle_index = 0

    if sequence.cycle_step and sequence.cycle_step > 0 then
        cycle_index = 1

        for i = 1, sequence.cycle_step - 1 do
            cycle_index = cycle_index + (expansion_lengths[i] or 0)
        end
    end

    if sequence.repeating and (cycle_index < 1 or cycle_index > #commands) then
        cycle_index = 1
    end

    plan.cycle_index = cycle_index
    plan.repeating = sequence.repeating

    return plan
end

return ActionSemantics
