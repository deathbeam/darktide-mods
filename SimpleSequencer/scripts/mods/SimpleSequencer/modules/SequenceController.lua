local mod = get_mod('SimpleSequencer')
local Profiles = mod:io_dofile('SimpleSequencer/scripts/mods/SimpleSequencer/modules/SequenceProfiles')
local WeaponContext = mod:io_dofile('SimpleSequencer/scripts/mods/SimpleSequencer/modules/WeaponContext')
local ActionSemantics = mod:io_dofile('SimpleSequencer/scripts/mods/SimpleSequencer/modules/ActionSemantics')
local SequenceInterpreter = mod:io_dofile('SimpleSequencer/scripts/mods/SimpleSequencer/modules/SequenceInterpreter')
local SequenceController = class('SimpleSequencerSequenceController')

local BLOCK_INPUT = 'block'

local SEQUENCE_INPUTS = {
    action_one_pressed = true,
    action_one_hold = true,
    action_two_pressed = true,
    action_two_hold = true,
    weapon_extra_pressed = true,
    weapon_extra_hold = true,
    weapon_reload_hold = true,
    quick_wield = true,
}

local PRIMARY_INPUTS = {
    action_one_pressed = true,
    action_one_hold = true,
}

local SPECIAL_INPUTS = {
    special_action = true,
    special_action_hold = true,
    special_action_light = true,
    special_action_heavy = true,
    special_action_execute = true,
    special_action_pistol_whip = true,
    special_action_push = true,
    weapon_special = true,
    zoom_weapon_special = true,
}

local function _action_token(action, start_t)
    if not action or action == 'idle' then
        return 'idle'
    end

    return action .. ':' .. tostring(start_t or 0)
end

local function _game_time(context)
    local extension = context and context.extension
    local fixed_time = extension and extension._last_fixed_t

    if fixed_time then
        return fixed_time
    end

    return Managers and Managers.time and Managers.time:time('gameplay') or 0
end

local function _game_frame(context)
    local extension = context and context.extension

    return extension and extension._last_fixed_frame or _game_time(context)
end

local function _terminal_release_input(goal, template)
    local inputs = goal and goal.inputs
    local action_inputs = template and template.action_inputs
    local entries = template and template.action_input_hierarchy

    if not inputs or type(entries) ~= 'table' then
        return nil
    end

    for _, input in ipairs(inputs) do
        local transition
        for _, entry in ipairs(entries) do
            if entry.input == input then
                transition = entry.transition
                break
            end
        end

        if type(transition) ~= 'table' then
            return nil
        end

        entries = transition
    end

    for _, entry in ipairs(entries) do
        local input = entry.input
        local config = input and action_inputs and action_inputs[input]

        if config and config.dont_queue and entry.transition == 'base' then
            return input
        end
    end
end

local function _requires_held_primary(template, input_name, input_settings)
    local action_inputs = template and template.action_inputs
    local config = action_inputs and action_inputs[input_name]
    local element = config and config.input_sequence and config.input_sequence[1]
    local input_setting = element and element.input_setting
    local active_element = element

    if input_setting and input_settings and input_settings[input_setting.setting] == input_setting.setting_value then
        active_element = input_setting
    end

    if not active_element then
        return false
    end

    if active_element.input == 'action_one_hold' and active_element.value == true then
        return true
    end

    for _, input in ipairs(active_element.inputs or {}) do
        if input.input == 'action_one_hold' and input.value == true then
            return true
        end
    end

    return false
end

