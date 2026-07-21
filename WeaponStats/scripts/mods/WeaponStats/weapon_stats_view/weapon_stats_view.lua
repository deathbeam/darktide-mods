local mod = get_mod('WeaponStats')

local WeaponTemplates = mod:original_require('scripts/settings/equipment/weapon_templates/weapon_templates')
local WeaponTemplate = mod:original_require('scripts/utilities/weapon/weapon_template')

local Builder = mod:io_dofile('WeaponStats/scripts/mods/WeaponStats/weapon_stats_builder')
local SharedUtils = mod:io_dofile('WeaponStats/scripts/mods/WeaponStats/shared/shared_utils')
local Utils = mod:io_dofile('WeaponStats/scripts/mods/WeaponStats/weapon_stats_utils')
local make_view = mod:io_dofile('WeaponStats/scripts/mods/WeaponStats/shared/shared_view_base')
local make_detail_blueprints =
    mod:io_dofile('WeaponStats/scripts/mods/WeaponStats/weapon_stats_view/weapon_stats_detail_blueprints')

local MAX_STAT_VALUE = 0.8

local ICON_PACKAGES = {
    'packages/ui/hud/player_weapon/player_weapon',
    'packages/ui/views/masteries_overview_view/masteries_overview_view',
}

local WeaponStatsView = make_view(mod, {
    class_name = 'WeaponStatsView',
    prefix = 'weapon_stats',
    shared_utils = SharedUtils,
    icon_packages = ICON_PACKAGES,
    definitions_path = 'WeaponStats/scripts/mods/WeaponStats/weapon_stats_view/weapon_stats_view_definitions',
    list_blueprints_path = 'WeaponStats/scripts/mods/WeaponStats/weapon_stats_view/weapon_stats_view_blueprints',
})

-- Cached on the class so re-opening the view is instant.
function WeaponStatsView:_build_weapon_list()
    if WeaponStatsView._weapon_list then
        return WeaponStatsView._weapon_list
    end

    local list = {}
    for name, weapon_template in pairs(WeaponTemplates) do
        if weapon_template.base_stats ~= nil then
            local is_ranged = WeaponTemplate.is_ranged(weapon_template)
            local display_name, sub_name = Utils.weapon_display_name(name)
            list[#list + 1] = {
                name = display_name or Utils.friendly_action_label(name),
                sub_display_name = sub_name,
                weapon_template = weapon_template,
                is_ranged = is_ranged,
                icon = Utils.weapon_hud_icon(name, is_ranged),
            }
        end
    end

    table.sort(list, function(a, b)
        if a.is_ranged ~= b.is_ranged then
            return not a.is_ranged -- melee first
        end
        return a.name:lower() < b.name:lower()
    end)

    WeaponStatsView._weapon_list = list
    return list
end

-- Placeholder item with every stat trait maxed (0.8), in the shape build_stats expects.
function WeaponStatsView._placeholder_item(weapon_template)
    local template_name = weapon_template.name
    local stats = {}
    for stat_name, stat_definition in pairs(weapon_template.base_stats or {}) do
        if stat_definition.is_stat_trait == true then
            stats[#stats + 1] = {
                name = stat_name,
                value = MAX_STAT_VALUE,
            }
        end
    end
    return {
        weapon_template = template_name,
        base_stats = stats,
        perks = {},
        traits = {},
        overclocks = {},
    }
end

function WeaponStatsView:_on_init(settings, context)
    self._weapon_list = self:_build_weapon_list()
    self._initial_weapon_template = context and context.weapon_template_name or nil
end

-- Matches the in-game card: title = family, subtext = kind + pattern • mark.
function WeaponStatsView:_format_entry_subtext(entry)
    local kind = entry.is_ranged and mod:localize('kind_ranged') or mod:localize('kind_melee')
    if entry.sub_display_name and entry.sub_display_name ~= '' then
        return kind .. ' • ' .. entry.sub_display_name, Color.terminal_text_body_sub_header(255, true)
    end
    return kind, Color.terminal_text_body_sub_header(255, true)
