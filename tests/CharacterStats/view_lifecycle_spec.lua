local root = debug.getinfo(1, 'S').source:sub(2):match('^(.*)/tests/CharacterStats/') or '.'

local function load_view()
    local build_count = { value = 0 }
    local shared_utils = {
        stats_view_names = {},
        apply_loc_settings = function() end,
        load_icon_packages = function()
            return {}
        end,
        register_stats_view = function() end,
    }
    local builder = {
        build_stats = function()
            build_count.value = build_count.value + 1
            return { { type = 'stat', value = '42' } }, nil, nil, nil
        end,
    }
    local mod = {
        get_name = function()
            return 'CharacterStats'
        end,
        localize = function(_, text_id)
            return text_id
        end,
        original_require = function()
            return {}
        end,
        io_dofile = function(_, path)
            if path == 'CharacterStats/scripts/mods/CharacterStats/shared/shared_utils' then
                return shared_utils
            elseif path == 'CharacterStats/scripts/mods/CharacterStats/character_stats_builder' then
                return builder
            elseif path == 'CharacterStats/scripts/mods/CharacterStats/shared/shared_view_base' then
                return dofile(root .. '/scripts/shared/shared_view_base.lua')
            elseif
                path
                == 'CharacterStats/scripts/mods/CharacterStats/character_stats_view/character_stats_detail_blueprints'
            then
                return function()
                    return {}
                end
            elseif path == 'CharacterStats/scripts/mods/CharacterStats/CharacterStats_localization' then
                return {}
            end
        end,
    }
    local base_view = {
        on_enter = function() end,
        on_exit = function() end,
    }
    local previous = {
        callback = _G.callback,
        class = _G.class,
        get_mod = _G.get_mod,
        Managers = _G.Managers,
    }

    _G.callback = function()
        return function() end
    end
    _G.class = function()
        return { super = base_view }
    end
    _G.get_mod = function()
        return mod
    end
    _G.Managers = {}

    local view_class =
        dofile(root .. '/CharacterStats/scripts/mods/CharacterStats/character_stats_view/character_stats_view.lua')

    _G.callback = previous.callback
    _G.class = previous.class
    _G.get_mod = previous.get_mod
    _G.Managers = previous.Managers

    return view_class, build_count
end

describe('CharacterStats view lifecycle', function()
    it('rebuilds the detail panel after the cached view is reopened', function()
        local View, build_count = load_view()
        local presented_count = 0
        local detail_setup_count = 0
        local view = setmetatable({
            _definitions = { detail_grid_settings = { grid_size = { 600 } } },
            _detail_built = true,
            _detail_entry = { name = 'Character Stats' },
            _detail_grid = {
                length_scrolled = function()
                    return 0
                end,
                present_grid_layout = function()
                    presented_count = presented_count + 1
                end,
            },
        }, { __index = View })

        view._setup_detail_grid = function()
            detail_setup_count = detail_setup_count + 1
        end
        view._setup_input_legend = function() end
        view._setup_list_grid = function() end
        view._setup_search = function() end
        view._setup_entries = function() end

        local previous_callback = _G.callback
        local previous_managers = _G.Managers
        _G.callback = function()
            return function() end
        end
        _G.Managers = {}
        view:on_enter()
        view:_on_update(0, 0, nil)
        view:_on_update(0, 0, nil)
        _G.callback = previous_callback
        _G.Managers = previous_managers

        assert.are.equal(1, detail_setup_count)
        assert.are.equal(1, build_count.value)
        assert.are.equal(1, presented_count)
    end)
end)
