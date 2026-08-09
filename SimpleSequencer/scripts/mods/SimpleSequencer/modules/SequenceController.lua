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

local function _empty_plan()
    return {
        goals = {},
        goal_cycle_index = 0,
        unresolved_steps = {},
    }
end

function SequenceController:init(mod, mode_manager)
    self.mod = mod
    self.mode_manager = mode_manager
    self.index = 1
    self.plan = _empty_plan()
    self.context = nil
    self.context_key = nil
    self.primary_down = false
    self.secondary_down = false
    self.primary_release_required = false
    self.aim_mode = 'hip'
    self.input_settings = { toggle_ads = false }
    self.no_repeat_restored = false
    self.goal_terminal_token = nil
    self.terminal_release_input = nil
    self.chain_origin_token = nil
    self.chain_origin_input = nil
    self.chain_origin_followup = nil
    self.input_override_blocked = false
    self.action_event_token = nil
    self.action_event_input = nil
    self.damage_window_exit_token = nil
    self.interpreter = SequenceInterpreter:new()
end

function SequenceController:invalidate()
    self.context_key = nil
end

function SequenceController:is_active()
    return self:_goal() ~= nil and not self.input_override_blocked and (self.primary_down or self.secondary_down)
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
        self:_event_input(_action_token(action_name, start_t))
    )
    local next_input = progress and goal.inputs[progress + 1]

    return next_input and WeaponContext.can_chain(action_settings, start_t, next_input, self.context) or false
end

function SequenceController:_goal()
    return self.index and self.plan.goals and self.plan.goals[self.index]
end

function SequenceController:_pending_goal_input()
    local goal = self:_goal()
    if not goal or self.goal_terminal_token then
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
        self:_event_input(_action_token(action_name, start_t))
    )

    return progress and goal.inputs and goal.inputs[progress + 1] or nil
end

function SequenceController:_next_goal()
    local goals = self.plan.goals
    local next_index = self.index and self.index + 1

    if not next_index or not goals then
        return nil
    end

    if next_index > #goals then
        next_index = self.plan.goal_cycle_index > 0 and self.plan.goal_cycle_index or nil
    end

    return next_index and goals[next_index]
end

function SequenceController:_damage_window_closed(action_name, start_t, action_settings)
    if action_settings and action_settings.kind == 'sweep' and action_settings.damage_window_end then
        return self.damage_window_exit_token == _action_token(action_name, start_t)
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
        self:_event_input(_action_token(action_name, start_t))
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
    self.chain_origin_token = _action_token(action_name, start_t)
    self.chain_origin_input = next_input
    self.chain_origin_followup = next_input == 'start_attack' and next_goal.inputs[(next_progress or 0) + 2] or nil

    return true
end

function SequenceController:reset()
    self.primary_down = false
    self.secondary_down = false
    self.primary_release_required = false
    self.index = 1
    self.no_repeat_restored = false
    self.goal_terminal_token = nil
    self.terminal_release_input = nil
    self.chain_origin_token = nil
    self.chain_origin_input = nil
    self.chain_origin_followup = nil
    self.input_override_blocked = false
    self.action_event_token = nil
    self.action_event_input = nil
    self.damage_window_exit_token = nil
    self.interpreter:reset()
end

function SequenceController:_event_input(action_token)
    return self.action_event_token == action_token and self.action_event_input or nil
end

-- Action start events are the authoritative progress signal; polling only fills gaps.
function SequenceController:on_action_started(action_name, t)
    if not action_name or action_name == 'none' then
        return
    end

    self.action_event_token = _action_token(action_name, t)
    self.action_event_input = self.interpreter:active_input_name()
end

function SequenceController:on_damage_window_exited()
    local action_name, start_t, action_settings = WeaponContext.action(self.context)

    if action_settings and action_settings.kind == 'sweep' and action_settings.damage_window_end then
        self.damage_window_exit_token = _action_token(action_name, start_t)
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
    self.plan = _empty_plan()

    local profile = context.kind ~= 'none' and self.mode_manager:profile(context.kind, context.name)

    if profile then
        local sequence = Profiles.build_sequence(profile, context.kind, self.aim_mode)
        self.plan = ActionSemantics.compile(sequence, context)

        if #self.plan.unresolved_steps > 0 and self.mod.info then
            local unresolved = {}

            for _, step in ipairs(self.plan.unresolved_steps) do
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
    local goals = self.plan.goals

    if not goals or #goals == 0 then
        return
    end

    if self.index >= #goals then
        if self.plan.goal_cycle_index > 0 then
            self.index = self.plan.goal_cycle_index
        else
            self.index = nil
        end
    else
        self.index = self.index + 1
    end

    self.goal_terminal_token = nil
    self.terminal_release_input = nil
    self.input_override_blocked = false
    self.interpreter:reset()
    self.chain_origin_token = nil
    self.chain_origin_input = nil
    self.chain_origin_followup = nil
end

