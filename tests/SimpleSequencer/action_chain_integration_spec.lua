local DarktideMock = require('tests.shared.darktide_mock')

describe('SimpleSequencer action chains', function()
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
                    transition = { { input = 'heavy_attack', transition = 'base' } },
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
                    allowed_chain_actions = { heavy_attack = { action_name = 'action_heavy' } },
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
                action_heavy = { kind = 'sweep', start_input = 'heavy_attack' },
            },
        })
        mock:set_wielded_slot('slot_primary')
        local engine = mock:load_controller(new_manager({
            sequence_cycle_point = 'no_repeat',
            sequence_step_1 = 'push_attack',
            sequence_step_2 = 'heavy_attack',
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
end)
