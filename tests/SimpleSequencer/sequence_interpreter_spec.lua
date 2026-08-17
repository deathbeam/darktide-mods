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

        interpreter:set_program(template, { 'light_attack' }, 0)

        assert.is_true(interpreter:can_interpret())
        assert.is_false(interpreter:value('action_one_hold', true, 0))
        assert.is_true(interpreter:controls('action_one_hold'))
    end)

    it('reports a configured target with no input sequence as unavailable', function()
        local interpreter = Interpreter:new()
        local template = { action_inputs = {} }

        interpreter:set_program(template, { 'start_attack' }, 0)
        assert.is_false(interpreter:can_interpret())
        assert.is_true(interpreter:is_missing_sequence())

        interpreter:set_program(template, nil, 0)
        assert.is_false(interpreter:is_missing_sequence())
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

        interpreter:set_program(template, { 'heavy_attack' }, 0)

        assert.is_true(interpreter:value('action_one_hold', false, 0))
        assert.is_true(interpreter:value('action_one_hold', false, 0.1))
        assert.is_true(interpreter:value('action_one_hold', true, 0.25))
        assert.is_false(interpreter:value('action_one_hold', true, 0.26))
    end)

    it('records a submission only after its final input element', function()
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

        interpreter:set_program(template, { 'heavy_attack' }, 0)
        interpreter:value('action_one_hold', false, 0)
        interpreter:update(0.25)
        assert.same({}, interpreter.submitted_inputs)
        interpreter:value('action_one_hold', true, 0.26)
        interpreter:update(0.27)
        assert.same({ 'heavy_attack' }, interpreter.submitted_inputs)
    end)

    it('consumes queued input when the action event arrives after submission', function()
        local interpreter = Interpreter:new()
        interpreter.input_name = 'follow_up'
        interpreter.submitted_inputs = { 'start_attack' }

        assert.are.equal('start_attack', interpreter:consume_action_input())
        assert.same({}, interpreter.submitted_inputs)
    end)

    it('starts a buffered follow-up duration from the action boundary', function()
        local interpreter = Interpreter:new()
        local template = {
            action_inputs = {
                start_attack = { input_sequence = { { input = 'action_one_hold', value = true } } },
                heavy_attack = {
                    input_sequence = {
                        { duration = 0.35, input = 'action_one_hold', value = true },
                        { input = 'action_one_hold', value = false },
                    },
                },
            },
        }

        interpreter:set_program(template, { 'start_attack', 'heavy_attack' }, 0, nil, 0)
        interpreter:value('action_one_hold', true, 0, 0)
        interpreter:update(0.01, 1)
        interpreter:value('action_one_hold', true, 0.1, 2)

        assert.are.equal('start_attack', interpreter:consume_action_input(nil, 0.2))
        assert.is_true(interpreter:value('action_one_hold', true, 0.4, 3))
        assert.is_true(interpreter:value('action_one_hold', true, 0.56, 4))
        assert.is_false(interpreter:value('action_one_hold', true, 0.57, 5))
    end)

    it('restarts a completed duration follow-up when its buffered root action starts', function()
        local interpreter = Interpreter:new()
        local template = {
            action_inputs = {
                start_attack = { input_sequence = { { input = 'action_one_hold', value = true } } },
                heavy_attack = {
                    input_sequence = {
                        { duration = 0.25, input = 'action_one_hold', value = true },
                        { input = 'action_one_hold', value = false },
                    },
                },
            },
        }

        interpreter:set_program(template, { 'start_attack', 'heavy_attack' }, 0, nil, 0)
        interpreter:value('action_one_hold', true, 0, 0)
        interpreter:update(0.01, 1)
        interpreter:value('action_one_hold', true, 0.01, 1)
        interpreter:update(0.25, 2)
        interpreter:value('action_one_hold', true, 0.26, 3)
        interpreter:update(0.27, 4)

        assert.is_true(interpreter:has_submitted())
        assert.are.equal('start_attack', interpreter:consume_action_input(nil, 0.3))
        assert.is_false(interpreter:has_submitted())
        assert.same({}, interpreter.submitted_inputs)
        assert.is_true(interpreter:value('action_one_hold', true, 0.31, 5))
    end)

    it('marks the current input when the action event arrives first', function()
        local interpreter = Interpreter:new()
        local template = {
            action_inputs = {
                light_attack = { input_sequence = { { input = 'action_one_hold', value = true } } },
            },
        }

        interpreter:set_program(template, { 'light_attack' }, 0)

        assert.are.equal('light_attack', interpreter:consume_action_input())
        assert.are.equal('light_attack', interpreter.started_input)
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
        interpreter:set_program(template, { 'push_follow_up' }, 0.25, nil, 0)

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

        interpreter:set_program(template, { 'push' }, 0)

        assert.is_true(interpreter:value('action_two_hold', false, 0))
        assert.is_true(interpreter:value('action_one_pressed', false, 0))
    end)

    it('advances an armed follow-up before parser inputs are read', function()
        local interpreter = Interpreter:new()
        local template = {
            action_inputs = {
                block = { input_sequence = { { input = 'action_two_hold', value = true } } },
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

        interpreter:set_program(template, { 'block', 'push' }, 0)
        assert.is_true(interpreter:value('action_two_hold', false, 0))
        interpreter:update(0.02)
        assert.are.equal('push', interpreter:active_input_name())
        assert.is_true(interpreter:value('action_one_pressed', false, 0.02))
        assert.is_true(interpreter:value('action_two_hold', false, 0.02))
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

        interpreter:set_program(template, { 'special_action' }, 0)

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

        interpreter:set_program(template, { 'start_attack', 'light_attack' }, 0)

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

        interpreter:set_program(template, { 'start_attack' }, 0)
        assert.is_true(interpreter:value('action_one_hold', true, 0))
        assert.is_false(interpreter:value('action_one_hold', true, 0.02))
        assert.is_false(interpreter:value('action_one_pressed', true, 0.02))
        assert.is_true(interpreter:value('action_two_hold', true, 0.02))
    end)

    it('preserves a submitted release on a transformed input', function()
        local interpreter = Interpreter:new()
        local template = {
            action_inputs = {
                light_attack_special = {
                    input_sequence = { { input = 'weapon_extra_hold', value = false } },
                },
            },
        }

        interpreter:set_program(template, { 'light_attack_special' }, 0)
        assert.is_false(interpreter:value('weapon_extra_hold', true, 0))
        assert.is_false(interpreter:value('weapon_extra_hold', true, 0.01))
        assert.is_false(interpreter:value('weapon_extra_hold', true, 0.02))
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

        interpreter:set_program(template, { 'start_attack' }, 0)
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

        interpreter:set_program(template, { 'test_input' }, 0)

        assert.is_false(interpreter:value('action_two_hold', true, 0))
    end)

    it('starts duration follow-ups when the preceding input matched', function()
        local interpreter = Interpreter:new()
        local template = {
            action_inputs = {
                start_attack = {
                    input_sequence = { { input = 'action_one_hold', value = true } },
                },
                heavy_attack = {
                    input_sequence = {
                        { duration = 0.25, input = 'action_one_hold', value = true },
                        { input = 'action_one_hold', value = false },
                    },
                },
            },
        }

        interpreter:set_program(template, { 'start_attack', 'heavy_attack' }, 0)

        assert.is_true(interpreter:value('action_one_hold', true, 0))
        assert.is_true(interpreter:value('action_one_hold', true, 0.24))
        assert.is_true(interpreter:value('action_one_hold', true, 0.25))
        assert.is_false(interpreter:value('action_one_hold', true, 0.26))
    end)

    it('releases a reevaluated root before its queued action starts', function()
        local interpreter = Interpreter:new()
        local template = {
            action_inputs = {
                start_attack = {
                    reevaluation_time = 0.18,
                    input_sequence = { { input = 'action_one_hold', value = true } },
                },
                light_attack = {
                    input_sequence = { { input = 'action_one_hold', value = false } },
                },
            },
        }

        interpreter:set_program(template, { 'start_attack', 'light_attack' }, 0)
        assert.is_true(interpreter:value('action_one_hold', true, 0))
        assert.is_false(interpreter:value('action_one_hold', true, 0.01))
        assert.are.equal('start_attack', interpreter:pending_action_input())

        assert.are.equal('start_attack', interpreter:consume_action_input())
        assert.are.equal('light_attack', interpreter:pending_action_input())
    end)
end)