function SequenceController:_maybe_advance_goal()
    local goal = self:_goal()

    if not goal then
        return false
    end

    local action_name, start_t, action_settings = WeaponContext.action(self.context)

    if action_name == 'idle' then
        if self.goal_terminal_token then
            self:_advance()
        end

        return true
    end

    local start_input = action_settings and action_settings.start_input
    local used_input = self:_event_input(_action_token(action_name, start_t))
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

    if self.chain_origin_token == action_token then
        return true
    end

    if self.chain_origin_token then
        self.chain_origin_token = nil
    end

    if self.goal_terminal_token then
        if action_token ~= self.goal_terminal_token then
            self:_advance()
        elseif self.terminal_release_input then
            if self.interpreter.submitted then
                self:_advance_if_chain_ready(start_t, action_settings)
            end
        else
            self:_advance_if_chain_ready(start_t, action_settings)
        end

        return true
    end

    if progress == #(goal.inputs or {}) then
        self.goal_terminal_token = action_token
        self.terminal_release_input = self:_next_goal()
            and _terminal_release_input(goal, self.context and self.context.template)

        if not self.terminal_release_input then
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

    if self.goal_terminal_token then
        return self.terminal_release_input or goal.command == BLOCK_INPUT and BLOCK_INPUT or nil
    end

    local action_name, start_t, action_settings = WeaponContext.action(self.context)
    local action_token = _action_token(action_name, start_t)

    if self.chain_origin_token == action_token then
        return self.chain_origin_input, self.chain_origin_followup
    elseif self.chain_origin_token then
        self.chain_origin_token = nil
        self.chain_origin_input = nil
        self.chain_origin_followup = nil
    end
    local used_input = self:_event_input(action_token)
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
    local followup_input = next_input == 'start_attack' and goal.inputs[progress + 2] or nil
    local can_chain = progress == 0
        or next_input and WeaponContext.can_chain(action_settings, start_t, next_input, self.context)
    local can_buffer = next_input
        and next_input ~= 'start_attack'
        and WeaponContext.can_buffer_input(action_settings, start_t, next_input, self.context)

    if can_chain or can_buffer then
        return next_input, followup_input
    end
end

function SequenceController:_sync_interpreter()
    local t = _game_time(self.context)
    local target, followup_input = self:_goal_input()
    local _, start_t = WeaponContext.action(self.context)
    local followup_inputs = followup_input and { followup_input } or nil

    self.interpreter:set_target(
        self.context and self.context.template,
        target,
        t,
        self.input_settings,
        start_t,
        followup_inputs
    )

    return target, t
end

function SequenceController:_override_input(action_name, raw_value)
    if self.input_override_blocked then
        return raw_value
    end

    local target, t = self:_sync_interpreter()
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
            self.goal_terminal_token and not self.terminal_release_input
            or not target and not self.secondary_down and not preserve_primary_hold
            or target == BLOCK_INPUT
            or SPECIAL_INPUTS[target] and not self.interpreter:controls(action_name)
        )
    then
        return false
    end

    if target and self.interpreter:can_interpret() then
        return self.interpreter:value(action_name, raw_value, t)
    end

    if target then
        self.input_override_blocked = true

        if self.mod.info then
            self.mod:info('[interpreter] missing input_sequence for ' .. tostring(target))
        end
    end

    return raw_value
end

function SequenceController:_restore_after_no_repeat()
    if self.index or self.plan.goal_cycle_index > 0 or self.no_repeat_restored then
        return false
    end

    self.no_repeat_restored = true
    self.mode_manager:toggle()

    return true
end

function SequenceController:handle_input(action_name, raw_value)
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
        local primary_down = self.primary_down
        self.aim_mode = aim_mode
        self.context_key = nil
        context = self:_refresh_context()
        self.primary_down = primary_down
    end

    if action_name == 'action_two_hold' then
        self.secondary_down = not not raw_value
    elseif action_name == 'action_two_pressed' and toggle_ads and raw_value then
        self.secondary_down = self.aim_mode == 'ads'
    end

    local has_goals = self.plan.goals and #self.plan.goals > 0

    if not has_goals then
        return raw_value
    end

    self:_maybe_advance_goal()

    local _, _, action_settings = WeaponContext.action(context)
    local preserve_primary_hold = action_settings and action_settings.kind == 'vent_overheat'

    local previous_primary_down = self.primary_down
    local released_primary = false

    if action_name == 'action_one_hold' then
        if self.primary_release_required then
            self.primary_down = false

            if not raw_value then
                self.primary_release_required = false
            end
        else
            self.primary_down = preserve_primary_hold and not raw_value and previous_primary_down or not not raw_value
        end

        released_primary = previous_primary_down and not self.primary_down
    elseif action_name == 'action_one_pressed' and raw_value then
        local push_input = context.kind == 'MELEE' and self.secondary_down

        if not push_input and not self.primary_release_required then
            self.primary_down = true
        end
    end

    if released_primary then
        self:reset()
        return raw_value
    end

    if self:_restore_after_no_repeat() then
        return raw_value
    end

    if not self.index then
        if PRIMARY_INPUTS[action_name] then
            return false
        end

        return raw_value
    end

    if not self.primary_down and not self:is_active() then
        return raw_value
    end

    return self:_override_input(action_name, raw_value)
end

function SequenceController:update()
    self:_refresh_context()

    local has_goals = self.plan.goals and #self.plan.goals > 0

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
