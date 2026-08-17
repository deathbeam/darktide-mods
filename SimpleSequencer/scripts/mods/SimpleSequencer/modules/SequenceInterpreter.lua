local SequenceInterpreter = class('SimpleSequencerSequenceInterpreter')

local RETRY_MARGIN = 0.05

local function _active_element(element, input_settings)
    if not element then
        return nil
    end

    local input_setting = element.input_setting
    if input_setting and input_settings and input_settings[input_setting.setting] == input_setting.setting_value then
        return input_setting
    end

    return element
end

local function _requirements(element, input_settings)
    local active_element = _active_element(element, input_settings)
    local result = {}

    if not active_element then
        return result
    end

    if active_element.inputs then
        local inputs = active_element.inputs
        local count = active_element.input_mode == 'all' and #inputs or math.min(#inputs, 1)

        for index = 1, count do
            local input = inputs[index]
            result[input.input] = { value = input.value }
        end
    elseif active_element.input then
        result[active_element.input] = { value = active_element.value }
    end

    local hold_input = active_element.hold_input
    local requirement = hold_input and result[hold_input]

    if hold_input and (not requirement or requirement.value ~= false) then
        result[hold_input] = { value = true }
    end
    return result
end

function SequenceInterpreter:init()
    self:reset()
end

function SequenceInterpreter:reset()
    self.template = nil
    self.root_input = nil
    self.input_name = nil
    self.elements = nil
    self.input_settings = nil
    self.program_inputs = nil
    self.next_input_index = 2
    self.element_index = 1
    self.element_start_t = nil
    self.frame_t = nil
    self.duration_advanced_t = nil
    self.matched = false
    self.matched_t = nil
    self.submitted = false
    self.submitted_t = nil
    self.submitted_inputs = {}
    self.started_input = nil
    self.restart_after = nil
end

function SequenceInterpreter:_begin_input(input_name, t)
    local config = self.template.action_inputs and self.template.action_inputs[input_name]

    self.input_name = input_name
    self.elements = config and config.input_sequence or nil
    local element = self.elements and _active_element(self.elements[1], self.input_settings)
    local retry_window = config and config.buffer_time
    if retry_window and element and element.time_window then
        retry_window = math.min(retry_window, element.time_window)
    end

    self.restart_after = retry_window and retry_window > 0.1 and retry_window - RETRY_MARGIN or nil
    self.element_index = 1
    self.element_start_t = t
    self.frame_t = nil
    self.duration_advanced_t = nil
    self.matched = false
    self.matched_t = nil
    self.submitted = false
end

function SequenceInterpreter:_begin_next_input(t)
    local input_name = self.program_inputs and self.program_inputs[self.next_input_index]

    if not input_name then
        return false
    end

    self.next_input_index = self.next_input_index + 1
    self:_begin_input(input_name, t)

    return true
end

