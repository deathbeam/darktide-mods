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

    it('detects a ranged action at its chain boundary', function()
        local settings = {
            start_input = 'shoot_pressed',
            allowed_chain_actions = {
                shoot_pressed = {
                    chain_time = 0.2,
                },
            },
        }
        mock:set_action('action_shoot', settings, 1)
        mock.now = 1.3

        assert.is_true(WeaponContext.can_chain(settings, 1, 'shoot_pressed', 'test_ranged'))
    end)
end)
