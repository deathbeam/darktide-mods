local mod = get_mod('SimpleSequencer')
local Profiles = mod:io_dofile('SimpleSequencer/scripts/mods/SimpleSequencer/modules/SequenceProfiles')
local WeaponContext = mod:io_dofile('SimpleSequencer/scripts/mods/SimpleSequencer/modules/WeaponContext')
local ActionSemantics = mod:io_dofile('SimpleSequencer/scripts/mods/SimpleSequencer/modules/ActionSemantics')
local SequenceInterpreter = mod:io_dofile('SimpleSequencer/scripts/mods/SimpleSequencer/modules/SequenceInterpreter')
local SequenceController = class('SimpleSequencerSequenceController')

local function _is_primary_input(action_name)
    return action_name == 'action_one_pressed' or action_name == 'action_one_hold'
end

local function _action_token(action, start_t)
    if not action or action == 'idle' then
        return 'idle'
    end

    return action .. ':' .. tostring(start_t or 0)
end

local function _is_damage_window(action_settings)
    return action_settings and action_settings.kind == 'sweep' and action_settings.damage_window_end
end

local function _matched_input_index(goal, action_name, action_settings, context, used_input)
    return ActionSemantics.matched_input_index(
        goal,
        action_settings and action_settings.start_input,
        action_name,
        context and context.template,
        used_input
    )
end

local function _empty_plan()
    return {
        goals = {},
        goal_cycle_index = 0,
    }
end

local function _goal_index_at_or_after_step(plan, step)
    if not plan or not step then
        return nil
    end

    local next_index
    for index, goal in ipairs(plan.goals or {}) do
        if goal.step == step then
            return index
        end
        if not next_index and goal.step > step then
            next_index = index
        end
    end

    return next_index or (plan.goal_cycle_index > 0 and plan.goal_cycle_index or nil)
end

function SequenceController:_terminal_program()
    local program = self.sequence.program

    return program and program.kind == 'terminal' and program or nil
end

function SequenceController:init(mode_manager)
    self.mode_manager = mode_manager
    self.sequence = {
        index = 1,
        plan = _empty_plan(),
        no_repeat_restored = false,
        program = nil,
    }
    self.action = {
        started = nil,
        window_token = nil,
    }
    self.context = nil
    self.context_key = nil
    self.pending_transition = nil
    self.activation = { primary = false, secondary = false }
    self.aim_mode = 'hip'
    self.input_settings = { toggle_ads = false }
    self.interpreter = SequenceInterpreter:new()
end

function SequenceController:invalidate()
    self.context_key = nil
    self.pending_transition = nil
end

function SequenceController:is_active()
    local goal = self:_goal()
    return goal ~= nil
        and not self.interpreter:is_missing_sequence()
        and (self.activation.primary or self.activation.secondary and goal.command == 'charged')
end

function SequenceController:can_switch_mode()
    local action_name, start_t, action_settings = WeaponContext.action(self.context)
    local has_damage_window = _is_damage_window(action_settings)
    if has_damage_window then
        -- Recovery no longer affects gameplay once the attack cannot deal damage.
        return self.action.window_token == _action_token(action_name, start_t)
    end
    if not action_name or action_name == 'idle' then
        return true
    end

    local goal = self:_goal()
    local progress = _matched_input_index(
        goal,
        action_name,
        action_settings,
        self.context,
        self:_started_input(_action_token(action_name, start_t))
    )
    local next_input = progress and goal.inputs[progress + 1]

    return next_input and WeaponContext.can_chain(action_settings, start_t, next_input, self.context) or false
end

function SequenceController:_goal()
    return self.sequence.index and self.sequence.plan.goals and self.sequence.plan.goals[self.sequence.index]
end