local function _following_inputs(inputs, index)
    if not inputs then
        return nil
    end

    local following = {}
    for input_index = index, #inputs do
        following[#following + 1] = inputs[input_index]
    end

    return #following > 0 and following or nil
end

local function _transition_after(template, inputs, target_index)
    local entries = template and template.action_input_hierarchy
    if not entries then
        return nil
    end

    for input_index = 1, target_index do
        local transition
        for _, entry in ipairs(entries) do
            if entry.input == inputs[input_index] then
                transition = entry.transition
                break
            end
        end

        if not transition then
            return nil
        elseif input_index == target_index then
            return transition
        elseif type(transition) ~= 'table' then
            return nil
        end

        entries = transition
    end
end

local function _program_followups(goal, progress, template)
    local inputs = goal and goal.inputs
    local input_index = progress + 1
    local input_name = inputs and inputs[input_index]
    if not input_name then
        return nil
    end

    if input_name == 'start_attack' then
        local followup_input = inputs[input_index + 1]
        return followup_input and { followup_input } or nil
    end

    if progress == 0 then
        return nil
    end

    local followups = {}
    while input_index < #inputs do
        local transition = _transition_after(template, inputs, input_index)
        local next_input = inputs[input_index + 1]
        local nested = false

        if type(transition) == 'table' then
            for _, entry in ipairs(transition) do
                if entry.input == next_input then
                    nested = true
                    break
                end
            end
        end

        if not nested then
            break
        end

        followups[#followups + 1] = next_input
        input_index = input_index + 1
    end

    return #followups > 0 and followups or nil
end

local function _empty_plan()
    return {
        goals = {},
        goal_cycle_index = 0,
        unresolved_steps = {},
    }
end

function SequenceController:_terminal_transition()
    local transition = self.sequence.transition

    return transition and transition.kind == 'terminal' and transition or nil
end

function SequenceController:init(mod, mode_manager)
    self.mod = mod
    self.mode_manager = mode_manager
    self.sequence = {
        index = 1,
        plan = _empty_plan(),
        no_repeat_restored = false,
        transition = nil,
        program = nil,
        program_is_terminal = false,
    }
    self.action = {
        started = nil,
        window_token = nil,
    }
    self.context = nil
    self.context_key = nil
    self.activation = { primary = false, secondary = false }
    self.aim_mode = 'hip'
    self.input_settings = { toggle_ads = false }
    self.interpreter = SequenceInterpreter:new()
end

function SequenceController:invalidate()
    self.context_key = nil
end

function SequenceController:is_active()
    return self:_goal() ~= nil
        and not self.interpreter:is_missing_sequence()
        and (self.activation.primary or self.activation.secondary)
end

function SequenceController:can_switch_mode()
    local action_name, start_t, action_settings = WeaponContext.action(self.context)

    if not action_name or action_name == 'idle' then
        return true
    end

    local goal = self:_goal()
    local progress = ActionSemantics.matched_input_index(
        goal,
        action_settings and action_settings.start_input,
        action_name,
        self.context and self.context.template,
        self:_started_input(_action_token(action_name, start_t))
    )
    local next_input = progress and goal.inputs[progress + 1]

    return next_input and WeaponContext.can_chain(action_settings, start_t, next_input, self.context) or false
end

function SequenceController:_goal()
    return self.sequence.index and self.sequence.plan.goals and self.sequence.plan.goals[self.sequence.index]
end

function SequenceController:_pending_goal_input()
    local goal = self:_goal()
    if not goal or self:_terminal_transition() then
        return nil
    end

    local action_name, start_t, action_settings = WeaponContext.action(self.context)
    if action_name == 'idle' then
        return goal.inputs and goal.inputs[1] or nil
    end

    local progress = ActionSemantics.matched_input_index(
        goal,
        action_settings and action_settings.start_input,
        action_name,
        self.context and self.context.template,
        self:_started_input(_action_token(action_name, start_t))
    )

    return progress and goal.inputs and goal.inputs[progress + 1] or nil
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

function SequenceController:_damage_window_closed(action_name, start_t, action_settings)
    if action_settings and action_settings.kind == 'sweep' and action_settings.damage_window_end then
        return self.action.window_token == _action_token(action_name, start_t)
    end

    return true
end

function SequenceController:_advance_if_chain_ready(start_t, action_settings)
    local next_goal = self:_next_goal()
    local action_name = WeaponContext.action(self.context)
    if not self:_damage_window_closed(action_name, start_t, action_settings) then
        return false
    end

    local next_progress = ActionSemantics.matched_input_index(
        next_goal,
        action_settings and action_settings.start_input,
        action_name,
        self.context and self.context.template,
        self:_started_input(_action_token(action_name, start_t))
    )

    if next_goal and next_progress == #(next_goal.inputs or {}) then
        next_progress = 0
    end
    local next_input = next_goal and next_goal.inputs and next_goal.inputs[(next_progress or 0) + 1]

    local can_chain = next_input and WeaponContext.can_chain(action_settings, start_t, next_input, self.context)
    local can_buffer = next_input
        and next_input ~= 'start_attack'
        and WeaponContext.can_buffer_input(action_settings, start_t, next_input, self.context)

    if not (can_chain or can_buffer) then
        return false
    end

    self:_advance()
    self.sequence.transition = {
        kind = 'chain',
        token = _action_token(action_name, start_t),
        input = next_input,
        followup = _program_followups(next_goal, next_progress or 0, self.context and self.context.template),
    }

    return true
end

function SequenceController:reset()
    local sequence = self.sequence
    self.activation.primary = false
    self.activation.secondary = false
    sequence.index = 1
    sequence.no_repeat_restored = false
    sequence.transition = nil
    sequence.program = nil
    sequence.program_is_terminal = false
    self.action.started = nil
    self.action.window_token = nil
    self.interpreter:reset()
end

function SequenceController:_started_input(action_token)
    local started = self.action.started

    return started and started.token == action_token and started.input or nil
end

-- Action start events are the authoritative progress signal; polling only fills gaps.
function SequenceController:on_action_started(action_name, t)
    if not action_name or action_name == 'none' then
        return
    end

    self.action.started = {
        token = _action_token(action_name, t),
        input = self.interpreter:action_input_name(),
    }
end

function SequenceController:on_damage_window_exited()
    local action_name, start_t, action_settings = WeaponContext.action(self.context)

    if action_settings and action_settings.kind == 'sweep' and action_settings.damage_window_end then
        self.action.window_token = _action_token(action_name, start_t)
    end
end

function SequenceController:on_slot_wielded()
    self.context = WeaponContext.read()
    self:reset()
    self:invalidate()
end

function SequenceController:_refresh_context()
    local context = WeaponContext.read()

    context.aim_mode = self.aim_mode
    self.context = context

    local key = self.mode_manager:active() .. ':' .. context.kind .. ':' .. context.name .. ':' .. self.aim_mode

    if self.context_key == key then
        return context
    end

    self.context_key = key
    self.sequence.plan = _empty_plan()

    local profile = context.kind ~= 'none' and self.mode_manager:profile(context.kind, context.name)

    if profile then
        local sequence = Profiles.build_sequence(profile, context.kind, self.aim_mode)
        local plan = ActionSemantics.compile(sequence, context)
        self.sequence.plan = plan

        if #plan.unresolved_steps > 0 and self.mod.info then
            local unresolved = {}

            for _, step in ipairs(plan.unresolved_steps) do
                unresolved[#unresolved + 1] = step.command
            end

            self.mod:info('[planner] unresolved steps for ' .. context.name .. ': ' .. table.concat(unresolved, ', '))
        end
        self.profile = profile
    else
        self.profile = nil
    end

    self:reset()

    return context
end

function SequenceController:_advance()
    local sequence = self.sequence
    local goals = sequence.plan.goals

    if not goals or #goals == 0 then
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

    sequence.transition = nil
    sequence.program = nil
    sequence.program_is_terminal = false
    self.interpreter:reset()
end

function SequenceController:_maybe_advance_goal()
    local goal = self:_goal()

    if not goal then
        return false
    end

    local action_name, start_t, action_settings = WeaponContext.action(self.context)

    if action_name == 'idle' then
        if self:_terminal_transition() then
            self:_advance()
        end

        return true
    end

    local start_input = action_settings and action_settings.start_input
    local used_input = self:_started_input(_action_token(action_name, start_t))
    local progress = ActionSemantics.matched_input_index(
        goal,
        start_input,
        action_name,
        self.context and self.context.template,
        used_input
    )

    if not progress then
        return false
    end

    local action_token = _action_token(action_name, start_t)

    local transition = self.sequence.transition
    if transition and transition.kind == 'chain' then
        if transition.token == action_token then
            return true
        end

        self.sequence.transition = nil
    end

    local terminal = self:_terminal_transition()
    if terminal then
        if action_token ~= terminal.token then
            self:_advance()
        elseif terminal.release_input then
            if self.interpreter.submitted then
                self:_advance_if_chain_ready(start_t, action_settings)
            end
        else
            self:_advance_if_chain_ready(start_t, action_settings)
        end

        return true
    end

    if progress == #(goal.inputs or {}) then
        local release_input = self:_next_goal()
            and _terminal_release_input(goal, self.context and self.context.template)
        self.sequence.transition = {
            kind = 'terminal',
            token = action_token,
            release_input = release_input,
        }

        if not release_input then
            self:_advance_if_chain_ready(start_t, action_settings)
        end
    end

    return true
end

function SequenceController:_charge_ready(start_t, action_settings)
    local goal = self:_goal()
    local action_kind = action_settings and action_settings.kind

    if not goal or goal.command ~= 'charged' or not action_kind or not string.find(action_kind, 'charge', 1, true) then
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

function SequenceController:_goal_input()
    local goal = self:_goal()

    if not goal then
        return nil
    end

    local terminal = self:_terminal_transition()
    if terminal then
        return terminal.release_input or goal.command == BLOCK_INPUT and BLOCK_INPUT or nil
    end

    local action_name, start_t, action_settings = WeaponContext.action(self.context)
    local action_token = _action_token(action_name, start_t)
    local transition = self.sequence.transition
    if transition and transition.kind == 'chain' then
        if transition.token == action_token then
            return transition.input, transition.followup
        end

        self.sequence.transition = nil
    end

    local used_input = self:_started_input(action_token)
    local progress = action_name == 'idle' and 0
        or ActionSemantics.matched_input_index(
            goal,
            action_settings and action_settings.start_input,
            action_name,
            self.context and self.context.template,
            used_input
        )

    if progress == nil and action_settings then
        local first_input = goal.inputs and goal.inputs[1]
        local can_start = first_input and WeaponContext.can_chain(action_settings, start_t, first_input, self.context)

        progress = can_start and 0 or nil
    end

    if progress == nil then
        return nil
    end

    if not self:_charge_ready(start_t, action_settings) then
        return nil
    end

    local next_input = goal.inputs[progress + 1]
    local followup_inputs = _program_followups(goal, progress, self.context and self.context.template)
    local can_chain = progress == 0
        or next_input and WeaponContext.can_chain(action_settings, start_t, next_input, self.context)
    local can_buffer = next_input
        and next_input ~= 'start_attack'
        and WeaponContext.can_buffer_input(action_settings, start_t, next_input, self.context)

    if can_chain or can_buffer then
        return next_input, followup_inputs
    end
end

function SequenceController:_sync_interpreter()
    local t = _game_time(self.context)
    local frame = _game_frame(self.context)
    local sequence = self.sequence
    local program = sequence.program
    if program then
        self.interpreter:update(t, frame)
    end

    local terminal = self:_terminal_transition()
    if terminal then
        local release_input = terminal.release_input or self:_goal().command == BLOCK_INPUT and BLOCK_INPUT or nil
        if not release_input then
            return nil, t
        end

        if not sequence.program_is_terminal or not program or #program ~= 1 or program[1] ~= release_input then
            program = { release_input }
            sequence.program = program
            sequence.program_is_terminal = true
            self.interpreter:reset()
        end
    else
        local input_name, followup_inputs = self:_goal_input()
        local active_input = self.interpreter:active_input_name()
        if not program or self.interpreter.submitted and input_name and active_input ~= input_name then
            if not input_name then
                return nil, t
            end

            program = { input_name }
            for _, followup_input in ipairs(followup_inputs or {}) do
                program[#program + 1] = followup_input
            end
            sequence.program = program
            sequence.program_is_terminal = false
        end
    end

    if not program then
        return nil, t
    end

    local _, start_t = WeaponContext.action(self.context)
    self.interpreter:set_target(
        self.context and self.context.template,
        program[1],
        t,
        self.input_settings,
        start_t,
        _following_inputs(program, 2)
    )
    self.interpreter:update(t, frame)

    return self.interpreter:active_input_name(), t, frame
end

function SequenceController:_override_input(action_name, raw_value)
    if self.interpreter:is_missing_sequence() then
        return raw_value
    end

    local target, t, frame = self:_sync_interpreter()
    local terminal = self:_terminal_transition()
    local preserve_primary_hold = not target
        and action_name == 'action_one_hold'
        and raw_value
        and _requires_held_primary(
            self.context and self.context.template,
            self:_pending_goal_input(),
            self.input_settings
        )

    if
        PRIMARY_INPUTS[action_name]
        and (
            terminal and not terminal.release_input
            or not target and not self.activation.secondary and not preserve_primary_hold
            or target == BLOCK_INPUT
            or SPECIAL_INPUTS[target] and not self.interpreter:controls(action_name)
        )
    then
        return false
    end

    if target and self.interpreter:can_interpret() then
        return self.interpreter:value(action_name, raw_value, t, frame)
    end

    if target and self.interpreter:is_missing_sequence() and self.mod.info then
        self.mod:info('[interpreter] missing input_sequence for ' .. tostring(target))
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

    if not SEQUENCE_INPUTS[action_name] then
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
                local first_input = goal and goal.inputs and goal.inputs[1]
                local can_restart = current_action ~= 'idle'
                    and first_input
                    and WeaponContext.can_chain(action_settings, start_t, first_input, context)

                if can_restart then
                    self.sequence.transition = {
                        kind = 'chain',
                        token = _action_token(current_action, start_t),
                        input = first_input,
                        followup = _program_followups(goal, 0, context and context.template),
                    }
                end
            end

            self.activation.primary = true
        end
    end

    if released_primary then
        self:reset()
        return raw_value
    end

    self:_maybe_advance_goal()

    if self:_restore_after_no_repeat() then
        return raw_value
    end

    if not self.sequence.index then
        if PRIMARY_INPUTS[action_name] then
            return false
        end

        return raw_value
    end

    if not self.activation.primary and not self:is_active() then
        return raw_value
    end

    return self:_override_input(action_name, raw_value)
end

function SequenceController:update()
    self:_refresh_context()

    local has_goals = self.sequence.plan.goals and #self.sequence.plan.goals > 0

    if has_goals then
        self:_maybe_advance_goal()
    end

    if self:is_active() then
        self:_sync_interpreter()
    else
        self:_restore_after_no_repeat()
    end
end

return SequenceController
