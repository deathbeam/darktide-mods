local DarktideMock = require('tests.shared.darktide_mock')
local root = debug.getinfo(1, 'S').source:sub(2):match('^(.*)/tests/SimpleSequencer/') or '.'

describe('SimpleSequencer settings data', function()
    it('uses unique setting IDs and localization keys', function()
        local mock = DarktideMock.new()

        function mock.mod:localize(key)
            return 'localized:' .. key
        end

        package.preload['scripts/settings/ui/ui_settings'] = function()
            return { weapon_patterns = {} }
        end
        package.preload['scripts/settings/equipment/weapon_templates/weapon_templates'] = function()
            return {}
        end

        local data = dofile(root .. '/SimpleSequencer/scripts/mods/SimpleSequencer/SimpleSequencer_data.lua')
        local localizations =
            dofile(root .. '/SimpleSequencer/scripts/mods/SimpleSequencer/SimpleSequencer_localization.lua')
        local seen = {}

        local function assert_unique(widgets)
            for _, widget in ipairs(widgets or {}) do
                assert.is_string(widget.type, 'missing widget type: ' .. tostring(widget.setting_id))
                if widget.setting_id then
                    assert.is_nil(seen[widget.setting_id], 'duplicate setting_id: ' .. widget.setting_id)
                    seen[widget.setting_id] = true
                end

                assert_unique(widget.sub_widgets)
            end
        end

        assert_unique(data.options.widgets)

        local function assert_localized(widgets)
            for _, widget in ipairs(widgets or {}) do
                local key = widget.title or widget.setting_id
                assert.is_table(localizations[key], 'missing localization: ' .. key)

                if widget.type == 'dropdown' and widget.options.localize ~= false then
                    for _, option in ipairs(widget.options) do
                        assert.is_table(localizations[option.text], 'missing localization: ' .. option.text)
                    end
                end

                assert_localized(widget.sub_widgets)
            end
        end

        assert_localized(data.options.widgets)

        local function find_widget(widgets, setting_id)
            for _, widget in ipairs(widgets or {}) do
                if widget.setting_id == setting_id then
                    return widget
                end

                local nested = find_widget(widget.sub_widgets, setting_id)
                if nested then
                    return nested
                end
            end
        end

        assert.is_not_nil(find_widget(data.options.widgets, 'mode_1_select'))
        assert.is_not_nil(find_widget(data.options.widgets, 'mode_2_select'))
        assert.is_not_nil(find_widget(data.options.widgets, 'mode_3_select'))
        assert.is_not_nil(find_widget(data.options.widgets, 'mode_4_select'))
        assert.are.equal('select_mode', find_widget(data.options.widgets, 'mode_1_select').title)
        assert.is_nil(find_widget(data.options.widgets, 'mode_1_display_settings'))
        assert.is_not_nil(find_widget(data.options.widgets, 'mode_1_display_name'))
        local color_widget = find_widget(data.options.widgets, 'mode_4_display_color')
        assert.is_not_nil(color_widget)
        assert.are.equal('color', color_widget.type)
        assert.is_false(color_widget.has_alpha)

        local melee_button = find_widget(data.options.widgets, 'melee_use_current_weapon')
        assert.are.equal('button', melee_button.type)
        assert.are.equal('use_current_melee_weapon', melee_button.function_name)

        local melee_step = find_widget(data.options.widgets, 'melee_sequence_step_1')
        local has_special_action_heavy = false
        for _, option in ipairs(melee_step.options) do
            assert.are_not_equal('wield', option.value)
            assert.are_not_equal('quick_swap_cancel', option.value)
            has_special_action_heavy = has_special_action_heavy or option.value == 'special_action_heavy'
        end
        assert.is_true(has_special_action_heavy)

        local editing_mode = find_widget(data.options.widgets, 'editing_mode')
        assert.are.same({ 1 }, editing_mode.options[1].show_widgets)
        assert.are.same({ 2 }, editing_mode.options[2].show_widgets)
        assert.are.same({ 3 }, editing_mode.options[3].show_widgets)
        assert.are.same({ 4 }, editing_mode.options[4].show_widgets)
        assert.are.equal('mode_1_settings', editing_mode.sub_widgets[1].setting_id)
        assert.are.equal('mode_2_settings', editing_mode.sub_widgets[2].setting_id)
        assert.are.equal('mode_3_settings', editing_mode.sub_widgets[3].setting_id)
        assert.are.equal('mode_4_settings', editing_mode.sub_widgets[4].setting_id)
        local hud_display_mode = find_widget(data.options.widgets, 'hud_display_mode')
        assert.are.same({ 1, 2 }, hud_display_mode.options[2].show_widgets)
        assert.are.equal('hud_position_x', hud_display_mode.sub_widgets[1].setting_id)
        assert.are.equal('hud_position_y', hud_display_mode.sub_widgets[2].setting_id)
    end)
end)
