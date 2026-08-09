local DarktideMock = require('tests.shared.darktide_mock')

describe('SimpleSequencer SequenceController', function()
    local mock

    before_each(function()
        mock = DarktideMock.new()
    end)

    local function new_manager(profile)
        local manager = {
            toggles = 0,
        }

        function manager:active()
            return 'mode_1'
        end

        function manager:profile()
            return profile
        end

        function manager:toggle()
            self.toggles = self.toggles + 1
        end

        return manager
    end

    local function input(engine, action_name, value, raw_inputs)
        return mock:handle_input(engine, action_name, value, raw_inputs)
    end

    it('resets goal and input state', function()
        local engine = mock:load_controller(new_manager(nil))

        engine.sequence.index = 2
        engine.sequence.plan.goals = { { command = 'light_attack', inputs = { 'start_attack' } } }
        engine.sequence.no_repeat_restored = true
        engine.action.started = { token = 'light_attack:1', input = 'light_attack' }
        engine.action.window_token = 'light_attack:1'
        engine.activation.primary = true
        engine.activation.secondary = true
        engine.sequence.transition = { kind = 'terminal', token = 'light_attack:1' }
        engine.interpreter.input_name = 'start_attack'

        engine:reset()

        assert.are.equal(1, engine.sequence.index)
        assert.is_false(engine.activation.primary)
        assert.is_false(engine.activation.secondary)
        assert.is_false(engine.sequence.no_repeat_restored)
        assert.is_nil(engine.sequence.transition)
        assert.is_nil(engine.action.started)
        assert.is_nil(engine.action.window_token)
        assert.is_nil(engine.interpreter.input_name)
    end)

    it('records the interpreter input when an action starts', function()
        mock:set_weapon('slot_primary', 'test_action_start_input', {
            displayed_attacks = { primary = { type = 'melee' } },
            actions = {
                action_push = {
                    kind = 'push',
                    allowed_chain_actions = {
                        push_follow_up = { action_name = 'action_push_follow' },
                    },
                },
                action_push_follow = { kind = 'sweep' },
            },
        })
        mock:set_wielded_slot('slot_primary')
        local engine = mock:load_controller(new_manager(nil))
        engine:_refresh_context()
        engine.interpreter.input_name = 'push_follow_up'

        engine:on_action_started('action_push_follow', 1)

        assert.are.equal('push_follow_up', engine.action.started.input)
    end)

    it('advances goals from action-input metadata', function()
        local profile = {
            sequence_cycle_point = 'no_repeat',
            sequence_step_1 = 'light_attack',
        }
        local engine = mock:load_controller(new_manager(profile))
        mock:set_wielded_slot('slot_primary')
        engine:_refresh_context()

        assert.same({ 'start_attack', 'light_attack' }, engine.sequence.plan.goals[1].inputs)

        engine.activation.primary = true
        mock:set_action('action_melee_start', { kind = 'windup', start_input = 'start_attack' }, 0)
        input(engine, 'action_one_hold', true)

        mock:set_action('action_light', { kind = 'sweep', start_input = 'light_attack' }, 1)
        input(engine, 'action_one_hold', true)
        assert.is_not_nil(engine.sequence.transition)

        mock:set_action('none')
        input(engine, 'action_one_hold', true)

        assert.is_nil(engine.sequence.index)
    end)

    it('waits for the braced charge chain before firing', function()
        local profile = {
            automatic_fire_ads = 'charged',
        }
        mock:set_weapon('slot_secondary', 'test_ads', {
            action_inputs = {
                brace = { input_sequence = { { input = 'action_two_hold', value = true } } },
                shoot_braced = { input_sequence = { { input = 'action_one_pressed', value = true } } },
            },
            action_input_hierarchy = {
                {
                    input = 'brace',
                    transition = { { input = 'shoot_braced', transition = 'base' } },
                },
            },
            actions = {
                action_charge = {
                    kind = 'overload_charge',
                    start_input = 'brace',
                    allowed_chain_actions = {
                        shoot_braced = { action_name = 'action_shoot_charged', chain_time = 0.75 },
                    },
                },
                action_shoot_charged = { kind = 'shoot_hit_scan', use_charge = true },
            },
        })
        mock:set_wielded_slot('slot_secondary')
        local engine = mock:load_controller(new_manager(profile))
        mock:set_charge(1, 1, 0)

        mock:set_action('none')
        assert.is_true(input(engine, 'action_two_hold', true))

        mock:set_action('action_charge', engine.context.template.actions.action_charge, 0)
        assert.is_false(input(engine, 'action_one_pressed', false))

        mock.now = 0.75
        assert.is_true(input(engine, 'action_one_pressed', false))
    end)

    it('interprets charge thresholds as a percentage of maximum charge', function()
        local profile = {
            automatic_fire_ads = 'charged',
            auto_charge_threshold = 50,
        }
        mock:set_weapon('slot_secondary', 'test_fractional_charge', {
            action_inputs = {
                brace = { input_sequence = { { input = 'action_two_hold', value = true } } },
            },
            actions = {
                action_charge = {
                    kind = 'overload_charge',
                    start_input = 'brace',
                },
            },
        })
        mock:set_wielded_slot('slot_secondary')
        local engine = mock:load_controller(new_manager(profile))
        engine:_refresh_context()
        engine.sequence.plan = { goals = { { command = 'charged', inputs = { 'brace' } } } }
        mock:set_charge(0.2625, 0.525, 0)
        mock:set_action('action_charge', engine.context.template.actions.action_charge, 0)

        assert.is_true(engine:_charge_ready(0, engine.context.template.actions.action_charge))
    end)

    it('keeps automatic fire on the ADS plan with toggle ADS', function()
        local profile = {
            automatic_fire_ads = 'charged',
        }
        mock:set_weapon('slot_secondary', 'test_toggle_ads', {
            action_inputs = {
                brace = {
                    input_sequence = {
                        {
                            input = 'action_two_hold',
                            value = true,
                            input_setting = {
                                input = 'action_two_pressed',
                                setting = 'toggle_ads',
                                setting_value = true,
                                value = true,
                            },
                        },
                    },
                },
                shoot_braced = { input_sequence = { { input = 'action_one_pressed', value = true } } },
            },
            action_input_hierarchy = {
                {
                    input = 'brace',
                    transition = { { input = 'shoot_braced', transition = 'base' } },
                },
            },
            actions = {
                action_charge = {
                    kind = 'overload_charge',
                    start_input = 'brace',
                    allowed_chain_actions = {
                        shoot_braced = { action_name = 'action_shoot_charged', chain_time = 0.75 },
                    },
                },
                action_shoot_charged = {
                    kind = 'shoot_hit_scan',
                    use_charge = true,
                    allowed_chain_actions = {
                        brace = { action_name = 'action_charge', chain_time = 0 },
                    },
                },
            },
        })
        mock:set_wielded_slot('slot_secondary')
        local engine = mock:load_controller(new_manager(profile))
        mock:set_charge(1, 1, 0)

        input(engine, 'toggle_ads', true)
        input(engine, 'action_two_pressed', true)
        mock:set_action('action_charge', {
            kind = 'overload_charge',
            start_input = 'brace',
            allowed_chain_actions = {
                shoot_braced = { action_name = 'action_shoot_charged', chain_time = 0.75 },
            },
        }, 0)
        mock.now = 0.75
        assert.is_true(input(engine, 'action_one_pressed', false))

        mock:set_action('action_shoot_charged', {
            kind = 'shoot_hit_scan',
            allowed_chain_actions = {
                brace = { action_name = 'action_charge', chain_time = 0 },
            },
        }, 0.75)
        input(engine, 'action_one_pressed', false)

        assert.is_true(input(engine, 'action_two_pressed', false))
    end)

    it('continues from a push into its follow-up chain', function()
        local profile = {
            sequence_cycle_point = 'no_repeat',
            sequence_step_1 = 'push',
            sequence_step_2 = 'push_attack',
        }
        mock:set_weapon('slot_primary', 'test_push_follow_up', {
            displayed_attacks = { primary = { type = 'melee' } },
            actions = {
                action_push_follow = { kind = 'sweep' },
            },
        })
        mock:set_wielded_slot('slot_primary')
        local engine = mock:load_controller(new_manager(profile))
        mock:set_action('action_push', {
            kind = 'push',
            start_input = 'push',
            allowed_chain_actions = {
                push_follow_up = { action_name = 'action_push_follow', chain_time = 0 },
            },
        }, 0)

        assert.is_true(input(engine, 'action_one_hold', true))
    end)

    it('recognizes a chained melee action without start-input metadata', function()
        local profile = {
            sequence_cycle_point = 'no_repeat',
            sequence_step_1 = 'light_attack',
        }
        mock:set_weapon('slot_primary', 'test_melee', {
            displayed_attacks = { primary = { type = 'melee' } },
            actions = {
                action_melee_start = {
                    kind = 'windup',
                    start_input = 'start_attack',
                    allowed_chain_actions = {
                        light_attack = { action_name = 'action_left_light' },
                    },
                },
                action_left_light = { kind = 'sweep' },
            },
        })
        mock:set_wielded_slot('slot_primary')
        local engine = mock:load_controller(new_manager(profile))
        engine:_refresh_context()
        engine.activation.primary = true

        mock:set_action('action_melee_start', { kind = 'windup', start_input = 'start_attack' }, 0)
        input(engine, 'action_one_hold', true)
        mock:set_action('action_left_light', { kind = 'sweep' }, 1)
        input(engine, 'action_one_hold', true)

        assert.is_not_nil(engine.sequence.transition)
    end)

    it('uses the action-start event input when chain metadata cannot resolve progress', function()
        local profile = {
            sequence_cycle_point = 'no_repeat',
            sequence_step_1 = 'light_attack',
        }
        mock:set_weapon('slot_primary', 'test_transonic_variant', {
            displayed_attacks = { primary = { type = 'melee' } },
            actions = {
                action_light_1_special = { kind = 'sweep' },
            },
        })
        mock:set_wielded_slot('slot_primary')
        local engine = mock:load_controller(new_manager(profile))
        engine:_refresh_context()
        engine.activation.primary = true

        engine.interpreter.input_name = 'light_attack'
        mock:set_action('action_light_1_special', { kind = 'sweep' }, 1)
        input(engine, 'action_one_hold', true)

        assert.is_not_nil(engine.sequence.transition)
    end)

    it('advances to the next goal at an action chain boundary', function()
        local profile = {
            sequence_cycle_point = 'no_repeat',
            sequence_step_1 = 'heavy_attack',
            sequence_step_2 = 'light_attack',
        }
        mock:set_weapon('slot_primary', 'test_melee_chain', {
            displayed_attacks = { primary = { type = 'melee' } },
            actions = {
                action_melee_start = {
                    kind = 'windup',
                    start_input = 'start_attack',
                    allowed_chain_actions = {
                        heavy_attack = { action_name = 'action_left_heavy' },
                    },
                },
                action_left_heavy = { kind = 'sweep' },
            },
        })
        mock:set_wielded_slot('slot_primary')
        local engine = mock:load_controller(new_manager(profile))
        engine:_refresh_context()
        engine.activation.primary = true

        mock:set_action('action_left_heavy', {
            kind = 'sweep',
            allowed_chain_actions = {
                start_attack = { chain_time = 0, action_name = 'action_melee_start' },
            },
        }, 1)
        mock.now = 1
        input(engine, 'action_one_hold', true)

        assert.are.equal(2, engine.sequence.index)
        assert.same({ 'start_attack', 'light_attack' }, engine.sequence.plan.goals[2].inputs)
        assert.are.equal('start_attack', engine:_goal_input())
    end)

    it('blocks unsupported inputs instead of falling back', function()
        local profile = {
            sequence_cycle_point = 'no_repeat',
            sequence_step_1 = 'light_attack',
        }
        local engine = mock:load_controller(new_manager(profile))
        mock:set_wielded_slot('slot_primary')
        engine:_refresh_context()
        engine.context.template.action_inputs.start_attack = nil
        engine.activation.primary = true

        assert.is_false(engine:_override_input('action_one_pressed', false))
        assert.is_true(engine.interpreter:is_missing_sequence())
    end)

    it('reports activity only for a running goal', function()
        local engine = mock:load_controller(new_manager(nil))
        engine.profile = {}
        engine.sequence.plan.goals = { { command = 'light_attack', inputs = { 'start_attack' } } }
        engine.activation.primary = true

        assert.is_true(engine:is_active())

        engine.sequence.index = nil
        assert.is_false(engine:is_active())
    end)

    it('passes a same-frame manual push attack through before the block input is read', function()
        local profile = {
            sequence_cycle_point = 'sequence_step_1',
            sequence_step_1 = 'light_attack',
        }
        local engine = mock:load_controller(new_manager(profile))
        mock:set_wielded_slot('slot_primary')
        engine:_refresh_context()
        engine.activation.primary = true
        engine.interpreter.submitted = true
        engine.sequence.transition = { kind = 'terminal', token = 'action_light:0' }
        mock:set_action('action_light', {
            kind = 'sweep',
            start_input = 'light_attack',
            allowed_chain_actions = {
                start_attack = { action_name = 'action_melee_start', chain_time = 0.5 },
            },
        }, 0)
        mock.now = 0.1

        assert.is_true(input(engine, 'action_one_pressed', true, { action_two_hold = true }))
        assert.is_false(engine.activation.primary)
        assert.is_false(engine.interpreter.submitted)
        assert.is_nil(engine.sequence.transition)
        assert.is_true(mock.input.secondary_held)
        assert.is_true(input(engine, 'action_two_hold', true))
    end)

    it('does not cancel automated push input while physical block is up', function()
        local profile = {
            sequence_cycle_point = 'sequence_step_1',
            sequence_step_1 = 'push_attack',
        }
        local engine = mock:load_controller(new_manager(profile))
        mock:set_wielded_slot('slot_primary')
        engine:_refresh_context()
        engine.activation.primary = true
        mock:set_action('action_block', {
            kind = 'block',
            start_input = 'block',
            allowed_chain_actions = {
                push = { action_name = 'action_push' },
            },
        }, 0)

        assert.is_true(input(engine, 'action_one_pressed', false))
        assert.are.equal(1, engine.sequence.index)
        assert.is_true(engine.activation.primary)
        assert.is_false(engine.activation.secondary)
    end)

    it('restores a no-repeat mode only once after completion', function()
        local manager = new_manager(nil)
        local engine = mock:load_controller(manager)

        engine.sequence.plan.goals = { { command = 'light_attack', inputs = { 'start_attack' } } }
        engine.sequence.index = 1
        engine:_advance()

        assert.is_nil(engine.sequence.index)
        assert.is_true(engine:_restore_after_no_repeat())
        assert.are.equal(1, manager.toggles)
        assert.is_false(engine:_restore_after_no_repeat())
        assert.are.equal(1, manager.toggles)
    end)

    it('waits for a start attack chain instead of buffering it early', function()
        mock:set_weapon('slot_primary', 'test_light_recovery', {
            displayed_attacks = { primary = { type = 'melee' } },
            action_inputs = {
                start_attack = {
                    buffer_time = 0.3,
                    input_sequence = { { input = 'action_one_hold', value = true } },
                },
                light_attack = {
                    buffer_time = 0.3,
                    input_sequence = { { input = 'action_one_hold', value = false } },
                },
            },
            actions = {
                action_light = {
                    kind = 'sweep',
                    start_input = 'light_attack',
                    allowed_chain_actions = {
                        start_attack = { action_name = 'action_melee_start', chain_time = 0.5 },
                    },
                },
                action_melee_start = {
                    kind = 'windup',
                    start_input = 'start_attack',
                    allowed_chain_actions = {
                        light_attack = { action_name = 'action_light', chain_time = 0 },
                    },
                },
            },
        })
        mock:set_wielded_slot('slot_primary')
        local engine = mock:load_controller(new_manager(nil))
        engine:_refresh_context()
        engine.profile = {}
        engine.sequence.plan = {
            goals = {
                { command = 'light_attack', inputs = { 'start_attack', 'light_attack' } },
                { command = 'light_attack', inputs = { 'start_attack', 'light_attack' } },
            },
            goal_cycle_index = 0,
        }
        engine.activation.primary = true
        mock:set_action('action_light', {
            kind = 'sweep',
            start_input = 'light_attack',
            allowed_chain_actions = {
                start_attack = { action_name = 'action_melee_start', chain_time = 0.5 },
            },
        }, 0)
        engine.sequence.transition = { kind = 'terminal', token = 'action_light:0' }

        mock.now = 0.1
        assert.is_false(input(engine, 'action_one_hold', true))

        mock.now = 0.2
        assert.is_false(input(engine, 'action_one_hold', true))

        mock.now = 0.5
        assert.is_true(input(engine, 'action_one_hold', true))

        mock.now = 0.52
        assert.is_false(input(engine, 'action_one_hold', true))
    end)
end)
