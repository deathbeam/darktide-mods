local Input = class('SimpleSequencerInput')

function Input:init()
    self:reset()
end

function Input:reset()
    self.primary_held = false
    self.secondary_held = false
    self.events = {}
end

function Input:clear_events()
    self.events = {}
end

function Input:observe(action_name, value, read_input)
    local secondary_was_held = self.secondary_held
    local primary_pressed = action_name == 'action_one_pressed' and value

    if action_name == 'action_one_hold' then
        self.primary_held = not not value
    elseif action_name == 'action_two_hold' then
        self.secondary_held = not not value
    elseif primary_pressed and read_input then
        self.secondary_held = not not read_input('action_two_hold')
    end

    local previous = self.events[action_name]
    local event = {
        action_name = action_name,
        value = value,
        primary_pressed = previous and previous.primary_pressed or not not primary_pressed,
        primary_held = self.primary_held,
        secondary_held = self.secondary_held,
        secondary_pressed = previous and previous.secondary_pressed or self.secondary_held and not secondary_was_held,
    }
    self.events[action_name] = event

    return event
end

function Input:frame_event(action_name, value, frame_inputs)
    local observed = self.events[action_name]

    return {
        action_name = action_name,
        value = value,
        primary_pressed = observed and observed.primary_pressed or false,
        primary_held = self.primary_held,
        secondary_held = self.secondary_held,
        secondary_pressed = observed and observed.secondary_pressed or false,
        frame_inputs = frame_inputs,
    }
end

return Input