function SequenceController:_next_goal()
    local goals = self.sequence.plan.goals
    local next_index = self.sequence.index and self.sequence.index + 1

    if not next_index or not goals then
        return nil
    end

    if next_index > #goals then
        next_index = self.sequence.plan.goal_cycle_index > 0 and self.sequence.plan.goal_cycle_index or nil
    end

    return next_index and goals[next_index]
end

function SequenceController:_apply_transition(transition, continuation_step, continue_sequence)
    local preserve_activation = transition.preserve_activation
    local primary_active = preserve_activation and self.activation.primary
    local secondary_active = preserve_activation and self.activation.secondary

    self:reset()
    self.context = transition.context
    self.context_key = transition.key
    self.sequence.plan = transition.plan
    self.profile = transition.profile

    if continue_sequence then
        self.sequence.index = _goal_index_at_or_after_step(transition.plan, continuation_step)
    end
    if preserve_activation then
        self.activation.primary = primary_active
        self.activation.secondary = secondary_active
    end
end

function SequenceController:_advance_if_chain_ready(start_t, action_settings)
    local next_goal = self:_next_goal()
    local transition = self.pending_transition
    local next_context = self.context
    if transition then
        local next_index = next_goal and _goal_index_at_or_after_step(transition.plan, next_goal.step)
        next_goal = next_index and transition.plan.goals[next_index] or nil
        next_context = transition.context
    end
    local action_name = WeaponContext.action(self.context)
    local action_token = _action_token(action_name, start_t)
    if _is_damage_window(action_settings) and self.action.window_token ~= action_token then
        return false
    end

    local next_progress =
        _matched_input_index(next_goal, action_name, action_settings, next_context, self:_started_input(action_token))

    local next_program
    if next_goal and next_progress == #(next_goal.inputs or {}) then
        next_program = next_goal.repeat_program or ActionSemantics.program_after(next_goal, 0)
    else
        next_program = ActionSemantics.program_after(next_goal, next_progress or 0)
    end
    local next_input = next_program and next_program[1]
    local repeat_at_chain_boundary = next_goal
        and next_progress == #(next_goal.inputs or {})
        and next_goal.repeat_at_chain_boundary

    local can_chain = next_input and WeaponContext.can_chain(action_settings, start_t, next_input, next_context)
    local can_buffer = not repeat_at_chain_boundary
        and next_input
        and (not ActionSemantics.is_attack_start_input(next_input) or not self.activation.secondary)
        and WeaponContext.can_buffer_input(action_settings, next_input, next_context)

    if not (can_chain or can_buffer) then
        return false
    end

    self:_advance()
    self.sequence.program = {
        kind = 'chain',
        token = action_token,
        inputs = next_program,
    }

    return true
end

function SequenceController:_reset_sequence()
    self.activation.primary = false
    self.activation.secondary = false
    self.sequence.index = 1
    self.sequence.no_repeat_restored = false
    self.sequence.program = nil
    self.pending_transition = nil
    self.interpreter:reset()
end

function SequenceController:reset()
    self:_reset_sequence()
    self.action.started = nil
    self.action.window_token = nil
end

function SequenceController:_started_input(action_token)
    local started = self.action.started
    return started and started.token == action_token and started.input or nil
end

function SequenceController:_resolved_inputs(inputs, frame_inputs, family_input, action_settings, start_t)
    local context = self.context
    local template = context and context.template
    local resolved = ActionSemantics.resolve_input_aliases(template, inputs, frame_inputs, family_input)

    if not family_input or not resolved[1] then
        return resolved
    end

    local frame_resolved = ActionSemantics.resolve_input_aliases(template, inputs, frame_inputs)
    if frame_resolved[1] == resolved[1] then
        return resolved
    end

    local family_open = WeaponContext.can_chain(action_settings, start_t, resolved[1], context)
        or WeaponContext.can_buffer_input(action_settings, resolved[1], context)
    local frame_open = WeaponContext.can_chain(action_settings, start_t, frame_resolved[1], context)
        or WeaponContext.can_buffer_input(action_settings, frame_resolved[1], context)

    return not family_open and frame_open and frame_resolved or resolved
