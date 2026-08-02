local DarktideMock = require('tests.shared.darktide_mock')

describe('SimpleSequencer SequenceEngine', function()
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

    it('resets transient sequence and input state', function()
        local engine = mock:load_sequence_engine(new_manager(nil))

        engine.index = 4
        engine.commands = { 'shoot' }
        engine.completed = true
        engine.primary_down = true
        engine.primary_rearm_pending = true
        engine.last_action_token = 'shoot:1'
        engine.previous_command = 'charge'
        engine.idle_match_index = 2
        engine.last_fire_time = 10
        engine.fire_token = 4
        engine.sweep_state = 'after_damage_window'
        engine.no_repeat_restored = true

        engine:reset()

        assert.are.equal(1, engine.index)
        assert.is_false(engine.completed)
        assert.is_false(engine.primary_down)
        assert.is_false(engine.primary_rearm_pending)
        assert.is_nil(engine.last_action_token)
        assert.is_nil(engine.previous_command)
        assert.is_nil(engine.idle_match_index)
        assert.are.equal(0, engine.last_fire_time)
        assert.is_nil(engine.fire_token)
        assert.is_nil(engine.sweep_state)
        assert.is_false(engine.no_repeat_restored)
    end)

    it('classifies charge-ammo actions using their metadata', function()
        mock:set_action('action_charge', {
            kind = 'charge_ammo',
            start_input = 'shoot_pressed',
        }, 1)

        local engine = mock:load_sequence_engine(new_manager(nil))
        local current_action = engine:_current_action()

        assert.are.equal('charge', current_action)
    end)

    it('allows an ammo-limited charge to complete at its maximum', function()
        mock:set_charge(0.25, 0.25, 2)
        mock:set_action('action_charge', {
            kind = 'charge_ammo',
            start_input = 'shoot_pressed',
        }, 1)

        local engine = mock:load_sequence_engine(new_manager(nil))
        engine.context = engine.context or mock:load_weapon_context().read()
        engine.profile = {
            auto_charge_threshold = 100,
        }

        assert.is_true(engine:_charge_ready(1, { kind = 'charge_ammo' }))
    end)

    it('rejects inherited charge time unless the action keeps the charge', function()
        mock:set_charge(1, 1, 1)
        mock:set_action('action_charge', {
            kind = 'charge_ammo',
            start_input = 'shoot_pressed',
        }, 2)

        local engine = mock:load_sequence_engine(new_manager(nil))
        engine.context = mock:load_weapon_context().read()
        engine.profile = {
            auto_charge_threshold = 100,
        }

        assert.is_false(engine:_charge_ready(2, { kind = 'charge_ammo' }))
        assert.is_true(engine:_charge_ready(2, { kind = 'charge_ammo', keep_charge = true }))
    end)

    it('preserves a held primary input while changing ranged aim mode', function()
        local profile = {
            automatic_fire_hip = 'standard',
            automatic_fire_ads = 'standard',
        }
        local engine = mock:load_sequence_engine(new_manager(profile))

        mock:set_action('action_aim', {
            kind = 'aim',
            start_input = 'zoom',
        }, 1)
        engine:handle_input('action_one_hold', true)
        assert.is_true(engine.primary_down)

        local result = engine:handle_input('action_two_hold', true)

        assert.is_true(result)
        assert.are.equal('ads', engine.ranged_mode)
        assert.is_true(engine.primary_down)
    end)

    it('rearms a held ranged primary after a weapon swap', function()
        local profile = {
            automatic_fire_hip = 'standard',
            automatic_fire_ads = 'standard',
        }
        local engine = mock:load_sequence_engine(new_manager(profile))
        local context = mock:load_weapon_context().read()
        engine.context = context
        engine.context_key = 'mode_1:RANGED:test_ranged:hip'
        engine.commands = { 'quick_wield', 'shoot' }
        engine.index = 1
        engine.profile = profile
        engine.primary_down = true

        mock:set_action('action_wield', { kind = 'windup' }, 1)
        engine:handle_input('action_one_hold', true)
        assert.is_true(engine.primary_rearm_pending)

        mock:set_action('none')
        local result = engine:handle_input('action_one_pressed', false)

        assert.is_true(result)
        assert.is_false(engine.primary_rearm_pending)
    end)

    it('pulses held ranged fire at the chain boundary', function()
        mock:set_action('action_shoot', {
            start_input = 'shoot_pressed',
            allowed_chain_actions = {
                shoot_pressed = { chain_time = 0.225 },
            },
        }, 0)
        mock.now = 0.226

        local engine = mock:load_sequence_engine(new_manager(nil))
        engine.context = mock:load_weapon_context().read()
        engine.context_key = 'mode_1:RANGED:test_ranged:hip'
        engine.commands = { 'shoot', 'idle' }
        engine.index = 1
        engine.cycle_index = 1
        engine.repeating = true
        engine.profile = { rate_of_fire_hip = 0 }

        local current_action, start_t, chain_ready = engine:_current_action()
        assert.are.equal('shoot', current_action)
        assert.is_true(chain_ready)
        engine:_maybe_advance(current_action, start_t, chain_ready)

        current_action, start_t, chain_ready = engine:_current_action()
        engine:_maybe_advance(current_action, start_t, chain_ready)

        assert.are.equal(1, engine.index)
        assert.is_true(engine:_fire_pulse(current_action, false, chain_ready))
    end)

    it('preserves a held primary through automatic vent recovery', function()
        local profile = { rate_of_fire_hip = 0 }
        local engine = mock:load_sequence_engine(new_manager(profile))
        engine.context = mock:load_weapon_context().read()
        engine.context_key = 'mode_1:RANGED:test_ranged:hip'
        engine.commands = { 'shoot', 'idle' }
        engine.index = 1
        engine.cycle_index = 1
        engine.repeating = true
        engine.profile = profile

        mock:set_action('action_charge_direct', { kind = 'overload_charge' }, 0)
        assert.is_true(engine:handle_input('action_one_pressed', true))
        assert.is_true(engine.primary_down)

        mock:set_action('action_vent_override', { kind = 'vent_overheat' }, 1)
        engine:handle_input('action_one_hold', false)
        assert.is_true(engine.primary_down)

        mock.now = 2
        mock:set_action('none')
        engine:handle_input('action_one_hold', true)
        local result = engine:handle_input('action_one_pressed', false)

        assert.is_true(result)
        engine:handle_input('action_one_hold', false)
        assert.is_false(engine.primary_down)
    end)

    it('restores a no-repeat sequence mode only once', function()
        local manager = new_manager(nil)
        local engine = mock:load_sequence_engine(manager)

        engine.commands = { 'light_attack' }
        engine.index = 1
        engine.repeating = false
        engine:_advance()

        assert.is_true(engine.completed)
        assert.is_true(engine:_restore_after_no_repeat())
        assert.are.equal(1, manager.toggles)
        assert.is_false(engine:_restore_after_no_repeat())
        assert.are.equal(1, manager.toggles)
    end)
end)
