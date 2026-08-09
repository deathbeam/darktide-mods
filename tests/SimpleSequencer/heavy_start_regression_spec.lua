local DarktideMock = require('tests.shared.darktide_mock')

describe('SimpleSequencer heavy starts', function()
    local function new_manager(profile)
        return {
            active = function()
                return 'mode_1'
            end,
            profile = function()
                return profile
            end,
            toggle = function() end,
        }
    end

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
        local engine = mock:load_controller(new_manager({
            sequence_cycle_point = 'sequence_step_1',
            sequence_step_1 = 'heavy_attack',
        }))

        mock.now = 0.2
        mock:run_input_frame(engine, { action_one_hold = true })
        mock:set_action('action_melee_start', template.actions.action_melee_start, action_start_t)
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
end)
