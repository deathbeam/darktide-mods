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
        local sample = input:observe('action_one_pressed', true, function(action_name)
            return action_name == 'action_two_hold'
        end)

        assert.is_true(sample.primary_pressed)
        assert.is_true(sample.secondary_held)
        assert.is_true(sample.secondary_pressed)
    end)

    it('tracks a held and released physical block independently of primary input', function()
        local input = Input:new()
        local held = input:observe('action_two_hold', true)
        local still_held = input:observe('action_one_pressed', true, function()
            return true
        end)
        local released = input:observe('action_two_hold', false)

        assert.is_true(held.secondary_pressed)
        assert.is_true(still_held.secondary_held)
        assert.is_false(still_held.secondary_pressed)
        assert.is_false(released.secondary_held)
    end)

    it('tracks the physical primary hold separately from a primary press', function()
        local input = Input:new()
        local pressed = input:observe('action_one_pressed', true, function()
            return false
        end)
        local held = input:observe('action_one_hold', true)
        local released = input:observe('action_one_hold', false)

        assert.is_true(pressed.primary_pressed)
        assert.is_false(pressed.primary_held)
        assert.is_true(held.primary_held)
        assert.is_false(released.primary_held)
    end)
end)
