local mod = get_mod('SimpleSequencer')
local Profiles = mod:io_dofile('SimpleSequencer/scripts/mods/SimpleSequencer/modules/SequenceProfiles')
local WeaponContext = mod:io_dofile('SimpleSequencer/scripts/mods/SimpleSequencer/modules/WeaponContext')

local HEAVY_WINDUP_COMMANDS = {
    heavy_attack = 'heavy_attack',
    special_heavy_attack = 'special_heavy_attack',
    special_heavy_execute = 'special_heavy_execute',
}

local SequenceEngine = class('SimpleSequencerSequenceEngine')

local PRIMARY_HOLD_COMMANDS = {
    start_attack = true,
    light_attack = true,
    heavy_attack = true,
    shoot = true,
    push_follow_up = true,
}

local CURRENT_ACTION_HOLD_OVERRIDES = {
    start_attack = {
        light_attack = false,
        shoot = false,
    },
    light_attack = {
        idle = false,
        light_attack = false,
    },
    heavy_attack = {
        idle = false,
        light_attack = false,
    },
    push = {
        light_attack = false,
        heavy_attack = false,
        push = true,
        push_follow_up = true,
    },
    push_follow_up = {
        block = true,
        push = true,
        push_follow_up = true,
    },
    block = {
        start_attack = false,
        light_attack = false,
        heavy_attack = false,
        push = true,
        push_follow_up = true,
    },
    shoot = {
        idle = true,
        charge = false,
    },
    charge = {
        shoot_alt = false,
    },
}

local EXTRA_COMMANDS = {
    special_start_attack = true,
    special_light_attack = true,
    special_heavy_execute = true,
    special_action = true,
    special_invert = true,
}

local ACTION_INTERRUPTS = {
    action_two_hold = true,
    weapon_extra_pressed = true,
    weapon_extra_hold = true,
    weapon_reload_hold = true,
    quick_wield = true,
    sprint = true,
}

local function _time()
    local time_manager = Managers and Managers.time

    if time_manager and time_manager.time then
        return time_manager:time('gameplay')
    end

    return os.clock()
end

local function _classify_action(action_name, action_settings, expected_command)
    if not action_name or action_name == 'idle' then
        return 'idle'
    end

    local start_input = action_settings and action_settings.start_input
    local kind = action_settings and action_settings.kind

    if start_input == 'special_action_hold' then
        return 'special_start_attack'
    elseif start_input == 'special_action_light' then
        return 'special_light_attack'
    elseif start_input == 'special_action_heavy' then
        return 'special_heavy_execute'
    elseif start_input == 'special_action' then
        return 'special_action'
    elseif start_input == 'shoot_pressed' then
        return 'shoot'
    elseif start_input == 'charge' then
        return 'charge'
    elseif kind == 'trigger_explosion' then
        return 'special_heavy_execute'
    end

    if
        expected_command == 'special_start_attack' and (kind == 'windup' or string.find(action_name, 'start', 1, true))
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

    if string.find(action_name, 'invert', 1, true) then
        return 'special_invert'
    elseif
        string.find(action_name, 'activate_special', 1, true) or string.find(action_name, 'toggle_special', 1, true)
    then
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

local function _action_token(action, start_t)
    if action == 'idle' then
        return 'idle'
    end

    return action .. ':' .. tostring(start_t or 0)
end

function SequenceEngine:init(mod, mode_manager)
    self.mod = mod
    self.mode_manager = mode_manager
    self.index = 1
    self.commands = {}
    self.cycle_index = 0
    self.repeating = false
    self.completed = false
    self.context = nil
    self.context_key = nil
    self.primary_down = false
    self.ranged_mode = 'hip'
    self.last_action_token = nil
    self.previous_command = nil
    self.idle_match_index = nil
    self.last_fire_time = 0
    self.fire_token = nil
    self.sweep_state = nil
    self.no_repeat_restored = false
end

function SequenceEngine:invalidate()
    self.context_key = nil
end

function SequenceEngine:is_in_action()
    local action_name = select(1, WeaponContext.action(self.context))

    return action_name ~= 'idle'
end

function SequenceEngine:is_safe_to_switch_mode()
    local current_action, _, _, chain_ready = self:_current_action()

    return current_action == 'idle' or chain_ready
