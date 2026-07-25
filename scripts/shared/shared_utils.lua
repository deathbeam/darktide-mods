local Breeds = require('scripts/settings/breed/breeds')

local SharedUtils = {}

-- View names registered via register_stats_view. Lives on _G because each mod loads
-- its own copy of this file (via io_dofile), so a SharedUtils field would be per-mod
-- and never see the sibling mods' views. Opening one stats view closes the others.
local stats_view_names = rawget(_G, 'dmf_stats_view_names') or {}
_G.dmf_stats_view_names = stats_view_names
SharedUtils.stats_view_names = stats_view_names

-- Per-view setting_ids (set by register_stats_view). shared_view_base reads this to
-- auto-build the in-view settings list; on_setting_changed refreshes the detail panel.
local stats_view_setting_ids = rawget(_G, 'dmf_stats_view_setting_ids') or {}
_G.dmf_stats_view_setting_ids = stats_view_setting_ids
SharedUtils.stats_view_setting_ids = stats_view_setting_ids

-- Terminal-style {255, r, g, b} color per armor type name. Singletons: callers
-- store the reference but never mutate it.
local ARMOR_COLORS = {
    unarmored = { 255, 90, 195, 90 },
    armored = { 255, 215, 150, 50 },
    super_armor = { 255, 150, 155, 175 },
    berserker = { 255, 210, 70, 70 },
    resistant = { 255, 160, 95, 195 },
    disgustingly_resilient = { 255, 150, 185, 70 },
    player = { 255, 90, 195, 90 },
    void_shield = { 255, 80, 165, 240 },
}

-- Fallback for armor types without a known color mapping.
local ARMOR_COLOR_FALLBACK = { 255, 200, 200, 200 }

-- Flat difficulty-skull icons per enemy category, escalating with threat.
-- Shared across EnemyStats (regular/specialist/elite/boss) and CombatStats
-- (horde/special/disabler/elite/monster). Mods map their category names to
-- these via their own lookup; this is just the icon set.
local CATEGORY_ICONS = {
    horde = 'content/ui/materials/icons/difficulty/flat/difficulty_skull_uprising',
    unknown = 'content/ui/materials/icons/difficulty/flat/difficulty_skull_uprising',
    ritualist = 'content/ui/materials/icons/difficulty/flat/difficulty_skull_malice',
    specialist = 'content/ui/materials/icons/difficulty/flat/difficulty_skull_malice',
    elite = 'content/ui/materials/icons/difficulty/flat/difficulty_skull_heresy',
    captain = 'content/ui/materials/icons/difficulty/flat/difficulty_skull_damnation',
    monstrosity = 'content/ui/materials/icons/difficulty/flat/difficulty_skull_damnation',
    boss = 'content/ui/materials/icons/difficulty/flat/difficulty_skull_damnation',
}

function SharedUtils.category_icon(category)
    return CATEGORY_ICONS[category]
end

-- Canonical breed classification shared across the stats mods. Returns one of:
-- monstrosity, captain, disabler, specialist, elite, horde, roamer, ritualist, unknown.
-- Order matters — most specific first. All disabler-tagged breeds also carry special,
-- and all is_boss breeds carry either monster or captain/cultist_captain.
function SharedUtils.classify_breed(breed)
    if not breed then
        return 'unknown'
    end

    local tags = breed.tags
    if tags then
        if tags.monster then
            return 'monstrosity'
        elseif tags.captain or tags.cultist_captain then
            return 'captain'
        elseif tags.disabler then
            return 'disabler'
        elseif tags.special then
            return 'specialist'
        elseif tags.elite then
            return 'elite'
        elseif tags.ritualist then
            return 'ritualist'
        elseif tags.horde then
            return 'horde'
        elseif tags.roamer then
            return 'roamer'
        end
    end

    if breed.is_boss then
        return 'monstrosity'
    end

    return 'unknown'
end

-- Localize a game loc key, returning nil on miss or when the game has no entry.
function SharedUtils.safe_localize(text)
    if not text or text == '' or text == 'n/a' then
        return nil
    end

    local success, localized = pcall(Localize, text)
    if not success then
        return nil
    end

    if
        localized
        and type(localized) == 'string'
        and localized ~= text
        and not localized:find('^loc_')
        and not localized:lower():find('unlocalized')
    then
        return localized
    end

    return nil
end

-- Number: integer when whole (within 0.05), else one decimal. '-' for nil.
function SharedUtils.fmt_num(n)
    if n == nil then
        return '-'
    end
    if math.abs(n - math.floor(n)) < 0.05 then
        return string.format('%d', math.floor(n + 0.5))
    end
    if math.abs(n) >= 100 then
        return string.format('%.0f', n)
    end
    return string.format('%.1f', n)
end

-- Percentage: 0 or 1 decimal (whole% drops the decimal). '-' for nil. Takes a fraction (0.2 -> 20%).
function SharedUtils.fmt_pct(n)
    if n == nil then
        return '-'
    end
    local pct = n * 100
    local fmt = math.abs(pct - math.floor(pct)) < 0.05 and '%.0f%%' or '%.1f%%'
    return string.format(fmt, pct)
