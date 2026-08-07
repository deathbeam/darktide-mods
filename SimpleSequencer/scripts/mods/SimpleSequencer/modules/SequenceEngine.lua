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

local PRIMARY_PRESS_CHAIN_STATES = {
    block = true,
    heavy_attack = true,
    push = true,
    start_attack = true,
}

local HEAVY_WINDUP_INPUTS = { 'heavy_attack' }
local SPECIAL_HEAVY_WINDUP_INPUTS = { 'special_action_heavy', 'special_action_execute', 'heavy_attack' }

local SPECIAL_ATTACK_INPUT_POLICY = {
    weapon_extra_hold = true,
    suppress_primary_hold = true,
    suppress_primary_pressed = true,
}

local INPUT_POLICIES = {
    idle = {
        suppress_primary_hold = true,
        suppress_primary_pressed = true,
        hold_overrides = {
            light_attack = false,
            heavy_attack = false,
            shoot = true,
        },
    },
    start_attack = {
        action_one_hold = true,
        press_when_idle = true,
        hold_overrides = {
            block = false,
            push = 'pulse',
            push_follow_up = 'pulse',
        },
    },
    light_attack = {
        action_one_hold = true,
        press_from = PRIMARY_PRESS_CHAIN_STATES,
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
        press_from = PRIMARY_PRESS_CHAIN_STATES,
        hold_overrides = {
            block = true,
            push = true,
            push_follow_up = true,
        },
    },
    push_follow_up = {
        action_one_hold = true,
        action_two_hold = true,
        press_from = PRIMARY_PRESS_CHAIN_STATES,
        hold_overrides = {
            block = true,
            push = true,
            push_follow_up = true,
        },
    },
    special_start_attack = SPECIAL_ATTACK_INPUT_POLICY,
    special_light_attack = SPECIAL_ATTACK_INPUT_POLICY,
    special_heavy_execute = SPECIAL_ATTACK_INPUT_POLICY,
    special_action = {
        weapon_extra_pressed = true,
        suppress_primary_hold = true,
        suppress_primary_pressed = true,
    },
    quick_swap_cancel = {
        quick_wield = true,
        suppress_primary_hold = true,
        suppress_primary_pressed = true,
    },
}

local function _action_token(action, start_t)
    if not action or action == 'idle' then
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
    self.running_action_token = nil
    self.running_action_state = nil
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

function SequenceEngine:is_active()
    return (self.primary_down or self:_secondary_driver_active())
        and not self.completed
        and self.profile ~= nil
        and self:_command() ~= nil
end

function SequenceEngine:can_switch_mode()
    local current_action, _, chain_ready = self:_current_action()

    return current_action == 'idle' or chain_ready
end

function SequenceEngine:_command()
    return self.index and self.plan.commands[self.index]
end

function SequenceEngine:_secondary_driver_active()
    local policy = INPUT_POLICIES[self:_command()]
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
    self.running_action_token = nil
    self.running_action_state = nil
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
        local sequence = Profiles.build_sequence(profile, context.kind, self.ranged_mode)
        self.plan = ActionSemantics.compile(sequence, context)

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
    local running_action_token = (self.context and self.context.slot or 'none')
        .. ':'
        .. _action_token(action_name, start_t)

    -- Expected-command disambiguation must not relabel an action after the sequence advances.
    if self.running_action_token ~= running_action_token then
        self.running_action_token = running_action_token
        self.running_action_state = ActionSemantics.classify_current(action_name, action_settings, command)
    end

    local current_action = self.running_action_state
    local windup_inputs

    if current_action == 'start_attack' and command == 'heavy_attack' then
        windup_inputs = HEAVY_WINDUP_INPUTS
    elseif current_action == 'special_start_attack' and command == 'special_heavy_execute' then
        windup_inputs = SPECIAL_HEAVY_WINDUP_INPUTS
    end

    for _, input_name in ipairs(windup_inputs or {}) do
        if WeaponContext.can_chain(action_settings, start_t, input_name, self.context) then
            current_action = command
            self.running_action_state = command
            break
        end
    end

    local next_command = self.index and self.plan.commands[self.index + 1]
    local chain_input

    if action_settings and action_settings.kind == 'sweep' and self.sweep_state == 'after_damage_window' then
        chain_input = 'start_attack'
    elseif current_action == 'light_attack' or current_action == 'heavy_attack' then
        chain_input = 'start_attack'
    elseif current_action == 'push' and command == 'idle' then
        -- Push actions expose the next chain before their nominal action end.
        chain_input = next_command
    elseif current_action == 'shoot' then
        chain_input = action_settings and action_settings.start_input or 'shoot_pressed'
    end

    local chain_ready = chain_input and WeaponContext.can_chain(action_settings, start_t, chain_input, self.context)
        or false

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

    if command ~= matched_action then
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

function SequenceEngine:_should_reset_for_interrupt(action_name, value, command)
    if not value or not self.mod:get('reset_on_interrupt') or not INPUT_INTERRUPTS[action_name] then
        return false
    end

    if action_name == 'action_two_hold' and self.context.kind == 'RANGED' then
        return false
    end

    local policy = INPUT_POLICIES[command]
    return not (policy and policy[action_name])
end

function SequenceEngine:_fire_pulse(current_action, raw_value, chain_ready)
    local fire_ready = current_action == 'idle'
        or chain_ready
        or current_action == 'charge'
        or current_action == 'special_action'
        or current_action == 'special_light_attack'

    if raw_value then
        if fire_ready then
            self.fire_token = self.index
        end

        return true
    end

    if not fire_ready or self.fire_token == self.index then
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
    local policy = INPUT_POLICIES[command]
    if action_name == 'action_one_hold' then
        local hold_overrides = policy and policy.hold_overrides
        local current_action_override = hold_overrides and hold_overrides[current_action]

        if current_action_override == 'pulse' then
            return self:_primary_hold_pulse(raw_value, current_action, start_t, action_settings)
        elseif current_action_override ~= nil then
            return current_action_override
        elseif policy and policy.suppress_primary_hold then
            return false
        end

        return policy and policy[action_name] and true or raw_value
    end

    if action_name == 'action_one_pressed' then
        if policy and policy.suppress_primary_pressed then
            return false
        elseif command == 'shoot' then
            return self:_fire_pulse(current_action, raw_value, chain_ready)
        elseif policy and policy.press_when_idle then
            return raw_value or current_action == 'idle'
        elseif policy and policy.press_from then
            return raw_value or policy.press_from[current_action] == true
        end
    elseif action_name == 'action_two_hold' then
        local kind = action_settings and action_settings.kind
        local preserve_input = kind == 'aim'
            or kind == 'unaim'
            or ActionSemantics.uses_primary_charge(self.context, action_settings)

        if preserve_input then
            return raw_value
        elseif command == 'shoot' and self.automatic_fire == 'charged' and current_action == 'charge' then
            return true
        elseif policy and policy[action_name] then
            return true
        end
    elseif
        (action_name == 'weapon_extra_pressed' or action_name == 'weapon_extra_hold')
        and policy
        and policy[action_name]
    then
        return true
    elseif action_name == 'quick_wield' and policy and policy[action_name] then
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
    local preserve_primary_hold = action_settings and action_settings.kind == 'vent_overheat'

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
