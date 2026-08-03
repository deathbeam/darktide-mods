local mod = get_mod('EnemyStats')

local SharedUtils = mod:io_dofile('EnemyStats/scripts/mods/EnemyStats/shared/shared_utils')
local Data = mod:io_dofile('EnemyStats/scripts/mods/EnemyStats/enemy_stats_utils')
local make_view = mod:io_dofile('EnemyStats/scripts/mods/EnemyStats/shared/shared_view_base')
local make_detail_blueprints =
    mod:io_dofile('EnemyStats/scripts/mods/EnemyStats/enemy_stats_view/enemy_stats_detail_blueprints')

local EnemyStatsView = make_view(mod, {
    class_name = 'EnemyStatsView',
    prefix = 'enemy_stats',
    shared_utils = SharedUtils,
    definitions_path = 'EnemyStats/scripts/mods/EnemyStats/enemy_stats_view/enemy_stats_view_definitions',
    list_blueprints_path = 'EnemyStats/scripts/mods/EnemyStats/enemy_stats_view/enemy_stats_view_blueprints',
})

function EnemyStatsView:_on_init(settings, context)
    self._enemy_groups = Data.build_enemy_list()
end

-- Enemy list ------------------------------------------------------------

function EnemyStatsView:_setup_entries()
    local search_widget = self._widgets_by_name.enemy_stats_search
    local search_text = search_widget and search_widget.content.input_text or ''
    search_text = search_text:lower()

    local entries = {}
    for i = 1, #self._enemy_groups do
        local entry = self._enemy_groups[i]
        local label = entry.label
        local match = search_text == ''
            or label:lower():find(search_text, 1, true)
            or entry.breed_name:lower():find(search_text, 1, true)
        if match then
            entries[#entries + 1] = {
                widget_type = 'enemy_entry',
                name = label,
                subtext = self:_format_list_subtext(entry),
                subtext_color = Color.terminal_text_body_sub_header(255, true),
                icon = entry.icon,
                breed_name = entry.breed_name,
                category = entry.category,
                size = entry.size,
                is_ranged = entry.is_ranged,
                faction = entry.faction,
            }
        end
    end

    self:_present_list(entries)
end

function EnemyStatsView:_format_list_subtext(entry)
    local role_label = mod:localize(entry.is_ranged and 'role_ranged' or 'role_melee')
    local category_label = mod:localize('kind_' .. entry.category)
    local faction_label = mod:localize('faction_' .. entry.faction)
    return string.format('%s | %s | %s', role_label, category_label, faction_label)
end

-- Detail panel -----------------------------------------------------------

