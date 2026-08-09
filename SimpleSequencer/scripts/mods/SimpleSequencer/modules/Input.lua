local Input = class('SimpleSequencerInput')

local FRAME_INPUTS = {
    'action_one_pressed',
    'action_one_hold',
    'action_two_pressed',
    'action_two_hold',
    'weapon_extra_pressed',
    'weapon_extra_hold',
    'weapon_reload_hold',
    'toggle_ads',
}

local FRAME_INPUT_LOOKUP = {}
for _, action_name in ipairs(FRAME_INPUTS) do
    FRAME_INPUT_LOOKUP[action_name] = true
end

function Input:init()
    self:reset()
end

function Input:reset()
    self.primary_held = false
    self.secondary_held = false
    self.snapshot_frame = nil
    self.snapshot_state = nil
end

function Input:snapshot(action_name, read_input, input_extension)
    if not FRAME_INPUT_LOOKUP[action_name] then
        return nil
    end
    local human_input = input_extension and input_extension._human_unit_input
    local frame = human_input and human_input._frame
    if frame == nil then
        return nil
    end
    if self.snapshot_frame == frame and self.snapshot_state then
        return self.snapshot_state
    end

    local values = {}
    for _, action_name in ipairs(FRAME_INPUTS) do
        values[action_name] = not not read_input(action_name)
    end

    local secondary_was_held = self.secondary_held
    self.primary_held = values.action_one_hold
    self.secondary_held = values.action_two_hold
    self.snapshot_frame = frame
    self.snapshot_state = {
        frame = frame,
        action_names = FRAME_INPUTS,
        values = values,
        primary_pressed = values.action_one_pressed,
        primary_held = self.primary_held,
        secondary_held = self.secondary_held,
        secondary_pressed = self.secondary_held and not secondary_was_held,
    }

    return self.snapshot_state
end

return Input