end

-- Multiplier: xN.NN. '-' for nil.
function SharedUtils.fmt_mult(n)
    if n == nil then
        return '-'
    end
    return string.format('x%.2f', n)
end

-- Convert a snake_case key to Title Case (e.g. "base_damage" -> "Base Damage").
function SharedUtils.prettify(key)
    if type(key) ~= 'string' then
        return tostring(key)
    end
    local prettified = key:gsub('_', ' ')
    prettified = prettified:gsub('(%a)(%a+)', function(first, rest)
        return first:upper() .. rest
    end)
    return prettified
end

-- Localize `prefix .. key`, falling back to prettify(key) when the loc entry is
-- missing (DMF returns "<...>"). Returns nil when key itself is nil.
function SharedUtils.localize_or_prettify(mod, prefix, key)
    if key == nil then
        return nil
    end
    local loc_id = prefix .. tostring(key)
    local localized = mod:localize(loc_id)
    if localized and not localized:find('^<') then
        return localized
    end
    return SharedUtils.prettify(key)
end

-- Localized breed display name: resolves `breed.display_name` via the game's
-- Localize, falling back to prettify(breed_name) when the breed or its loc key
-- is missing. Returns nil only when breed_name itself is nil.
function SharedUtils.breed_display_name(breed_name)
    if not breed_name then
        return nil
    end
    local breed = Breeds[breed_name]
    return (breed and SharedUtils.safe_localize(breed.display_name)) or SharedUtils.prettify(breed_name)
end

-- Register global localization strings (e.g. for ESC menu buttons) and patch
-- mod:localize to resolve game_loc keys via the game's Localize first, falling
-- back to the mod's own table. `loc_settings` is the table returned by a mod's
-- *_localization.lua (with optional `global_loc` and `game_loc` fields).
function SharedUtils.apply_loc_settings(mod, loc_settings)
    if not loc_settings then
        return
    end
    if loc_settings.global_loc then
        mod:add_global_localize_strings(loc_settings.global_loc)
    end
    local game_loc = loc_settings.game_loc
    if game_loc then
        local _orig_localize = mod.localize

        function mod:localize(text_id, ...)
            local loc_id = game_loc[text_id]
            if loc_id then
                local s = SharedUtils.safe_localize(loc_id)
                if s then
                    return s
                end
            end
            return _orig_localize(self, text_id, ...)
        end
    end
end

