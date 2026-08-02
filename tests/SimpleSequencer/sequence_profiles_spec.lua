local root = debug.getinfo(1, 'S').source:sub(2):match('^(.*)/tests/SimpleSequencer/') or '.'
local Profiles = dofile(root .. '/SimpleSequencer/scripts/mods/SimpleSequencer/modules/SequenceProfiles.lua')

describe('SimpleSequencer SequenceProfiles', function()
    it('expands a repeating melee profile into action states', function()
        local data = {
            mode_1 = {
                MELEE = {
                    global_melee = {
                        sequence_cycle_point = 'sequence_step_1',
                        sequence_step_1 = 'light_attack',
                    },
                },
                RANGED = {},
            },
        }

        Profiles.ensure(data)
        local commands, cycle_index, repeating = Profiles.build(data.mode_1.MELEE.global_melee, 'MELEE')

        assert.same({ 'start_attack', 'light_attack', 'idle' }, commands)
        assert.are.equal(1, cycle_index)
        assert.is_true(repeating)
    end)

    it('leaves a no-repeat melee profile without a cycle point', function()
        local profile = {
            sequence_cycle_point = 'no_repeat',
            sequence_step_1 = 'light_attack',
        }

        local commands, cycle_index, repeating = Profiles.build(profile, 'MELEE')

        assert.same({ 'start_attack', 'light_attack', 'idle' }, commands)
        assert.are.equal(0, cycle_index)
        assert.is_false(repeating)
    end)

    it('fills missing profile settings without replacing existing values', function()
        local data = {
            mode_1 = {
                MELEE = {
                    global_melee = {
                        sequence_step_1 = 'heavy_attack',
                    },
                },
                RANGED = {},
            },
        }

        Profiles.ensure(data)
        local profile = data.mode_1.MELEE.global_melee

        assert.are.equal('heavy_attack', profile.sequence_step_1)
        assert.are.equal('none', profile.sequence_step_2)
        assert.are.equal('sequence_step_1', profile.sequence_cycle_point)
    end)
end)
