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
        engine.sequence.plan.goals = {
            { command = 'light_attack', inputs = { 'start_attack' }, programs = { { 'start_attack' } } },
        }
        engine.sequence.no_repeat_restored = true
        engine.action.started = { token = 'light_attack:1', input = 'light_attack' }
        engine.action.window_token = 'light_attack:1'
        engine.activation.primary = true
        engine.activation.secondary = true
        engine.sequence.program = { kind = 'terminal', token = 'light_attack:1' }
        engine.interpreter.input_name = 'start_attack'

        engine:reset()

        assert.are.equal(1, engine.sequence.index)
        assert.is_false(engine.activation.primary)
        assert.is_false(engine.activation.secondary)
        assert.is_false(engine.sequence.no_repeat_restored)
        assert.is_nil(engine.sequence.program)
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

    it('uses string automatic inputs without consuming parser state', function()
        local engine = mock:load_controller(new_manager(nil))
        engine.interpreter.input_name = 'stale_input'

        engine:on_action_started('action_automatic', 1, 'automatic_input')

        assert.are.equal('automatic_input', engine.action.started.input)
        assert.are.equal('stale_input', engine.interpreter.input_name)
    end)

    it('falls back to interpreter input for non-string automatic values', function()
        local engine = mock:load_controller(new_manager(nil))
        engine.interpreter.input_name = 'queued_input'

        engine:on_action_started('action_finish_reason', 1, true)

        assert.are.equal('queued_input', engine.action.started.input)
        assert.are.equal('queued_input', engine.interpreter.started_input)
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
        assert.are.equal('terminal', engine.sequence.program.kind)

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
        engine.sequence.plan = {
            goals = { { command = 'charged', inputs = { 'brace' }, programs = { { 'brace' } } } },
        }
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

    it('returns all remaining inputs when arming a Push path', function()
        mock:set_weapon('slot_primary', 'test_push_program', {
            actions = { action_push = { kind = 'push' } },
        })
        mock:set_wielded_slot('slot_primary')
        local engine = mock:load_controller(new_manager(nil))
        engine:_refresh_context()
        engine.sequence.plan.goals = {
            {
                command = 'push_attack',
                inputs = { 'block', 'push', 'push_follow_up' },
                programs = { { 'block' }, { 'push', 'push_follow_up' }, { 'push_follow_up' } },
            },
        }
        engine.sequence.index = 1
        engine.activation.primary = true
        mock:set_action('action_block', {
            kind = 'block',
            start_input = 'block',
            allowed_chain_actions = {
                push = { action_name = 'action_push' },
            },
        }, 0)

        local input_name, followup_inputs = engine:_goal_input()
        assert.are.equal('push', input_name)
        assert.same({ 'push_follow_up' }, followup_inputs)
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

        assert.are.equal('terminal', engine.sequence.program.kind)
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

        assert.are.equal('terminal', engine.sequence.program.kind)
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
        engine.sequence.plan.goals = {
            { command = 'light_attack', inputs = { 'start_attack' }, programs = { { 'start_attack' } } },
        }
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
        engine.sequence.program = { kind = 'terminal', token = 'action_light:0' }
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
        assert.is_nil(engine.sequence.program)
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

        engine.sequence.plan.goals = {
            { command = 'light_attack', inputs = { 'start_attack' }, programs = { { 'start_attack' } } },
        }
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
                {
                    command = 'light_attack',
                    inputs = { 'start_attack', 'light_attack' },
                    programs = { { 'start_attack', 'light_attack' }, { 'light_attack' } },
                },
                {
                    command = 'light_attack',
                    inputs = { 'start_attack', 'light_attack' },
                    programs = { { 'start_attack', 'light_attack' }, { 'light_attack' } },
                },
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
        engine.sequence.program = { kind = 'terminal', token = 'action_light:0' }

        mock.now = 0.1
        assert.is_false(input(engine, 'action_one_hold', true))

        mock.now = 0.2
        assert.is_false(input(engine, 'action_one_hold', true))

        mock.now = 0.5
        assert.is_true(input(engine, 'action_one_hold', true))

        mock.now = 0.52
        assert.is_false(input(engine, 'action_one_hold', true))
    end)

    it('restarts a released light sequence before the current action becomes idle', function()
        mock:set_weapon('slot_primary', 'test_released_light', {
            displayed_attacks = { primary = { type = 'melee' } },
            actions = {
                action_light = {
                    kind = 'sweep',
                    start_input = 'light_attack',
                    allowed_chain_actions = {
                        start_attack = { action_name = 'action_melee_start', chain_time = 0 },
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
                {
                    command = 'light_attack',
                    inputs = { 'start_attack', 'light_attack' },
                    programs = { { 'start_attack', 'light_attack' }, { 'light_attack' } },
                },
            },
            goal_cycle_index = 0,
        }
        engine.activation.primary = true
        engine.sequence.program = { kind = 'terminal', token = 'action_light:0' }
        mock:set_action('action_light', engine.context.template.actions.action_light, 0)

        assert.is_false(input(engine, 'action_one_hold', false))
        assert.is_false(engine.activation.primary)
        assert.is_nil(engine.sequence.program)
        assert.is_nil(engine.interpreter.input_name)

        mock.now = 0.1
        local _, action_input = mock:run_input_frame(engine, {
            action_one_pressed = true,
            action_one_hold = true,
        })

        assert.are.equal('start_attack', action_input)
        assert.are.equal('action_melee_start', mock:current_action_name())
    end)
    it('replans special attacks after their parser program, not after the action becomes idle', function()
        local profile = {
            sequence_cycle_point = 'sequence_step_1',
            sequence_step_1 = 'special_action_heavy',
        }
        mock:set_weapon('slot_primary', 'test_charge_aware_special_attack', {
            displayed_attacks = { primary = { type = 'melee' } },
            weapon_special_tweak_data = { num_charges_to_consume_on_activation = 1 },
            action_inputs = {
                start_attack_special = { input_sequence = { { input = 'weapon_extra_hold', value = true } } },
                heavy_attack_special = { input_sequence = { { input = 'weapon_extra_hold', value = false } } },
            },
            action_input_hierarchy = {
                { input = 'start_attack', transition = { { input = 'heavy_attack', transition = 'base' } } },
                {
                    input = 'start_attack_special',
                    transition = { { input = 'heavy_attack_special', transition = 'base' } },
                },
            },
        })
        mock:set_wielded_slot('slot_primary')
        mock:set_special_charges(0)
        local engine = mock:load_controller(new_manager(profile))
        engine:_refresh_context()
        engine.activation.primary = true
        mock:set_action('action_heavy', { kind = 'sweep' }, 0)
        mock:set_special_charges(2)
        engine:_refresh_context()
        assert.same({ 'start_attack_special', 'heavy_attack_special' }, engine:_goal().inputs)
        assert.is_true(engine.activation.primary)

        engine.interpreter.input_name = 'heavy_attack_special'
        engine.interpreter.submitted = false
        engine.action.started = { input = 'start_attack_special' }
        mock:set_action('action_special_start', { kind = 'windup' }, 1)
        mock:set_special_active(true)
        mock:set_special_charges(1)
        engine:_refresh_context()
        assert.same({ 'start_attack_special', 'heavy_attack_special' }, engine:_goal().inputs)
        assert.are.equal(1, engine.context.special_charges)
        assert.is_true(engine.context.special_active)
        assert.is_nil(engine.pending_transition)
        assert.are.equal('heavy_attack_special', engine.interpreter:active_input_name())

        mock:set_special_charges(0)
        engine:_refresh_context()
        assert.same({ 'start_attack_special', 'heavy_attack_special' }, engine:_goal().inputs)

        engine.interpreter.submitted = true
        engine.action.started = { input = 'start_attack_special' }
        engine.sequence.program = {
            kind = 'normal',
            inputs = { 'start_attack_special', 'heavy_attack_special' },
        }
        engine:_refresh_context()
        assert.is_not_nil(engine.pending_transition)
        assert.same({ 'start_attack_special', 'heavy_attack_special' }, engine:_goal().inputs)
        engine.interpreter.template = engine.context.template
        engine.interpreter.target_name = 'start_attack_special'
        engine.interpreter.followup_inputs = { 'heavy_attack_special' }
        engine.interpreter.restart_after = 0.1
        engine.interpreter.submitted_t = 0
        mock.now = 1
        engine:_sync_interpreter()
        assert.are.equal('heavy_attack_special', engine.interpreter:active_input_name())

        mock:set_action('action_special_heavy', { kind = 'sweep' }, 1.8)
        engine.action.started = { input = 'heavy_attack_special' }
        engine:_refresh_context()
        assert.same({ 'start_attack', 'heavy_attack' }, engine:_goal().inputs)
        assert.is_true(engine.activation.primary)
    end)
end)
describe('SimpleSequencer SequenceController integration', function()
    local mock

    before_each(function()
        mock = DarktideMock.new()
    end)

    local function new_manager(profile)
        return {
            active = function()
                return 'mode_1'
            end,
            profile = function()
                return profile
            end,
            toggle = function() end,
        }
    end

    it('fires a braced plasma shot only at the game chain boundary', function()
        mock:set_weapon('slot_secondary', 'test_plasma', {
            action_inputs = {
                brace = { input_sequence = { { input = 'action_two_hold', value = true } } },
                shoot_braced = {
                    buffer_time = 0.1,
                    input_sequence = { { input = 'action_one_pressed', value = true } },
                },
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
        local engine = mock:load_controller(new_manager({ automatic_fire_ads = 'charged' }))
        mock:set_charge(0.99, 1, 0)

        local _, input = mock:run_input_frame(engine, { action_two_hold = true })
        assert.are.equal('brace', input)
        assert.are.equal('action_charge', mock:current_action_name())

        mock.now = 0.64
        _, input = mock:run_input_frame(engine, { action_two_hold = true })
        assert.is_nil(input)
        assert.are.equal('action_charge', mock:current_action_name())

        mock.now = 0.65
        _, input = mock:run_input_frame(engine, { action_two_hold = true })
        assert.is_nil(input)
        assert.are.equal('action_charge', mock:current_action_name())

        mock:set_charge(1, 1, 0)
        mock.now = 0.75
        _, input = mock:run_input_frame(engine, { action_two_hold = true })
        assert.are.equal('shoot_braced', input)
        assert.are.equal('action_shoot_charged', mock:current_action_name())
    end)

    it('prioritizes block over the primary start attack for secondary sequences', function()
        local function run(command)
            mock = DarktideMock.new()
            mock:set_weapon('slot_primary', 'test_secondary_sequence', {
                displayed_attacks = { primary = { type = 'melee' } },
                actions = {
                    action_melee_start = { kind = 'windup', start_input = 'start_attack' },
                    action_block = {
                        kind = 'block',
                        start_input = 'block',
                        allowed_chain_actions = { push = { action_name = 'action_push' } },
                    },
                    action_push = {
                        kind = 'push',
                        allowed_chain_actions = { push_follow_up = { action_name = 'action_push_follow' } },
                    },
                    action_push_follow = { kind = 'sweep' },
                },
            })
            mock:set_wielded_slot('slot_primary')
            local engine = mock:load_controller(new_manager({
                sequence_cycle_point = 'no_repeat',
                sequence_step_1 = command,
            }))
            local held_inputs = { action_one_hold = true }
            local inputs, input = mock:run_input_frame(engine, held_inputs)

            assert.are.equal('block', input)
            assert.are.equal('action_block', mock:current_action_name())

            if command == 'block' then
                inputs, input = mock:run_input_frame(engine, held_inputs)
                assert.is_true(inputs.action_two_hold)
                assert.is_false(inputs.action_one_hold)
                return
            end

            _, input = mock:run_input_frame(engine, held_inputs)
            assert.are.equal('push', input)
            assert.are.equal('action_push', mock:current_action_name())

            if command == 'push' then
                return
            end

            mock.now = 0.25
            _, input = mock:run_input_frame(engine, held_inputs)
            assert.are.equal('push_follow_up', input)
            assert.are.equal('action_push_follow', mock:current_action_name())
        end

        run('block')
        run('push')
        run('push_attack')
    end)

    it('returns a push follow-up to base before starting a following heavy attack', function()
        mock:set_weapon('slot_primary', 'test_push_follow_up_heavy', {
            displayed_attacks = { primary = { type = 'melee' } },
            action_inputs = {
                finish_push_follow_up = {
                    dont_queue = true,
                    input_sequence = { { input = 'action_one_hold', value = false } },
                },
            },
            action_input_hierarchy = {
                {
                    input = 'start_attack',
                    transition = {
                        { input = 'heavy_attack', transition = 'base' },
                        { input = 'light_attack', transition = 'base' },
                    },
                },
                {
                    input = 'block',
                    transition = {
                        {
                            input = 'push',
                            transition = {
                                {
                                    input = 'push_follow_up',
                                    transition = { { input = 'finish_push_follow_up', transition = 'base' } },
                                },
                            },
                        },
                    },
                },
            },
            actions = {
                action_melee_start = {
                    kind = 'windup',
                    start_input = 'start_attack',
                    allowed_chain_actions = {
                        heavy_attack = { action_name = 'action_heavy' },
                        light_attack = { action_name = 'action_light' },
                    },
                },
                action_block = {
                    kind = 'block',
                    start_input = 'block',
                    allowed_chain_actions = { push = { action_name = 'action_push' } },
                },
                action_push = {
                    kind = 'push',
                    allowed_chain_actions = { push_follow_up = { action_name = 'action_push_follow' } },
                },
                action_push_follow = {
                    kind = 'sweep',
                    allowed_chain_actions = { start_attack = { action_name = 'action_melee_start' } },
                },
                action_heavy = {
                    kind = 'sweep',
                    start_input = 'heavy_attack',
                    allowed_chain_actions = { start_attack = { action_name = 'action_melee_start' } },
                },
                action_light = { kind = 'sweep', start_input = 'light_attack' },
            },
        })
        mock:set_wielded_slot('slot_primary')
        local engine = mock:load_controller(new_manager({
            sequence_cycle_point = 'no_repeat',
            sequence_step_1 = 'push_attack',
            sequence_step_2 = 'heavy_attack',
            sequence_step_3 = 'light_attack',
        }))
        local held_inputs = { action_one_hold = true }
        local _, input = mock:run_input_frame(engine, held_inputs)

        assert.are.equal('block', input)
        _, input = mock:run_input_frame(engine, held_inputs)
        assert.are.equal('push', input)
        mock.now = 0.25
        _, input = mock:run_input_frame(engine, held_inputs)
        assert.are.equal('push_follow_up', input)

        mock.now = 0.26
        local inputs
        inputs, input = mock:run_input_frame(engine, held_inputs)
        assert.are.equal('finish_push_follow_up', input)
        assert.is_false(inputs.action_one_hold)

        mock.now = 0.27
        _, input = mock:run_input_frame(engine, held_inputs)
        assert.are.equal('start_attack', input)
        assert.are.equal('action_melee_start', mock:current_action_name())
        mock.now = 0.28
        mock:run_input_frame(engine, held_inputs)
        mock.now = 0.53
        mock:run_input_frame(engine, held_inputs)
        mock.now = 0.54
        _, input = mock:run_input_frame(engine, held_inputs)
        assert.are.equal('heavy_attack', input)
        assert.are.equal('action_heavy', mock:current_action_name())

        mock.now = 0.55
        _, input = mock:run_input_frame(engine, held_inputs)
        assert.are.equal('start_attack', input)
        assert.are.equal('action_melee_start', mock:current_action_name())
        mock.now = 0.56
        _, input = mock:run_input_frame(engine, held_inputs)
        assert.are.equal('light_attack', input)
    end)

    it('uses terminal return-to-base inputs before chaining from block and push', function()
        local function run(command, release_input)
            mock = DarktideMock.new()
            local block_transition
            local actions = {
                action_melee_start = {
                    kind = 'windup',
                    start_input = 'start_attack',
                    allowed_chain_actions = { heavy_attack = { action_name = 'action_heavy' } },
                },
                action_heavy = { kind = 'sweep', start_input = 'heavy_attack' },
            }

            if command == 'block' then
                block_transition = { { input = release_input, transition = 'base' } }
                actions.action_block = {
                    kind = 'block',
                    start_input = 'block',
                    allowed_chain_actions = { start_attack = { action_name = 'action_melee_start' } },
                }
            else
                block_transition = {
                    {
                        input = 'push',
                        transition = { { input = release_input, transition = 'base' } },
                    },
                }
                actions.action_block = {
                    kind = 'block',
                    start_input = 'block',
                    allowed_chain_actions = { push = { action_name = 'action_push' } },
                }
                actions.action_push = {
                    kind = 'push',
                    allowed_chain_actions = { start_attack = { action_name = 'action_melee_start' } },
                }
            end

            mock:set_weapon('slot_primary', 'test_terminal_release_' .. command, {
                displayed_attacks = { primary = { type = 'melee' } },
                action_inputs = {
                    [release_input] = {
                        dont_queue = true,
                        input_sequence = { { input = 'action_one_hold', value = false } },
                    },
                },
                action_input_hierarchy = {
                    {
                        input = 'start_attack',
                        transition = { { input = 'heavy_attack', transition = 'base' } },
                    },
                    { input = 'block', transition = block_transition },
                },
                actions = actions,
            })
            mock:set_wielded_slot('slot_primary')
            local engine = mock:load_controller(new_manager({
                sequence_cycle_point = 'no_repeat',
                sequence_step_1 = command,
                sequence_step_2 = 'heavy_attack',
            }))
            local held_inputs = { action_one_hold = true }
            local _, input = mock:run_input_frame(engine, held_inputs)

            assert.are.equal('block', input)

            local release_t = 0.01
            if command == 'push' then
                mock.now = release_t
                _, input = mock:run_input_frame(engine, held_inputs)
                assert.are.equal('push', input)
                release_t = 0.02
            end

            mock.now = release_t
            _, input = mock:run_input_frame(engine, held_inputs)
            assert.are.equal(release_input, input)
            mock.now = release_t + 0.01
            _, input = mock:run_input_frame(engine, held_inputs)
            assert.are.equal('start_attack', input)
            assert.are.equal('action_melee_start', mock:current_action_name())
        end

        run('block', 'finish_block')
        run('push', 'finish_push')
    end)

    it('keeps the Push Follow-up path armed while Push waits to be consumed', function()
        mock:set_weapon('slot_primary', 'test_delayed_push', {
            displayed_attacks = { primary = { type = 'melee' } },
            action_inputs = {
                push_follow_up = {
                    input_sequence = {
                        {
                            hold_input = 'action_two_hold',
                            input = 'action_one_hold',
                            value = true,
                        },
                    },
                },
            },
            action_input_hierarchy = {
                {
                    input = 'block',
                    transition = {
                        {
                            input = 'push',
                            transition = { { input = 'push_follow_up', transition = 'base' } },
                        },
                    },
                },
            },
            actions = {
                action_block = {
                    kind = 'block',
                    start_input = 'block',
                    allowed_chain_actions = { push = { action_name = 'action_push', chain_time = 0 } },
                },
                action_push = {
                    kind = 'push',
                    start_input = 'push',
                    allowed_chain_actions = {
                        push_follow_up = { action_name = 'action_push_follow', chain_time = 0 },
                    },
                },
                action_push_follow = { kind = 'sweep' },
            },
        })
        mock:set_wielded_slot('slot_primary')
        mock:set_input_delay(1)
        local engine = mock:load_controller(new_manager({
            sequence_cycle_point = 'no_repeat',
            sequence_step_1 = 'push_attack',
        }))
        local held_inputs = { action_one_hold = true }

        local _, input = mock:run_input_frame(engine, held_inputs)
        assert.are.equal('block', input)
        _, input = mock:run_input_frame(engine, held_inputs)
        assert.are.equal('action_block', mock:current_action_name())
        _, input = mock:run_input_frame(engine, held_inputs)
        assert.are.equal('push', input)

        local inputs
        inputs, input = mock:run_input_frame(engine, held_inputs)
        assert.are.equal('push_follow_up', input)
        assert.is_true(inputs.action_one_hold)
        assert.is_true(inputs.action_two_hold)
        assert.are.equal('action_push', mock:current_action_name())
        assert.are.equal('push', engine.action.started.input)
        _, input = mock:run_input_frame(engine, held_inputs)
        assert.are.equal('push_follow_up', input)
        assert.are.equal('action_push_follow', mock:current_action_name())
        assert.are.equal('push_follow_up', engine.action.started.input)
    end)

    it('keeps a push follow-up held until its game chain opens', function()
        mock:set_weapon('slot_primary', 'test_push', {
            displayed_attacks = { primary = { type = 'melee' } },
            action_input_hierarchy = {
                {
                    input = 'block',
                    transition = {
                        {
                            input = 'push',
                            transition = { { input = 'push_follow_up', transition = 'base' } },
                        },
                    },
                },
            },
            actions = {
                action_block = {
                    kind = 'block',
                    start_input = 'block',
                    allowed_chain_actions = {
                        push = { action_name = 'action_push', chain_time = 0 },
                    },
                },
                action_push = {
                    kind = 'push',
                    start_input = 'push',
                    allowed_chain_actions = {
                        push_follow_up = { action_name = 'action_push_follow', chain_time = 0.25 },
                    },
                },
                action_push_follow = { kind = 'sweep' },
            },
        })
        mock:set_wielded_slot('slot_primary')
        local engine = mock:load_controller(new_manager({
            sequence_cycle_point = 'no_repeat',
            sequence_step_1 = 'push',
            sequence_step_2 = 'push_attack',
        }))
        local held_inputs = { action_one_hold = true }

        mock:run_input_frame(engine, held_inputs)
        mock:run_input_frame(engine, held_inputs)
        assert.are.equal('action_push', mock:current_action_name())

        mock.now = 0.24
        mock:run_input_frame(engine, held_inputs)
        assert.are.equal('action_push', mock:current_action_name())

        mock.now = 0.25
        local _, input = mock:run_input_frame(engine, held_inputs)
        assert.are.equal('push_follow_up', input)
        assert.are.equal('action_push_follow', mock:current_action_name())
    end)

    it('keeps primary held while a delayed push follow-up sequence arms', function()
        mock:set_weapon('slot_primary', 'test_delayed_push_follow_up', {
            displayed_attacks = { primary = { type = 'melee' } },
            action_inputs = {
                push_follow_up = {
                    buffer_time = 0.1,
                    input_sequence = {
                        {
                            duration = 0.3,
                            hold_input = 'action_two_hold',
                            input = 'action_one_hold',
                            value = true,
                        },
                    },
                },
            },
            action_input_hierarchy = {
                {
                    input = 'block',
                    transition = {
                        {
                            input = 'push',
                            transition = { { input = 'push_follow_up', transition = 'base' } },
                        },
                    },
                },
            },
            actions = {
                action_block = {
                    kind = 'block',
                    start_input = 'block',
                    allowed_chain_actions = { push = { action_name = 'action_push' } },
                },
                action_push = {
                    kind = 'push',
                    allowed_chain_actions = {
                        push_follow_up = {
                            { action_name = 'action_push_follow_special', chain_time = 0.3 },
                            { action_name = 'action_push_follow', chain_time = 0.3 },
                        },
                    },
                },
                action_push_follow_special = {
                    kind = 'sweep',
                    action_condition_func = function()
                        return false
                    end,
                },
                action_push_follow = { kind = 'sweep' },
            },
        })
        mock:set_wielded_slot('slot_primary')
        local engine = mock:load_controller(new_manager({
            sequence_cycle_point = 'no_repeat',
            sequence_step_1 = 'push_attack',
        }))
        local held_inputs = { action_one_hold = true }
        local _, input = mock:run_input_frame(engine, held_inputs)

        assert.are.equal('block', input)
        mock.now = 0.01
        _, input = mock:run_input_frame(engine, held_inputs)
        assert.are.equal('push', input)
        for _, t in ipairs({ 0.02, 0.1, 0.19 }) do
            mock.now = t
            mock:run_input_frame(engine, held_inputs)
        end
        mock.now = 0.31
        _, input = mock:run_input_frame(engine, held_inputs)

        assert.are.equal('push_follow_up', input)
        assert.are.equal('action_push_follow', mock:current_action_name())
    end)

    it('does not queue a second standard shot after a physical click releases', function()
        mock:set_weapon('slot_secondary', 'test_standard_click', {
            action_inputs = {
                shoot_pressed = {
                    buffer_time = 0.2,
                    max_queue = 2,
                    input_sequence = { { input = 'action_one_pressed', value = true } },
                },
            },
            action_input_hierarchy = { { input = 'shoot_pressed', transition = 'stay' } },
            actions = {
                action_shoot = {
                    kind = 'shoot_hit_scan',
                    start_input = 'shoot_pressed',
                    allowed_chain_actions = {
                        shoot_pressed = { action_name = 'action_shoot', chain_time = 0 },
                    },
                },
            },
        })
        mock:set_wielded_slot('slot_secondary')
        local engine = mock:load_controller(new_manager({ automatic_fire_hip = 'standard' }))

        local _, input = mock:run_input_frame(engine, { action_one_pressed = true, action_one_hold = true })
        assert.are.equal('shoot_pressed', input)
        mock.now = 0.01
        _, input = mock:run_input_frame(engine, {})
        assert.is_nil(input)
    end)

    it('waits for primary input before firing an ADS standard program', function()
        mock:set_weapon('slot_secondary', 'test_ads_standard', {
            action_inputs = {
                zoom = { input_sequence = { { input = 'action_two_hold', value = true } } },
                zoom_shoot = {
                    buffer_time = 0.225,
                    input_sequence = { { input = 'action_one_pressed', value = true } },
                },
            },
            action_input_hierarchy = {
                { input = 'shoot_pressed', transition = 'stay' },
                { input = 'zoom', transition = { { input = 'zoom_shoot', transition = 'stay' } } },
            },
            actions = {
                action_zoom = {
                    kind = 'aim',
                    start_input = 'zoom',
                    allowed_chain_actions = {
                        zoom_shoot = { action_name = 'action_shoot_zoomed', chain_time = 0 },
                    },
                },
                action_shoot_zoomed = {
                    kind = 'shoot_hit_scan',
                    start_input = 'zoom_shoot',
                    allowed_chain_actions = {
                        zoom_shoot = { action_name = 'action_shoot_zoomed', chain_time = 0.2 },
                    },
                },
            },
        })
        mock:set_wielded_slot('slot_secondary')
        local engine = mock:load_controller(new_manager({ automatic_fire_ads = 'standard' }))
        local ads_inputs = { action_two_hold = true }
        local _, input = mock:run_input_frame(engine, ads_inputs)
        assert.are.equal('zoom', input)
        assert.are.equal('action_zoom', mock:current_action_name())
        mock.now = 0.01
        _, input = mock:run_input_frame(engine, ads_inputs)
        assert.is_nil(input)
        mock.now = 0.02
        _, input = mock:run_input_frame(engine, {
            action_one_pressed = true,
            action_one_hold = true,
            action_two_hold = true,
        })
        assert.are.equal('zoom_shoot', input)
        mock.now = 0.03
        _, input = mock:run_input_frame(engine, { action_one_hold = true, action_two_hold = true })
        assert.is_nil(input)
        mock.now = 0.22
        _, input = mock:run_input_frame(engine, { action_one_hold = true, action_two_hold = true })
        assert.are.equal('zoom_shoot', input)
    end)

    it('pulses held standard fire at each game chain boundary', function()
        mock:set_weapon('slot_secondary', 'test_ranged_repeat', {
            action_input_hierarchy = { { input = 'shoot_pressed', transition = 'base' } },
            actions = {
                action_shoot = {
                    kind = 'shoot_hit_scan',
                    start_input = 'shoot_pressed',
                    allowed_chain_actions = {
                        shoot_pressed = { action_name = 'action_shoot', chain_time = 0.2 },
                    },
                },
            },
        })
        mock:set_wielded_slot('slot_secondary')
        local engine = mock:load_controller(new_manager({ automatic_fire_hip = 'standard' }))
        local held_inputs = { action_one_hold = true }

        mock:run_input_frame(engine, held_inputs)
        local _, input = mock:run_input_frame(engine, held_inputs)
        assert.are.equal('shoot_pressed', input)
        assert.are.equal('action_shoot', mock:current_action_name())

        mock.now = 0.19
        _, input = mock:run_input_frame(engine, held_inputs)
        assert.is_nil(input)

        mock.now = 0.2
        _, input = mock:run_input_frame(engine, held_inputs)
        assert.are.equal('shoot_pressed', input)
    end)

    it('fires standard shots after activating a ranged special state', function()
        mock:set_weapon('slot_secondary', 'test_special_state', {
            action_inputs = {
                special_action = { input_sequence = { { input = 'weapon_extra_pressed', value = true } } },
                shoot_pressed = { input_sequence = { { input = 'action_one_pressed', value = true } } },
            },
            action_input_hierarchy = {
                { input = 'special_action', transition = 'base' },
                { input = 'shoot_pressed', transition = 'stay' },
            },
            actions = {
                action_special = {
                    kind = 'activate_special',
                    start_input = 'special_action',
                    allowed_chain_actions = {
                        shoot_pressed = { action_name = 'action_shoot', chain_time = 0 },
                    },
                },
                action_shoot = { kind = 'shoot_hit_scan', start_input = 'shoot_pressed' },
            },
        })
        mock:set_wielded_slot('slot_secondary')
        local engine = mock:load_controller(new_manager({ automatic_fire_hip = 'special' }))
        local held_inputs = { action_one_hold = true }
        local _, input = mock:run_input_frame(engine, held_inputs)
        assert.are.equal('special_action', input)
        assert.are.equal('action_special', mock:current_action_name())

        mock:set_special_active(true)
        _, input = mock:run_input_frame(engine, held_inputs)
        assert.are.equal('shoot_pressed', input)
        assert.are.equal('action_shoot', mock:current_action_name())
    end)

    it('leaves physical input unchanged while a charge-gated special activation is unavailable', function()
        mock:set_weapon('slot_primary', 'test_charge_gated_special', {
            displayed_attacks = { primary = { type = 'melee' } },
            action_inputs = {
                start_attack = { input_sequence = { { input = 'action_one_hold', value = true } } },
                special_action = { input_sequence = { { input = 'weapon_extra_pressed', value = true } } },
            },
            action_input_hierarchy = {
                { input = 'start_attack', transition = 'base' },
                { input = 'special_action', transition = 'base' },
            },
            actions = {
                action_melee_start = { kind = 'windup', start_input = 'start_attack' },
                action_special = { kind = 'toggle_special', start_input = 'special_action' },
            },
            weapon_special_tweak_data = { num_charges_to_activate = 1 },
        })
        mock:set_wielded_slot('slot_primary')
        local engine = mock:load_controller(new_manager({
            sequence_cycle_point = 'sequence_step_1',
            sequence_step_1 = 'special_action',
        }))
        local held_inputs = { action_one_hold = true }

        local inputs, input = mock:run_input_frame(engine, held_inputs)
        assert.is_true(inputs.action_one_hold)
        assert.are.equal('start_attack', input)
        assert.are.equal('action_melee_start', mock:current_action_name())
    end)

    it('releases a held heavy attack as soon as its game input duration completes', function()
        mock:set_weapon('slot_primary', 'test_heavy', {
            displayed_attacks = { primary = { type = 'melee' } },
            action_input_hierarchy = {
                {
                    input = 'start_attack',
                    transition = { { input = 'heavy_attack', transition = 'base' } },
                },
            },
            actions = {
                action_melee_start = {
                    kind = 'windup',
                    start_input = 'start_attack',
                    allowed_chain_actions = {
                        heavy_attack = { action_name = 'action_heavy', chain_time = 0.25 },
                    },
                },
                action_heavy = { kind = 'sweep', start_input = 'heavy_attack' },
            },
        })
        mock:set_wielded_slot('slot_primary')
        local engine = mock:load_controller(new_manager({
            sequence_cycle_point = 'no_repeat',
            sequence_step_1 = 'heavy_attack',
        }))
        local held_inputs = { action_one_hold = true }

        mock:run_input_frame(engine, held_inputs)
        assert.are.equal('action_melee_start', mock:current_action_name())

        mock.now = 0.24
        mock:run_input_frame(engine, held_inputs)
        assert.are.equal('action_melee_start', mock:current_action_name())

        mock.now = 0.25
        mock:run_input_frame(engine, held_inputs)
        assert.are.equal('action_melee_start', mock:current_action_name())

        mock.now = 0.26
        local _, input = mock:run_input_frame(engine, held_inputs)
        assert.are.equal('heavy_attack', input)
        assert.are.equal('action_heavy', mock:current_action_name())
    end)

    it('rearms held fire after an automatic vent interrupt', function()
        mock:set_weapon('slot_secondary', 'test_vent_recovery', {
            action_input_hierarchy = { { input = 'shoot_pressed', transition = 'base' } },
            actions = {
                action_shoot = {
                    kind = 'shoot_hit_scan',
                    start_input = 'shoot_pressed',
                    allowed_chain_actions = {
                        shoot_pressed = { action_name = 'action_shoot', chain_time = 0.2 },
                    },
                },
            },
        })
        mock:set_wielded_slot('slot_secondary')
        local engine = mock:load_controller(new_manager({ automatic_fire_hip = 'standard' }))
        local held_inputs = { action_one_hold = true }

        mock:run_input_frame(engine, held_inputs)
        mock:run_input_frame(engine, held_inputs)
        assert.are.equal('action_shoot', mock:current_action_name())

        mock.now = 0.1
        mock:set_action('action_vent_override', { kind = 'vent_overheat' }, 0.1)
        mock:run_input_frame(engine, { action_one_hold = false })

        mock.now = 0.2
        mock:set_action('none')
        local _, input = mock:run_input_frame(engine, held_inputs)
        assert.are.equal('shoot_pressed', input)
    end)

    it('buffers a light input before a delayed light chain can become a heavy', function()
        mock:set_weapon('slot_primary', 'test_delayed_light', {
            displayed_attacks = { primary = { type = 'melee' } },
            action_inputs = {
                light_attack = {
                    buffer_time = 0.3,
                    input_sequence = { { input = 'action_one_hold', time_window = 0.3, value = false } },
                },
                heavy_attack = {
                    buffer_time = 0.5,
                    input_sequence = {
                        { duration = 0.3, input = 'action_one_hold', value = true },
                        { auto_complete = true, input = 'action_one_hold', time_window = 1, value = false },
                    },
                },
            },
            action_input_hierarchy = {
                {
                    input = 'start_attack',
                    transition = {
                        { input = 'light_attack', transition = 'base' },
                        { input = 'heavy_attack', transition = 'base' },
                    },
                },
            },
            actions = {
                action_melee_start = {
                    kind = 'windup',
                    start_input = 'start_attack',
                    allowed_chain_actions = {
                        light_attack = { action_name = 'action_light', chain_time = 0.31 },
                        heavy_attack = { action_name = 'action_heavy', chain_time = 0.55 },
                    },
                },
                action_light = { kind = 'sweep' },
                action_heavy = { kind = 'sweep' },
            },
        })
        mock:set_wielded_slot('slot_primary')
        local engine = mock:load_controller(new_manager({
            sequence_cycle_point = 'no_repeat',
            sequence_step_1 = 'light_attack',
        }))
        local held_inputs = { action_one_hold = true }

        mock:run_input_frame(engine, held_inputs)
        assert.are.equal('action_melee_start', mock:current_action_name())

        mock.now = 0.02
        local _, input = mock:run_input_frame(engine, held_inputs)
        assert.are.equal('light_attack', input)

        mock.now = 0.31
        mock:run_input_frame(engine, held_inputs)
        assert.are.equal('action_light', mock:current_action_name())

        mock.now = 0.55
        mock:run_input_frame(engine, held_inputs)
        assert.are.equal('action_light', mock:current_action_name())
    end)

    it('retries a stale buffered tap so a delayed light chain cannot auto-complete into a heavy', function()
        mock:set_weapon('slot_primary', 'test_transonic_delay', {
            displayed_attacks = { primary = { type = 'melee' } },
            action_inputs = {
                start_attack = {
                    buffer_time = 0.35,
                    input_sequence = { { input = 'action_one_hold', value = true } },
                },
                light_attack = {
                    buffer_time = 0.3,
                    input_sequence = { { input = 'action_one_hold', time_window = 0.25, value = false } },
                },
                heavy_attack = {
                    buffer_time = 0.5,
                    input_sequence = {
                        { duration = 0.25, input = 'action_one_hold', value = true },
                        { auto_complete = true, input = 'action_one_hold', time_window = 1, value = false },
                    },
                },
            },
            action_input_hierarchy = {
                {
                    input = 'start_attack',
                    transition = {
                        { input = 'light_attack', transition = 'base' },
                        { input = 'heavy_attack', transition = 'base' },
                    },
                },
            },
            actions = {
                action_start_1 = {
                    kind = 'windup',
                    start_input = 'start_attack',
                    allowed_chain_actions = {
                        light_attack = { action_name = 'action_light_1' },
                        heavy_attack = { action_name = 'action_heavy_1', chain_time = 0.575 },
                    },
                },
                action_light_1 = {
                    kind = 'sweep',
                    allowed_chain_actions = {
                        start_attack = { action_name = 'action_start_2', chain_time = 0.6 },
                    },
                },
                action_start_2 = {
                    kind = 'windup',
                    allowed_chain_actions = {
                        light_attack = { action_name = 'action_light_2' },
                        heavy_attack = { action_name = 'action_heavy_2', chain_time = 0.575 },
                    },
                },
                action_light_2 = { kind = 'sweep' },
                action_heavy_1 = { kind = 'sweep' },
                action_heavy_2 = { kind = 'sweep' },
            },
        })
        mock:set_wielded_slot('slot_primary')
        local engine = mock:load_controller(new_manager({
            sequence_cycle_point = 'sequence_step_1',
            sequence_step_1 = 'light_attack',
        }))
        local held_inputs = { action_one_hold = true }

        mock:run_input_frame(engine, held_inputs)
        mock:run_input_frame(engine, held_inputs)
        assert.are.equal('action_light_1', mock:current_action_name())

        -- The buffered tap expires before the 0.6 chain opens; the retry must re-queue it.
        for t = 0.05, 0.75, 0.01 do
            mock.now = t
            mock:run_input_frame(engine, held_inputs)
            assert.is_not_equal('action_heavy_1', mock:current_action_name())
            assert.is_not_equal('action_heavy_2', mock:current_action_name())
        end

        assert.are.equal('action_light_2', mock:current_action_name())
    end)

    it('keeps primary input out of a combat blade special until its light chain opens', function()
        mock:set_weapon('slot_primary', 'test_combat_blade_special', {
            displayed_attacks = { primary = { type = 'melee' } },
            actions = {
                action_special_uppercut = {
                    kind = 'sweep',
                    start_input = 'special_action',
                    allowed_chain_actions = {
                        start_attack = { action_name = 'action_melee_start_left', chain_time = 0.6 },
                    },
                },
                action_melee_start_left = {
                    kind = 'windup',
                    start_input = 'start_attack',
                    allowed_chain_actions = {
                        light_attack = { action_name = 'action_light_left' },
                    },
                },
                action_light_left = { kind = 'sweep', start_input = 'light_attack' },
            },
        })
        mock:set_wielded_slot('slot_primary')
        local engine = mock:load_controller(new_manager({
            sequence_cycle_point = 'no_repeat',
            sequence_step_1 = 'special_action',
            sequence_step_2 = 'light_attack',
        }))
        local held_inputs = { action_one_hold = true }

        local inputs, input = mock:run_input_frame(engine, {
            action_one_pressed = true,
            action_one_hold = true,
        })
        assert.is_false(inputs.action_one_pressed)
        assert.is_false(inputs.action_one_hold)
        assert.are.equal('special_action', input)
        assert.are.equal('action_special_uppercut', mock:current_action_name())

        mock.now = 0.4
        mock:run_input_frame(engine, held_inputs)
        assert.are.equal('action_special_uppercut', mock:current_action_name())

        mock.now = 0.6
        _, input = mock:run_input_frame(engine, held_inputs)
        assert.are.equal('start_attack', input)
        assert.are.equal('action_melee_start_left', mock:current_action_name())

        mock.now = 0.61
        _, input = mock:run_input_frame(engine, held_inputs)
        assert.are.equal('light_attack', input)
        assert.are.equal('action_light_left', mock:current_action_name())
    end)

    it('suppresses primary while starting a power-sword special attack', function()
        mock:set_weapon('slot_primary', 'test_power_sword_special', {
            displayed_attacks = { primary = { type = 'melee' } },
            action_inputs = {
                start_attack = { input_sequence = { { input = 'action_one_hold', value = true } } },
                start_attack_special = { input_sequence = { { input = 'weapon_extra_hold', value = true } } },
                light_attack_special = {
                    input_sequence = { { input = 'weapon_extra_hold', time_window = 0.35, value = false } },
                },
            },
            action_input_hierarchy = {
                { input = 'start_attack', transition = 'base' },
                {
                    input = 'start_attack_special',
                    transition = { { input = 'light_attack_special', transition = 'base' } },
                },
            },
            actions = {
                action_melee_start = { kind = 'windup', start_input = 'start_attack' },
                action_melee_start_special = {
                    kind = 'windup',
                    start_input = 'start_attack_special',
                    allowed_chain_actions = {
                        light_attack_special = { action_name = 'action_light_special' },
                    },
                },
                action_light_special = { kind = 'sweep' },
            },
        })
        mock:set_wielded_slot('slot_primary')
        local engine = mock:load_controller(new_manager({
            sequence_cycle_point = 'no_repeat',
            sequence_step_1 = 'special_action',
        }))

        local inputs, input = mock:run_input_frame(engine, { action_one_hold = true })

        assert.is_false(inputs.action_one_hold)
        assert.is_true(inputs.weapon_extra_hold)
        assert.are.equal('start_attack_special', input)
        assert.are.equal('action_melee_start_special', mock:current_action_name())

        mock.now = 0.01
        inputs, input = mock:run_input_frame(engine, { action_one_hold = true })
        assert.is_false(inputs.weapon_extra_hold)
        assert.are.equal('light_attack_special', input)
        assert.are.equal('action_light_special', mock:current_action_name())
    end)

    it('weaves a manual power-sword special into the normal combo', function()
        mock:set_weapon('slot_primary', 'test_manual_power_sword_special', {
            displayed_attacks = { primary = { type = 'melee' } },
            action_input_hierarchy = {
                {
                    input = 'start_attack',
                    transition = {
                        { input = 'light_attack', transition = 'base' },
                        { input = 'heavy_attack', transition = 'base' },
                    },
                },
                {
                    input = 'start_attack_special',
                    transition = {
                        { input = 'light_attack_special', transition = 'base' },
                        { input = 'heavy_attack_special', transition = 'base' },
                    },
                },
            },
            actions = {
                action_melee_start = {
                    kind = 'windup',
                    start_input = 'start_attack',
                    allowed_chain_actions = {
                        light_attack = { action_name = 'action_light' },
                        heavy_attack = { action_name = 'action_heavy' },
                    },
                },
                action_light = { kind = 'sweep', start_input = 'light_attack' },
                action_heavy = { kind = 'sweep', start_input = 'heavy_attack' },
                action_light_special = {
                    kind = 'sweep',
                    allowed_chain_actions = {
                        start_attack_special = { action_name = 'action_melee_start_special' },
                    },
                },
                action_melee_start_special = {
                    kind = 'windup',
                    start_input = 'start_attack_special',
                    allowed_chain_actions = {
                        light_attack_special = { action_name = 'action_light_special' },
                        heavy_attack_special = { action_name = 'action_heavy_special' },
                    },
                },
                action_heavy_special = { kind = 'sweep' },
            },
        })
        mock:set_wielded_slot('slot_primary')
        local engine = mock:load_controller(new_manager({
            sequence_cycle_point = 'sequence_step_1',
            sequence_step_1 = 'light_attack',
            sequence_step_2 = 'heavy_attack',
        }))
        engine:_refresh_context()
        engine.activation.primary = true
        engine.interpreter.input_name = 'light_attack_special'
        mock:set_action('action_light_special', engine.context.template.actions.action_light_special, 1)
        mock:set_special_active(true)
        engine:_refresh_context()
        engine:_maybe_advance_goal()
        assert.are.equal(2, engine.sequence.index)
        assert.are.equal('chain', engine.sequence.program.kind)
        assert.same({ 'start_attack', 'heavy_attack' }, engine.sequence.program.inputs)
    end)
    it('advances once after a powered windup reaches its sweep', function()
        mock:set_weapon('slot_primary', 'test_powered_windup_progress', {
            displayed_attacks = { primary = { type = 'melee' } },
            actions = {
                action_melee_start_special = {
                    activate_special_during_windup = true,
                    allowed_chain_actions = {
                        light_attack_special = { action_name = 'action_light_special' },
                    },
                    kind = 'windup',
                },
                action_light_special = {
                    activate_special_during_sweep = true,
                    kind = 'sweep',
                },
            },
        })
        mock:set_wielded_slot('slot_primary')
        local engine = mock:load_controller(new_manager({
            sequence_cycle_point = 'sequence_step_1',
            sequence_step_1 = 'light_attack',
            sequence_step_2 = 'heavy_attack',
        }))
        engine:_refresh_context()
        engine.activation.primary = true

        mock:set_action('action_melee_start_special', engine.context.template.actions.action_melee_start_special, 1)
        engine.action.started = { token = 'action_melee_start_special:1', input = nil }
        engine:_maybe_advance_goal()
        assert.are.equal(1, engine.sequence.index)

        mock:set_action('action_light_special', engine.context.template.actions.action_light_special, 1.5)
        engine.action.started = { token = 'action_light_special:1.5', input = nil }
        engine:_maybe_advance_goal()
        mock:set_action('action_melee_start_normal', {
            allowed_chain_actions = {
                start_attack = { action_name = 'action_melee_start_normal', chain_time = 0 },
            },
            kind = 'windup',
        }, 2)
        engine:_maybe_advance_goal()
        mock:set_action('idle')
        engine:_maybe_advance_goal()

        assert.are.equal(2, engine.sequence.index)
    end)

    it('preserves the combo after a manually started special heavy attack', function()
        mock:set_weapon('slot_primary', 'test_manual_power_sword_heavy_special', {
            displayed_attacks = { primary = { type = 'melee' } },
            action_input_hierarchy = {
                {
                    input = 'start_attack',
                    transition = {
                        { input = 'light_attack', transition = 'base' },
                        { input = 'heavy_attack', transition = 'base' },
                    },
                },
                {
                    input = 'start_attack_special',
                    transition = { { input = 'heavy_attack_special', transition = 'base' } },
                },
            },
            actions = {
                action_melee_start = {
                    kind = 'windup',
                    start_input = 'start_attack',
                    allowed_chain_actions = {
                        light_attack = { action_name = 'action_light' },
                        heavy_attack = { action_name = 'action_heavy' },
                    },
                },
                action_light = { kind = 'sweep', start_input = 'light_attack' },
                action_heavy = { kind = 'sweep', start_input = 'heavy_attack' },
                action_melee_start_special = {
                    activate_special_during_windup = true,
                    kind = 'windup',
                    allowed_chain_actions = {
                        heavy_attack_special = { action_name = 'action_heavy_special' },
                    },
                },
                action_heavy_special = {
                    activate_special_during_sweep = true,
                    kind = 'sweep',
                    allowed_chain_actions = {
                        start_attack = { action_name = 'action_melee_start' },
                    },
                },
            },
        })
        mock:set_wielded_slot('slot_primary')
        local engine = mock:load_controller(new_manager({
            sequence_cycle_point = 'sequence_step_1',
            sequence_step_1 = 'light_attack',
            sequence_step_2 = 'heavy_attack',
        }))
        engine:_refresh_context()
        engine.activation.primary = true
        mock:set_action('action_light', engine.context.template.actions.action_light, 1)
        engine.action.started = { token = 'action_light:1', input = 'light_attack' }
        mock:set_special_active(true)
        mock:set_action('action_melee_start_special', engine.context.template.actions.action_melee_start_special, 1.1)
        mock:set_action('action_heavy_special', engine.context.template.actions.action_heavy_special, 1.5)
        engine:_maybe_advance_goal()
        assert.are.equal(2, engine.sequence.index)
        assert.are.equal('chain', engine.sequence.program.kind)
        assert.same({ 'start_attack', 'heavy_attack' }, engine.sequence.program.inputs)
        assert.is_true(engine:handle_input({
            action_name = 'action_one_hold',
            value = true,
            primary_held = true,
            primary_pressed = false,
            secondary_held = false,
            secondary_pressed = false,
        }))
    end)

    it('holds the power-sword special input before releasing its heavy attack', function()
        mock:set_weapon('slot_primary', 'test_power_sword_special_heavy', {
            displayed_attacks = { primary = { type = 'melee' } },
            action_inputs = {
                start_attack = { input_sequence = { { input = 'action_one_hold', value = true } } },
                start_attack_special = { input_sequence = { { input = 'weapon_extra_hold', value = true } } },
                light_attack_special = {
                    input_sequence = { { input = 'weapon_extra_hold', time_window = 0.35, value = false } },
                },
                heavy_attack_special = {
                    buffer_time = 0.5,
                    input_sequence = {
                        { duration = 0.35, input = 'weapon_extra_hold', value = true },
                        { auto_complete = true, input = 'weapon_extra_hold', time_window = 1.6, value = false },
                    },
                },
            },
            action_input_hierarchy = {
                { input = 'start_attack', transition = 'base' },
                {
                    input = 'start_attack_special',
                    transition = {
                        { input = 'light_attack_special', transition = 'base' },
                        { input = 'heavy_attack_special', transition = 'base' },
                    },
                },
            },
            actions = {
                action_melee_start = { kind = 'windup', start_input = 'start_attack' },
                action_melee_start_special = {
                    kind = 'windup',
                    start_input = 'start_attack_special',
                    allowed_chain_actions = {
                        light_attack_special = { action_name = 'action_light_special' },
                        heavy_attack_special = { action_name = 'action_heavy_special', chain_time = 0.8 },
                    },
                },
                action_light_special = { kind = 'sweep' },
                action_heavy_special = { kind = 'sweep' },
            },
        })
        mock:set_wielded_slot('slot_primary')
        local engine = mock:load_controller(new_manager({
            sequence_cycle_point = 'no_repeat',
            sequence_step_1 = 'special_action_heavy',
        }))

        local _, input = mock:run_input_frame(engine, { action_one_hold = true })
        assert.are.equal('start_attack_special', input)
        assert.are.equal('action_melee_start_special', mock:current_action_name())

        mock:set_special_active(true)

        mock.now = 0.01
        local inputs
        inputs, input = mock:run_input_frame(engine, { action_one_hold = true })
        assert.is_true(inputs.weapon_extra_hold)
        assert.is_nil(input)

        mock.now = 0.36
        inputs, input = mock:run_input_frame(engine, { action_one_hold = true })
        assert.is_false(inputs.weapon_extra_hold)
        assert.is_nil(input)

        mock.now = 0.37
        _, input = mock:run_input_frame(engine, { action_one_hold = true })
        assert.are.equal('heavy_attack_special', input)
        assert.are.equal('action_melee_start_special', mock:current_action_name())

        mock.now = 0.8
        _, input = mock:run_input_frame(engine, { action_one_hold = true })
        assert.are.equal('heavy_attack_special', input)
        assert.are.equal('action_heavy_special', mock:current_action_name())
    end)

    it('does not interrupt a combat blade light before its damage window closes', function()
        mock:set_weapon('slot_primary', 'test_combat_blade_special_loop', {
            displayed_attacks = { primary = { type = 'melee' } },
            action_inputs = {
                special_action = {
                    buffer_time = 0.5,
                    input_sequence = { { input = 'weapon_extra_pressed', value = true } },
                },
            },
            actions = {
                action_special_uppercut = {
                    kind = 'sweep',
                    start_input = 'special_action',
                    allowed_chain_actions = {
                        start_attack = { action_name = 'action_melee_start_left', chain_time = 0.6 },
                    },
                },
                action_melee_start_left = {
                    kind = 'windup',
                    start_input = 'start_attack',
                    allowed_chain_actions = {
                        light_attack = { action_name = 'action_light_left' },
                    },
                },
                action_light_left = {
                    damage_window_end = 0.46,
                    kind = 'sweep',
                    start_input = 'light_attack',
                    allowed_chain_actions = {
                        start_attack = { action_name = 'action_melee_start_left', chain_time = 0.23 },
                        special_action = { action_name = 'action_special_uppercut', chain_time = 0.23 },
                    },
                },
            },
        })
        mock:set_wielded_slot('slot_primary')
        local engine = mock:load_controller(new_manager({
            sequence_cycle_point = 'sequence_step_1',
            sequence_step_1 = 'special_action',
            sequence_step_2 = 'light_attack',
        }))
        local held_inputs = { action_one_hold = true }

        mock:run_input_frame(engine, { action_one_pressed = true, action_one_hold = true })
        mock.now = 0.6
        mock:run_input_frame(engine, held_inputs)
        mock.now = 0.61
        mock:run_input_frame(engine, held_inputs)
        assert.are.equal('action_light_left', mock:current_action_name())

        mock.now = 0.9
        mock:run_input_frame(engine, held_inputs)
        assert.are.equal('action_light_left', mock:current_action_name())

        mock.now = 1.07
        engine:on_damage_window_exited()
        local _, input = mock:run_input_frame(engine, held_inputs)
        assert.are.equal('special_action', input)
        assert.are.equal('action_special_uppercut', mock:current_action_name())
    end)

    it('allows mode switching after a sweep damage window closes', function()
        mock:set_weapon('slot_primary', 'test_mode_switch_damage_window', {
            displayed_attacks = { primary = { type = 'melee' } },
            actions = {
                action_light = {
                    kind = 'sweep',
                    start_input = 'light_attack',
                    damage_window_end = 0.46,
                },
            },
        })
        mock:set_wielded_slot('slot_primary')
        local engine = mock:load_controller(new_manager({
            sequence_cycle_point = 'no_repeat',
            sequence_step_1 = 'light_attack',
            sequence_step_2 = 'heavy_attack',
        }))
        engine:_refresh_context()
        mock:set_action('action_light', engine.context.template.actions.action_light, 0)

        assert.is_false(engine:can_switch_mode())

        engine:on_damage_window_exited()

        assert.is_true(engine:can_switch_mode())
    end)

    it('ignores a mismatched damage window exit', function()
        mock:set_weapon('slot_primary', 'test_mismatched_damage_window', {
            displayed_attacks = { primary = { type = 'melee' } },
            actions = {
                action_light = { kind = 'sweep', damage_window_end = 0.46 },
            },
        })
        mock:set_wielded_slot('slot_primary')
        local engine = mock:load_controller(new_manager({
            sequence_cycle_point = 'no_repeat',
            sequence_step_1 = 'light_attack',
            sequence_step_2 = 'heavy_attack',
        }))
        engine:_refresh_context()
        mock:set_action('action_light', engine.context.template.actions.action_light, 0)
        local mismatched_settings = { kind = 'sweep', damage_window_end = 0.46 }

        engine:on_damage_window_exited(mismatched_settings)

        assert.is_false(engine:can_switch_mode())
    end)

    it('keeps held primary out of an external action before the light release', function()
        mock:set_weapon('slot_primary', 'test_ability_interrupt', {
            displayed_attacks = { primary = { type = 'melee' } },
            actions = {
                action_melee_start = {
                    kind = 'windup',
                    start_input = 'start_attack',
                    allowed_chain_actions = {
                        light_attack = { action_name = 'action_light' },
                        combat_ability = { action_name = 'combat_ability' },
                    },
                },
                action_light = { kind = 'sweep', start_input = 'light_attack' },
                combat_ability = {
                    kind = 'unwield_to_specific',
                    start_input = 'combat_ability',
                },
                action_wield = {
                    kind = 'wield',
                    start_input = 'wield',
                    allowed_chain_actions = {
                        start_attack = { action_name = 'action_melee_start', chain_time = 0.1 },
                    },
                },
            },
        })
        mock:set_wielded_slot('slot_primary')
        local engine = mock:load_controller(new_manager({
            sequence_cycle_point = 'sequence_step_1',
            sequence_step_1 = 'light_attack',
        }))
        local held_inputs = { action_one_hold = true }

        mock:run_input_frame(engine, held_inputs)
        assert.are.equal('action_melee_start', mock:current_action_name())

        mock.now = 0.01
        mock:set_action('combat_ability', {
            kind = 'unwield_to_specific',
            start_input = 'combat_ability',
        }, 0.01, 'combat_ability')
        local inputs = mock:run_input_frame(engine, held_inputs)

        assert.is_false(inputs.action_one_hold)

        mock.now = 1
        mock:set_action('action_wield', {
            kind = 'wield',
            start_input = 'wield',
            allowed_chain_actions = {
                start_attack = { action_name = 'action_melee_start', chain_time = 0.1 },
            },
        }, 1, 'wield')
        mock:run_input_frame(engine, held_inputs)

        mock.now = 1.1
        mock:run_input_frame(engine, held_inputs)
        assert.are.equal('action_melee_start', mock:current_action_name())

        mock.now = 1.11
        mock:run_input_frame(engine, held_inputs)
        assert.are.equal('action_light', mock:current_action_name())
    end)

    it('chains the next goal from an action that interrupts a completed attack', function()
        mock:set_weapon('slot_primary', 'test_completed_attack_interrupt', {
            displayed_attacks = { primary = { type = 'melee' } },
            action_inputs = {
                light_attack = {
                    input_sequence = { { input = 'action_one_hold', time_window = 0.2, value = false } },
                },
            },
            actions = {
                action_melee_start = {
                    kind = 'windup',
                    start_input = 'start_attack',
                    allowed_chain_actions = {
                        light_attack = { action_name = 'action_light' },
                        heavy_attack = { action_name = 'action_heavy' },
                    },
                },
                action_light = { kind = 'sweep' },
                action_heavy = { kind = 'sweep' },
                action_wield = {
                    kind = 'wield',
                    start_input = 'wield',
                    allowed_chain_actions = {
                        start_attack = { action_name = 'action_melee_start', chain_time = 0 },
                    },
                },
            },
        })
        mock:set_wielded_slot('slot_primary')
        local engine = mock:load_controller(new_manager({
            sequence_cycle_point = 'sequence_step_1',
            sequence_step_1 = 'light_attack',
            sequence_step_2 = 'heavy_attack',
        }))
        local held_inputs = { action_one_hold = true }

        mock:run_input_frame(engine, held_inputs)
        mock.now = 0.01
        mock:run_input_frame(engine, held_inputs)
        mock.now = 0.02
        mock:run_input_frame(engine, held_inputs)
        assert.are.equal('action_light', mock:current_action_name())

        mock.now = 0.03
        mock:set_action('action_wield', engine.context.template.actions.action_wield, mock.now, 'wield')
        local _, input = mock:run_input_frame(engine, held_inputs)

        assert.are.equal('start_attack', input)
        assert.are.equal('action_melee_start', mock:current_action_name())

        mock.now = 0.04
        mock:run_input_frame(engine, held_inputs)
        mock.now = 0.28
        mock:run_input_frame(engine, held_inputs)
        mock.now = 0.29
        _, input = mock:run_input_frame(engine, held_inputs)
        assert.are.equal('heavy_attack', input)
        assert.are.equal('action_heavy', mock:current_action_name())
    end)

    it('allows a manual push while a sequence is active', function()
        mock:set_weapon('slot_primary', 'test_manual_push', {
            displayed_attacks = { primary = { type = 'melee' } },
            actions = {
                action_block = {
                    kind = 'block',
                    start_input = 'block',
                    allowed_chain_actions = {
                        push = { action_name = 'action_push' },
                    },
                },
                action_push = {
                    kind = 'push',
                    start_input = 'push',
                },
                action_light = {
                    kind = 'sweep',
                    start_input = 'light_attack',
                },
            },
        })
        mock:set_wielded_slot('slot_primary')
        local engine = mock:load_controller(new_manager({
            sequence_cycle_point = 'no_repeat',
            sequence_step_1 = 'light_attack',
        }))
        local blocked_inputs = { action_two_hold = true }

        mock:run_input_frame(engine, blocked_inputs)
        assert.are.equal('action_block', mock:current_action_name())

        local inputs, input = mock:run_input_frame(engine, {
            action_one_pressed = true,
            action_one_hold = true,
            action_two_hold = true,
        })

        assert.are.equal('push', input)
        assert.are.equal('action_push', mock:current_action_name())
    end)
    local function run_heavy_start(action_start_t)
        local mock = DarktideMock.new()
        local template = {
            displayed_attacks = { primary = { type = 'melee' } },
            action_inputs = {
                start_attack = { input_sequence = { { input = 'action_one_hold', value = true } } },
                light_attack = {
                    input_sequence = { { input = 'action_one_hold', time_window = 0.3, value = false } },
                },
                heavy_attack = {
                    input_sequence = {
                        { duration = 0.3, input = 'action_one_hold', value = true },
                        { auto_complete = true, input = 'action_one_hold', time_window = 1, value = false },
                    },
                },
            },
            action_input_hierarchy = {
                {
                    input = 'start_attack',
                    transition = {
                        { input = 'light_attack', transition = 'base' },
                        { input = 'heavy_attack', transition = 'base' },
                    },
                },
            },
            actions = {
                action_melee_start = {
                    kind = 'windup',
                    start_input = 'start_attack',
                    allowed_chain_actions = {
                        light_attack = { action_name = 'action_left_light' },
                        heavy_attack = { action_name = 'action_left_heavy' },
                    },
                },
                action_left_light = { kind = 'sweep' },
                action_left_heavy = { kind = 'sweep' },
            },
        }
        mock:set_weapon('slot_primary', 'combatknife_p1_m1', template)
        mock:set_wielded_slot('slot_primary')
        local engine = mock:load_controller(new_manager({
            sequence_cycle_point = 'sequence_step_1',
            sequence_step_1 = 'heavy_attack',
        }))

        mock.now = 0.2
        mock:run_input_frame(engine, { action_one_hold = true })
        mock:set_action('action_melee_start', template.actions.action_melee_start, action_start_t)
        -- The parser can begin Heavy after the current windup action has already started.
        for _, t in ipairs({ 0.21, 0.31, 0.35, 0.51, 0.56 }) do
            mock.now = t
            mock:run_input_frame(engine, { action_one_hold = true })
        end

        return mock:current_action_name()
    end

    it('starts Heavy when the action and parser clocks agree', function()
        assert.are.equal('action_left_heavy', run_heavy_start(0.2))
    end)

    it('does not turn a delayed Heavy parser input into Light', function()
        assert.are.equal('action_left_heavy', run_heavy_start(0))
    end)
end)