-- Load a list of UI packages, returning the ones actually loaded so they can be released later.
function SharedUtils.load_icon_packages(mod, packages)
    if not packages then
        return {}
    end
    local application = Application and Application.can_get_resource
    local loaded = {}
    for _, pkg in ipairs(packages) do
        local available = false
        if application then
            local ok, exists = pcall(application, 'package', pkg)
            available = ok and exists or false
        end
        if available and mod:package_status(pkg) ~= 'loaded' then
            mod:load_package(pkg, nil, true)
            loaded[#loaded + 1] = pkg
        end
    end
    return loaded
end

-- Release packages previously loaded by load_icon_packages.
function SharedUtils.release_icon_packages(mod, loaded)
    if not loaded then
        return
    end
    for i = 1, #loaded do
        if mod:package_status(loaded[i]) == 'loaded' then
            mod:unload_package(loaded[i])
        end
    end
end

-- Copy text to the system clipboard, returning true on success.
function SharedUtils.copy_to_clipboard(text)
    if not text or text == '' then
        return false
    end
    local ok = pcall(Clipboard.put, text)
    return ok or false
end

-- Strips game rich-text tags ({#color(...)}, {#reset()}, {#size(...)}, etc.) so
-- copied text is plain and readable.
local function _strip_rich_text(text)
    if not text then
        return ''
    end
    return (tostring(text):gsub('{#%w+%b()}', ''))
end

local function _cell_text(cell)
    if type(cell) == 'table' then
        return _strip_rich_text(cell.text)
    end
    return _strip_rich_text(tostring(cell or ''))
end

local function _table_to_md(columns, rows, name_column_label)
    local parts = {}
    local header = { name_column_label or '' }
    for c = 1, #columns do
        header[#header + 1] = columns[c] and columns[c].label or ''
    end
    parts[#parts + 1] = '| ' .. table.concat(header, ' | ') .. ' |'
    parts[#parts + 1] = '|' .. string.rep(' --- |', #columns + 1)
    for r = 1, #rows do
        local row = rows[r]
        local cells = row.cells or {}
        local line = { row.name or '' }
        for c = 1, #cells do
            line[#line + 1] = _cell_text(cells[c])
        end
        parts[#parts + 1] = '| ' .. table.concat(line, ' | ') .. ' |'
    end
    return table.concat(parts, '\n')
end

-- Serialize a detail layout (list of widget_type entries shared by the stats
-- mods) to markdown text suitable for clipboard copy.
function SharedUtils.layout_to_markdown(title, layout)
    if not layout or #layout == 0 then
        return title or ''
    end
    local lines = {}
    if title and title ~= '' then
        lines[#lines + 1] = '# ' .. title
        lines[#lines + 1] = ''
    end
    for i = 1, #layout do
        local e = layout[i]
        local wt = e and e.widget_type
        if wt == 'header_icon' then
            lines[#lines + 1] = '## ' .. _strip_rich_text(e.text or '')
            if e.subtext and e.subtext ~= '' then
                lines[#lines + 1] = '*' .. _strip_rich_text(e.subtext) .. '*'
            end
        elseif wt == 'section' then
            local depth = e.level == 2 and 4 or (e.level == 3 and 5 or 3)
            lines[#lines + 1] = ''
            lines[#lines + 1] = string.rep('#', depth) .. ' ' .. (e.text or '')
            if e.subtext and e.subtext ~= '' then
                lines[#lines + 1] = '*' .. _strip_rich_text(e.subtext) .. '*'
            end
        elseif wt == 'stat' or wt == 'substat' then
            local label = e.label or ''
            local value = e.value or ''
            local indent = string.rep('  ', e.indent or 0)
            lines[#lines + 1] =
                string.format('%s- **%s**: %s', indent, _strip_rich_text(label), _strip_rich_text(value))
        elseif wt == 'text' then
            lines[#lines + 1] = (e.text or '')
        elseif wt == 'table' then
            if e.columns and e.rows then
                lines[#lines + 1] = ''
                lines[#lines + 1] = _table_to_md(e.columns, e.rows, e.name_column_label)
                lines[#lines + 1] = ''
            end
        elseif wt == 'chain' then
            if e.title then
                lines[#lines + 1] = ''
                lines[#lines + 1] = '### ' .. e.title
            end
            if e.chain then
                for c = 1, #e.chain do
                    local step = e.chain[c]
                    if step then
                        lines[#lines + 1] = string.format('- %s', tostring(step))
                    end
                end
            end
        elseif wt == 'progress_bar' then
            local label = e.label or ''
            local value = e.value or ''
            lines[#lines + 1] = string.format('- **%s**: %s', _strip_rich_text(label), _strip_rich_text(value))
        end
    end
    return table.concat(lines, '\n')
end

function SharedUtils.armor_color(armor_key)
    return ARMOR_COLORS[armor_key] or ARMOR_COLOR_FALLBACK
end

function SharedUtils.register_stats_view(mod, config)
    local view_name = config.view_name
    local class_name = config.class_name
    local path = config.path
    local button_text_loc = config.button_text_loc
    local setting_ids = config.setting_ids

    stats_view_names[#stats_view_names + 1] = view_name
    mod:add_require_path(path)
    mod:register_view({
        view_name = view_name,
        view_settings = {
            init_view_function = function()
                return true
            end,
            class = class_name,
            disable_game_world = false,
            game_world_blur = 0,
            load_always = true,
            load_in_hub = true,
            path = path,
            package = 'packages/ui/views/options_view/options_view',
            state_bound = false,
            enter_sound_events = {
                'wwise/events/ui/play_ui_enter_short',
            },
            exit_sound_events = {
                'wwise/events/ui/play_ui_back_short',
            },
            wwise_states = {
                options = 'ingame_menu',
            },
        },
        view_transitions = {},
        view_options = {
            close_all = false,
            close_previous = false,
            close_transition_time = nil,
            transition_time = nil,
        },
    })

    if setting_ids and #setting_ids > 0 then
        stats_view_setting_ids[view_name] = setting_ids

        local refresh_ids = {}
        for i = 1, #setting_ids do
            refresh_ids[setting_ids[i]] = true
        end

        -- Preserve the mod's own on_setting_changed (if any).
        local previous = mod.on_setting_changed
        mod.on_setting_changed = function(id)
            if previous then
                previous(id)
            end
            if not refresh_ids[id] then
                return
            end
            local ui_manager = Managers.ui
            if not ui_manager or not ui_manager:view_active(view_name) then
                return
            end
            local view = ui_manager:view_instance(view_name)
            if view and view._present_detail then
                view:_present_detail(view._detail_entry)
            end
        end
    end

    local menu_button = {
        text = button_text_loc,
        type = 'button',
        icon = 'content/ui/materials/icons/system/escape/settings',
        trigger_function = function()
            Managers.ui:open_view(view_name)
        end,
    }

    mod:hook(CLASS.SystemView, '_setup_content_widgets', function(func, self, content, ...)
        local patched = content
        if content then
            patched = {}
            for state_key, list in pairs(content) do
                local cloned = table.clone(list)
                local insert_at = #cloned + 1
                for i = 1, #cloned do
                    if cloned[i].type == 'spacing_vertical' then
                        insert_at = i
                        break
                    end
                end
                if mod:get('add_to_esc_menu') then
                    table.insert(cloned, insert_at, menu_button)
                end
                patched[state_key] = cloned
            end
        end
        return func(self, patched, ...)
    end)
end

return SharedUtils
