local source = debug.getinfo(1, 'S').source
local source_path = source:sub(1, 1) == '@' and source:sub(2) or source
local root = source_path:match('^(.*)/tests/shared/') or '.'
root = root .. (root:sub(-1) == '/' and '' or '/')

local DarktideMock = {}

local DEFAULT_ACTION_INPUT_HIERARCHY = {
    {
        input = 'start_attack',
        transition = {
            { input = 'light_attack', transition = 'base' },
            { input = 'heavy_attack', transition = 'base' },
            { input = 'special_action_hold', transition = 'base' },
        },
    },
    {
        input = 'block',
        transition = {
            {
                input = 'push',
                transition = {
                    { input = 'push_follow_up', transition = 'base' },
                },
            },
        },
    },
    { input = 'special_action', transition = 'base' },
    { input = 'special_action_hold', transition = 'base' },
    { input = 'wield', transition = 'stay' },
    { input = 'shoot_pressed', transition = 'base' },
}

local DEFAULT_ACTION_INPUTS = {
    start_attack = {
        buffer_time = 0.3,
        input_sequence = { { input = 'action_one_hold', value = true } },
    },
    light_attack = {
        buffer_time = 0.3,
        input_sequence = { { input = 'action_one_hold', value = false } },
    },
    heavy_attack = {
        buffer_time = 0.5,
        input_sequence = {
            { duration = 0.25, input = 'action_one_hold', value = true },
            { input = 'action_one_hold', value = false },
        },
    },
    block = {
        buffer_time = 0.1,
        input_sequence = { { input = 'action_two_hold', value = true } },
    },
    push = {
        buffer_time = 0.2,
        input_sequence = {
            { hold_input = 'action_two_hold', input = 'action_one_pressed', value = true },
        },
    },
    push_follow_up = {
        buffer_time = 0.3,
        input_sequence = {
            { duration = 0.25, hold_input = 'action_two_hold', input = 'action_one_hold', value = true },
        },
    },
    special_action_hold = {
        input_sequence = { { input = 'weapon_extra_hold', value = true } },
    },
    special_action = {
        input_sequence = { { input = 'weapon_extra_pressed', value = true } },
    },
    shoot_pressed = {
        input_sequence = { { input = 'action_one_pressed', value = true } },
    },
    shoot = {
        input_sequence = { { input = 'action_one_pressed', value = true } },
    },
    shoot_hold = {
        input_sequence = { { input = 'action_one_hold', value = true } },
    },
    shoot_charge = {
        input_sequence = { { input = 'action_one_pressed', value = true } },
    },
}

local function _active_input_element(element, inputs)
    local input_setting = element.input_setting

    if input_setting and inputs[input_setting.setting] == input_setting.setting_value then
        return input_setting
    end

    return element
end

local function _element_matches(element, inputs)
    local active_element = _active_input_element(element, inputs)
    local candidates = active_element.inputs

    if candidates then
        if active_element.input_mode == 'all' then
            for _, candidate in ipairs(candidates) do
                if inputs[candidate.input] ~= candidate.value then
                    return false
                end
            end

            return true
        end

        for _, candidate in ipairs(candidates) do
            if inputs[candidate.input] == candidate.value then
                return true
            end
        end

        return false
    end

    return active_element.input and inputs[active_element.input] == active_element.value or false
end

local function _clone(value)
    if type(value) ~= 'table' then
        return value
    end

    local result = {}

    for key, child in pairs(value) do
        result[key] = _clone(child)
    end

    return result
end

local function _observed_input(input_state, action_name, value, raw_inputs)
    local secondary_was_held = input_state.secondary_held
    local primary_pressed = action_name == 'action_one_pressed' and value

    if action_name == 'action_one_hold' then
        input_state.primary_held = not not value
    elseif action_name == 'action_two_hold' then
        input_state.secondary_held = not not value
    elseif primary_pressed then
        local secondary_held = raw_inputs.action_two_hold
        input_state.secondary_held = not not (secondary_held == nil and input_state.secondary_held or secondary_held)
    end

    return {
        action_name = action_name,
        value = value,
        primary_pressed = not not primary_pressed,
        primary_held = input_state.primary_held,
        secondary_held = input_state.secondary_held,
        secondary_pressed = input_state.secondary_held and not secondary_was_held,
    }
