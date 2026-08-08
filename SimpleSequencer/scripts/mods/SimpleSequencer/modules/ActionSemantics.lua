local ActionSemantics = {}

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

local function _resolve_command(context, command)
    local template = context.template
    local candidates = COMMAND_TARGETS[command]
    local default_candidates = candidates

    if context.ranged_mode == 'ads' and (command == 'standard' or command == 'charged') then
        candidates = { 'shoot_braced' }
    end

    if not candidates then
        return nil
    end

    local path = _find_path(template, candidates)

    if not path and candidates ~= default_candidates then
        path = _find_path(template, default_candidates)
    end

    if not path and (command == 'special' or command == 'special_charged') then
        local fallback = _resolve_command(context, 'special_action')

        if fallback then
            return fallback
        end
    end

    return path and { inputs = path } or nil
end

local function _chain_matches_action(chain_actions, action_name)
    if type(chain_actions) ~= 'table' then
        return false
    end

    if chain_actions.action_name == action_name then
        return true
    end

    for _, chain_action in ipairs(chain_actions) do
        if chain_action.action_name == action_name then
            return true
        end
    end

    return false
end

local function _action_chain_matches_input(template, input_name, action_name)
    for _, settings in pairs(template.actions or {}) do
        local chain_actions = settings.allowed_chain_actions and settings.allowed_chain_actions[input_name]

        if _chain_matches_action(chain_actions, action_name) then
            return true
        end
    end

    return false
end

-- Runtime action matching
function ActionSemantics.matched_input_index(goal, start_input, action_name, template, used_input)
    if not goal then
        return nil
    end

    -- The action-start event input is exact; chain metadata below is only a fallback.
    if used_input then
        for index, input_name in ipairs(goal.inputs or {}) do
            if input_name == used_input then
                return index
            end
        end
    end

    for index, input_name in ipairs(goal.inputs or {}) do
        if input_name == start_input then
            return index
        end
    end

    if action_name and template then
        local action = template.actions and template.actions[action_name]

        for index, input_name in ipairs(goal.inputs or {}) do
            if action and action.start_input == input_name then
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

-- Compile profile steps into template-derived goals.
function ActionSemantics.compile(sequence, context)
    local plan = {
        goals = {},
        goal_cycle_index = 0,
        repeating = false,
        unresolved_steps = {},
    }

    if not sequence or not context or not context.template then
        return plan
    end

    local steps = sequence.steps or {}
    local resolved_steps = {}

    for i = 1, #steps do
        local command = steps[i]
        local resolved = _resolve_command(context, command)

        resolved_steps[i] = resolved ~= nil

        if resolved then
            plan.goals[#plan.goals + 1] = {
                command = command,
                inputs = resolved.inputs,
                step = i,
            }
        else
            plan.unresolved_steps[#plan.unresolved_steps + 1] = {
                command = command,
                step = i,
            }
        end
    end

    if #plan.goals == 0 then
        return plan
    end

    if sequence.cycle_step and sequence.cycle_step > 0 then
        local goal_cycle_index = 0

        for i = 1, sequence.cycle_step - 1 do
            if resolved_steps[i] then
                goal_cycle_index = goal_cycle_index + 1
            end
        end

        plan.goal_cycle_index = goal_cycle_index + 1
    end

    if sequence.repeating then
        if plan.goal_cycle_index < 1 or plan.goal_cycle_index > #plan.goals then
            plan.goal_cycle_index = 1
        end
    end

    plan.repeating = sequence.repeating

    return plan
end

return ActionSemantics
