local DarktideMock = require('tests.shared.darktide_mock')
local root = debug.getinfo(1, 'S').source:sub(2):match('^(.*)/tests/SimpleSequencer/') or '.'
local mock = DarktideMock.new()
local ProfileSchema = dofile(root .. '/SimpleSequencer/scripts/mods/SimpleSequencer/modules/ProfileSchema.lua')
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
        local plan = Profiles.compile(data.mode_1.MELEE.global_melee, 'MELEE')

        assert.same({ 'light_attack' }, plan.steps)
        assert.are.equal(1, plan.cycle_step)
        assert.is_true(plan.repeating)
    end)

    it('leaves a no-repeat melee profile without a cycle point', function()
        local profile = {
            sequence_cycle_point = 'no_repeat',
            sequence_step_1 = 'light_attack',
        }

        local plan = Profiles.compile(profile, 'MELEE')

        assert.same({ 'light_attack' }, plan.steps)
        assert.are.equal(0, plan.cycle_step)
        assert.is_false(plan.repeating)
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

    it('derives setting keys from profile defaults', function()
        local function contains(keys, expected)
            for _, key in ipairs(keys) do
                if key == expected then
                    return true
                end
            end

            return false
        end

        local melee_keys = ProfileSchema.keys('MELEE')
        local ranged_keys = ProfileSchema.keys('RANGED')

        assert.are.equal(7, #melee_keys)
        assert.is_true(contains(melee_keys, 'sequence_cycle_point'))
        assert.is_true(contains(melee_keys, 'sequence_step_6'))
        assert.are.equal(3, #ranged_keys)
        assert.is_true(contains(ranged_keys, 'auto_charge_threshold'))
    end)
end)
