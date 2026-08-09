local Input = class('SimpleSequencerInput')

function Input:init()
    self:reset()
end

function Input:reset()
    self.primary_held = false
    self.secondary_held = false
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

    return {
        action_name = action_name,
        value = value,
        primary_pressed = not not primary_pressed,
        primary_held = self.primary_held,
        secondary_held = self.secondary_held,
        secondary_pressed = self.secondary_held and not secondary_was_held,
    }
end

return Input