end

function SequenceEngine:_command()
    return self.index and self.commands[self.index]
end

function SequenceEngine:reset()
    self.primary_down = false
    self.index = 1
    self.completed = false
    self.last_action_token = nil
    self.previous_command = nil
    self.idle_match_index = nil
    self.last_fire_time = 0
    self.fire_token = nil
    self.sweep_state = nil
    self.no_repeat_restored = false
end

function SequenceEngine:set_sweep_state(state)
    self.sweep_state = state
end

function SequenceEngine:_refresh_context()
    local context = WeaponContext.read()
    local key = tostring(self.mode_manager.revision)
        .. ':'
        .. self.mode_manager:active()
        .. ':'
        .. context.kind
        .. ':'
        .. context.name
        .. ':'
        .. self.ranged_mode

    if self.context_key == key then
        return context
    end

    self.context_key = key
    self.context = context
    self.commands, self.cycle_index, self.repeating = {}, 0, false

    local profile = context.kind ~= 'none' and self.mode_manager:profile(context.kind, context.name)

    if profile then
        self.commands, self.cycle_index, self.repeating =
            Profiles.build(profile, context.kind, context.name, self.ranged_mode)
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
    local current_action = _classify_action(action_name, action_settings, command)
    local chain_ready = false

    local heavy_windup_action = HEAVY_WINDUP_COMMANDS[command]

    if
        heavy_windup_action
        and (current_action == 'start_attack' or current_action == 'special_start_attack')
        and WeaponContext.can_chain_heavy_attack(action_settings, start_t, self.context.name)
    then
        current_action = heavy_windup_action
    end

    if action_settings and action_settings.kind == 'sweep' and self.sweep_state == 'after_damage_window' then
        chain_ready = true
    elseif current_action == 'light_attack' or current_action == 'heavy_attack' then
        chain_ready = WeaponContext.can_chain_start_attack(action_settings, start_t)
    elseif current_action == 'shoot' then
        chain_ready = WeaponContext.can_chain_shoot(action_settings, start_t, self.context.name)
    end

    return current_action, start_t, action_name, chain_ready
end

function SequenceEngine:_charge_ready(start_t)
    local threshold = (self.profile and self.profile.auto_charge_threshold or 100) / 100
    local charge_start_t = WeaponContext.charge_start_time(self.context)

    if charge_start_t and start_t and charge_start_t < start_t then
        return false
    end

    return WeaponContext.charge_level(self.context) >= threshold
end

function SequenceEngine:_advance()
    local completed_command = self:_command()

    if completed_command then
        self.previous_command = completed_command
    end

    if self.index >= #self.commands then
        if self.cycle_index > 0 or self.repeating then
            self.index = self.cycle_index > 0 and self.cycle_index or 1
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

function SequenceEngine:_maybe_advance(current_action, start_t, chain_ready)
    local command = self:_command()

    if not command then
        return
    end

    if command == 'charge' and current_action == 'charge' and not self:_charge_ready(start_t) then
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
        or command == 'special_invert' and matched_action == 'special_action'

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
    if not self.completed or self.repeating or self.no_repeat_restored then
        return false
    end

    self.no_repeat_restored = true
    self.mode_manager:toggle()

    return true
end

function SequenceEngine:_profile_allows_input()
    if not self.profile or self.completed then
        return false
    end

    return true
end

function SequenceEngine:_required(command, action_name)
    if action_name == 'action_one_hold' then
        return PRIMARY_HOLD_COMMANDS[command] or false
    elseif action_name == 'action_two_hold' then
        return command == 'charge' or command == 'block' or command == 'push' or command == 'push_follow_up'
    elseif action_name == 'weapon_extra_pressed' or action_name == 'weapon_extra_hold' then
        return EXTRA_COMMANDS[command] or false
    elseif action_name == 'weapon_reload_hold' then
        return command == 'weapon_reload'
    elseif action_name == 'quick_wield' then
        return command == 'quick_wield'
    end

    return false
end

function SequenceEngine:_should_reset_for_interrupt(action_name, value, command)
    if not value or not self.mod:get('reset_on_interrupt') or not ACTION_INTERRUPTS[action_name] then
        return false
    end

    if action_name == 'action_two_hold' and self.context.kind == 'RANGED' then
        return false
    end

    return not self:_required(command, action_name)
