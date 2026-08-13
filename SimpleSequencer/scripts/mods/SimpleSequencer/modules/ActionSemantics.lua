local ActionSemantics = {}

local COMMAND_TARGETS = {
    light_attack = { 'light_attack' },
    heavy_attack = { 'heavy_attack' },
    special_action = { 'special_action', 'weapon_special', 'zoom_weapon_special' },
    special_action_heavy = { 'special_action_heavy', 'special_action_execute' },
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
}

local function _canonical_input(input_name)
    if type(input_name) ~= 'string' then
        return input_name
    end

    return input_name:gsub('_special$', '')
end
local SPECIAL_ATTACK_TARGETS = {
    special_action = { 'light_attack_special' },
    special_action_heavy = { 'heavy_attack_special' },
}

local SPECIAL_INPUTS = {
    special_action = true,
    start_attack_special = true,
    special_action_hold = true,
    special_action_light = true,
    special_action_heavy = true,
    special_action_execute = true,
    special_action_pistol_whip = true,
    special_action_push = true,
    weapon_special = true,
    zoom_weapon_special = true,
}

function ActionSemantics.is_special_input(input_name)
    return SPECIAL_INPUTS[input_name] or false
end

-- Runtime plan derivation

local function _path_to_input(entries, target, path, visited)
    if type(entries) ~= 'table' then
        return nil
    end

    for _, entry in ipairs(entries) do
        local input = entry and entry.input

        if input and not visited[input] then
            local next_path = {}
            for index = 1, #path do
                next_path[index] = path[index]
            end
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

        for _, entry in ipairs(hierarchy) do
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

local function _transition_after(template, inputs, input_index)
    local entries = template and template.action_input_hierarchy
    if not entries then
        return nil
    end

    for index = 1, input_index do
        local transition
        for _, entry in ipairs(entries) do
            if entry.input == inputs[index] then
                transition = entry.transition
                break
            end
        end

        if not transition then
            return nil
        elseif index == input_index then
            return transition
        elseif type(transition) ~= 'table' then
            return nil
        end

        entries = transition
    end
end

