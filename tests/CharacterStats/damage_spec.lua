local DarktideMock = require('tests.shared.darktide_mock')

local root = debug.getinfo(1, 'S').source:sub(2):match('^(.*)/tests/CharacterStats/') or '.'
local TEMPLATE_NAME = 'dynamic_charge_damage'

local function load_utils(with_class_loadout)
    local mock = DarktideMock.new()
    local dependencies = {
        ['scripts/settings/buff/buff_settings'] = {
            stat_buff_types = {
                damage_vs_electrocuted = 'additive_multiplier',
            },
            stat_buff_type_base_values = {
                damage_vs_electrocuted = 1,
            },
        },
        ['scripts/settings/difficulty/player_difficulty_settings'] = {},
        ['scripts/utilities/character_sheet'] = with_class_loadout and {
            class_loadout = function(_, destination)
                destination.combat_ability = { max_charges = 3 }
            end,
        } or {},
        ['scripts/settings/ability/player_abilities/player_abilities'] = {
            cryptic_discharge = { max_charges = 3 },
        },
        ['scripts/settings/buff/buff_templates'] = {
            [TEMPLATE_NAME] = {
                stat_buffs = {
                    damage_vs_electrocuted = 1,
                },
                stat_buff_multipliers = {
                    damage_vs_electrocuted = function(template_data)
                        return 0.1 + template_data.ability_extension:max_ability_charges('combat_ability') * 0.05
                    end,
                },
            },
        },
    }

    function mock.mod:original_require(path)
        return dependencies[path] or {}
    end

    function mock.mod:io_dofile(path)
        if path == 'CharacterStats/scripts/mods/CharacterStats/shared/shared_utils' then
            return {
                prettify = function(key)
                    return key
                end,
                safe_localize = function(key)
                    return key
                end,
            }
        end
        return dofile(root .. '/' .. path .. '.lua')
    end

    mock:install()
    return dofile(root .. '/CharacterStats/scripts/mods/CharacterStats/character_stats_utils.lua'), mock
end

describe('CharacterStats dynamic damage buffs', function()
    local function fold_damage(Utils, mock, abilities)
        local profile = {
            abilities = abilities,
            archetype = {
                name = 'cryptic',
                talents = {
                    dynamic_charge_damage = {
                        display_name = 'Dynamic Charge Damage',
                        passive = { buff_template_name = TEMPLATE_NAME },
                    },
                },
            },
            talents = { dynamic_charge_damage = 1 },
        }
        return Utils.folded_stat_buffs(mock.unit, profile, mock.player, {
            assume_proc_stacks = true,
        })
    end
    it('resolves a data-defined stat multiplier with configured maximum ability charges', function()
        local Utils, mock = load_utils()
        local folded = fold_damage(Utils, mock, { combat_ability = 'cryptic_discharge' })
        assert.are.equal(1.25, folded.values.damage_vs_electrocuted)
        assert.are.equal(0.25, folded.sources.damage_vs_electrocuted[1].delta)
    end)
    it('resolves configured maximum charges through the class loadout in the hub', function()
        local Utils, mock = load_utils(true)
        local folded = fold_damage(Utils, mock, {})
        assert.are.equal(1.25, folded.values.damage_vs_electrocuted)
    end)
end)