end

function SequenceEngine:_fire_delay()
    local value = self.ranged_mode == 'ads' and self.profile and self.profile.rate_of_fire_ads
        or self.profile and self.profile.rate_of_fire_hip
    local configured = (value or 0) / 1000

    return math.max(configured, 0.05)
end

function SequenceEngine:_fire_pulse(current_action, raw_value, chain_ready)
    if raw_value then
        self.last_fire_time = _time()
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

    local now = _time()

    if now - self.last_fire_time < self:_fire_delay() then
        return false
    end

    self.last_fire_time = now
    self.fire_token = self.index

    return true
end

function SequenceEngine:_override(action_name, raw_value, current_action, command, chain_ready)
    if action_name == 'action_one_hold' then
        local current_action_overrides = CURRENT_ACTION_HOLD_OVERRIDES[current_action]
        local current_action_override = current_action_overrides and current_action_overrides[command]

        if current_action_override ~= nil then
            return current_action_override
        elseif command == 'idle' then
            return false
        elseif command == 'charge' or EXTRA_COMMANDS[command] or command == 'block' or command == 'push' then
            return false
        end

        return PRIMARY_HOLD_COMMANDS[command] and true or raw_value
    end

    if action_name == 'action_one_pressed' then
        if command == 'idle' then
            return false
        end

        if command == 'heavy_attack' or command == 'charge' or command == 'block' or EXTRA_COMMANDS[command] then
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
        if command == 'shoot' and self.automatic_fire == 'charged' and current_action == 'charge' then
            return true
        elseif self:_required(command, action_name) then
            return true
        end
    elseif action_name == 'weapon_extra_pressed' or action_name == 'weapon_extra_hold' then
        if self:_required(command, action_name) then
            return true
        end
    elseif action_name == 'weapon_reload_hold' or action_name == 'quick_wield' then
        if self:_required(command, action_name) then
            return true
        end
    end

    return raw_value
end

function SequenceEngine:handle_input(action_name, raw_value)
    if
        action_name ~= 'action_one_pressed'
        and action_name ~= 'action_one_hold'
        and not ACTION_INTERRUPTS[action_name]
    then
        return raw_value
    end

    local context = self:_refresh_context()

    if action_name == 'action_two_hold' and context.kind == 'RANGED' then
        local ranged_mode = raw_value and 'ads' or 'hip'

        if self.ranged_mode ~= ranged_mode then
            self.ranged_mode = ranged_mode
            self.context_key = nil
            self:reset('ranged_mode_changed')
            context = self:_refresh_context()
        end
    end

    local previous_primary_down = self.primary_down
    local released_primary = false

    if action_name == 'action_one_hold' then
        self.primary_down = not not raw_value
        released_primary = previous_primary_down and not self.primary_down

        if released_primary then
            self:reset()
        end
    elseif action_name == 'action_one_pressed' and raw_value then
        self.primary_down = true
    end

    if released_primary then
        return raw_value
    end

    local current_action, start_t, _, chain_ready = self:_current_action()
    self:_maybe_advance(current_action, start_t, chain_ready)
    if self:_restore_after_no_repeat() then
        return raw_value
    end

    local command = self:_command()

    local auto_fire_without_primary = action_name == 'action_one_pressed'
        and self.context.kind == 'RANGED'
        and self.automatic_fire == 'charged'
        and command == 'shoot'

    if not self.primary_down and not auto_fire_without_primary then
        return raw_value
    end

    if self.completed then
        if action_name == 'action_one_pressed' or action_name == 'action_one_hold' then
            return false
        end

        return raw_value
    end

    if not command or not self:_profile_allows_input() then
        return raw_value
    end

    if self:_should_reset_for_interrupt(action_name, raw_value, command) then
        self:reset()

        return raw_value
    end

    return self:_override(action_name, raw_value, current_action, command, chain_ready)
end

function SequenceEngine:update()
    self:_refresh_context()

    if not self.primary_down then
        return
    end

    local current_action, start_t, _, chain_ready = self:_current_action()
    self:_maybe_advance(current_action, start_t, chain_ready)
    self:_restore_after_no_repeat()
end

return SequenceEngine
