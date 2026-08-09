local source = debug.getinfo(1, 'S').source
local source_path = source:sub(1, 1) == '@' and source:sub(2) or source
local root = source_path:match('^(.*)/tests/SimpleSequencer/') or '.'
root = root .. (root:sub(-1) == '/' and '' or '/')
local DarktideMock = require('tests.shared.darktide_mock')

describe('SimpleSequencer SequenceInterpreter', function()
    local Interpreter

    before_each(function()
        DarktideMock.new()
        Interpreter = dofile(root .. 'SimpleSequencer/scripts/mods/SimpleSequencer/modules/SequenceInterpreter.lua')
    end)

    it('derives raw input values from a template action sequence', function()
        local interpreter = Interpreter:new()
        local template = {
            action_inputs = {
                light_attack = {
                    input_sequence = {
                        { input = 'action_one_hold', value = false },
                    },
                },
            },
        }

        interpreter:set_target(template, 'light_attack', 0)

        assert.is_true(interpreter:can_interpret())
        assert.is_false(interpreter:value('action_one_hold', true, 0))
        assert.is_true(interpreter:controls('action_one_hold'))
    end)

    it('releases the next input on the frame after a duration completes', function()
        local interpreter = Interpreter:new()
        local template = {
            action_inputs = {
                heavy_attack = {
                    input_sequence = {
                        { duration = 0.25, input = 'action_one_hold', value = true },
                        { input = 'action_one_hold', value = false },
                    },
                },
            },
        }

        interpreter:set_target(template, 'heavy_attack', 0)

        assert.is_true(interpreter:value('action_one_hold', false, 0))
        assert.is_true(interpreter:value('action_one_hold', false, 0.1))
        assert.is_true(interpreter:value('action_one_hold', true, 0.25))
        assert.is_false(interpreter:value('action_one_hold', true, 0.26))
    end)

    it('drives duration requirements before completing an elapsed input', function()
        local interpreter = Interpreter:new()
        local template = {
            action_inputs = {
                push_follow_up = {
                    input_sequence = {
                        {
                            duration = 0.25,
                            hold_input = 'action_two_hold',
                            input = 'action_one_hold',
                            value = true,
                        },
                    },
                },
            },
        }
        interpreter:set_target(template, 'push_follow_up', 0.25, nil, 0)

        assert.is_true(interpreter:value('action_one_hold', false, 0.25))
        assert.is_true(interpreter:value('action_two_hold', false, 0.25))
        assert.is_false(interpreter.submitted)
    end)

    it('preserves required hold inputs for compound actions', function()
        local interpreter = Interpreter:new()
        local template = {
            action_inputs = {
                push = {
                    input_sequence = {
                        {
                            hold_input = 'action_two_hold',
                            input = 'action_one_pressed',
                            value = true,
                        },
                    },
                },
            },
        }

        interpreter:set_target(template, 'push', 0)

        assert.is_true(interpreter:value('action_two_hold', false, 0))
        assert.is_true(interpreter:value('action_one_pressed', false, 0))
    end)

    it('uses one candidate for an any-input sequence', function()
        local interpreter = Interpreter:new()
        local template = {
            action_inputs = {
                special_action = {
                    input_sequence = {
                        {
                            inputs = {
                                { input = 'action_one_pressed', value = true },
                                { input = 'action_two_pressed', value = true },
                            },
                        },
                    },
                },
            },
        }

        interpreter:set_target(template, 'special_action', 0)

        assert.is_true(interpreter:value('action_one_pressed', false, 0))
        assert.is_false(interpreter:value('action_two_pressed', false, 0))
    end)

    it('follows start attack with a light release on the next frame', function()
        local interpreter = Interpreter:new()
        local template = {
            action_inputs = {
                start_attack = {
                    input_sequence = { { input = 'action_one_hold', value = true } },
                },
                light_attack = {
                    input_sequence = { { input = 'action_one_hold', value = false } },
                },
            },
        }

        interpreter:set_target(template, 'start_attack', 0, nil, nil, { 'light_attack' })

        assert.is_true(interpreter:value('action_one_hold', true, 0))
        assert.is_false(interpreter:value('action_one_hold', true, 0.02))
    end)

    it('keeps primary forced off after submission while the queued entry waits', function()
        local interpreter = Interpreter:new()
        local template = {
            action_inputs = {
                start_attack = {
                    buffer_time = 0.35,
                    input_sequence = { { input = 'action_one_hold', value = true } },
                },
            },
        }

        interpreter:set_target(template, 'start_attack', 0)
        assert.is_true(interpreter:value('action_one_hold', true, 0))
        assert.is_false(interpreter:value('action_one_hold', true, 0.02))
        assert.is_false(interpreter:value('action_one_pressed', true, 0.02))
        assert.is_true(interpreter:value('action_two_hold', true, 0.02))
    end)

    it('restarts a stale submitted input before its buffer expires', function()
        local interpreter = Interpreter:new()
        local template = {
            action_inputs = {
                start_attack = {
                    buffer_time = 0.35,
                    input_sequence = { { input = 'action_one_hold', value = true } },
                },
            },
        }

        interpreter:set_target(template, 'start_attack', 0)
        interpreter:value('action_one_hold', true, 0)
        interpreter:value('action_one_hold', true, 0.02)
        assert.is_false(interpreter:value('action_one_hold', true, 0.31))
        assert.is_true(interpreter:value('action_one_hold', true, 0.33))
    end)

    it('preserves an explicit false hold input', function()
        local interpreter = Interpreter:new()
        local template = {
            action_inputs = {
                test_input = {
                    input_sequence = {
                        {
                            hold_input = 'action_two_hold',
                            input = 'action_two_hold',
                            value = false,
                        },
                    },
                },
            },
        }

        interpreter:set_target(template, 'test_input', 0)

        assert.is_false(interpreter:value('action_two_hold', true, 0))
    end)
end)
