local DarktideMock = require('tests.shared.darktide_mock')

describe('SimpleSequencer WeaponContext', function()
    local mock
    local WeaponContext

    before_each(function()
        mock = DarktideMock.new()
        WeaponContext = mock:load_weapon_context()
    end)

    it('reads the active ranged weapon and its action state', function()
        mock:set_action('action_shoot', {
            kind = 'damage_target',
            start_input = 'shoot_pressed',
        }, 1)

        local context = WeaponContext.read()
        local action_name, start_t, action_settings = WeaponContext.action(context)

        assert.are.equal('RANGED', context.kind)
        assert.are.equal('test_ranged', context.name)
        assert.are.equal('action_shoot', action_name)
        assert.are.equal(1, start_t)
        assert.are.equal('damage_target', action_settings.kind)
    end)

    it('falls back safely when the weapon extension is unavailable', function()
        mock.extension = nil

        local context = WeaponContext.read()
        local action_name, start_t, action_settings = WeaponContext.action(context)

        assert.are.equal('none', context.kind)
        assert.are.equal('none', context.name)
        assert.are.equal('idle', action_name)
        assert.is_nil(start_t)
        assert.is_nil(action_settings)
    end)

    it('treats a missing special-active component field as inactive', function()
        local weapon = mock.extension._weapons.slot_secondary
        weapon.inventory_slot_component = setmetatable({ __config = {} }, {
            __index = function()
                error('missing component field')
            end,
        })

        local context = WeaponContext.read()
        assert.is_false(context.special_active)
    end)

    it('reads the special-charge state for charge-gated weapons', function()
        mock:set_weapon('slot_secondary', 'test_special_charges', {
            weapon_special_tweak_data = { num_charges_to_consume_on_activation = 1 },
        })
        local component = mock.extension._weapons.slot_secondary.inventory_slot_component
        component.__config.num_special_charges = true
        component.num_special_charges = 0

        local context = WeaponContext.read()
        assert.are.equal(0, context.special_charges)
        assert.are.equal(1, context.special_charge_cost)
    end)

    it('reads the charge cost used by hit-charge special activations', function()
        mock:set_weapon('slot_secondary', 'test_hit_charges', {
            weapon_special_tweak_data = { num_charges_to_activate = 5 },
        })
        local component = mock.extension._weapons.slot_secondary.inventory_slot_component
        component.num_special_charges = 4

        local context = WeaponContext.read()
        assert.are.equal(4, context.special_charges)
        assert.are.equal(5, context.special_charge_cost)
    end)

    it('matches game chain timing at the boundary and inside a chain window', function()
        local settings = {
            start_input = 'shoot_pressed',
            allowed_chain_actions = {
                shoot_pressed = {
                    chain_time = 0.2,
                    chain_until = 0.4,
                },
            },
        }
        mock:set_action('action_shoot', settings, 1)
        local context = WeaponContext.read()
        context.extension._weapon_action_component.time_scale = 2
        mock.now = 1.1
        assert.is_true(WeaponContext.can_chain(settings, 1, 'shoot_pressed', context))
        mock.now = 1.05
        assert.is_true(WeaponContext.can_chain(settings, 1, 'shoot_pressed', context))
    end)

    it('opens an action-input buffer before its chain boundary', function()
        local settings = {
            kind = 'windup',
            allowed_chain_actions = {
                light_attack = {
                    action_name = 'action_light',
                    chain_time = 0.31,
                },
            },
        }
        mock:set_weapon('slot_primary', 'test_buffered_light', {
            action_inputs = {
                light_attack = { buffer_time = 0.3 },
            },
        })
        mock:set_wielded_slot('slot_primary')
        mock:set_action('action_melee_start', settings, 1)
        local context = WeaponContext.read()

        mock.now = 1.009
        assert.is_false(WeaponContext.can_buffer_input(settings, 1, 'light_attack', context))

        mock.now = 1.01
        assert.is_true(WeaponContext.can_buffer_input(settings, 1, 'light_attack', context))
    end)

    it('uses the weapon action time scale while buffering a chain', function()
        local settings = {
            kind = 'overload_charge',
            allowed_chain_actions = {
                shoot_braced = {
                    action_name = 'action_shoot_charged',
                    chain_time = 0.8,
                },
            },
        }
        mock:set_weapon('slot_secondary', 'test_scaled_buffer', {
            action_inputs = { shoot_braced = { buffer_time = 0.1 } },
        })
        mock:set_wielded_slot('slot_secondary')
        mock:set_action('action_charge', settings, 1)
        mock.extension._weapon_action_component.time_scale = 2
        local context = WeaponContext.read()

        mock.now = 1.35
        assert.is_true(WeaponContext.can_buffer_input(settings, 1, 'shoot_braced', context))
    end)

    it('does not buffer a chain whose target action condition cannot pass', function()
        local settings = {
            kind = 'windup',
            allowed_chain_actions = {
                light_attack = {
                    action_name = 'action_light',
                    chain_time = 0.31,
                },
            },
        }
        mock:set_weapon('slot_primary', 'test_blocked_buffer', {
            action_inputs = {
                light_attack = { buffer_time = 0.3 },
            },
            actions = {
                action_light = {
                    action_condition_func = function()
                        return false
                    end,
                },
            },
        })
        mock:set_wielded_slot('slot_primary')
        mock:set_action('action_melee_start', settings, 1)
        local context = WeaponContext.read()

        mock.now = 1.01
        assert.is_false(WeaponContext.can_buffer_input(settings, 1, 'light_attack', context))
    end)

    it('uses the weapon extension as the source of chain validity', function()
        local settings = {
            allowed_chain_actions = {
                shoot_pressed = { chain_time = 0 },
            },
        }
        mock:set_action('action_shoot', settings, 1)
        local context = WeaponContext.read()
        local calls = 0

        function context.extension:action_input_is_currently_valid(component_name, action_input, used_input, current_t)
            calls = calls + 1
            assert.are.equal('weapon_action', component_name)
            assert.are.equal('shoot_pressed', action_input)
            assert.is_nil(used_input)
            assert.are.equal(mock.now, current_t)

            return false
        end

        assert.is_false(WeaponContext.can_chain(settings, 1, 'shoot_pressed', context))
        assert.are.equal(1, calls)
    end)

    it('uses the game chain time for heavy attacks', function()
        local settings = {
            kind = 'windup',
            allowed_chain_actions = {
                heavy_attack = {
                    action_name = 'action_left_heavy',
                    chain_time = 0.3,
                },
            },
        }
        mock:set_wielded_slot('slot_primary')
        mock:set_action('action_melee_start', settings, 1)
        local context = WeaponContext.read()

        mock.now = 1.29
        assert.is_false(WeaponContext.can_chain(settings, 1, 'heavy_attack', context))
        mock.now = 1.3
        assert.is_true(WeaponContext.can_chain(settings, 1, 'heavy_attack', context))
    end)

    it('honors running action state requirements from the weapon chain', function()
        local settings = {
            allowed_chain_actions = {
                shoot_pressed = {
                    chain_time = 0.2,
                    running_action_state_requirement = { ready = true },
                },
            },
        }
        mock:set_action('action_shoot', settings, 1)
        local context = WeaponContext.read()
        context.extension._action_handler._registered_components.weapon_action.running_action = {
            running_action_state = function()
                return 'not_ready'
            end,
        }
        mock.now = 1.3
        assert.is_false(WeaponContext.can_chain(settings, 1, 'shoot_pressed', context))

        context.extension._action_handler._registered_components.weapon_action.running_action.running_action_state = function()
            return 'ready'
        end
        assert.is_true(WeaponContext.can_chain(settings, 1, 'shoot_pressed', context))
    end)

    it('does not report sprint-only chains after sprint or slide ends', function()
        local settings = {
            kind = 'windup',
            allowed_chain_actions = {
                light_attack = {
                    action_name = 'action_sprint_light',
                    chain_time = 0.15,
                },
            },
        }
        mock:set_action('action_melee_start_slide', settings, 1)
        local context = WeaponContext.read()
        context.template.actions.action_sprint_light = {
            action_condition_func = function(_, condition_func_params)
                return condition_func_params.movement_state_component.method == 'sliding'
            end,
        }
        context.extension._action_handler._action_context = {
            movement_state_component = { method = 'walking' },
        }
        mock.now = 2
        assert.is_false(WeaponContext.can_chain(settings, 1, 'light_attack', context))
    end)

    it('prefers an exact chain alias over its canonical fallback', function()
        local settings = {
            allowed_chain_actions = {
                light_attack_special = { chain_time = 0.2 },
                light_attack = { chain_time = 0.1 },
            },
        }
        mock:set_action('action_melee_start', settings, 1)
        local context = WeaponContext.read()
        local requested_input
        function context.extension:action_input_is_currently_valid(_, action_input)
            requested_input = action_input
            return true
        end
        mock.now = 1.3

        assert.is_true(WeaponContext.can_chain(settings, 1, 'light_attack_special', context))
        assert.are.equal('light_attack_special', requested_input)
    end)
end)
