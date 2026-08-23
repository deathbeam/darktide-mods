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
    it('syncs configuration for the selected editing mode', function()
        local mock = DarktideMock.new()
        local ModeManager = dofile(root .. '/SimpleSequencer/scripts/mods/SimpleSequencer/modules/ModeManager.lua')

        function mock.mod:set(setting_id, value)
            mock.settings[setting_id] = value
        end

        local manager = ModeManager:new(mock.mod)
        mock.settings.editing_mode = 'mode_2'
        manager:on_setting_changed('editing_mode')

        mock.settings.melee_sequence_step_1 = 'heavy_attack'
        mock.settings.mode_2_display_name = 'Burst Mode'
        manager:on_setting_changed('melee_sequence_step_1')
        manager:on_setting_changed('mode_2_display_name')

        assert.are.equal('mode_2', manager.editing_mode)
        assert.are.equal('heavy_attack', manager.data.mode_2.MELEE.global_melee.sequence_step_1)
        assert.are.equal('none', manager.data.mode_1.MELEE.global_melee.sequence_step_1)
        assert.are.equal('Burst Mode', manager:display('mode_2').name)
    end)

    it('defers controller reset until the next update', function()
        local mock = DarktideMock.new()
        function mock.mod:set(setting_id, value)
            mock.settings[setting_id] = value
        end
        local ModeManager = dofile(root .. '/SimpleSequencer/scripts/mods/SimpleSequencer/modules/ModeManager.lua')
        local manager = ModeManager:new(mock.mod)
        local reset_count = 0
        mock.mod.controller = {
            can_switch_mode = function()
                return true
            end,
            invalidate = function() end,
            reset = function()
                reset_count = reset_count + 1
            end,
        }

        assert.is_true(manager:select('mode_2'))
        assert.are.equal('mode_1', manager:active())
        assert.are.equal(0, reset_count)

        manager:update()

        assert.are.equal('mode_2', manager:active())
        assert.are.equal(1, reset_count)
    end)
    it('uses the default when saved display color data is invalid', function()
        local mock = DarktideMock.new()
        mock.settings.mode_1_display_color = { 85, 226, 255 }
        mock.settings.mode_1_color_r = 0
        mock.settings.mode_1_color_g = 0
        mock.settings.mode_1_color_b = 0
        function mock.mod:set(setting_id, value)
            mock.settings[setting_id] = value
        end
        local ModeManager = dofile(root .. '/SimpleSequencer/scripts/mods/SimpleSequencer/modules/ModeManager.lua')
        local manager = ModeManager:new(mock.mod)
        assert.are.same({ 255, 255, 190, 80 }, manager:display('mode_1').color)
        assert.are.same({ 255, 255, 190, 80 }, mock.settings.mode_1_display_color)
        assert.are.equal(0, mock.settings.mode_1_color_r)
        assert.are.equal(0, mock.settings.mode_1_color_g)
        assert.are.equal(0, mock.settings.mode_1_color_b)
    end)
end)
