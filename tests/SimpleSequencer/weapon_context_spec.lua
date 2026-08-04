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

    it('derives special support from weapon template metadata', function()
        mock:set_weapon('slot_secondary', 'test_ranged', {
            action_inputs = { special_action_hold = {} },
        })

        local context = WeaponContext.read()

        assert.is_true(WeaponContext.has_special(context))
    end)

    it('reads charge level, maximum, and start time defensively', function()
        mock:set_charge(0.5, 0.75, 2)
        local context = WeaponContext.read()

        local charge_level, max_charge, charge_start_time = WeaponContext.charge_state(context)

        assert.are.equal(0.5, charge_level)
        assert.are.equal(0.75, max_charge)
        assert.are.equal(2, charge_start_time)
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
        assert.is_true(WeaponContext.can_chain(settings, 1, 'shoot_pressed', 'test_ranged', context))
        mock.now = 1.05
        assert.is_true(WeaponContext.can_chain(settings, 1, 'shoot_pressed', 'test_ranged', context))
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
        assert.is_false(WeaponContext.can_chain(settings, 1, 'shoot_pressed', 'test_ranged', context))

        context.extension._action_handler._registered_components.weapon_action.running_action.running_action_state = function()
            return 'ready'
        end
        assert.is_true(WeaponContext.can_chain(settings, 1, 'shoot_pressed', 'test_ranged', context))
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
        assert.is_false(WeaponContext.can_chain(settings, 1, 'light_attack', 'test_ranged', context))
    end)
end)
