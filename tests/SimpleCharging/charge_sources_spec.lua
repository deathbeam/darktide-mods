local DarktideMock = require('tests.shared.darktide_mock')

local root = debug.getinfo(1, 'S').source:sub(2):match('^(.*)/tests/SimpleCharging/') or '.'

local function _load_sources(mock)
    mock:install()

    return dofile(root .. '/SimpleCharging/scripts/mods/SimpleCharging/modules/ChargeSources.lua')
end

local function _settings()
    return {
        show_weapon_charge = false,
    }
end

describe('SimpleCharging ChargeSources', function()
    it('reads stepped stacking blessings from the equipped item', function()
        local mock = DarktideMock.new()
        local ChargeSources = _load_sources(mock)
        local buff = {
            _template = {
                name = 'weapon_trait_bespoke_bolter_p1_stacking_power_bonus_on_staggering_enemies',
                class_name = 'stepped_stat_buff',
                min_max_step_func = function()
                    return 0, 5
                end,
            },
            _template_data = {},
            _template_context = {
                item_slot_name = 'slot_secondary',
            },
            visual_stack_count = function()
                return 3
            end,
        }
        local context = {
            buff_extension = {
                _buffs = { buff },
            },
            wielded_slot = 'slot_secondary',
        }

        local sources = ChargeSources.collect(context, _settings())

        assert.are.equal(1, #sources)
        assert.are.equal(3, sources[1].value)
        assert.are.equal(5, sources[1].maximum)
        assert.are.equal(0.6, sources[1].fraction)
    end)

    it('uses the child maximum for charge-time parent buffs', function()
        local mock = DarktideMock.new()
        local ChargeSources = _load_sources(mock)
        local parent = {
            _template = {
                name = 'weapon_trait_bespoke_ogryn_pickaxe_2h_p1_toughness_on_hit_based_on_charge_time',
                class_name = 'weapon_trait_parent_proc_buff',
                child_buff_template = 'weapon_trait_bespoke_ogryn_pickaxe_2h_p1_toughness_on_hit_based_on_charge_time_visual_stack_count',
            },
            _template_data = {},
            _template_context = {
                item_slot_name = 'slot_secondary',
            },
            visual_stack_count = function()
                return 2
            end,
        }
        local child = {
            _template = {
                name = 'weapon_trait_bespoke_ogryn_pickaxe_2h_p1_toughness_on_hit_based_on_charge_time_visual_stack_count',
                class_name = 'buff',
                hide_icon_in_hud = true,
                max_stacks = 3,
            },
        }
        local context = {
            buff_extension = {
                _buffs = { parent, child },
            },
            wielded_slot = 'slot_secondary',
        }

        local sources = ChargeSources.collect(context, _settings())

        assert.are.equal(1, #sources)
        assert.are.equal(2, sources[1].value)
        assert.are.equal(3, sources[1].maximum)
    end)

    it('shows effective critical chance for crit-scaling blessings', function()
        local mock = DarktideMock.new()
        local ChargeSources = _load_sources(mock)
        local buff = {
            _template = {
                name = 'weapon_trait_bespoke_autogun_p3_crit_chance_based_on_aim_time',
                class_name = 'stepped_stat_buff',
                min_max_step_func = function()
                    return 0, 10
                end,
            },
            _template_data = {},
            _template_context = {
                item_slot_name = 'slot_secondary',
            },
            visual_stack_count = function()
                return 4
            end,
        }
        local context = {
            player = {
                profile = function()
                    return {
                        archetype = {
                            base_critical_strike_chance = 0.1,
                        },
                    }
                end,
            },
            buff_extension = {
                _buffs = { buff },
                stat_buffs = function()
                    return {
                        critical_strike_chance = 0.05,
                        ranged_critical_strike_chance = 0.2,
                    }
                end,
            },
            weapon_extension = {},
            wielded_slot = 'slot_secondary',
            kind = 'ranged',
        }

        local sources = ChargeSources.collect(context, _settings())

        assert.are.equal(1, #sources)
        assert.is_true(math.abs(sources[1].value - 0.35) < 0.0001)
        assert.are.equal(1, sources[1].maximum)
        assert.is_true(math.abs(sources[1].fraction - 0.35) < 0.0001)
    end)

    it('hides inactive sources', function()
        local mock = DarktideMock.new()
        local ChargeSources = _load_sources(mock)
        local buff = {
            _template = {
                name = 'weapon_trait_bespoke_bolter_p1_stacking_power_bonus_on_staggering_enemies',
                class_name = 'stepped_stat_buff',
                min_max_step_func = function()
                    return 0, 5
                end,
            },
            _template_data = {},
            _template_context = {
                item_slot_name = 'slot_secondary',
            },
            visual_stack_count = function()
                return 0
            end,
        }
        local context = {
            buff_extension = {
                _buffs = { buff },
            },
            wielded_slot = 'slot_secondary',
        }
        local settings = _settings()

        local sources = ChargeSources.collect(context, settings)

        assert.are.equal(0, #sources)
    end)

    it('shows weapon charge when enabled', function()
        local mock = DarktideMock.new()
        local ChargeSources = _load_sources(mock)
        local context = {
            charge_component = {
                charge_level = 0.5,
                max_charge = 1,
            },
            weapon_action = {
                current_action_name = 'action_charge',
            },
            buff_extension = {
                _buffs = {},
            },
        }
        local settings = _settings()
        settings.show_weapon_charge = true

        local sources = ChargeSources.collect(context, settings)

        assert.are.equal(1, #sources)
        assert.are.equal('weapon_charge', sources[1].id)
        assert.are.equal(0.5, sources[1].fraction)
    end)
end)
