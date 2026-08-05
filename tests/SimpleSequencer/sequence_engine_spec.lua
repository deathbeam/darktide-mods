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
        engine.plan.commands = { 'shoot' }
        engine.completed = true
        engine.primary_down = true
        engine.secondary_down = true
        engine.primary_hold_pulse_token = 'push_follow_up:1'
        engine.primary_rearm_pending = true
        engine.last_action_token = 'shoot:1'
        engine.previous_command = 'charge'
        engine.idle_match_index = 2
        engine.fire_token = 4
        engine.sweep_state = 'after_damage_window'
        engine.no_repeat_restored = true

        engine:reset()

        assert.are.equal(1, engine.index)
        assert.is_false(engine.completed)
        assert.is_false(engine.primary_down)
        assert.is_false(engine.secondary_down)
        assert.is_nil(engine.primary_hold_pulse_token)
        assert.is_false(engine.primary_rearm_pending)
        assert.is_nil(engine.last_action_token)
        assert.is_nil(engine.previous_command)
        assert.is_nil(engine.idle_match_index)
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

    it('keeps plasma standard autofire on the primary input', function()
        local profile = {
            automatic_fire_hip = 'standard',
            automatic_fire_ads = 'standard',
        }
        mock:set_weapon('slot_secondary', 'plasmagun_p1_m1', {
            action_input_hierarchy = {
                { input = 'shoot_charge', transition = 'base' },
            },
            actions = {
                action_charge_direct = {
                    kind = 'overload_charge',
                    start_input = 'shoot_charge',
                },
            },
        })

        local engine = mock:load_sequence_engine(new_manager(profile))
        engine:_refresh_context()

        assert.same({ 'shoot', 'idle' }, engine.plan.commands)
        assert.is_true(engine:_required('shoot', 'action_one_hold'))
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
        engine.plan.commands = { 'quick_wield', 'shoot' }
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

    it('does not end a sweep before its next chain becomes available', function()
        local engine = mock:load_sequence_engine(new_manager(nil))
        mock:set_wielded_slot('slot_primary')
        engine.context = mock:load_weapon_context().read()
        engine.context_key = 'mode_1:MELEE:test_melee:hip'
        engine.plan.commands = { 'light_attack', 'idle' }
        engine.profile = {}
        engine.sweep_state = 'after_damage_window'
        mock:set_action('action_light', {
            kind = 'sweep',
            allowed_chain_actions = {
                start_attack = { chain_time = 0.6 },
            },
        }, 0)
        mock.now = 0.3

        local _, _, early_chain_ready = engine:_current_action()

        mock.now = 0.6
        local _, _, chain_ready = engine:_current_action()

        assert.is_false(early_chain_ready)
        assert.is_true(chain_ready)
    end)

    it('uses the push chain boundary before the push action ends', function()
        local engine = mock:load_sequence_engine(new_manager(nil))
        mock:set_wielded_slot('slot_primary')
        engine.context = mock:load_weapon_context().read()
        engine.context_key = 'mode_1:MELEE:test_melee:hip'
        engine.plan.commands = { 'push', 'idle', 'start_attack' }
        engine.index = 2
        engine.previous_command = 'push'
        engine.profile = {}
        mock:set_action('action_push', {
            kind = 'push',
            allowed_chain_actions = {
                start_attack = { chain_time = 0.3 },
            },
        }, 0)
        mock.now = 0.3

        local current_action, _, chain_ready = engine:_current_action()
        engine:_maybe_advance(current_action, 0, chain_ready)

        assert.are.equal('push', current_action)
        assert.is_true(chain_ready)
        assert.are.equal('start_attack', engine:_command())
    end)

    it('waits for the weapon chain boundary before pulsing after a push follow-up', function()
        local engine = mock:load_sequence_engine(new_manager(nil))
        mock:set_weapon('slot_primary', 'combatsword_p3_m1', {
            displayed_attacks = { primary = { type = 'melee' } },
        })
        mock:set_wielded_slot('slot_primary')
        engine.context = mock:load_weapon_context().read()
        engine.context_key = 'mode_1:MELEE:combatsword_p3_m1:hip'
        engine.plan.commands = { 'start_attack', 'light_attack', 'idle' }
        engine.index = 1
        engine.plan.cycle_index = 1
        engine.plan.repeating = true
        engine.profile = {}
        engine.primary_down = true
        engine.secondary_down = true
        mock:set_action('action_right_light_pushfollow', {
            kind = 'sweep',
            allowed_chain_actions = {
                start_attack = { chain_time = 0.4 },
            },
        }, 0)
        mock.now = 0
        local pre_release_result = engine:handle_input('action_one_hold', true)
        engine:handle_input('action_two_hold', false)
        mock.now = 0.2
        local early_result = engine:handle_input('action_one_hold', true)
        mock.now = 0.399
        local before_boundary_result = engine:handle_input('action_one_hold', true)
        mock.now = 0.401
        local boundary_result = engine:handle_input('action_one_hold', true)
        local after_boundary_result = engine:handle_input('action_one_hold', true)
        mock:set_action('action_melee_start_left', {
            kind = 'windup',
            start_input = 'start_attack',
            allowed_chain_actions = {
                light_attack = { chain_time = 0 },
                heavy_attack = { chain_time = 0.5 },
            },
        }, 0.401)
        local windup_result = engine:handle_input('action_one_hold', true)

        assert.is_true(pre_release_result)
        assert.is_false(early_result)
        assert.is_false(before_boundary_result)
        assert.is_true(boundary_result)
        assert.is_false(after_boundary_result)
        assert.is_false(windup_result)
        assert.are.equal('light_attack', engine:_command())
    end)

    it('keeps a push follow-up held while secondary input is down', function()
        local engine = mock:load_sequence_engine(new_manager(nil))
        engine.context = mock:load_weapon_context().read()
        engine.context_key = 'mode_1:MELEE:test_melee:hip'
        engine.plan.commands = { 'start_attack', 'light_attack', 'idle' }
        engine.index = 1
        engine.plan.cycle_index = 1
        engine.plan.repeating = true
        engine.profile = {}
        engine.primary_down = true
        engine.secondary_down = false
        mock:set_action('action_push', { kind = 'push' }, 1)

        engine:handle_input('action_two_hold', true)
        local result = engine:handle_input('action_one_hold', true)

        assert.is_true(result)
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
        engine.plan.commands = { 'shoot', 'idle' }
        engine.index = 1
        engine.plan.cycle_index = 1
        engine.plan.repeating = true

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
        local profile = {}
        local engine = mock:load_sequence_engine(new_manager(profile))
        engine.context = mock:load_weapon_context().read()
        engine.context_key = 'mode_1:RANGED:test_ranged:hip'
        engine.plan.commands = { 'shoot', 'idle' }
        engine.index = 1
        engine.plan.cycle_index = 1
        engine.plan.repeating = true
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

        engine.plan.commands = { 'light_attack' }
        engine.index = 1
        engine.plan.repeating = false
        engine:_advance()

        assert.is_true(engine.completed)
        assert.is_true(engine:_restore_after_no_repeat())
        assert.are.equal(1, manager.toggles)
        assert.is_false(engine:_restore_after_no_repeat())
        assert.are.equal(1, manager.toggles)
    end)
end)