end

-- Action start events are the authoritative progress signal; polling only fills gaps.
function SequenceController:on_action_started(action_name, t, automatic_input, action_settings, parser_input)
    if not action_name or action_name == 'none' then
        return
    end

    if action_settings and action_settings.kind == 'unwield_to_specific' then
        self:reset()
    elseif automatic_input then
        local goal = self:_goal()
        local progress = _matched_input_index(goal, action_name, action_settings, self.context, automatic_input)
        if goal and not progress then
            self.interpreter:reset()
            self.sequence.program = nil
        end
    end

    local pending_input = self.interpreter:pending_action_input()
    local input_matches_action
    if automatic_input or not pending_input then
        input_matches_action = true
    elseif parser_input then
        input_matches_action = ActionSemantics.input_aliases_match(pending_input, parser_input)
    else
        input_matches_action = ActionSemantics.action_matches_input(
            self.context and self.context.template,
            pending_input,
            action_name,
            action_settings
        )
    end
    local input
    if input_matches_action then
        input = self.interpreter:consume_action_input(automatic_input, t)
    else
        self.interpreter:reset()
        self.sequence.program = nil
    end
    input = parser_input or action_settings and action_settings.start_input or input
    self.action.started = {
        token = _action_token(action_name, t),
        input = input,
        settings = action_settings,
    }
end

function SequenceController:on_damage_window_exited(action_settings)
    if action_settings then
        if
            not _is_damage_window(action_settings)
            or not self.action.started
            or self.action.started.settings ~= action_settings
        then
            return
        end

        self.action.window_token = self.action.started.token
        return
    end

    local action_name, start_t, current_action_settings = WeaponContext.action(self.context)
    if _is_damage_window(current_action_settings) then
        self.action.window_token = _action_token(action_name, start_t)
    end
end

function SequenceController:on_slot_wielded()
    self.context = WeaponContext.read()
    self:reset()
    self:invalidate()
end

function SequenceController:_refresh_context()
    local previous_context = self.context
    local context = WeaponContext.read()
    context.aim_mode = self.aim_mode

    local key = self.mode_manager:active()
        .. ':'
        .. context.kind
        .. ':'
        .. context.name
        .. ':'
        .. self.aim_mode
        .. ':'
        .. tostring(context.special_active)
        .. ':'
        .. tostring(context.special_charges)
    if self.context_key == key then
        self.context = context
        self.pending_transition = nil
        return context
    end

    local same_weapon = previous_context
        and previous_context.kind == context.kind
        and previous_context.name == context.name
        and previous_context.aim_mode == context.aim_mode
    local special_active_changed = same_weapon and previous_context.special_active ~= context.special_active
    local special_charges_changed = same_weapon and previous_context.special_charges ~= context.special_charges
    local context_state_changed = special_active_changed or special_charges_changed
    local profile = context.kind ~= 'none' and self.mode_manager:profile(context.kind, context.name)
    local sequence = profile and Profiles.build_sequence(profile, context.kind, self.aim_mode)
    local plan = sequence and ActionSemantics.compile(sequence, context) or _empty_plan()

    if context_state_changed and ActionSemantics.same_plan(self.sequence.plan, plan) then
        self.context = context
        self.context_key = key
        self.profile = profile
        self.pending_transition = nil
        return context
    end

    local transition = {
        context = context,
        key = key,
        plan = plan,
        profile = profile,
        preserve_activation = context_state_changed,
    }
    local current_action = WeaponContext.action(context)
    -- Apply charge-driven plans at a goal boundary so the current attack can finish.
    if context.kind == 'MELEE' and context_state_changed and self.activation.primary and current_action ~= 'idle' then
        self.pending_transition = transition
        return context
    end

    self:_apply_transition(transition)
    return context
end

