local mod = get_mod('SimpleSequencer')
local Profiles = mod:io_dofile('SimpleSequencer/scripts/mods/SimpleSequencer/modules/SequenceProfiles')
local WeaponContext = mod:io_dofile('SimpleSequencer/scripts/mods/SimpleSequencer/modules/WeaponContext')
local ActionSemantics = mod:io_dofile('SimpleSequencer/scripts/mods/SimpleSequencer/modules/ActionSemantics')
local SequenceEngine = class('SimpleSequencerSequenceEngine')

local INPUT_INTERRUPTS = {
    action_two_hold = true,
    weapon_extra_pressed = true,
    weapon_extra_hold = true,
    weapon_reload_hold = true,
    quick_wield = true,
    sprint = true,
}

local PRESERVE_PRIMARY_HOLD_ACTIONS = {
    vent_overheat = true,
}

local function _action_token(action, start_t)
    if action == 'idle' then
        return 'idle'
    end

    return action .. ':' .. tostring(start_t or 0)
end

local function _empty_plan()
    return {
        commands = {},
        cycle_index = 0,
        repeating = false,
        unresolved_steps = {},
    }
end

function SequenceEngine:init(mod, mode_manager)
    self.mod = mod
    self.mode_manager = mode_manager
    self.index = 1
    self.plan = _empty_plan()
    self.completed = false
    self.context = nil
    self.context_key = nil
    self.primary_down = false
    self.secondary_down = false
    self.primary_release_required = false
    self.primary_hold_pulse_token = nil
    self.ranged_mode = 'hip'
    self.last_action_token = nil
    self.previous_command = nil
    self.idle_match_index = nil
    self.fire_token = nil
    self.sweep_state = nil
    self.no_repeat_restored = false
    self.swap_cancel = nil
end

function SequenceEngine:invalidate()
    self.context_key = nil
end

function SequenceEngine:is_in_action()
    local action_name = WeaponContext.action(self.context)

    return action_name ~= 'idle'
end

function SequenceEngine:is_active()
    return (self.primary_down or self:_secondary_driver_active())
        and not self.completed
        and self.profile ~= nil
        and self:_command() ~= nil
end

function SequenceEngine:is_safe_to_switch_mode()
    local current_action, _, chain_ready = self:_current_action()

    return current_action == 'idle' or chain_ready
end

function SequenceEngine:_command()
    return self.index and self.plan.commands[self.index]
end

function SequenceEngine:_secondary_driver_active()
    local policy = ActionSemantics.command_policy(self:_command())
    return self.secondary_down and policy and policy.action_two_hold == true or false
end

function SequenceEngine:reset()
    self.primary_down = false
    self.secondary_down = false
    self.primary_release_required = false
    self.primary_hold_pulse_token = nil
    self.index = 1
    self.completed = false
    self.last_action_token = nil
    self.previous_command = nil
    self.idle_match_index = nil
    self.fire_token = nil
    self.sweep_state = nil
    self.no_repeat_restored = false
    self.swap_cancel = nil
end

function SequenceEngine:set_sweep_state(state)
    self.sweep_state = state
end

function SequenceEngine:on_slot_wielded()
    local context = WeaponContext.read()
    local swap_cancel = self.swap_cancel
    self.context = context

    if not swap_cancel then
        self:reset()
        self:invalidate()
        return
    end

    local at_origin = context.slot == swap_cancel.origin_slot

    if not at_origin then
        swap_cancel.returning = true
    elseif swap_cancel.returning then
        self.swap_cancel = nil
        self:_advance()
    end
end