function SequenceInterpreter:_record_submission()
    if self.started_input == self.input_name then
        self.started_input = nil
    else
        self.submitted_inputs[#self.submitted_inputs + 1] = self.input_name
    end
end

function SequenceInterpreter:set_program(template, inputs, t, input_settings, sequence_start_t)
    local input_name = inputs and inputs[1]

    -- The parser advances at match time, before the controller's next update.
    if not template or not input_name then
        self:reset()
        return
    end

    local next_input = self.program_inputs and self.program_inputs[self.next_input_index]
    local element = self.elements and self.elements[self.element_index]
    if self.template == template and next_input == input_name then
        if self.matched and element and not element.duration then
            self.next_input_index = self.next_input_index + 1
            self:_begin_input(input_name, self.matched_t or t or 0)
        end

        self.input_settings = input_settings
        return
    end

    if self.template == template and (self.root_input == input_name or self.input_name == input_name) then
        self.input_settings = input_settings
        return
    end

    self:reset()

    self.template = template
    self.root_input = input_name
    self.input_settings = input_settings
    self.program_inputs = inputs

    self:_begin_input(input_name, sequence_start_t or t or 0)
end

function SequenceInterpreter:can_interpret()
    return self.input_name ~= nil and type(self.elements) == 'table' and #self.elements > 0
end

function SequenceInterpreter:has_submitted()
    return self.submitted
end

function SequenceInterpreter:is_missing_sequence()
    return self.input_name ~= nil and not self:can_interpret()
end

function SequenceInterpreter:active_input_name()
    return self.input_name
end

function SequenceInterpreter:pending_action_input()
    return self.submitted_inputs[1] or self.input_name
end

function SequenceInterpreter:consume_action_input(automatic_input, t)
    local submitted_inputs = self.submitted_inputs
    local active_input = self.input_name
    local input_name = submitted_inputs[1]
    local consumed_submission = false
    local first_element = self.elements and _active_element(self.elements[1], self.input_settings)

    if type(automatic_input) == 'string' then
        if input_name == automatic_input then
            table.remove(submitted_inputs, 1)
            consumed_submission = true
        end
        if self.started_input == automatic_input then
            self.started_input = nil
        end
        input_name = automatic_input
    else
        input_name = table.remove(submitted_inputs, 1)
        consumed_submission = input_name ~= nil
        if not input_name then
            self.started_input = self.input_name
            input_name = self.input_name
        end
    end

    -- A buffered root may enter its duration follow-up before the windup action starts.
    if
        consumed_submission
        and self.template
        and active_input
        and input_name ~= active_input
        and first_element
        and first_element.duration
        and t
    then
        while submitted_inputs[1] == active_input do
            table.remove(submitted_inputs, 1)
        end
        self:_begin_input(active_input, t)
    end

    return input_name
end

function SequenceInterpreter:update(t, frame)
    self:_advance_frame(t or 0, frame or t or 0)
end

function SequenceInterpreter:_advance_frame(t, frame)
    if self.frame_t == frame then
        return
    end

    self.frame_t = frame
    self.duration_advanced_t = nil

    if self.submitted then
        if self.restart_after and self.submitted_t and t - self.submitted_t >= self.restart_after then
            self.next_input_index = 2
            self:_begin_input(self.root_input, t)
            self.frame_t = frame
        end

        return
    end

    local element = self.elements and self.elements[self.element_index]

    if not element then
        self:_record_submission()
        self.submitted = true
        self.submitted_t = t
        return
    end

    local elapsed = t - self.element_start_t
    local duration_complete = element.duration and elapsed >= element.duration
    local complete = self.matched and (duration_complete or not element.duration)

    if complete then
        local completion_t = element.duration and t or self.matched_t or t
        self.element_index = self.element_index + 1
        self.element_start_t = t
        self.matched = false
        self.matched_t = nil

        if element.duration then
            self.duration_advanced_t = t
        end

        if not self.elements[self.element_index] then
            self:_record_submission()
            if not self:_begin_next_input(completion_t) then
                self.submitted = true
                self.submitted_t = t
            end
        end
    end
end

function SequenceInterpreter:_current_requirements()
    local element = self.elements and self.elements[self.element_index]

    return element and _requirements(element, self.input_settings) or nil
end

function SequenceInterpreter:controls(action_name)
    local requirements = self:_current_requirements()

    return self.input_name ~= nil and requirements and requirements[action_name] ~= nil
end

function SequenceInterpreter:value(action_name, raw_value, t, frame)
    if not self.input_name then
        return raw_value
    end

    self:update(t, frame)
    t = t or 0

    if self.duration_advanced_t == t then
        return raw_value
    end

    -- Preserve a submitted release while the queued action awaits its chain.
    if self.submitted then
        local final_element = self.elements and self.elements[#self.elements]
        local requirements = _requirements(final_element, self.input_settings)
        local requirement = requirements[action_name]
        if requirement and requirement.value == false then
            return false
        end

        if action_name == 'action_one_pressed' or action_name == 'action_one_hold' then
            return false
        end

        return raw_value
    end

    local requirements = self:_current_requirements()
    local requirement = requirements and requirements[action_name]

    if not requirement then
        return raw_value
    end

    self.matched = true
    self.matched_t = t

    return requirement.value
end

return SequenceInterpreter
