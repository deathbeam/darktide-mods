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
    return ActionSemantics.plan({
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

        local plan = ActionSemantics.plan({
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

    it('falls back to a standard special when no charged variant exists', function()
        local template = _template()
        table.remove(template.action_input_hierarchy, 3)

        local plan = _plan(template, 'special_charged')

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
        local plan = ActionSemantics.plan({
            steps = { 'light_attack' },
            cycle_step = 1,
            repeating = true,
        }, { template = {} })

        assert.same({}, plan.commands)
        assert.same({ { command = 'light_attack', step = 1 } }, plan.unresolved_steps)
        assert.is_false(plan.repeating)
    end)

    it('translates profile-step cycle positions into runtime command positions', function()
        local plan = ActionSemantics.plan({
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

    it('uses the expected command to classify sweep actions', function()
        local action = ActionSemantics.classify_current('sweep_attack', { kind = 'sweep' }, 'heavy_attack')

        assert.are.equal('heavy_attack', action)
    end)

    it('falls back to common action-name patterns', function()
        assert.are.equal('quick_wield', ActionSemantics.classify_current('quick_wield', nil, 'quick_wield'))
        assert.are.equal('push_follow_up', ActionSemantics.classify_current('pushfollow', nil, 'push_follow_up'))
    end)

    it('owns execution policy for canonical command states', function()
        local special_policy = ActionSemantics.command_policy('special_action')

        assert.is_true(special_policy.weapon_extra_pressed)
        assert.is_true(special_policy.suppress_primary_hold)
        assert.are.equal('pulse', ActionSemantics.command_policy('start_attack').hold_overrides.push)
    end)
end)