local function _programs(template, inputs)
    local programs = {}

    for input_index, input_name in ipairs(inputs) do
        local program = { input_name }
        programs[input_index] = program

        if (input_name == 'start_attack' or input_name == 'start_attack_special') and inputs[input_index + 1] then
            program[#program + 1] = inputs[input_index + 1]
        elseif input_index > 1 then
            local next_input_index = input_index + 1
            local entries = _transition_after(template, inputs, input_index)

            while type(entries) == 'table' and inputs[next_input_index] do
                local next_input = inputs[next_input_index]
                local transition
                for _, entry in ipairs(entries) do
                    if entry.input == next_input then
                        transition = entry.transition
                        break
                    end
                end

                if not transition then
                    break
                end

                program[#program + 1] = next_input
                entries = transition
                next_input_index = next_input_index + 1
            end
        end
    end

    return programs
end

local function _repeat_program(template, inputs, programs)
    local transition = _transition_after(template, inputs, #inputs)
    local repeat_at_chain_boundary = transition == 'stay'
    return repeat_at_chain_boundary and programs[#programs] or programs[1], repeat_at_chain_boundary
end

local function _resolve_command(context, command)
    local target_command = command == 'special' and context.special_active and 'standard' or command
    local template = context.template
    local candidates = COMMAND_TARGETS[target_command]
    local default_candidates = candidates

    if context.aim_mode == 'ads' and (target_command == 'standard' or target_command == 'charged') then
        candidates = { 'shoot_braced', 'zoom_shoot' }
    end

    if not candidates then
        return nil
    end
    local special_attack_candidates = context.kind == 'MELEE' and SPECIAL_ATTACK_TARGETS[command]
    local special_attack_path = special_attack_candidates and _find_path(template, special_attack_candidates)
    local special_attack_fallback = false
    if
        special_attack_path
        and type(context.special_charges) == 'number'
        and type(context.special_charge_cost) == 'number'
        and context.special_charges < context.special_charge_cost
    then
        candidates = COMMAND_TARGETS[command == 'special_action_heavy' and 'heavy_attack' or 'light_attack']
        special_attack_path = nil
        special_attack_fallback = true
    end
    local path = special_attack_path or _find_path(template, candidates)
    if not path and candidates ~= default_candidates then
        path = _find_path(template, default_candidates)
    end

    if
        not path
        and (
            target_command == 'special'
            or target_command == 'special_charged'
            or target_command == 'special_action_heavy'
        )
    then
        local fallback = _resolve_command(context, 'special_action')
        if fallback then
            return fallback
        end
    end

    if not path then
        return nil
    end

    local programs = _programs(template, path)
    local repeat_program, repeat_at_chain_boundary = _repeat_program(template, path, programs)
    return {
        inputs = path,
        programs = programs,
        repeat_program = repeat_program,
        repeat_at_chain_boundary = repeat_at_chain_boundary,
        special_attack = special_attack_path ~= nil,
        special_attack_fallback = special_attack_fallback,
    }
end

local function _chain_action_matches(chain_actions, action_name)
    if type(chain_actions) ~= 'table' then
        return false
    end
    if chain_actions.action_name == action_name then
        return true
    end
    for _, chain_action in ipairs(chain_actions) do
        if chain_action and chain_action.action_name == action_name then
            return true
        end
    end
    return false
end

local function _chain_actions_for_input(allowed_chain_actions, input_name)
    if type(allowed_chain_actions) ~= 'table' then
        return nil
    end

    local chain_actions = allowed_chain_actions[input_name]
    if type(chain_actions) == 'table' then
        return chain_actions
    end

    local canonical_input = _canonical_input(input_name)
    if type(canonical_input) ~= 'string' then
        return nil
    end

    chain_actions = allowed_chain_actions[canonical_input]
    if type(chain_actions) == 'table' then
        return chain_actions
    end

    chain_actions = allowed_chain_actions[canonical_input .. '_special']
    return type(chain_actions) == 'table' and chain_actions or nil
end

local function _action_chain_matches_input(template, input_name, action_name)
    for _, settings in pairs(template.actions or {}) do
        local chain_actions = _chain_actions_for_input(settings.allowed_chain_actions, input_name)
        if _chain_action_matches(chain_actions, action_name) then
            return true
        end
    end

    return false
end

function ActionSemantics.matched_input_index(goal, start_input, action_name, template, used_input)
    if not goal then
        return nil
    end

    -- The action setting identifies the transition; interpreter submissions fill gaps only.
    if start_input then
        for index, input_name in ipairs(goal.inputs or {}) do
            if _canonical_input(input_name) == _canonical_input(start_input) then
                return index
            end
        end
    end

    if used_input then
        for index, input_name in ipairs(goal.inputs or {}) do
            if _canonical_input(input_name) == _canonical_input(used_input) then
                return index
            end
        end
    end

    if action_name and template then
        local action = template.actions and template.actions[action_name]

        -- Powered sweeps omit start_input; their windups are only intermediate actions.
        if action and not action.start_input and action.activate_special_during_sweep then
            for index = #(goal.inputs or {}), 1, -1 do
                if
                    _canonical_input(goal.inputs[index]) == 'light_attack'
                    or _canonical_input(goal.inputs[index]) == 'heavy_attack'
                then
                    return index
                end
            end
        end

        for index, input_name in ipairs(goal.inputs or {}) do
            if action and _canonical_input(action.start_input) == _canonical_input(input_name) then
                return index
            end
        end

        for index, input_name in ipairs(goal.inputs or {}) do
            if _action_chain_matches_input(template, input_name, action_name) then
                return index
            end
        end
    end

    return nil
end

function ActionSemantics.program_after(goal, progress)
    local programs = goal and goal.programs
    return programs and programs[(progress or 0) + 1] or nil
end

local function _same_list(first, second)
    if first == second then
        return true
    end
    if type(first) ~= 'table' or type(second) ~= 'table' or #first ~= #second then
        return false
    end
    for index = 1, #first do
        if first[index] ~= second[index] then
            return false
        end
    end
    return true
end

local function _same_programs(first, second)
    if first == second then
        return true
    end
    if type(first) ~= 'table' or type(second) ~= 'table' or #first ~= #second then
        return false
    end
    for index = 1, #first do
        if not _same_list(first[index], second[index]) then
            return false
        end
    end
    return true
end

function ActionSemantics.same_plan(first, second)
    if first == second then
        return true
    end
    if type(first) ~= 'table' or type(second) ~= 'table' then
        return false
    end
    if first.goal_cycle_index ~= second.goal_cycle_index or #first.goals ~= #second.goals then
        return false
    end
    for index = 1, #first.goals do
        local first_goal = first.goals[index]
        local second_goal = second.goals[index]
        if
            first_goal.command ~= second_goal.command
            or first_goal.repeat_at_chain_boundary ~= second_goal.repeat_at_chain_boundary
            or first_goal.special_attack ~= second_goal.special_attack
            or not _same_list(first_goal.inputs, second_goal.inputs)
            or not _same_programs(first_goal.programs, second_goal.programs)
            or not _same_list(first_goal.repeat_program, second_goal.repeat_program)
        then
            return false
        end
    end
    return true
end

-- Compile profile steps into template-derived goals.
function ActionSemantics.compile(sequence, context)
    local plan = {
        goals = {},
        goal_cycle_index = 0,
    }

    if not sequence or not context or not context.template then
        return plan
    end

    local steps = sequence.steps or {}

    for i = 1, #steps do
        local command = steps[i]
        local resolved = _resolve_command(context, command)
        local special_command = command == 'special_action' or command == 'special_action_heavy'
        local special_attack = resolved and (resolved.special_attack or resolved.special_attack_fallback)
        local insufficient_charges = type(context.special_charges) == 'number'
            and type(context.special_charge_cost) == 'number'
            and context.special_charges < context.special_charge_cost
        local skip_special_activation = context.kind == 'MELEE'
            and special_command
            and not special_attack
            and (context.special_active or insufficient_charges)
        if skip_special_activation then
            resolved = nil
        end

        if resolved then
            plan.goals[#plan.goals + 1] = {
                command = command,
                inputs = resolved.inputs,
                programs = resolved.programs,
                repeat_program = resolved.repeat_program,
                repeat_at_chain_boundary = resolved.repeat_at_chain_boundary,
                step = i,
                special_attack = resolved.special_attack,
            }
        end
    end

    if #plan.goals == 0 then
        return plan
    end

    if sequence.cycle_step and sequence.cycle_step > 0 then
        for _, goal in ipairs(plan.goals) do
            if goal.step < sequence.cycle_step then
                plan.goal_cycle_index = plan.goal_cycle_index + 1
            end
        end

        plan.goal_cycle_index = plan.goal_cycle_index + 1
    end

    if sequence.repeating then
        if plan.goal_cycle_index < 1 or plan.goal_cycle_index > #plan.goals then
            plan.goal_cycle_index = 1
        end
    end
    return plan
end

return ActionSemantics