function SequenceController:_advance()
    local sequence = self.sequence
    local goals = sequence.plan.goals

    if not goals or #goals == 0 then
        return
    end
    local pending_transition = self.pending_transition
    if pending_transition then
        local next_goal = self:_next_goal()
        self:_apply_transition(pending_transition, next_goal and next_goal.step, true)
        return
    end

    if sequence.index >= #goals then
        if sequence.plan.goal_cycle_index > 0 then
            sequence.index = sequence.plan.goal_cycle_index
        else
            sequence.index = nil
        end
    else
        sequence.index = sequence.index + 1
    end

    sequence.program = nil
    self.interpreter:reset()
end

function SequenceController:_maybe_advance_goal()
    local goal = self:_goal()

    if not goal then
        return false
    end

    local action_name, start_t, action_settings = WeaponContext.action(self.context)

    if action_name == 'idle' then
        if self:_terminal_program() then
            self:_advance()
        end

        return true
    end

    local action_token = _action_token(action_name, start_t)
    local terminal = self:_terminal_program()
    local used_input = self:_started_input(action_token)
    local progress = _matched_input_index(goal, action_name, action_settings, self.context, used_input)

    if not progress then
        if terminal and action_token ~= terminal.token then
            self:_advance_if_chain_ready(start_t, action_settings)
        end

        return false
    end

    local program = self.sequence.program
    if program and program.kind == 'chain' then
        if program.token == action_token then
            return true
        end

        program.kind = 'normal'
        program.token = nil
    end

    if terminal then
        if action_token ~= terminal.token then
            self:_advance()
        elseif terminal.release_input then
            if self.interpreter:has_submitted() then
                self:_advance_if_chain_ready(start_t, action_settings)
            end
        else
            self:_advance_if_chain_ready(start_t, action_settings)
        end

        return true
    end

    if progress == #(goal.inputs or {}) then
        local release_input = self:_next_goal()
                and ActionSemantics.terminal_release_input(goal, self.context and self.context.template)
            or goal.command == 'block' and 'block'
            or nil
        self.sequence.program = {
            kind = 'terminal',
            token = action_token,
            release_input = release_input,
            inputs = release_input and { release_input } or nil,
        }
        self.interpreter:reset()

        if not release_input then
            self:_advance_if_chain_ready(start_t, action_settings)
        end
    end

    return true
end

function SequenceController:_charge_ready(start_t, action_settings)
    local goal = self:_goal()
    local action_kind = action_settings and action_settings.kind

    if
        not goal
        or goal.command ~= 'charged'
        or type(action_kind) ~= 'string'
        or not string.find(action_kind, 'charge', 1, true)
    then
        return true
    end

    local threshold = (self.profile and self.profile.auto_charge_threshold or 100) / 100
    local charge_level, max_charge, charge_start_t = WeaponContext.charge_state(self.context)
    local keep_charge = action_settings.keep_charge

    if charge_start_t and start_t and charge_start_t < start_t and not keep_charge then
        return false
    end

    local required_charge = threshold * (max_charge or 1)
    return charge_level >= required_charge
end

function SequenceController:_goal_program()
    local goal = self:_goal()

    if not goal then
        return nil
    end

    local terminal = self:_terminal_program()
    if terminal then
        return terminal.inputs
    end

    local action_name, start_t, action_settings = WeaponContext.action(self.context)
    local action_token = _action_token(action_name, start_t)
    local armed_program = self.sequence.program
    if armed_program and armed_program.kind == 'chain' then
        if armed_program.token == action_token then
            return armed_program.inputs
        end

        armed_program.kind = 'normal'
        armed_program.token = nil
    end

    local used_input = self:_started_input(action_token)
    local progress = action_name == 'idle' and 0
        or _matched_input_index(goal, action_name, action_settings, self.context, used_input)

    if progress == nil and action_settings then
        local first_input = goal.inputs and goal.inputs[1]
        local can_start = first_input and WeaponContext.can_chain(action_settings, start_t, first_input, self.context)
        if not can_start and first_input and not self.activation.secondary then
            can_start = WeaponContext.can_buffer_input(action_settings, first_input, self.context)
        end

        progress = can_start and 0 or nil
    end

    if progress == nil or not self:_charge_ready(start_t, action_settings) then
        return nil
    end

    local program = ActionSemantics.program_after(goal, progress)
    local next_input = program and program[1]
    local can_chain = progress == 0
        or next_input and WeaponContext.can_chain(action_settings, start_t, next_input, self.context)
    local can_buffer = next_input
        and (not ActionSemantics.is_attack_start_input(next_input) or not self.activation.secondary)
        and WeaponContext.can_buffer_input(action_settings, next_input, self.context)

    return (can_chain or can_buffer) and program or nil