end

-- Weapon list ------------------------------------------------------------

function WeaponStatsView:_setup_entries()
    local search_widget = self._widgets_by_name.weapon_stats_search
    local search_text = search_widget and search_widget.content.input_text or ''
    search_text = search_text:lower()

    local entries = {}
    for i = 1, #self._weapon_list do
        local weapon = self._weapon_list[i]
        local name = weapon.name
        local sub_name = weapon.sub_display_name or ''
        local match = search_text == ''
            or name:lower():find(search_text, 1, true)
            or sub_name:lower():find(search_text, 1, true)
            or weapon.name:lower():find(search_text, 1, true)
        if match then
            local entry = {
                widget_type = 'weapon_entry',
                name = weapon.name,
                sub_display_name = weapon.sub_display_name,
                weapon = weapon,
                is_ranged = weapon.is_ranged,
                icon = weapon.icon,
            }
            entry.subtext, entry.subtext_color = self:_format_entry_subtext(entry)
            entries[#entries + 1] = entry
        end
    end

    self:_present_list(entries)
end
function WeaponStatsView:_cb_on_list_presented()
    local entries = self._filtered_list
    if not entries or #entries == 0 then
        self:_present_detail(nil)
        return
    end

    local initial_template = self._initial_weapon_template
    local match_index = nil
    if initial_template then
        for i = 1, #entries do
            if entries[i].weapon.weapon_template.name == initial_template then
                match_index = i
                break
            end
        end
    end
    match_index = match_index or 1
    self._list_grid:select_grid_index(match_index)
    self._list_grid:scroll_to_grid_index(match_index)
    self:_select_entry(entries[match_index])
    self._initial_weapon_template = nil
end

-- Detail panel -----------------------------------------------------------

function WeaponStatsView:_present_detail(entry)
    if not self._detail_grid then
        return
    end

    self._detail_entry = entry
    local width = self:_detail_width()
    local blueprints = make_detail_blueprints(width)

    local layout = {}
    if entry then
        layout[#layout + 1] = {
            widget_type = 'header_icon',
            text = entry.name,
            color = Color.terminal_text_header(255, true),
            icon = entry.icon,
            subtext = entry.subtext,
            subtext_color = entry.subtext_color,
        }
        layout[#layout + 1] = { widget_type = 'spacer', size = 'group' }

        local weapon = entry.weapon
        local item = WeaponStatsView._placeholder_item(weapon.weapon_template)
        local records = Builder.build_stats(item)

        local stripe_count = 0
        for i = 1, #records do
            local record = records[i]
            local rtype = record.type
            if rtype == 'stat' then
                layout[#layout + 1] = {
                    widget_type = 'stat',
                    label = record.label,
                    value = record.value,
                    label_color = record.label_color,
                    value_color = record.value_color,
                    indent = record.indent or 0,
                    wrap = record.wrap,
                    icon = record.icon,
                    icon_frame = record.icon_frame,
                    stripe = stripe_count % 2 == 1,
                }
                stripe_count = stripe_count + 1
            elseif rtype == 'table' then
                layout[#layout + 1] = { widget_type = 'spacer', size = 'tight' }
                layout[#layout + 1] = {
                    widget_type = 'table',
                    columns = record.columns,
                    rows = record.rows,
                }
                stripe_count = 0
            elseif rtype == 'chain' then
                layout[#layout + 1] = {
                    widget_type = 'chain',
                    title = record.title,
                    chain = record.chain,
                }
                stripe_count = 0
            else
                layout[#layout + 1] = {
                    widget_type = rtype,
                    text = record.text,
                    color = record.color,
                    size = record.size,
                    indent = record.indent,
                    level = record.level,
                }
            end
        end
    end

    local left_click_callback = callback(self, 'cb_on_detail_entry_left_pressed')
    self._detail_layout = layout
    self._detail_grid:present_grid_layout(layout, blueprints, left_click_callback)
end

return WeaponStatsView
