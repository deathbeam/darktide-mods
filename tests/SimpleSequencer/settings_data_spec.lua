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
        assert.is_not_nil(find_widget(data.options.widgets, 'mode_4_display_color_b'))
    end)
end)
