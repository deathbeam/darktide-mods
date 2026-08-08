local root = debug.getinfo(1, 'S').source:sub(2):match('^(.*)/tests/SimpleSequencer/') or '.'
local ActionSemantics = dofile(root .. '/SimpleSequencer/scripts/mods/SimpleSequencer/modules/ActionSemantics.lua')

local function _template(actions, action_inputs, ranged_mode)
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
        ranged_mode = ranged_mode,
    }
end

local function _plan(template, steps, cycle_step, repeating)
    return ActionSemantics.compile({
        steps = steps,
        cycle_step = cycle_step,
        repeating = repeating,
    }, { template = template, ranged_mode = template.ranged_mode })
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

    it('selects special variants from the runtime hierarchy', function()
        local template = _template()
        local plan = _plan(template, { 'special' })
        local charged = _plan(template, { 'special_charged' })

        assert.same({ 'special_action_hold', 'special_action_light' }, plan.goals[1].inputs)
        assert.same({ 'special_action_hold', 'special_action_heavy' }, charged.goals[1].inputs)
    end)

    it('falls back to the generic special input when no variant exists', function()
        local template = _template()
        template.action_input_hierarchy[3].transition = nil

        local plan = _plan(template, { 'special_charged' })

        assert.same({ 'special_action' }, plan.goals[1].inputs)
        assert.are.equal('special_charged', plan.goals[1].command)
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

    it('reports unresolved profile steps and counts only compiled goals', function()
        local plan = _plan(_template(), { 'light_attack', 'missing', 'block' }, 3, true)

        assert.are.equal(2, #plan.goals)
        assert.same({ { command = 'missing', step = 2 } }, plan.unresolved_steps)
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
end)
