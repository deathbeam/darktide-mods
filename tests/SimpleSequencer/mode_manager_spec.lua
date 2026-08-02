local DarktideMock = require('tests.shared.darktide_mock')
local root = debug.getinfo(1, 'S').source:sub(2):match('^(.*)/tests/SimpleSequencer/') or '.'

describe('SimpleSequencer ModeManager', function()
    it('syncs the full selected melee profile into the settings UI', function()
        local mock = DarktideMock.new()
        local ModeManager = dofile(root .. '/SimpleSequencer/scripts/mods/SimpleSequencer/modules/ModeManager.lua')

        function mock.mod:set(setting_id, value)
            mock.settings[setting_id] = value
        end

        local manager = ModeManager:new(mock.mod)
        manager.selected_weapons.mode_1.MELEE = 'test_melee'
        manager.data.mode_1.MELEE.test_melee = {
            sequence_cycle_point = 'sequence_step_3',
            sequence_step_1 = 'heavy_attack',
        }

        manager:sync_settings()

        assert.are.equal('test_melee', mock.settings.melee_weapon_selection)
        assert.are.equal('sequence_step_3', mock.settings.melee_sequence_cycle_point)
        assert.are.equal('heavy_attack', mock.settings.melee_sequence_step_1)
    end)
end)