end

function SequenceController:_sync_interpreter(frame_inputs)
    local extension = self.context and self.context.extension
    local t = extension and extension._last_fixed_t
        or Managers and Managers.time and Managers.time:time('gameplay')
        or 0
    local frame = extension and extension._last_fixed_frame or t
    local sequence = self.sequence
    local action_name, start_t, action_settings = WeaponContext.action(self.context)
    local action_token = _action_token(action_name, start_t)
    local action_started = self.action.started and self.action.started.token == action_token
    local started_input = self:_started_input(action_token)
    local program = sequence.program
    if self.pending_transition and self.interpreter:has_submitted() then
        return nil, t
    end
    if program and program.inputs then
        self.interpreter:update(t, frame)
    end
    if self.pending_transition and self.interpreter:has_submitted() then
        return nil, t
    end

    local resolved_inputs
    if self:_terminal_program() then
        if not program.inputs then
            return nil, t
        end
    else
        local candidate = self:_goal_program()
        local resolved_candidate = candidate
                and self:_resolved_inputs(candidate, frame_inputs, started_input, action_settings, start_t)
            or nil
        local candidate_input = resolved_candidate and resolved_candidate[1]
        local active_input = self.interpreter:active_input_name()

        if not program then
            if not candidate then
                return nil, t
            end
            program = { kind = 'normal', inputs = candidate }
            sequence.program = program
        elseif
            program.kind == 'normal'
            and candidate_input
            and active_input ~= candidate_input
            and (self.interpreter:has_submitted() or action_started)
        then
            program = { kind = 'normal', inputs = candidate }
            sequence.program = program
        end

        if candidate == program.inputs then
            resolved_inputs = resolved_candidate
        end
    end

    if not program or not program.inputs then
        return nil, t
    end

    resolved_inputs = resolved_inputs
        or self:_resolved_inputs(program.inputs, frame_inputs, started_input, action_settings, start_t)
    self.interpreter:set_program(
        self.context and self.context.template,
        resolved_inputs,
        t,
        self.input_settings,
        action_started and start_t or t
    )
    self.interpreter:update(t, frame)

    return self.interpreter:active_input_name(), t, frame
end

function SequenceController:_override_input(action_name, raw_value, frame_inputs)
    if self.interpreter:is_missing_sequence() then
        return raw_value
    end

    local target, t, frame = self:_sync_interpreter(frame_inputs)
    local terminal = self:_terminal_program()
    local terminal_blocks_primary = false
    if terminal and not terminal.release_input then
        local current_action, start_t = WeaponContext.action(self.context)
        terminal_blocks_primary = terminal.token == _action_token(current_action, start_t)
    end

    local waiting_for_attack_start = false
    if not target and not self.activation.secondary then
        local goal = self:_goal()
        local first_input = goal and goal.inputs and goal.inputs[1]
        local _, _, action_settings = WeaponContext.action(self.context)
        waiting_for_attack_start = ActionSemantics.is_attack_start_input(first_input)
            and WeaponContext.has_chain(action_settings, first_input)
    end

    if
        _is_primary_input(action_name)
        and (
            terminal_blocks_primary
            or waiting_for_attack_start
            or target == 'block'
            or ActionSemantics.is_special_input(target) and not self.interpreter:controls(action_name)
        )
    then
        return false
    end

    if target and self.interpreter:can_interpret() then
        return self.interpreter:value(action_name, raw_value, t, frame)
    end

    return raw_value