function EnemyStatsView:_present_detail(entry)
    if not self._detail_grid then
        return
    end
    self._detail_entry = entry
    local width = self:_detail_width()
    local blueprints = make_detail_blueprints(width)

    local layout = {}
    if entry then
        local info = Data.breed_info(entry.breed_name)
        local category_icon = info and info.category_icon or nil
        layout[#layout + 1] = {
            widget_type = 'header_icon',
            text = entry.name,
            icon = category_icon,
            icon_size = { 96, 96 },
            subtext = entry.subtext,
            subtext_color = entry.subtext_color,
            color = Color.terminal_text_header(255, true),
        }
        layout[#layout + 1] = { widget_type = 'spacer', size = 'group' }

        local info = Data.breed_info(entry.breed_name)
        if info then
            layout[#layout + 1] = { widget_type = 'section', text = mod:localize('header_info') }
            layout[#layout + 1] = {
                widget_type = 'stat',
                label = mod:localize('stat_category'),
                value = mod:localize('kind_' .. info.category),
            }
            layout[#layout + 1] = {
                widget_type = 'stat',
                label = mod:localize('stat_size'),
                value = mod:localize('size_' .. info.size),
            }
            local role_key = info.is_ranged and 'role_ranged' or 'role_melee'
            layout[#layout + 1] = {
                widget_type = 'stat',
                label = mod:localize('stat_role'),
                value = mod:localize(role_key),
            }
            layout[#layout + 1] = {
                widget_type = 'stat',
                label = mod:localize('stat_faction'),
                value = mod:localize('faction_' .. info.faction),
            }
            if info.armor_type then
                layout[#layout + 1] = {
                    widget_type = 'stat',
                    label = mod:localize('stat_armor'),
                    value = mod:localize('armor_' .. info.armor_type),
                    value_color = SharedUtils.armor_color(info.armor_type),
                }
            end
            if info.challenge_rating then
                layout[#layout + 1] = {
                    widget_type = 'stat',
                    label = mod:localize('stat_challenge'),
                    value = string.format('%.2f', info.challenge_rating),
                }
            end
            if info.stagger_resistance then
                layout[#layout + 1] = {
                    widget_type = 'stat',
                    label = mod:localize('stat_stagger_resist'),
                    value = string.format('%.2f', info.stagger_resistance),
                }
            end
            if info.stagger_reduction then
                layout[#layout + 1] = {
                    widget_type = 'stat',
                    label = mod:localize('stat_stagger_reduction'),
                    value = string.format('%.2f', info.stagger_reduction),
                }
            end
            if info.run_speed then
                layout[#layout + 1] = {
                    widget_type = 'stat',
                    label = mod:localize('stat_run_speed'),
                    value = string.format('%.1f', info.run_speed),
                }
            end
            if info.walk_speed then
                layout[#layout + 1] = {
                    widget_type = 'stat',
                    label = mod:localize('stat_walk_speed'),
                    value = string.format('%.1f', info.walk_speed),
                }
            end
            if info.detection_radius then
                layout[#layout + 1] = {
                    widget_type = 'stat',
                    label = mod:localize('stat_detection_radius'),
                    value = string.format('%.0f', info.detection_radius),
                }
            end
            layout[#layout + 1] = { widget_type = 'spacer', size = 'group' }
        end

        local zones = Data.hit_zones(entry.breed_name)
        if zones and #zones > 0 then
            -- Body diagram for humanoid breeds (has torso + limbs).
            local zone_set = {}
            for i = 1, #zones do
                zone_set[zones[i].zone] = true
            end
            local is_humanoid = zone_set.torso and zone_set.upper_left_arm and zone_set.upper_left_leg

            layout[#layout + 1] = {
                widget_type = 'section',
                text = mod:localize('header_hit_zones'),
            }
            layout[#layout + 1] = {
                widget_type = 'table',
                name_column_label = mod:localize('stat_zone'),
                columns = {
                    { label = mod:localize('stat_armor') },
                    { label = mod:localize('stat_weakspots') },
                },
                rows = zones,
                diagram = is_humanoid,
            }
            layout[#layout + 1] = { widget_type = 'spacer', size = 'tight' }
        end

        local diff_rows = Data.difficulty_table(entry.breed_name)
        if diff_rows and #diff_rows > 0 then
            layout[#layout + 1] = {
                widget_type = 'section',
                text = mod:localize('header_health'),
            }
            layout[#layout + 1] = {
                widget_type = 'table',
                name_column_label = mod:localize('stat_difficulty'),
                columns = {
                    { label = mod:localize('stat_health') },
                    { label = mod:localize('stat_hit_mass') },
                },
                rows = diff_rows,
            }
            layout[#layout + 1] = { widget_type = 'spacer', size = 'tight' }
        end

        local stagger_rows = Data.stagger_table(entry.breed_name)
        if stagger_rows and #stagger_rows > 0 then
            layout[#layout + 1] = {
                widget_type = 'section',
                text = mod:localize('header_stagger'),
            }
            layout[#layout + 1] = {
                widget_type = 'table',
                name_column_label = mod:localize('stat_stagger_type'),
                columns = {
                    { label = mod:localize('stat_stagger_duration') },
                },
                rows = stagger_rows,
            }
            layout[#layout + 1] = { widget_type = 'spacer', size = 'group' }
        end

        local melee_rows, ranged_rows = Data.attack_tables(entry.breed_name)
        if melee_rows then
            layout[#layout + 1] = {
                widget_type = 'section',
                text = mod:localize('header_melee_attacks'),
            }
            layout[#layout + 1] = {
                widget_type = 'table',
                name_column_label = mod:localize('stat_action'),
                columns = Data.melee_attack_columns(),
                rows = melee_rows,
            }
            layout[#layout + 1] = { widget_type = 'spacer', size = 'tight' }
        end
        if ranged_rows then
            layout[#layout + 1] = {
                widget_type = 'section',
                text = mod:localize('header_ranged_attacks'),
            }
            layout[#layout + 1] = {
                widget_type = 'table',
                name_column_label = mod:localize('stat_action'),
                columns = Data.ranged_attack_columns(),
                rows = ranged_rows,
            }
            layout[#layout + 1] = { widget_type = 'spacer', size = 'group' }
        end
    end

    local left_click_callback = callback(self, 'cb_on_detail_entry_left_pressed')
    self._detail_layout = layout
    self:_present_detail_grid(layout, blueprints, left_click_callback)
end

return EnemyStatsView
