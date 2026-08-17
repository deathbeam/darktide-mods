local DarktideMock = require('tests.shared.darktide_mock')

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
describe('SimpleSequencer SequenceController integration', function()
    local mock

    before_each(function()
        mock = DarktideMock.new()
    end)

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
        assert.is_false(mock:last_network_inputs().action_one_hold)

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

        mock.now = 0.6
        local _, input = mock:run_input_frame(engine, held_inputs)
        assert.are.equal('start_attack', input)
        assert.are.equal('action_start_2', mock:current_action_name())

        -- Retry soon enough for Light to win before the queued Heavy can chain.
        mock.now = 0.87
        mock:run_input_frame(engine, held_inputs)
        mock.now = 0.88
        mock:run_input_frame(engine, held_inputs)

        for t = 0.89, 1.3, 0.01 do
            mock.now = t
            mock:run_input_frame(engine, held_inputs)
            assert.is_not_equal('action_heavy_1', mock:current_action_name())
            assert.is_not_equal('action_heavy_2', mock:current_action_name())
        end

        assert.are.equal('action_light_2', mock:current_action_name())
    end)

    it('keeps a special-mode Transonic push attack from continuing as Heavy', function()
        mock:set_weapon('slot_primary', 'transonic_sword_transonic_knife_p1_m1', {
            displayed_attacks = { primary = { type = 'melee' } },
            action_inputs = {
                start_attack = {
                    buffer_time = 0.35,
                    reevaluation_time = 0.18,
                    input_sequence = { { input = 'action_one_hold', value = true } },
                },
                light_attack = {
                    buffer_time = 0.3,
                    input_sequence = { { input = 'action_one_hold', time_window = 0.25, value = false } },
                },
                push_follow_up = {
                    buffer_time = 0.3,
                    input_sequence = {
                        { duration = 0.3, hold_input = 'action_two_hold', input = 'action_one_hold', value = true },
                    },
                },
                push_follow_up_release = {
                    buffer_time = 0,
                    dont_queue = true,
                    input_sequence = {
                        {
                            inputs = {
                                { input = 'action_one_hold', value = false },
                                { input = 'action_two_hold', value = false },
                            },
                            time_window = math.huge,
                        },
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
                {
                    input = 'block',
                    transition = {
                        {
                            input = 'push',
                            transition = {
                                {
                                    input = 'push_follow_up',
                                    transition = {
                                        { input = 'push_follow_up_release', transition = 'base' },
                                    },
                                },
                            },
                        },
                    },
                },
            },
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
                    allowed_chain_actions = {
                        push_follow_up = { action_name = 'action_pushfollow_special', chain_time = 0.3 },
                    },
                },
                action_pushfollow_special = {
                    kind = 'sweep',
                    damage_window_end = 0.38333333333333336,
                    allowed_chain_actions = {
                        start_attack = {
                            action_name = 'action_start_pushfollow_special_combo',
                            chain_time = 0.6,
                        },
                    },
                },
                action_start_pushfollow_special_combo = {
                    kind = 'windup',
                    allowed_chain_actions = {
                        light_attack = { action_name = 'action_light_pushfollow_special_combo' },
                        heavy_attack = { action_name = 'action_heavy_2_special', chain_time = 0.51 },
                    },
                },
                action_light_pushfollow_special_combo = { kind = 'sweep' },
                action_heavy_2_special = { kind = 'sweep' },
            },
        })
        mock:set_wielded_slot('slot_primary')
        mock:set_special_active(true)
        local engine = mock:load_controller(new_manager({
            sequence_cycle_point = 'sequence_step_1',
            sequence_step_1 = 'light_attack',
        }))

        mock:run_input_frame(engine, { action_two_hold = true })
        assert.are.equal('action_block', mock:current_action_name())

        mock.now = 0.01
        local _, input = mock:run_input_frame(engine, {
            action_one_pressed = true,
            action_one_hold = true,
            action_two_hold = true,
        })
        assert.are.equal('push', input)
        assert.are.equal('action_push', mock:current_action_name())

        local root_queued = false
        local root_released_before_windup = false
        for frame = 2, 90 do
            mock.now = frame * 0.01
            if frame == 70 then
                engine:on_damage_window_exited(engine.context.template.actions.action_pushfollow_special)
            end
            local overridden, parsed_input = mock:run_input_frame(engine, {
                action_one_hold = true,
                action_two_hold = frame <= 31,
            })
            root_queued = root_queued or parsed_input == 'start_attack'
            if
                root_queued
                and mock:current_action_name() == 'action_pushfollow_special'
                and overridden.action_one_hold == false
            then
                root_released_before_windup = true
            end
        end
        assert.is_true(root_released_before_windup)

        local start_frame
        for frame = 91, 200 do
            mock.now = frame * 0.01
            mock:run_input_frame(engine, { action_one_hold = true })
            if mock:current_action_name() == 'action_start_pushfollow_special_combo' then
                start_frame = frame
                break
            end
        end
        assert.is_not_nil(start_frame)

        local light_started = false
        for frame = start_frame + 1, 220 do
            mock.now = frame * 0.01
            mock:run_input_frame(engine, { action_one_hold = true })
            local action_name = mock:current_action_name()
            assert.is_not_equal('action_heavy_2_special', action_name)
            if action_name == 'action_light_pushfollow_special_combo' then
                light_started = true
                break
            end
        end

        assert.is_true(light_started)
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
        mock:run_input_frame(engine, held_inputs)
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

    it('continues a transformed special combo from Light into Heavy after a buffered windup', function()
        local special_available = true
        mock:set_weapon('slot_primary', 'test_replaced_power_sword_attack', {
            displayed_attacks = { primary = { type = 'melee' } },
            weapon_special_tweak_data = { num_charges_to_consume_on_activation = 1 },
            action_inputs = {
                start_attack = {
                    buffer_time = 0.35,
                    reevaluation_time = 0.18,
                    input_sequence = { { input = 'action_one_hold', value = true } },
                },
                light_attack = {
                    buffer_time = 0.3,
                    input_sequence = {
                        { input = 'action_one_hold', time_window = 0.35, value = false },
                    },
                },
                heavy_attack = {
                    buffer_time = 0.5,
                    input_sequence = {
                        { duration = 0.35, input = 'action_one_hold', value = true },
                        { auto_complete = true, input = 'action_one_hold', time_window = 1, value = false },
                    },
                },
                start_attack_special = {
                    buffer_time = 0.4,
                    reevaluation_time = 0.18,
                    input_sequence = { { input = 'weapon_extra_hold', value = true } },
                },
                light_attack_special = {
                    buffer_time = 0.3,
                    input_sequence = {
                        { input = 'weapon_extra_hold', time_window = 0.35, value = false },
                    },
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
                        light_attack = { action_name = 'action_light', chain_until = 0.8 },
                        heavy_attack = { action_name = 'action_heavy', chain_time = 0.8 },
                    },
                },
                action_light = { kind = 'sweep' },
                action_heavy = { kind = 'sweep' },
                action_melee_start_special_initial = {
                    activate_special_during_windup = true,
                    kind = 'windup',
                    start_input = 'start_attack_special',
                    allowed_chain_actions = {
                        light_attack_special = { action_name = 'action_light_special', chain_until = 0.7 },
                        heavy_attack_special = { action_name = 'action_heavy_special', chain_time = 0.7 },
                    },
                },
                action_melee_start_special = {
                    activate_special_during_windup = true,
                    kind = 'windup',
                    action_condition_func = function()
                        return special_available
                    end,
                    allowed_chain_actions = {
                        light_attack_special = { action_name = 'action_light_special', chain_until = 0.7 },
                        heavy_attack_special = { action_name = 'action_heavy_special', chain_time = 0.7 },
                    },
                },
                action_light_special = {
                    activate_special_during_sweep = true,
                    kind = 'sweep',
                    allowed_chain_actions = {
                        start_attack = { action_name = 'action_melee_start', chain_time = 0.5 },
                        start_attack_special = { action_name = 'action_melee_start_special', chain_time = 0.65 },
                    },
                },
                action_heavy_special = {
                    activate_special_during_sweep = true,
                    damage_window_end = 0.2,
                    kind = 'sweep',
                    allowed_chain_actions = {
                        start_attack = { action_name = 'action_melee_start', chain_time = 0.4 },
                        start_attack_special = { action_name = 'action_melee_start_special', chain_time = 0.4 },
                    },
                },
            },
        })
        mock:set_wielded_slot('slot_primary')
        mock:set_special_charges(1)
        mock:set_input_transform(function(inputs, raw_inputs)
            inputs.action_one_hold = not special_available and raw_inputs.action_one_hold or false
            inputs.weapon_extra_hold = special_available and raw_inputs.action_one_hold or false
        end)
        local engine = mock:load_controller(new_manager({
            sequence_cycle_point = 'sequence_step_1',
            sequence_step_1 = 'light_attack',
            sequence_step_2 = 'heavy_attack',
        }))
        local _, input = mock:run_input_frame(engine, { action_one_hold = true })
        assert.are.equal('start_attack_special', input)
        assert.are.equal('action_melee_start_special_initial', mock:current_action_name())

        local light_started_t
        for frame = 1, 90 do
            mock.now = frame * 0.01
            mock:run_input_frame(engine, { action_one_hold = true })
            local action_name = mock:current_action_name()
            assert.is_not_equal('action_heavy_special', action_name)
            if action_name == 'action_light_special' then
                light_started_t = mock.now
                break
            end
        end

        assert.is_not_nil(light_started_t)
        mock:set_input_delay(18)

        local heavy_windup_t
        local release_t
        local heavy_started = false
        local light_replaced_heavy = false
        for frame = 1, 250 do
            mock.now = light_started_t + frame * 0.01
            local inputs = mock:run_input_frame(engine, { action_one_hold = true })
            local action_name = mock:current_action_name()
            if action_name == 'action_melee_start_special' and not heavy_windup_t then
                heavy_windup_t = mock.now
                mock:set_input_delay(0)
            end
            if heavy_windup_t and not inputs.weapon_extra_hold and not release_t then
                release_t = mock.now
            end
            if heavy_windup_t and action_name == 'action_heavy_special' then
                heavy_started = true
                break
            elseif heavy_windup_t and action_name == 'action_light_special' then
                light_replaced_heavy = true
                break
            end
        end

        assert.is_not_nil(heavy_windup_t)
        if release_t then
            assert.is_true(release_t - heavy_windup_t >= 0.34)
            assert.is_true(release_t - heavy_windup_t <= 0.37)
        end
        assert.is_false(light_replaced_heavy)
        assert.is_true(
            heavy_started,
            string.format('%s windup=%s now=%s', mock:current_action_name(), heavy_windup_t, mock.now)
        )

        special_available = false
        mock:set_special_charges(0)
        local depletion_t = mock.now
        mock.now = depletion_t + 0.2
        engine:on_damage_window_exited(engine.context.template.actions.action_heavy_special)

        local normal_windup_t
        for frame = 21, 60 do
            mock.now = depletion_t + frame * 0.01
            mock:run_input_frame(engine, { action_one_hold = true })
            if mock:current_action_name() == 'action_melee_start' then
                normal_windup_t = mock.now
                break
            end
        end

        assert.is_not_nil(normal_windup_t)
        assert.is_true(normal_windup_t - depletion_t < 0.5)
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
                        start_attack = { action_name = 'action_melee_start' },
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

    it('passes held primary through an external action before the light release', function()
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
        mock:set_weapon('slot_combat_ability', 'test_ability', {})
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
        assert.is_true(inputs.action_one_hold)

        mock:set_wielded_slot('slot_combat_ability')
        engine:on_slot_wielded()
        inputs = mock:run_input_frame(engine, held_inputs)

        assert.is_true(inputs.action_one_hold)

        mock.now = 1
        mock:set_wielded_slot('slot_primary')
        engine:on_slot_wielded()
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
            action_inputs = {
                push_follow_up = {
                    buffer_time = 0.3,
                    input_sequence = {
                        { duration = 0.3, hold_input = 'action_two_hold', input = 'action_one_hold', value = true },
                    },
                },
            },
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
                    allowed_chain_actions = {
                        push_follow_up = { action_name = 'action_pushfollow', chain_time = 0.3 },
                        start_attack = { action_name = 'action_melee_start', chain_time = 0.3 },
                    },
                },
                action_pushfollow = { kind = 'sweep' },
                action_melee_start = {
                    kind = 'windup',
                    start_input = 'start_attack',
                    allowed_chain_actions = {
                        light_attack = { action_name = 'action_light' },
                    },
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

        for frame = 1, 30 do
            mock.now = frame * 0.01
            mock:run_input_frame(engine, {
                action_one_hold = true,
                action_two_hold = true,
            })
        end

        assert.are.equal('action_pushfollow', mock:current_action_name())
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
        mock:set_action('action_melee_start', template.actions.action_melee_start, action_start_t)
        local engine = mock:load_controller(new_manager({
            sequence_cycle_point = 'sequence_step_1',
            sequence_step_1 = 'heavy_attack',
        }))

        mock.now = 0.2
        mock:run_input_frame(engine, { action_one_hold = true })
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

    it('continues after a fast Devil Claw parry transition', function()
        mock:set_weapon('slot_primary', 'combatsword_p1_m1', {
            displayed_attacks = { primary = { type = 'melee' } },
            action_input_hierarchy = {
                { input = 'start_attack', transition = { { input = 'light_attack', transition = 'base' } } },
                { input = 'special_action', transition = 'base' },
                { input = 'parry', transition = 'base' },
            },
            actions = {
                action_melee_start = {
                    kind = 'windup',
                    start_input = 'start_attack',
                    allowed_chain_actions = {
                        light_attack = { action_name = 'action_light' },
                    },
                },
                action_light = { kind = 'sweep' },
                action_parry_special = {
                    kind = 'block',
                    start_input = 'special_action',
                    allowed_chain_actions = {
                        parry = { action_name = 'action_attack_special' },
                    },
                    running_action_state_to_action_input = {
                        has_blocked = { input_name = 'parry' },
                    },
                },
                action_attack_special = {
                    kind = 'sweep',
                    allowed_chain_actions = {
                        start_attack = { action_name = 'action_melee_start', chain_time = 0.4 },
                    },
                },
            },
        })
        mock:set_wielded_slot('slot_primary')
        local engine = mock:load_controller(new_manager({
            sequence_cycle_point = 'no_repeat',
            sequence_step_1 = 'special_action',
            sequence_step_2 = 'light_attack',
        }))
        local held_inputs = { action_one_hold = true }
        local _, input = mock:run_input_frame(engine, held_inputs)
        assert.are.equal('special_action', input)
        assert.are.equal('action_parry_special', mock:current_action_name())
        assert.are.equal(1, engine.sequence.index)
        assert.are.equal('normal', engine.sequence.program.kind)

        -- The parry can trigger before the controller polls the parry stance.
        mock:set_action('action_attack_special', engine.context.template.actions.action_attack_special, 0.1)
        engine:on_action_started(
            'action_attack_special',
            0.1,
            'parry',
            engine.context.template.actions.action_attack_special
        )
        mock.now = 0.1
        _, input = mock:run_input_frame(engine, held_inputs)
        assert.is_nil(input)
        assert.are.equal(1, engine.sequence.index)

        mock.now = 0.5
        _, input = mock:run_input_frame(engine, held_inputs)
        assert.are.equal('start_attack', input)
        assert.are.equal(2, engine.sequence.index)
        assert.are.equal('action_melee_start', mock:current_action_name())
    end)

    it('buffers a held attack during the Devil Claw manual parry window', function()
        mock:set_weapon('slot_primary', 'combatsword_p1_m3', {
            displayed_attacks = { primary = { type = 'melee' } },
            action_inputs = {
                start_attack = {
                    buffer_time = 0.3,
                    reevaluation_time = 0.18,
                    input_sequence = { { input = 'action_one_hold', value = true } },
                },
                light_attack = {
                    buffer_time = 0.3,
                    input_sequence = { { input = 'action_one_hold', value = false } },
                },
            },
            action_input_hierarchy = {
                {
                    input = 'start_attack',
                    transition = {
                        { input = 'light_attack', transition = 'base' },
                        { input = 'special_action', transition = 'base' },
                    },
                },
                { input = 'special_action', transition = 'base' },
            },
            actions = {
                action_melee_start_left = {
                    kind = 'windup',
                    start_input = 'start_attack',
                    allowed_chain_actions = {
                        light_attack = { action_name = 'action_left_light' },
                    },
                },
                action_left_light = {
                    kind = 'sweep',
                    allowed_chain_actions = {
                        special_action = { action_name = 'action_parry_special', chain_time = 0.4 },
                        start_attack = { action_name = 'action_melee_start_left', chain_time = 0.4 },
                    },
                },
                action_block = {
                    kind = 'block',
                    start_input = 'block',
                    allowed_chain_actions = {
                        special_action = { action_name = 'action_parry_special' },
                    },
                },
                action_parry_special = {
                    kind = 'block',
                    start_input = 'special_action',
                    total_time = 1.5,
                    allowed_chain_actions = {
                        start_attack = { action_name = 'action_melee_start_left', chain_time = 0.2 },
                    },
                },
            },
        })
        mock:set_wielded_slot('slot_primary')
        local engine = mock:load_controller(new_manager({
            sequence_cycle_point = 'sequence_step_1',
            sequence_step_1 = 'light_attack',
        }))
        mock:run_input_frame(engine, { action_one_hold = true })
        assert.are.equal('action_melee_start_left', mock:current_action_name())

        mock.now = 0.01
        mock:run_input_frame(engine, { action_one_hold = true })
        assert.are.equal('action_left_light', mock:current_action_name())

        for frame = 2, 41 do
            mock.now = frame * 0.01
            mock:run_input_frame(engine, { action_one_hold = true })
        end

        mock:set_input_transform(function(inputs)
            local action_name = mock:current_action_name()
            if action_name == 'action_block' or action_name == 'action_parry_special' then
                inputs.action_one_hold = false
            end
        end)
        mock.now = 0.42
        mock:set_action('action_block', engine.context.template.actions.action_block, mock.now)
        mock:reset_input_parser()
        mock:run_input_frame(engine, { action_one_hold = true, weapon_extra_pressed = true })
        assert.are.equal('action_parry_special', mock:current_action_name())

        local resumed_t
        for frame = 44, 80 do
            mock.now = frame * 0.01
            mock:run_input_frame(engine, { action_one_hold = true })
            if mock:current_action_name() == 'action_melee_start_left' then
                resumed_t = mock.now
                break
            end
            assert.are.equal('action_parry_special', mock:current_action_name())
        end
        assert.is_not_nil(resumed_t)
        assert.is_true(resumed_t < 0.7)

        mock.now = resumed_t + 0.01
        mock:run_input_frame(engine, { action_one_hold = true })
        assert.are.equal('action_left_light', mock:current_action_name())
    end)

    it('restarts a released light sequence during the current attack recovery', function()
        mock:set_weapon('slot_primary', 'test_light_repress', {
            displayed_attacks = { primary = { type = 'melee' } },
            actions = {
                action_melee_start_left = {
                    kind = 'windup',
                    start_input = 'start_attack',
                    allowed_chain_actions = {
                        light_attack = { action_name = 'action_left_light' },
                    },
                },
                action_left_light = {
                    damage_window_end = 0.35,
                    kind = 'sweep',
                    allowed_chain_actions = {
                        start_attack = { action_name = 'action_melee_start_left', chain_time = 0.4 },
                    },
                },
            },
        })
        mock:set_wielded_slot('slot_primary')
        local engine = mock:load_controller(new_manager({
            sequence_cycle_point = 'sequence_step_1',
            sequence_step_1 = 'light_attack',
        }))

        mock:run_input_frame(engine, { action_one_hold = true })
        mock.now = 0.01
        mock:run_input_frame(engine, { action_one_hold = true })
        assert.are.equal('action_left_light', mock:current_action_name())

        mock.now = 0.1
        mock:run_input_frame(engine, { action_one_hold = false })
        mock.now = 0.15
        mock:run_input_frame(engine, { action_one_pressed = true, action_one_hold = true })

        mock.now = 0.35
        engine:on_damage_window_exited(engine.context.template.actions.action_left_light)

        local resumed_t
        for frame = 35, 45 do
            mock.now = frame * 0.01
            mock:run_input_frame(engine, { action_one_hold = true })
            if mock:current_action_name() == 'action_melee_start_left' then
                resumed_t = mock.now
                break
            end
        end

        assert.is_not_nil(resumed_t)
        assert.is_true(resumed_t < 0.5)
    end)

    it('resets the current combo when a combat ability starts', function()
        mock:set_weapon('slot_primary', 'test_ability_reset', {
            displayed_attacks = { primary = { type = 'melee' } },
            action_input_hierarchy = {
                {
                    input = 'start_attack',
                    transition = {
                        { input = 'light_attack', transition = 'base' },
                        { input = 'heavy_attack', transition = 'base' },
                    },
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
        engine.sequence.index = 2
        engine.sequence.program = { kind = 'normal', inputs = { 'start_attack', 'heavy_attack' } }
        engine.activation.primary = true
        engine:on_action_started('combat_ability', 0, 'combat_ability', {
            kind = 'unwield_to_specific',
            start_input = 'combat_ability',
        })

        assert.are.equal(1, engine.sequence.index)
        assert.is_nil(engine.sequence.program)
        assert.is_false(engine.activation.primary)
    end)
end)
