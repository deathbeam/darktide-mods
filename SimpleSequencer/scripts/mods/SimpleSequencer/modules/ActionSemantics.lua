local ActionSemantics = {}

-- Canonical action states
local INPUT_STATE_ALIASES = {
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
}

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

local NO_IDLE_COMMANDS = { push_attack = true }

-- Policies are keyed by the expected command; hold overrides refine the current action.
local COMMAND_POLICIES = {
    idle = {
        hold_overrides = {
            light_attack = false,
            heavy_attack = false,
            shoot = true,
        },
    },
    start_attack = {
        action_one_hold = true,
        hold_overrides = {
            block = false,
            push = 'pulse',
            push_follow_up = 'pulse',
        },
    },
    light_attack = {
        action_one_hold = true,
        hold_overrides = {
            start_attack = false,
            light_attack = false,
            heavy_attack = false,
            block = false,
            push = false,
        },
    },
    heavy_attack = {
        action_one_hold = true,
        suppress_primary_pressed = true,
        heavy_windup = 'heavy_attack',
        hold_overrides = {
            block = false,
            push = false,
        },
    },
    shoot = {
        action_one_hold = true,
        hold_overrides = {
            start_attack = false,
            charge = false,
        },
    },
    charge = {
        action_two_hold = true,
        suppress_primary_pressed = true,
        hold_overrides = { shoot = true },
    },
    block = {
        action_two_hold = true,
        suppress_primary_hold = true,
        suppress_primary_pressed = true,
        hold_overrides = { push_follow_up = true },
    },
    push = {
        action_two_hold = true,
        suppress_primary_hold = true,
        hold_overrides = {
            block = true,
            push = true,
            push_follow_up = true,
        },
    },
    push_follow_up = {
        action_one_hold = true,
        action_two_hold = true,
        hold_overrides = {
            block = true,
            push = true,
            push_follow_up = true,
        },
    },
    special_start_attack = {
        weapon_extra_hold = true,
        suppress_primary_hold = true,
        suppress_primary_pressed = true,
    },
    special_light_attack = {
        weapon_extra_hold = true,
        suppress_primary_hold = true,
        suppress_primary_pressed = true,
    },
    special_heavy_execute = {
        weapon_extra_hold = true,
        suppress_primary_hold = true,
        suppress_primary_pressed = true,
        heavy_windup = 'special_heavy_execute',
    },
    special_action = {
        weapon_extra_pressed = true,
        suppress_primary_hold = true,
        suppress_primary_pressed = true,
    },
}

-- Input normalization
local function _classify_input(input_name)
    if not input_name then
        return nil
    end

    local state = INPUT_STATE_ALIASES[input_name]

    if state then
        return state
    end

    if string.find(input_name, 'wield', 1, true) then
        return 'quick_wield'
    elseif string.find(input_name, 'charge', 1, true) then
        return 'charge'
    elseif string.find(input_name, 'shoot', 1, true) then
        return 'shoot'
    elseif string.find(input_name, 'push_follow', 1, true) then
        return 'push_follow_up'
    elseif string.find(input_name, 'push', 1, true) then
        return 'push'
    elseif string.find(input_name, 'block', 1, true) then
        return 'block'
    elseif string.find(input_name, 'special', 1, true) then
        if string.find(input_name, 'heavy', 1, true) then
            return 'special_heavy_execute'
        elseif
            string.find(input_name, 'light', 1, true)
            or string.find(input_name, 'bash', 1, true)
            or string.find(input_name, 'pistol_whip', 1, true)
            or string.find(input_name, 'stab', 1, true)
        then
            return 'special_light_attack'
        elseif string.find(input_name, 'start', 1, true) or string.find(input_name, 'hold', 1, true) then
            return 'special_start_attack'
        end

        return 'special_action'
    end

    return nil
end