end

function SequenceController:_restore_after_no_repeat()
    local sequence = self.sequence
    if sequence.index or sequence.plan.goal_cycle_index > 0 or sequence.no_repeat_restored then
        return false
    end

    sequence.no_repeat_restored = true
    self.mode_manager:toggle()

    return true
end

function SequenceController:handle_input(input)
    local action_name = input.action_name
    local raw_value = input.value

    if action_name == 'toggle_ads' then
        self.input_settings.toggle_ads = not not raw_value

        return raw_value
    end

    local context = self:_refresh_context()
    local toggle_ads = self.input_settings.toggle_ads
    local aim_mode

    if context.kind == 'RANGED' then
        if action_name == 'action_two_hold' and not toggle_ads then
            aim_mode = raw_value and 'ads' or 'hip'
        elseif action_name == 'action_two_pressed' and toggle_ads and raw_value then
            aim_mode = self.aim_mode == 'ads' and 'hip' or 'ads'
        end
    end

    if aim_mode and self.aim_mode ~= aim_mode then
        local primary_active = self.activation.primary
        self.aim_mode = aim_mode
        self.context_key = nil
        context = self:_refresh_context()
        self.activation.primary = primary_active
    end

    if input.primary_pressed and input.secondary_held and context.kind == 'MELEE' then
        self:reset()

        return raw_value
    end

    if action_name == 'action_two_hold' then
        if context.kind == 'MELEE' and input.secondary_pressed then
            self:reset()

            return raw_value
        end

        self.activation.secondary = input.secondary_held
    elseif action_name == 'action_two_pressed' and toggle_ads and raw_value then
        self.activation.secondary = self.aim_mode == 'ads'
    end

    local has_goals = self.sequence.plan.goals and #self.sequence.plan.goals > 0

    if not has_goals then
        return raw_value
    end

    local current_action, start_t, action_settings = WeaponContext.action(context)
    local preserve_primary_hold = action_settings and action_settings.kind == 'vent_overheat'
    local previous_primary_active = self.activation.primary
    local released_primary = false

    if action_name == 'action_one_hold' then
        self.activation.primary = preserve_primary_hold and not input.primary_held and previous_primary_active
            or input.primary_held
        released_primary = previous_primary_active and not self.activation.primary
    elseif input.primary_pressed then
        local manual_push = context.kind == 'MELEE' and input.secondary_held

        if not manual_push then
            if not previous_primary_active then
                local goal = self:_goal()
                local program = ActionSemantics.program_after(goal, 0)
                local first_input = program and program[1]
                local can_restart = current_action ~= 'idle'
                    and first_input
                    and WeaponContext.can_chain(action_settings, start_t, first_input, context)

                if can_restart then
                    self.sequence.program = {
                        kind = 'chain',
                        token = _action_token(current_action, start_t),
                        inputs = program,
                    }
                end
            end

            self.activation.primary = true
        end
    end

    if released_primary then
        self:_reset_sequence()
        return raw_value
    end

    self:_maybe_advance_goal()

    if self:_restore_after_no_repeat() then
        return raw_value
    end

    if not self.sequence.index then
        return raw_value
    end

    if not self.activation.primary and not self:is_active() then
        return raw_value
    end

    return self:_override_input(action_name, raw_value, input.frame_inputs)
end

function SequenceController:update()
    self:_refresh_context()

    local has_goals = self.sequence.plan.goals and #self.sequence.plan.goals > 0
    if has_goals and (self.activation.primary or self.activation.secondary) then
        self:_maybe_advance_goal()
    else
        self:_restore_after_no_repeat()
    end
end

return SequenceController
