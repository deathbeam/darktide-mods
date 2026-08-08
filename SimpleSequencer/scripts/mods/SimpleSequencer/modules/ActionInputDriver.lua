local ActionInputDriver = class('SimpleSequencerActionInputDriver')

local function _requirements(element, input_settings)
    local active_element = element
    local input_setting = element.input_setting

    if input_setting and input_settings and input_settings[input_setting.setting] == input_setting.setting_value then
        active_element = input_setting
    end

    local result = {}

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

function ActionInputDriver:init()
    self:reset()
end

function ActionInputDriver:reset()
    self.template = nil
    self.target_name = nil
    self.input_name = nil
    self.elements = nil
    self.input_settings = nil
    self.followup_inputs = nil
    self.followup_index = 1
    self.element_index = 1
    self.element_start_t = nil
    self.frame_t = nil
    self.duration_advanced_t = nil
    self.matched = false
    self.submitted = false
    self.submitted_t = nil
    self.restart_after = nil
end

function ActionInputDriver:_begin_input(input_name, t)
    local config = self.template.action_inputs and self.template.action_inputs[input_name]

    self.input_name = input_name
    self.elements = config and config.input_sequence or nil
    self.element_index = 1
    self.element_start_t = t
    self.frame_t = nil
    self.duration_advanced_t = nil
    self.matched = false
    self.submitted = false
end

function ActionInputDriver:_begin_next_followup(t)
    local followups = self.followup_inputs
    local input_name = followups and followups[self.followup_index]

    if not input_name then
        return false
    end

    self.followup_index = self.followup_index + 1
    self:_begin_input(input_name, t)

    return true
end

function ActionInputDriver:set_target(template, input_name, t, input_settings, sequence_start_t, followup_inputs)
    if self.template == template and self.target_name == input_name then
        self.input_settings = input_settings
        return
    end

    self:reset()

    if not template or not input_name then
        return
    end

    self.template = template
    self.target_name = input_name
    self.input_settings = input_settings
    self.followup_inputs = followup_inputs

    local config = template.action_inputs and template.action_inputs[input_name]
    local buffer_time = config and config.buffer_time

    self.restart_after = buffer_time and buffer_time > 0.1 and buffer_time - 0.05 or nil
    self:_begin_input(input_name, sequence_start_t or t or 0)
end

function ActionInputDriver:can_drive()
    return self.input_name ~= nil and type(self.elements) == 'table' and #self.elements > 0
end

function ActionInputDriver:_advance_frame(t)
    if self.frame_t == t then
        return
    end

    self.frame_t = t
    self.duration_advanced_t = nil

    if self.submitted then
        if self.restart_after and self.submitted_t and t - self.submitted_t >= self.restart_after then
            self.followup_index = 1
            self:_begin_input(self.target_name, t)
            self.frame_t = t
        end

        return
    end

    local element = self.elements and self.elements[self.element_index]

    if not element then
        self.submitted = true
        self.submitted_t = t
        return
    end

    local elapsed = t - self.element_start_t
    local duration_complete = element.duration and elapsed >= element.duration
    local complete = duration_complete or self.matched and not element.duration

    if complete then
        self.element_index = self.element_index + 1
        self.element_start_t = t
        self.matched = false

        if element.duration then
            self.duration_advanced_t = t
        end

        if not self.elements[self.element_index] then
            if not self:_begin_next_followup(t) then
                self.submitted = true
                self.submitted_t = t
            end
        end
    end
end

function ActionInputDriver:_current_requirements()
    local element = self.elements and self.elements[self.element_index]

    return element and _requirements(element, self.input_settings) or nil
end

function ActionInputDriver:controls(action_name)
    local requirements = self:_current_requirements()

    return self.input_name ~= nil and requirements and requirements[action_name] ~= nil
end

function ActionInputDriver:value(action_name, raw_value, t)
    if not self.input_name then
        return raw_value
    end

    self:_advance_frame(t or 0)
    t = t or 0

    if self.duration_advanced_t == t then
        return raw_value
    end

    -- Keep physical primary input out of the parser while a queued entry awaits its chain.
    if self.submitted then
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

    return requirement.value
end

return ActionInputDriver
