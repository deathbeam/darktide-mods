local DarktideMock = require('tests.shared.darktide_mock')

local root = debug.getinfo(1, 'S').source:sub(2):match('^(.*)/tests/CharacterStats/') or '.'

local function load_utils()
    local mock = DarktideMock.new()
    local dependencies = {
        ['scripts/settings/buff/buff_settings'] = {
            stat_buff_types = {},
            stat_buff_type_base_values = {},
        },
        ['scripts/settings/difficulty/player_difficulty_settings'] = {
            archetype_wounds = {
                zealot = { 4, 3, 3, 2, 2 },
            },
        },
    }

    function mock.mod:original_require(path)
        return dependencies[path] or {}
    end

    function mock.mod:io_dofile(path)
        if path == 'CharacterStats/scripts/mods/CharacterStats/shared/shared_utils' then
            return {}
        end
        return dofile(root .. '/' .. path .. '.lua')
    end

    mock:install()
    local Utils = dofile(root .. '/CharacterStats/scripts/mods/CharacterStats/character_stats_utils.lua')
    return Utils, mock
end

describe('CharacterStats wounds', function()
    it('adds talent and curio wound bonuses to the difficulty base', function()
        local Utils = load_utils()

        local folded = {
            values = {
                extra_max_amount_of_wounds = 5,
            },
        }

        assert.are.equal(8, Utils.compute_max_wounds(folded, 3))
        assert.are.equal(7, Utils.compute_max_wounds(folded, 2))
        assert.are.equal(3, Utils.compute_max_wounds({ values = {} }, 3))
    end)

    it('uses a consistent max normal difficulty and the Havoc bracket when configured', function()
        local Utils = load_utils()
        Managers.state = {
            game_mode = {
                is_social_hub = function()
                    return true
                end,
            },
        }
        local archetype = { name = 'zealot' }
        assert.are.equal(2, Utils.compute_max_wounds({ values = {} }, 3, archetype, 0))
        assert.are.equal(3, Utils.compute_max_wounds({ values = {} }, 3, archetype, 1))
        assert.are.equal(2, Utils.compute_max_wounds({ values = {} }, 3, archetype, 40))
        Managers.state.game_mode.is_social_hub = function()
            return false
        end
        assert.are.equal(2, Utils.compute_max_wounds({ values = {} }, 3, archetype, 0))
    end)
end)