function SequenceEngine:_refresh_context()
    local context = WeaponContext.read()
    self.context = context

    -- The temporary weapon must not replace the plan compiled for the origin weapon.
    if self.swap_cancel then
        return context
    end

    local key = self.mode_manager:active() .. ':' .. context.kind .. ':' .. context.name .. ':' .. self.ranged_mode

    if self.context_key == key then
        return context
    end

    self.context_key = key
    self.plan = _empty_plan()

    local profile = context.kind ~= 'none' and self.mode_manager:profile(context.kind, context.name)

    if profile then
        local profile_plan = Profiles.compile(profile, context.kind, self.ranged_mode)
        self.plan = ActionSemantics.plan(profile_plan, context)

        if #self.plan.unresolved_steps > 0 and self.mod.info then
            local unresolved = {}

            for _, step in ipairs(self.plan.unresolved_steps) do
                unresolved[#unresolved + 1] = step.command
            end

            self.mod:info('[planner] unresolved steps for ' .. context.name .. ': ' .. table.concat(unresolved, ', '))
        end
        self.profile = profile
        self.automatic_fire = context.kind == 'RANGED'
                and (self.ranged_mode == 'ads' and profile.automatic_fire_ads or profile.automatic_fire_hip)
            or nil
    else
        self.profile = nil
        self.automatic_fire = nil
    end

    self:reset()

    return context
end

function SequenceEngine:_current_action()
    local action_name, start_t, action_settings = WeaponContext.action(self.context)
    local command = self:_command()
    local current_action = ActionSemantics.classify_current(action_name, action_settings, command)
    local chain_ready = false

    local command_policy = ActionSemantics.command_policy(command)
    local heavy_windup_action = command_policy and command_policy.heavy_windup

    if
        heavy_windup_action
        and (current_action == 'start_attack' or current_action == 'special_start_attack')
        and WeaponContext.can_chain(action_settings, start_t, 'heavy_attack', self.context)
    then
        current_action = heavy_windup_action
    end

    if action_settings and action_settings.kind == 'sweep' and self.sweep_state == 'after_damage_window' then
        chain_ready = WeaponContext.can_chain(action_settings, start_t, 'start_attack', self.context)
    elseif current_action == 'light_attack' or current_action == 'heavy_attack' then
        chain_ready = WeaponContext.can_chain(action_settings, start_t, 'start_attack', self.context)
    elseif current_action == 'push' and command == 'idle' then
        -- Push actions expose the next chain before their nominal action end.
        local next_command = self.plan.commands[self.index + 1]

        if next_command then
            chain_ready = WeaponContext.can_chain(action_settings, start_t, next_command, self.context)
        end
    elseif current_action == 'shoot' then
        local chain_name = action_settings and action_settings.start_input or 'shoot_pressed'
        chain_ready = WeaponContext.can_chain(action_settings, start_t, chain_name, self.context)
    end

    return current_action, start_t, chain_ready, action_settings
end

function SequenceEngine:_charge_ready(start_t, action_settings)
    local threshold = (self.profile and self.profile.auto_charge_threshold or 100) / 100
    local charge_level, max_charge, charge_start_t = WeaponContext.charge_state(self.context)
    threshold = max_charge and math.min(threshold, max_charge) or threshold
    local keep_charge = action_settings and action_settings.keep_charge

    if charge_start_t and start_t and charge_start_t < start_t and not keep_charge then
        return false
    end

    return charge_level >= threshold
end

function SequenceEngine:_advance()
    local completed_command = self:_command()

    if completed_command then
        self.previous_command = completed_command
    end

    if self.index >= #self.plan.commands then
        if self.plan.cycle_index > 0 or self.plan.repeating then
            self.index = self.plan.cycle_index > 0 and self.plan.cycle_index or 1
            self.completed = false
        else
            self.index = nil
            self.completed = true
        end
    else
        self.index = self.index + 1
    end

    self.last_action_token = nil
    self.idle_match_index = nil
    self.fire_token = nil
end

function SequenceEngine:_maybe_advance(current_action, start_t, chain_ready, action_settings)
    local command = self:_command()
    if not command then
        return
    end
    if command == 'charge' and current_action == 'charge' and not self:_charge_ready(start_t, action_settings) then
        return
    end

    local matched_action = current_action

    if chain_ready and command == 'idle' then
        matched_action = 'idle'
    end

    -- Ranged weapons can enter their next charge action without an idle action; melee windups must finish first.
    local direct_chain = self.context.kind == 'RANGED'
        and self.previous_command
        and matched_action ~= self.previous_command

    if command == 'idle' and (matched_action == 'idle' or direct_chain) then
        if self.idle_match_index ~= self.index then
            self.idle_match_index = self.index
            self:_advance()
        end

        return
    end

    local action_matches = command == matched_action

    if not action_matches then
        return
    end

    local token = _action_token(current_action, start_t)

    if self.last_action_token ~= token then
        self.last_action_token = token
        self:_advance()
    end
end

function SequenceEngine:_restore_after_no_repeat()
    if not self.completed or self.plan.repeating or self.no_repeat_restored then
        return false
    end

    self.no_repeat_restored = true
    self.mode_manager:toggle()

    return true
end

function SequenceEngine:_required(command, action_name)
    local policy = ActionSemantics.command_policy(command)

    if not policy then
        return false
    end

    return policy[action_name] == true
end

function SequenceEngine:_should_reset_for_interrupt(action_name, value, command)
    if not value or not self.mod:get('reset_on_interrupt') or not INPUT_INTERRUPTS[action_name] then
        return false
    end

    if action_name == 'action_two_hold' and self.context.kind == 'RANGED' then
        return false
    end

    return not self:_required(command, action_name)
end

function SequenceEngine:_fire_pulse(current_action, raw_value, chain_ready)
    if raw_value then
        self.fire_token = self.index

        return true
    end

    local can_fire_after_charge = chain_ready
        or current_action == 'charge'
        or current_action == 'special_action'
        or current_action == 'special_light_attack'

    if (current_action ~= 'idle' and not can_fire_after_charge) or self.fire_token == self.index then
        return false
    end
    self.fire_token = self.index

    return true
end

function SequenceEngine:_primary_hold_pulse(raw_value, current_action, start_t, action_settings)
    if self.secondary_down then
        return raw_value
    end

    local chain_ready = WeaponContext.can_chain(action_settings, start_t, 'start_attack', self.context)
    if not chain_ready then
        return false
    end

    local action_token = _action_token(current_action, start_t)
    if self.primary_hold_pulse_token == action_token then
        return false
    end

    if raw_value then
        self.primary_hold_pulse_token = action_token
        return true
    end

    return false
end

function SequenceEngine:_override(
    action_name,
    raw_value,
    current_action,
    command,
    chain_ready,
    action_settings,
    start_t
)
    local policy = ActionSemantics.command_policy(command)
    if action_name == 'action_one_hold' then
        local hold_overrides = policy and policy.hold_overrides
        local current_action_override = hold_overrides and hold_overrides[current_action]

        if current_action_override == 'pulse' then
            return self:_primary_hold_pulse(raw_value, current_action, start_t, action_settings)
        elseif current_action_override ~= nil then
            return current_action_override
        elseif command == 'idle' then
            return false
        elseif command == 'charge' then
            return raw_value
        elseif policy and policy.suppress_primary_hold then
            return false
        end

        return self:_required(command, action_name) and true or raw_value
    end

    if action_name == 'action_one_pressed' then
        if command == 'idle' then
            return false
        end

        if policy and policy.suppress_primary_pressed then
            return false
        end

        if command == 'shoot' then
            return self:_fire_pulse(current_action, raw_value, chain_ready)
        end

        if command == 'start_attack' then
            return raw_value or current_action == 'idle'
        elseif command == 'light_attack' or command == 'push' or command == 'push_follow_up' then
            return raw_value
                or current_action == 'start_attack'
                or current_action == 'heavy_attack'
                or current_action == 'block'
                or current_action == 'push'
        end
    elseif action_name == 'action_two_hold' then
        local action_inputs = self.context and self.context.template and self.context.template.action_inputs
        local start_input = action_settings and action_settings.start_input
        local input_settings = start_input and action_inputs and action_inputs[start_input]
        local input_sequence = input_settings and input_settings.input_sequence
        local first_input = input_sequence and input_sequence[1] and input_sequence[1].input
        local primary_charge = first_input == 'action_one_hold'
        local aim_transition = action_settings and (action_settings.kind == 'aim' or action_settings.kind == 'unaim')
        local actions = self.context and self.context.template and self.context.template.actions
        if not primary_charge and not start_input then
            for _, settings in pairs(actions or {}) do
                local kind = settings.kind
                local start = settings.start_input
                local input = start and action_inputs and action_inputs[start]
                local sequence = input and input.input_sequence
                local first = sequence and sequence[1] and sequence[1].input
                if kind and string.find(kind, 'charge', 1, true) and first == 'action_one_hold' then
                    primary_charge = true
                    break
                end
            end
        end
        if primary_charge then
            return raw_value
        elseif aim_transition then
            return raw_value
        elseif command == 'shoot' and self.automatic_fire == 'charged' and current_action == 'charge' then
            return true
        elseif self:_required(command, action_name) then
            return true
        end
    elseif action_name == 'weapon_extra_pressed' or action_name == 'weapon_extra_hold' then
        if self:_required(command, action_name) then
            return true
        end
    elseif action_name == 'quick_wield' and self:_required(command, action_name) then
        if not self.swap_cancel then
            self.swap_cancel = { origin_slot = self.context.slot }
            self.sweep_state = nil
        end

        return true
    end

    return raw_value
end

function SequenceEngine:handle_input(action_name, raw_value)
    if
        action_name ~= 'action_one_pressed'
        and action_name ~= 'action_one_hold'
        and not INPUT_INTERRUPTS[action_name]
    then
        return raw_value
    end

    local context = self:_refresh_context()

    if not self.swap_cancel and action_name == 'action_two_hold' and context.kind == 'RANGED' then
        local ranged_mode = raw_value and 'ads' or 'hip'

        if self.ranged_mode ~= ranged_mode then
            local primary_down = self.primary_down
            self.ranged_mode = ranged_mode
            self.context_key = nil
            context = self:_refresh_context()
            local active_action, active_start_t = self:_current_action()
            if active_action ~= 'idle' then
                self.last_action_token = _action_token(active_action, active_start_t)
            end
            self.primary_down = primary_down
        end
    end

    if action_name == 'action_two_hold' then
        self.secondary_down = not not raw_value
    end

    local current_action, start_t, chain_ready, action_settings = self:_current_action()
    local preserve_primary_hold = action_settings and PRESERVE_PRIMARY_HOLD_ACTIONS[action_settings.kind]

    -- Automatic venting aborts the pending shot action, so held autofire must rearm afterward.
    if preserve_primary_hold then
        self.fire_token = nil
    end
    local previous_primary_down = self.primary_down
    local released_primary = false

    if action_name == 'action_one_hold' then
        if self.primary_release_required then
            self.primary_down = false
            if not raw_value then
                self.primary_release_required = false
            end
        else
            local hold_interrupted_by_action = preserve_primary_hold and not raw_value
            self.primary_down = hold_interrupted_by_action and previous_primary_down or not not raw_value
        end
        released_primary = previous_primary_down and not self.primary_down
    elseif action_name == 'action_one_pressed' and raw_value then
        local push_input = self.context.kind == 'MELEE' and self.secondary_down
        if not push_input and not self.primary_release_required then
            self.primary_down = true
        end
    end

    if released_primary then
        self:reset()
        return raw_value
    end

    self:_maybe_advance(current_action, start_t, chain_ready, action_settings)
    if self:_restore_after_no_repeat() then
        return raw_value
    end

    local command = self:_command()

    local auto_fire_without_primary = action_name == 'action_one_pressed'
        and self.context.kind == 'RANGED'
        and self.automatic_fire == 'charged'
        and command == 'shoot'
    if self.completed then
        if action_name == 'action_one_pressed' or action_name == 'action_one_hold' then
            return false
        end
        return raw_value
    end
    if not command or not self.profile then
        return raw_value
    end
    if self:_should_reset_for_interrupt(action_name, raw_value, command) then
        local halt_until_primary_release = action_name == 'action_two_hold' and self.context.kind == 'MELEE'
        self:reset()
        if action_name == 'action_two_hold' then
            self.secondary_down = not not raw_value
            self.primary_release_required = halt_until_primary_release
        end
        return raw_value
    end
    if not self.primary_down and not auto_fire_without_primary then
        return raw_value
    end
    return self:_override(action_name, raw_value, current_action, command, chain_ready, action_settings, start_t)
end

function SequenceEngine:update()
    self:_refresh_context()

    if not self.primary_down and not self:_secondary_driver_active() then
        return
    end

    local current_action, start_t, chain_ready, action_settings = self:_current_action()
    self:_maybe_advance(current_action, start_t, chain_ready, action_settings)
    self:_restore_after_no_repeat()
end

return SequenceEngine
