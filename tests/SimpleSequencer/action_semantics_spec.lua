local root = debug.getinfo(1, 'S').source:sub(2):match('^(.*)/tests/SimpleSequencer/') or '.'
local ActionSemantics = dofile(root .. '/SimpleSequencer/scripts/mods/SimpleSequencer/modules/ActionSemantics.lua')

local function _template(actions, action_inputs, aim_mode)
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
                        transition = { { input = 'push_follow_up', transition = 'base' } },
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
        },
        action_inputs = action_inputs,
        actions = actions or {},
        aim_mode = aim_mode,
    }
end

local function _plan(template, steps, cycle_step, repeating)
    return ActionSemantics.compile({
        steps = steps,
        cycle_step = cycle_step,
        repeating = repeating,
    }, { template = template, aim_mode = template.aim_mode })
end

describe('SimpleSequencer ActionSemantics', function()
    it('compiles one goal directly from the input hierarchy', function()
        local plan = _plan(_template(), { 'light_attack' }, 1, true)
        local goal = plan.goals[1]

        assert.same({ 'start_attack', 'light_attack' }, goal.inputs)
        assert.are.equal('light_attack', goal.command)
        assert.are.equal(1, goal.step)
    end)

    it('derives nested push goals without expanding legacy action states', function()
        local plan = _plan(_template(), { 'push_attack' })

        assert.same({ 'block', 'push', 'push_follow_up' }, plan.goals[1].inputs)
    end)

    it('compiles parser subprograms for nested Push paths', function()
        local plan = _plan(_template(), { 'push_attack' })
        local programs = plan.goals[1].programs

        assert.same({ 'block' }, programs[1])
        assert.same({ 'push', 'push_follow_up' }, programs[2])
        assert.same({ 'push_follow_up' }, programs[3])
    end)

    it('keeps the immediate Start Attack follow-up in its compiled program', function()
        local plan = _plan(_template(), { 'heavy_attack' })
        local programs = plan.goals[1].programs

        assert.same({ 'start_attack', 'heavy_attack' }, programs[1])
        assert.same({ 'heavy_attack' }, programs[2])
    end)

    it('uses standard fire when a special state is active', function()
        local template = _template()
        template.action_input_hierarchy = {
            { input = 'special_action', transition = 'base' },
            { input = 'shoot_pressed', transition = 'stay' },
        }
        local sequence = { steps = { 'special' }, cycle_step = 1, repeating = true }
        local inactive = ActionSemantics.compile(sequence, { template = template, special_active = false })
        local active = ActionSemantics.compile(sequence, { template = template, special_active = true })

        assert.same({ 'special_action' }, inactive.goals[1].inputs)
        assert.same({ 'shoot_pressed' }, active.goals[1].inputs)
    end)

    it('selects special variants from the runtime hierarchy', function()
        local template = _template()
        local plan = _plan(template, { 'special' })
        local charged = _plan(template, { 'special_charged' })
        local special_action_heavy = _plan(template, { 'special_action_heavy' })

        assert.same({ 'special_action_hold', 'special_action_light' }, plan.goals[1].inputs)
        assert.same({ 'special_action_hold', 'special_action_heavy' }, charged.goals[1].inputs)
        assert.same({ 'special_action_hold', 'special_action_heavy' }, special_action_heavy.goals[1].inputs)
    end)

    it('falls back to the generic special input when no variant exists', function()
        local template = _template()
        template.action_input_hierarchy[3].transition = nil

        local plan = _plan(template, { 'special_charged' })
        local special_action_heavy = _plan(template, { 'special_action_heavy' })

        assert.same({ 'special_action' }, plan.goals[1].inputs)
        assert.are.equal('special_charged', plan.goals[1].command)
        assert.same({ 'special_action' }, special_action_heavy.goals[1].inputs)
        assert.are.equal('special_action_heavy', special_action_heavy.goals[1].command)
    end)

    it('skips melee special activations while the special state is active', function()
        local plan = ActionSemantics.compile(
            { steps = { 'special_action', 'special_action_heavy', 'light_attack' }, cycle_step = 1, repeating = true },
            { template = _template(), kind = 'MELEE', special_active = true }
        )

        assert.are.equal(1, #plan.goals)
        assert.same({ 'start_attack', 'light_attack' }, plan.goals[1].inputs)
    end)

    it('uses power-sword special attacks while the charge state is active', function()
        local template = _template()
        template.action_input_hierarchy = {
            {
                input = 'start_attack_special',
                transition = {
                    { input = 'light_attack_special', transition = 'base' },
                    { input = 'heavy_attack_special', transition = 'base' },
                },
            },
        }

        local plan = ActionSemantics.compile(
            { steps = { 'special_action', 'special_action_heavy' }, cycle_step = 1, repeating = true },
            { template = template, kind = 'MELEE', special_active = true }
        )

        assert.are.equal(2, #plan.goals)
        assert.same({ 'start_attack_special', 'light_attack_special' }, plan.goals[1].inputs)
        assert.same({ 'start_attack_special', 'heavy_attack_special' }, plan.goals[2].inputs)
        assert.same({ 'start_attack_special', 'heavy_attack_special' }, plan.goals[2].programs[1])
    end)

    it('falls back to normal attacks when a special attack lacks charges', function()
        local template = _template()
        template.action_input_hierarchy[#template.action_input_hierarchy + 1] = {
            input = 'start_attack_special',
            transition = {
                { input = 'light_attack_special', transition = 'base' },
                { input = 'heavy_attack_special', transition = 'base' },
            },
        }

        local plan = ActionSemantics.compile(
            { steps = { 'special_action', 'special_action_heavy' }, cycle_step = 1, repeating = true },
            { template = template, kind = 'MELEE', special_charges = 0, special_charge_cost = 1 }
        )

        assert.same({ 'start_attack', 'light_attack' }, plan.goals[1].inputs)
        assert.same({ 'start_attack', 'heavy_attack' }, plan.goals[2].inputs)
    end)

    it('skips charge-gated special activations and continues the sequence', function()
        local plan = ActionSemantics.compile(
            { steps = { 'special_action', 'special_action_heavy', 'light_attack' }, cycle_step = 1, repeating = true },
            { template = _template(), kind = 'MELEE', special_charges = 0, special_charge_cost = 1 }
        )

        assert.are.equal(1, #plan.goals)
        assert.same({ 'start_attack', 'light_attack' }, plan.goals[1].inputs)
    end)

    it('selects the brace release path for charged ADS goals', function()
        local template = _template({
            action_charge = {
                kind = 'overload_charge',
                start_input = 'brace',
                allowed_chain_actions = {
                    shoot_braced = { action_name = 'action_shoot_charged' },
                },
            },
            action_shoot_charged = { kind = 'shoot_hit_scan', use_charge = true },
        }, nil, 'ads')
        template.action_input_hierarchy = {
            {
                input = 'brace',
                transition = { { input = 'shoot_braced', transition = 'base' } },
            },
        }

        local plan = _plan(template, { 'charged' })
        local goal = plan.goals[1]

        assert.same({ 'brace', 'shoot_braced' }, goal.inputs)
        assert.are.equal(2, ActionSemantics.matched_input_index(goal, nil, 'action_shoot_charged', template))
    end)

    it('ignores unsupported profile steps and counts only compiled goals', function()
        local plan = _plan(_template(), { 'light_attack', 'missing', 'block' }, 3, true)

        assert.are.equal(2, #plan.goals)
        assert.are.equal(2, plan.goal_cycle_index)
    end)

    it('matches actions through their chain metadata when start_input is absent', function()
        local template = _template({
            action_melee_start = {
                allowed_chain_actions = {
                    light_attack = { action_name = 'action_left_light' },
                },
            },
            action_left_light = { kind = 'sweep' },
        })
        local plan = _plan(template, { 'light_attack' })
        local goal = plan.goals[1]

        assert.are.equal(2, ActionSemantics.matched_input_index(goal, nil, 'action_left_light', template))
    end)

    it('does not count a powered windup as its eventual sweep', function()
        local template = _template({
            action_light_special = { activate_special_during_sweep = true, kind = 'sweep' },
            action_melee_start_special = {
                activate_special_during_windup = true,
                allowed_chain_actions = {
                    light_attack_special = { action_name = 'action_light_special' },
                },
                kind = 'windup',
            },
        })
        local light_goal = { inputs = { 'start_attack', 'light_attack' } }
        local heavy_goal = { inputs = { 'start_attack', 'heavy_attack' } }

        assert.is_nil(ActionSemantics.matched_input_index(light_goal, nil, 'action_melee_start_special', template))
        assert.are.equal(
            2,
            ActionSemantics.matched_input_index(
                light_goal,
                nil,
                'action_light_special',
                template,
                'light_attack_special'
            )
        )
    end)

    it('prefers the active action start input over a shared chain target', function()
        local template = _template({
            action_push = {
                allowed_chain_actions = {
                    push = { action_name = 'action_block' },
                },
            },
            action_block = { start_input = 'block' },
        })
        local goal = { inputs = { 'block', 'push' } }

        assert.are.equal(1, ActionSemantics.matched_input_index(goal, 'block', 'action_block', template))
    end)

    it('prefers an action start input over a stale interpreter submission', function()
        local template = _template({ action_shoot_zoomed = { start_input = 'zoom_shoot' } })
        local goal = { inputs = { 'zoom', 'zoom_shoot' } }

        assert.are.equal(
            2,
            ActionSemantics.matched_input_index(goal, 'zoom_shoot', 'action_shoot_zoomed', template, 'zoom')
        )
    end)

    it('selects the zoom firing path for standard ADS goals', function()
        local template = _template(nil, nil, 'ads')
        template.action_input_hierarchy = {
            { input = 'shoot_pressed', transition = 'stay' },
            { input = 'zoom', transition = { { input = 'zoom_shoot', transition = 'stay' } } },
        }

        local plan = _plan(template, { 'standard' })

        assert.same({ 'zoom', 'zoom_shoot' }, plan.goals[1].inputs)
        assert.same({ 'zoom_shoot' }, plan.goals[1].repeat_program)
        assert.is_true(plan.goals[1].repeat_at_chain_boundary)
    end)

    it('matches a canonical chain alias when the exact alias is absent', function()
        local template = _template({
            action_melee_start = {
                allowed_chain_actions = {
                    light_attack = { action_name = 'action_target' },
                },
            },
            action_target = { kind = 'sweep' },
        })
        local goal = { inputs = { 'light_attack_special' } }

        assert.are.equal(1, ActionSemantics.matched_input_index(goal, nil, 'action_target', template))
    end)
end)