-- Live action classification
function ActionSemantics.classify_current(action_name, action_settings, expected_command)
    if not action_name or action_name == 'idle' then
        return 'idle'
    end

    local start_input = action_settings and action_settings.start_input
    local kind = action_settings and action_settings.kind

    if kind == 'charge_ammo' then
        return 'charge'
    elseif kind == 'trigger_explosion' then
        return 'shoot'
    end

    local input_state = _classify_input(start_input)

    if input_state then
        return input_state
    end

    if
        (expected_command == 'start_attack' or expected_command == 'light_attack' or expected_command == 'heavy_attack')
        and string.find(action_name, 'start', 1, true)
        and string.find(action_name, 'special', 1, true)
    then
        return 'start_attack'
    elseif
        expected_command == 'special_start_attack'
        and (kind == 'windup' or string.find(action_name, 'start', 1, true))
    then
        return 'special_start_attack'
    elseif expected_command == 'special_light_attack' and kind == 'sweep' then
        return 'special_light_attack'
    elseif expected_command == 'special_heavy_execute' and kind == 'sweep' then
        return 'special_heavy_execute'
    elseif expected_command == 'light_attack' and kind == 'sweep' then
        return 'light_attack'
    elseif expected_command == 'heavy_attack' and kind == 'sweep' then
        return 'heavy_attack'
    elseif expected_command == 'shoot' and (kind == 'chain_lightning' or kind == 'damage_target') then
        return 'shoot'
    end

    if string.find(action_name, 'wield', 1, true) then
        return 'quick_wield'
    end

    if string.find(action_name, 'reload', 1, true) or string.find(action_name, 'vent', 1, true) then
        return 'weapon_reload'
    end

    if string.find(action_name, 'pushfollow', 1, true) or string.find(action_name, 'push_follow', 1, true) then
        return 'push_follow_up'
    end

    if string.find(action_name, 'push', 1, true) or string.find(action_name, 'fling', 1, true) then
        return 'push'
    end

    if string.find(action_name, 'block', 1, true) then
        return 'block'
    end

    if string.find(action_name, 'shoot', 1, true) or action_name == 'rapid_left' then
        return 'shoot'
    end

    if string.find(action_name, 'charge', 1, true) then
        return 'charge'
    end

    if string.find(action_name, 'activate_special', 1, true) or string.find(action_name, 'toggle_special', 1, true) then
        return 'special_action'
    elseif string.find(action_name, 'stab_start', 1, true) or string.find(action_name, 'bash_start', 1, true) then
        return 'special_start_attack'
    elseif string.find(action_name, 'stab_heavy', 1, true) or string.find(action_name, 'bash_heavy', 1, true) then
        return 'special_heavy_execute'
    elseif string.find(action_name, 'bash', 1, true) or string.find(action_name, 'stab', 1, true) then
        return 'special_light_attack'
    end

    if string.find(action_name, 'special', 1, true) then
        if string.find(action_name, 'start', 1, true) then
            return 'special_start_attack'
        elseif string.find(action_name, 'execute', 1, true) or string.find(action_name, 'heavy', 1, true) then
            return 'special_heavy_execute'
        elseif string.find(action_name, 'light', 1, true) then
            return 'special_light_attack'
        end

        return 'special_action'
    end

    if string.find(action_name, 'start', 1, true) then
        return 'start_attack'
    end

    if string.find(action_name, 'heavy', 1, true) then
        return 'heavy_attack'
    end

    if string.find(action_name, 'light', 1, true) or string.find(action_name, 'swing', 1, true) then
        return 'light_attack'
    end

    return 'idle'
end

-- Execution policy
function ActionSemantics.command_policy(command)
    return COMMAND_POLICIES[command]
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

local function _chain_action_name(chain_action)
    return type(chain_action) == 'table' and chain_action.action_name
end

local function _is_shoot_action(action_name, settings)
    local kind = settings and settings.kind

    return settings
        and (
            settings.use_charge
            or type(kind) == 'string'
                and (string.find(kind, 'shoot', 1, true) or string.find(action_name or '', 'shoot', 1, true))
        )
end

local function _charged_release_input(template, input)
    local charge_action = _charge_action(template, input)

    if not charge_action then
        return nil
    end

    for input_name, chain_action in pairs(charge_action.allowed_chain_actions or {}) do
        local action_name = _chain_action_name(chain_action)
        local action = action_name and template.actions and template.actions[action_name]

        if action and _is_shoot_action(action_name, action) then
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

    local state = _classify_input(input)

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

local function _expand_command(template, command)
    local candidates = COMMAND_TARGETS[command]

    if not candidates then
        return nil
    end

    local path = _find_path(template, candidates)

    if not path and (command == 'special' or command == 'special_charged') then
        return _expand_command(template, 'special_action')
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

    if #states > 0 and not NO_IDLE_COMMANDS[command] then
        states[#states + 1] = 'idle'
    end

    return states
end

local function _new_plan(commands, cycle_index, repeating, unresolved_steps)
    return {
        commands = commands,
        cycle_index = cycle_index,
        repeating = repeating,
        unresolved_steps = unresolved_steps or {},
    }
end

-- Profile plan compilation
function ActionSemantics.plan(profile_plan, context)
    if not profile_plan or not context or not context.template then
        return _new_plan({}, 0, false)
    end

    local commands = {}
    local expansion_lengths = {}
    local unresolved_steps = {}
    local steps = profile_plan.steps or {}

    for i = 1, #steps do
        local command = steps[i]
        local expansion = _expand_command(context.template, command)

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
        return _new_plan({}, 0, false, unresolved_steps)
    end

    local cycle_index = 0

    if profile_plan.cycle_step and profile_plan.cycle_step > 0 then
        cycle_index = 1

        for i = 1, profile_plan.cycle_step - 1 do
            cycle_index = cycle_index + (expansion_lengths[i] or 0)
        end
    end

    if profile_plan.repeating and (cycle_index < 1 or cycle_index > #commands) then
        cycle_index = 1
    end

    return _new_plan(commands, cycle_index, profile_plan.repeating, unresolved_steps)
end

return ActionSemantics