end

local function _new_template(name, template)
    template = template or {}
    template.name = template.name or name
    template.actions = template.actions or {}
    template.action_inputs = template.action_inputs or {}

    for input_name, input in pairs(DEFAULT_ACTION_INPUTS) do
        if template.action_inputs[input_name] == nil then
            template.action_inputs[input_name] = _clone(input)
        end
    end
    template.action_input_hierarchy = template.action_input_hierarchy or _clone(DEFAULT_ACTION_INPUT_HIERARCHY)
    template.displayed_attacks = template.displayed_attacks or {
        primary = { type = 'ranged' },
    }

    return template
end

local function _new_class()
    local class = {}

    function class:new(...)
        local instance = setmetatable({}, { __index = class })

        if instance.init then
            instance:init(...)
        end

        return instance
    end

    return class
end

function DarktideMock.new()
    local mock = {
        now = 0,
        frame = 0,
        settings = {},
        unit = {},
        mod = {},
        extension = nil,
        player = nil,
    }
    mock.input_extension = { _human_unit_input = { _frame = mock.frame } }

    local inventory = {
        wielded_slot = 'slot_secondary',
    }
    local weapons = {}
    local action_component = {
        current_action_name = 'none',
        start_t = nil,
    }
    local charge_component = {
        charge_level = 0,
        max_charge = nil,
        charge_start_time = nil,
    }

    mock.extension = {
        _inventory_component = inventory,
        _weapons = weapons,
        _weapon_action_component = action_component,
        _action_module_charge_component = charge_component,
        _running_action_settings = nil,
        _action_handler = {
            _registered_components = {
                weapon_action = {},
            },
        },
    }

    function mock.extension:running_action_settings()
        return self._running_action_settings
    end

    function mock.extension:_wielded_weapon(current_inventory)
        local weapon = self._weapons[current_inventory.wielded_slot]

        return weapon
    end

    function mock.extension:action_input_is_currently_valid(_, action_input, _, current_t)
        local settings = self._running_action_settings
        local chain_actions = settings
            and settings.allowed_chain_actions
            and settings.allowed_chain_actions[action_input]

        if not chain_actions or not action_component.start_t then
            return false
        end

        local time_scale = action_component.time_scale or 1
        local time_in_action = current_t - action_component.start_t

        for index = 1, chain_actions[1] and #chain_actions or 1 do
            local chain_action = chain_actions[1] and chain_actions[index] or chain_actions
            local chain_time = chain_action.chain_time and chain_action.chain_time / time_scale
            local chain_until = chain_action.chain_until and chain_action.chain_until / time_scale
            local chain_ready = not chain_time
                or chain_time <= time_in_action
                or chain_until and time_in_action <= chain_until
            local state_requirement = chain_action.running_action_state_requirement
            local handler_data = self._action_handler._registered_components.weapon_action
            local running_action = handler_data.running_action
            local running_state = state_requirement
                and running_action
                and running_action.running_action_state
                and running_action:running_action_state(current_t, time_in_action)
            local state_ready = not state_requirement or running_state and state_requirement[running_state]

            local weapon = self:_wielded_weapon(self._inventory_component)
            local target = chain_action.action_name
                and weapon
                and weapon.weapon_template.actions[chain_action.action_name]
            local condition = target and target.action_condition_func
            local condition_params = self._action_handler._action_context
            local action_ready = not condition or condition(target, condition_params, nil, current_t, time_in_action)

            if chain_ready and state_ready and action_ready then
                return true
            end
        end

        return false
    end

    mock.player = {
        player_unit = mock.unit,
    }

    function mock.mod:get(setting_id)
        return mock.settings[setting_id]
    end

    function mock.mod:io_dofile(path)
        local filename = path:sub(-4) == '.lua' and path or path .. '.lua'

        return dofile(root .. filename)
    end

    function mock:set_action(action_name, settings, start_t)
        action_component.current_action_name = action_name or 'none'
        action_component.start_t = start_t
        mock.extension._running_action_settings = settings

        local controller = mock._controller

        if controller and action_name and action_name ~= 'none' then
            controller:on_action_started(action_name, start_t)
        end
    end

    function mock:set_charge(level, max_charge, start_t)
        charge_component.charge_level = level or 0
        charge_component.max_charge = max_charge
        charge_component.charge_start_time = start_t
    end

    function mock:set_weapon(slot, name, template)
        weapons[slot] = {
            weapon_template = _new_template(name, template),
        }
    end

    function mock:set_wielded_slot(slot)
        inventory.wielded_slot = slot
    end

    function mock:set_input_delay(frames)
        mock.input_delay_frames = frames or 0
    end

    function mock:set_input_order(input_order)
        mock.input_order = input_order
    end

    local function _wielded_template()
        local weapon = weapons[inventory.wielded_slot]
        return weapon and weapon.weapon_template or nil
    end

    local function _set_input_hierarchy(template, hierarchy)
        mock._input_template = template
        mock._input_hierarchy = hierarchy
        mock._input_sequences = {}

        for _, entry in ipairs(hierarchy or {}) do
            mock._input_sequences[entry.input] = {
                index = 1,
                start_t = mock.now,
                running = true,
            }
        end
    end

    local function _transition_input_hierarchy(template, input_name)
        for _, entry in ipairs(mock._input_hierarchy or {}) do
            if entry.input == input_name then
                local transition = entry.transition

                if transition == 'base' then
                    _set_input_hierarchy(template, template.action_input_hierarchy)
                elseif type(transition) == 'table' then
                    _set_input_hierarchy(template, transition)
                end

                return
            end
        end
    end

    local function _completed_input(template, inputs)
        for _, entry in ipairs(mock._input_hierarchy or {}) do
            local input_name = entry.input
            local config = template.action_inputs and template.action_inputs[input_name]
            local elements = config and config.input_sequence
            local sequence = mock._input_sequences[input_name]

            if elements and sequence and sequence.running then
                local element = elements[sequence.index]
                local active_element = element and _active_input_element(element, inputs)
                local held = not active_element or not active_element.hold_input or inputs[active_element.hold_input]
                local matched = active_element and _element_matches(element, inputs)
                local elapsed = active_element and mock.now - sequence.start_t or 0
                local complete = false

                if active_element and active_element.duration then
                    if elapsed >= active_element.duration then
                        complete = true
                    elseif not matched then
                        sequence.running = false
                    end
                elseif active_element and active_element.time_window then
                    if matched and held and elapsed <= active_element.time_window then
                        complete = true
                    elseif elapsed > active_element.time_window and active_element.auto_complete then
                        complete = true
                    elseif elapsed > active_element.time_window then
                        sequence.running = false
                    end
                elseif matched and held then
                    complete = true
                end

                if complete then
                    if elements[sequence.index + 1] then
                        sequence.index = sequence.index + 1
                        sequence.start_t = mock.now
                    else
                        sequence.index = 1
                        sequence.start_t = mock.now

                        return input_name
                    end
                end
            end
        end
    end

    local function _chain_action(template, chain_actions, t)
        for index = 1, chain_actions and (chain_actions[1] and #chain_actions or 1) or 0 do
            local chain_action = chain_actions[1] and chain_actions[index] or chain_actions
            local action_name = chain_action and chain_action.action_name
            local action_settings = action_name and template.actions[action_name]
            local condition = action_settings and action_settings.action_condition_func
            local valid = true

            if condition then
                local elapsed = action_component.start_t and t - action_component.start_t or 0
                local ok, result = pcall(condition, action_settings, nil, nil, t, elapsed)
                valid = ok and result == true
            end

            if action_settings and valid then
                return chain_action
            end
        end
    end

    local function _apply_input(template, input_name)
        local action_name = action_component.current_action_name
        local action_settings = mock.extension._running_action_settings

        if not action_name or action_name == 'none' then
            for next_action_name, settings in pairs(template.actions or {}) do
                if settings.start_input == input_name then
                    mock:set_action(next_action_name, settings, mock.now)

                    return true
                end
            end

            return false
        end

        local chain_actions = action_settings and action_settings.allowed_chain_actions
        local chain_action = _chain_action(template, chain_actions and chain_actions[input_name], mock.now)
        local next_action_name = chain_action and chain_action.action_name
        local next_settings = next_action_name and template.actions[next_action_name]
        local valid = chain_action
            and mock.extension:action_input_is_currently_valid('weapon_action', input_name, nil, mock.now)
        if not valid or not next_settings then
            return false
        end

        mock:set_action(next_action_name, next_settings, mock.now)

        return true
    end

    local function _queue_input(template, input_name)
        local config = template.action_inputs and template.action_inputs[input_name] or {}
        local buffer_time = config.buffer_time or 0
        local queue = mock._input_queue

        queue[#queue + 1] = {
            input_name = input_name,
            expires_t = mock.now + buffer_time,
            ready_frame = mock.frame + (mock.input_delay_frames or 0),
        }
    end

    local function _apply_queued_input(template)
        local queue = mock._input_queue
        local index = 1

        while queue[index] do
            local entry = queue[index]

            if mock.frame < entry.ready_frame then
                index = index + 1
            elseif mock.now > entry.expires_t then
                table.remove(queue, index)
            elseif _apply_input(template, entry.input_name) then
                table.remove(queue, index)

                return entry.input_name
            else
                index = index + 1
            end
        end
    end

    function mock:handle_input(engine, action_name, value, raw_inputs)
        raw_inputs = raw_inputs or {}
        if raw_inputs[action_name] == nil then
            raw_inputs[action_name] = value
        end

        local input = _observed_input(mock.input, action_name, value, raw_inputs)

        return engine:handle_input(input)
    end

    function mock:run_input_frame(engine, raw_inputs)
        raw_inputs = raw_inputs or {}
        mock.input_extension._human_unit_input._frame = mock.frame
        local input = mock.input:snapshot('action_one_pressed', function(action_name)
            return raw_inputs[action_name] or false
        end, mock.input_extension)
        local outputs = engine:handle_frame(input)
        local inputs = {}
        local input_order = mock.input_order or input.action_names
        for _, input_name in ipairs(input_order) do
            local output = outputs[input_name]
            inputs[input_name] = output == nil and raw_inputs[input_name] or output
        end
        for _, input_name in ipairs(input.action_names) do
            if inputs[input_name] == nil then
                local output = outputs[input_name]
                inputs[input_name] = output == nil and raw_inputs[input_name] or output
            end
        end

        local template = _wielded_template()
        local input_name
        local applied_input

        if template then
            if mock._input_template ~= template then
                mock._input_queue = {}
                _set_input_hierarchy(template, template.action_input_hierarchy)
            end

            input_name = _completed_input(template, inputs)
            if input_name then
                _transition_input_hierarchy(template, input_name)
                _queue_input(template, input_name)
            end

            applied_input = _apply_queued_input(template)
        end

        mock.frame = mock.frame + 1
        mock.extension._last_fixed_frame = mock.frame
        return inputs, input_name or applied_input
    end

    function mock:current_action_name()
        return action_component.current_action_name
    end

    function mock:install()
        _G.get_mod = function()
            return self.mod
        end

        _G.class = _new_class
        _G.Managers = {
            time = {
                time = function()
                    return self.now
                end,
            },
            player = {
                local_player_safe = function()
                    return self.player
                end,
            },
        }
        _G.ScriptUnit = {
            has_extension = function(unit, extension_name)
                if unit == self.unit and extension_name == 'weapon_system' then
                    return self.extension
                end

                return nil
            end,
        }
    end

    function mock:load_controller(mode_manager)
        self:install()
        local Input = dofile(root .. 'SimpleSequencer/scripts/mods/SimpleSequencer/modules/Input.lua')
        local Controller = dofile(root .. 'SimpleSequencer/scripts/mods/SimpleSequencer/modules/SequenceController.lua')
        local controller = Controller:new(self.mod, mode_manager)
        mock.input = Input:new()
        mock._controller = controller
        return controller
    end

    function mock:load_weapon_context()
        self:install()

        return dofile(root .. 'SimpleSequencer/scripts/mods/SimpleSequencer/modules/WeaponContext.lua')
    end

    mock:set_weapon('slot_secondary', 'test_ranged')
    mock:set_weapon('slot_primary', 'test_melee', {
        displayed_attacks = {
            primary = { type = 'melee' },
        },
    })
    mock:install()

    return mock
end

return DarktideMock
