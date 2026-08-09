local DarktideMock = require('tests.shared.darktide_mock')

local source = debug.getinfo(1, 'S').source
local source_path = source:sub(1, 1) == '@' and source:sub(2) or source
local root = source_path:match('^(.*)/tests/SimpleSequencer/') or '.'
root = root .. (root:sub(-1) == '/' and '' or '/')

describe('SimpleSequencer Input', function()
    local Input

    before_each(function()
        DarktideMock.new()
        Input = dofile(root .. 'SimpleSequencer/scripts/mods/SimpleSequencer/modules/Input.lua')
    end)

    it('samples physical block before a same-frame primary press', function()
        local input = Input:new()
        local input_extension = { _human_unit_input = { _frame = 1 } }
        local sample = input:snapshot('action_one_pressed', function(action_name)
            return action_name == 'action_one_pressed' or action_name == 'action_two_hold'
        end, input_extension)

        assert.is_true(sample.primary_pressed)
        assert.is_true(sample.secondary_held)
        assert.is_true(sample.secondary_pressed)
    end)

    it('tracks held and released physical block across snapshots', function()
        local input = Input:new()
        local input_extension = { _human_unit_input = { _frame = 1 } }
        local values = { action_two_hold = true }
        local held = input:snapshot('action_two_hold', function(action_name)
            return values[action_name]
        end, input_extension)
        input_extension._human_unit_input._frame = 2
        values.action_one_pressed = true
        local still_held = input:snapshot('action_one_pressed', function(action_name)
            return values[action_name]
        end, input_extension)
        input_extension._human_unit_input._frame = 3
        values.action_two_hold = false
        local released = input:snapshot('action_two_hold', function(action_name)
            return values[action_name]
        end, input_extension)

        assert.is_true(held.secondary_pressed)
        assert.is_true(still_held.secondary_held)
        assert.is_false(still_held.secondary_pressed)
        assert.is_false(released.secondary_held)
    end)

    it('tracks physical primary hold separately from a primary press', function()
        local input = Input:new()
        local input_extension = { _human_unit_input = { _frame = 1 } }
        local values = { action_one_pressed = true }
        local pressed = input:snapshot('action_one_pressed', function(action_name)
            return values[action_name]
        end, input_extension)
        input_extension._human_unit_input._frame = 2
        values.action_one_pressed = false
        values.action_one_hold = true
        local held = input:snapshot('action_one_hold', function(action_name)
            return values[action_name]
        end, input_extension)
        input_extension._human_unit_input._frame = 3
        values.action_one_hold = false
        local released = input:snapshot('action_one_hold', function(action_name)
            return values[action_name]
        end, input_extension)

        assert.is_true(pressed.primary_pressed)
        assert.is_false(pressed.primary_held)
        assert.is_true(held.primary_held)
        assert.is_false(released.primary_held)
    end)
    it('returns one stable physical snapshot per frame', function()
        local input = Input:new()
        local input_extension = { _human_unit_input = { _frame = 1 } }
        local values = { action_one_pressed = true, action_one_hold = true, action_two_hold = true }
        local first = input:snapshot('action_one_pressed', function(action_name)
            return values[action_name]
        end, input_extension)
        values.action_one_pressed = false
        values.action_one_hold = false
        values.action_two_hold = false
        local same_frame = input:snapshot('action_one_pressed', function(action_name)
            return values[action_name]
        end, input_extension)
        input_extension._human_unit_input._frame = 2
        local next_frame = input:snapshot('action_one_pressed', function(action_name)
            return values[action_name]
        end, input_extension)

        assert.are.equal(first, same_frame)
        assert.is_true(first.primary_pressed)
        assert.is_true(first.primary_held)
        assert.is_true(first.secondary_pressed)
        assert.is_false(next_frame.primary_held)
        assert.is_false(next_frame.secondary_held)
    end)

    it('uses the hooked input extension fixed frame', function()
        local input = Input:new()
        local input_extension = { _human_unit_input = { _frame = 1 } }
        local read_input = function()
            return false
        end
        local first = input:snapshot('action_one_pressed', read_input, input_extension)
        input_extension._human_unit_input._frame = 2
        local second = input:snapshot('action_one_pressed', read_input, input_extension)

        assert.are.equal(1, first.frame)
        assert.are.equal(2, second.frame)
        assert.are_not.equal(first, second)
    end)
    it('leaves weapon selection out of virtual input frames', function()
        local input = Input:new()
        local input_extension = { _human_unit_input = { _frame = 1 } }

        assert.is_nil(input:snapshot('quick_wield', function()
            return true
        end))
        assert.is_not_nil(input:snapshot('action_one_pressed', function()
            return false
        end, input_extension))
    end)
end)
