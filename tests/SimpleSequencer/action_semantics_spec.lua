local root = debug.getinfo(1, 'S').source:sub(2):match('^(.*)/tests/SimpleSequencer/') or '.'
local ActionSemantics = dofile(root .. '/SimpleSequencer/scripts/mods/SimpleSequencer/modules/ActionSemantics.lua')

local function _template(actions)
    return {
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
                            { input = 'push_follow_up', transition = 'base' },
                        },
                    },
                },
            },
            {
                input = 'special_action_hold',
                transition = {
                    { input = 'special_action_light', transition = 'base' },
                    { input = 'special_action_heavy', transition = 'base' },
                },
            },
            { input = 'special_action', transition = 'base' },
            { input = 'shoot_pressed', transition = 'base' },
            { input = 'wield', transition = 'stay' },
        },
        actions = actions or {},
    }
end

local function _plan(template, command)
    return ActionSemantics.compile({
        steps = { command },
        cycle_step = 1,
        repeating = true,
    }, { template = template })
end

describe('SimpleSequencer ActionSemantics', function()
    it('derives melee phases from the weapon input hierarchy', function()
        local plan = _plan(_template(), 'light_attack')

        assert.same({ 'start_attack', 'light_attack', 'idle' }, plan.commands)
    end)

    it('prefers direct hierarchy entries over nested transition paths', function()
        local template = _template()
        local transitions = template.action_input_hierarchy[1].transition
        transitions[#transitions + 1] = { input = 'block', transition = 'base' }
        transitions[#transitions + 1] = { input = 'special_action', transition = 'base' }

        local plan = ActionSemantics.compile({
            steps = { 'push_attack', 'light_attack', 'special_action' },
            cycle_step = 1,
            repeating = true,
        }, { template = template })

        assert.same({
            'block',
            'push',
            'push_follow_up',
            'start_attack',
            'light_attack',
            'idle',
            'special_action',
            'idle',
        }, plan.commands)
    end)

    it('derives nested push phases from the weapon input hierarchy', function()
        local plan = _plan(_template(), 'push_attack')

        assert.same({ 'block', 'push', 'push_follow_up' }, plan.commands)
    end)

    it('selects runtime special-action variants', function()
        local plan = _plan(_template(), 'special_charged')

        assert.same({ 'special_start_attack', 'special_heavy_execute', 'idle' }, plan.commands)
    end)

    it('plans special start and execute chains from runtime inputs', function()
        local template = _template()
        template.action_input_hierarchy[3] = {
            input = 'special_action_start',
            transition = {
                { input = 'special_action_execute', transition = 'base' },
            },
        }
        local plan = _plan(template, 'special_charged')

        assert.same({ 'special_start_attack', 'special_heavy_execute', 'idle' }, plan.commands)
    end)

    it('plans pistol-whip specials from their runtime input', function()
        local template = _template()
        template.action_input_hierarchy[3] = {
            input = 'special_action_pistol_whip',
            transition = 'base',
        }
        local plan = _plan(template, 'special')

        assert.same({ 'special_light_attack', 'idle' }, plan.commands)
    end)

    it('plans special pushes as special attacks rather than generic specials', function()
        local template = _template()
        template.action_input_hierarchy[3] = {
            input = 'special_action_push',
            transition = 'base',
        }
        local plan = _plan(template, 'special')

        assert.same({ 'special_light_attack', 'idle' }, plan.commands)
    end)

    it('supports weapon-special toggles such as flashlights', function()
        local template = _template({
            action_toggle_flashlight = {
                kind = 'toggle_special',
                start_input = 'weapon_special',
            },
        })
        template.action_input_hierarchy = {
            { input = 'weapon_special', transition = 'stay' },
        }
        local plan = _plan(template, 'special')

        assert.same({ 'special_action', 'idle' }, plan.commands)
        assert.are.equal(
            'special_action',
            ActionSemantics.classify_current(
                'action_toggle_flashlight',
                { kind = 'toggle_special', start_input = 'weapon_special' },
                'special_action'
            )
        )
    end)

    it('plans charged projectile inputs from their runtime hierarchy', function()
        local template = _template({
            action_charge = {
                kind = 'charge',
                start_input = 'charge',
            },
            action_shoot_charged = {
                kind = 'shoot_hit_scan',
                start_input = 'shoot_charged',
                use_charge = true,
            },
        })
        template.action_input_hierarchy = {
            {
                input = 'charge',
                transition = {
                    { input = 'shoot_charged', transition = 'base' },
                },
            },
        }
        local plan = _plan(template, 'charged')

        assert.same({ 'charge', 'shoot', 'idle' }, plan.commands)
    end)

    it('plans force-staff charged explosions as primary shots', function()
        local template = _template({
            action_charge = {
                kind = 'overload_charge_position_finder',
                start_input = 'charge',
            },
            action_trigger_explosion = {
                kind = 'trigger_explosion',
                start_input = 'trigger_explosion',
                use_charge = true,
            },
        })
        template.action_input_hierarchy = {
            {
                input = 'charge',
                transition = {
                    { input = 'trigger_explosion', transition = 'base' },
                },
            },
        }

        assert.same({ 'charge', 'shoot', 'idle' }, _plan(template, 'standard').commands)
        assert.same({ 'charge', 'shoot', 'idle' }, _plan(template, 'charged').commands)
    end)

    it('plans nonstandard charged roots from runtime metadata', function()
        local template = _template({
            action_charge_power = {
                kind = 'smite_targeting',
                start_input = 'charge_power',
            },
        })
        template.action_input_hierarchy = {
            { input = 'charge_power', transition = 'base' },
        }
        local plan = _plan(template, 'charged')

        assert.same({ 'charge', 'shoot', 'idle' }, plan.commands)
    end)

    it('keeps plasma standard fire on the primary input', function()
        local template = _template({
            action_charge_direct = {
                kind = 'overload_charge',
                start_input = 'shoot_charge',
            },
        })
        template.action_input_hierarchy = {
            { input = 'shoot_charge', transition = 'base' },
        }
        local plan = _plan(template, 'standard')

        assert.same({ 'shoot', 'idle' }, plan.commands)
    end)

    it('falls back to a generic special when no charged variant exists', function()
        local template = _template()
        table.remove(template.action_input_hierarchy, 3)

        local plan = _plan(template, 'special_charged')

        assert.same({ 'special_action', 'idle' }, plan.commands)
    end)

    it('keeps explicit standard specials firing after the special action', function()
        local plan = _plan(_template(), 'special_standard')

        assert.same({ 'special_action', 'shoot', 'idle' }, plan.commands)
    end)

    it('recognizes charged ranged actions from action metadata', function()
        local template = _template({
            action_charge = {
                kind = 'charge_ammo',
                allowed_chain_actions = {
                    shoot_release_charged = { action_name = 'action_shoot' },
                },
                start_input = 'shoot_pressed',
            },
            action_shoot = {
                kind = 'shoot_hit_scan',
            },
        })
        local plan = _plan(template, 'charged')

        assert.same({ 'charge', 'shoot', 'idle' }, plan.commands)
    end)

    it('reports unresolved commands when the runtime graph cannot describe them', function()
        local plan = ActionSemantics.compile({
            steps = { 'light_attack' },
            cycle_step = 1,
            repeating = true,
        }, { template = {} })

        assert.same({}, plan.commands)
        assert.same({ { command = 'light_attack', step = 1 } }, plan.unresolved_steps)
        assert.is_false(plan.repeating)
    end)

    it('plans quick-swap cancels only for weapon slots that can return to their origin', function()
        local sequence = {
            steps = { 'quick_swap_cancel' },
            cycle_step = 1,
            repeating = true,
        }
        local supported = ActionSemantics.compile(sequence, {
            template = _template(),
            slot = 'slot_primary',
        })
        local unsupported = ActionSemantics.compile(sequence, {
            template = _template(),
            slot = 'slot_grenade_ability',
        })

        assert.same({ 'quick_swap_cancel' }, supported.commands)
        assert.same({}, unsupported.commands)
        assert.same({ { command = 'quick_swap_cancel', step = 1 } }, unsupported.unresolved_steps)
    end)

    it('translates profile-step cycle positions into runtime command positions', function()
        local plan = ActionSemantics.compile({
            steps = { 'light_attack', 'push_attack' },
            cycle_step = 2,
            repeating = true,
        }, { template = _template() })

        assert.same({
            'start_attack',
            'light_attack',
            'idle',
            'block',
            'push',
            'push_follow_up',
        }, plan.commands)
        assert.are.equal(4, plan.cycle_index)
        assert.is_true(plan.repeating)
    end)

    it('keeps repeating cycle positions inside the compiled command plan', function()
        local plan = ActionSemantics.compile({
            steps = { 'light_attack' },
            cycle_step = 2,
            repeating = true,
        }, { template = _template() })

        assert.are.equal(1, plan.cycle_index)
        assert.is_true(plan.repeating)
    end)

    it('classifies current-source attack names before incidental suffixes', function()
        local cases = {
            action_start_wield = 'start_attack',
            action_light_wield = 'light_attack',
            action_heavy_wield = 'heavy_attack',
            action_left_heavy_special = 'heavy_attack',
            action_light_1_special = 'light_attack',
            action_right_light_heavy_follow_up_2 = 'light_attack',
            action_special_sweep_activate_heavy = 'special_heavy_execute',
            action_toggle_flashlight = 'special_action',
            action_unwield = 'quick_wield',
            action_attack_special_2 = 'light_attack',
        }

        for action_name, expected in pairs(cases) do
            assert.are.equal(expected, ActionSemantics.classify_current(action_name, nil), action_name)
        end
    end)

    it('uses expected commands only to resolve ambiguous runtime actions', function()
        assert.are.equal(
            'start_attack',
            ActionSemantics.classify_current('action_melee_start_special', { kind = 'windup' }, 'heavy_attack')
        )
        assert.are.equal(
            'push_follow_up',
            ActionSemantics.classify_current('unnamed_sweep', { kind = 'sweep' }, 'push_follow_up')
        )
        assert.are.equal(
            'light_attack',
            ActionSemantics.classify_current('action_light_wield', { kind = 'sweep' }, 'heavy_attack')
        )
        assert.are.equal(
            'special_heavy_execute',
            ActionSemantics.classify_current(
                'action_special_sweep_activate_heavy',
                { kind = 'sweep' },
                'special_light_attack'
            )
        )
        assert.are.equal(
            'special_action',
            ActionSemantics.classify_current('action_attack_special', { kind = 'sweep' }, 'light_attack')
        )
    end)

    it('detects primary-bound charge inputs from template metadata', function()
        local template = _template({
            action_charge = {
                kind = 'overload_charge',
                start_input = 'shoot_charge',
            },
        })
        template.action_inputs = {
            shoot_charge = {
                input_sequence = {
                    { inputs = { { input = 'action_one_hold' } } },
                },
            },
        }
        local context = { template = template }

        assert.is_true(ActionSemantics.uses_primary_charge(context, nil))
        assert.is_true(ActionSemantics.uses_primary_charge(context, { start_input = 'shoot_charge' }))
        assert.is_false(ActionSemantics.uses_primary_charge(context, { start_input = 'missing_input' }))
    end)

    it('classifies charge-ammo actions from their metadata', function()
        local action = ActionSemantics.classify_current('action_charge', {
            kind = 'charge_ammo',
            start_input = 'shoot_pressed',
        }, 'charge')

        assert.are.equal('charge', action)
    end)

    it('classifies special input metadata before action-name fallbacks', function()
        local action = ActionSemantics.classify_current('activate_special', {
            start_input = 'special_action_heavy',
        }, 'special_heavy_execute')

        assert.are.equal('special_heavy_execute', action)
    end)

    it('classifies force-staff trigger explosions as shots', function()
        local action =
            ActionSemantics.classify_current('action_trigger_explosion', { kind = 'trigger_explosion' }, 'shoot')

        assert.are.equal('shoot', action)
    end)

    it('uses the expected command to classify sweep actions', function()
        local action = ActionSemantics.classify_current('sweep_attack', { kind = 'sweep' }, 'heavy_attack')

        assert.are.equal('heavy_attack', action)
    end)

    it('falls back to common action-name patterns', function()
        assert.are.equal('quick_wield', ActionSemantics.classify_current('quick_wield', nil))
        assert.are.equal('push_follow_up', ActionSemantics.classify_current('pushfollow', nil, 'push_follow_up'))
    end)
end)
