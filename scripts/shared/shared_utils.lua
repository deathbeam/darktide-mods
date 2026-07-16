local ArmorSettings = require('scripts/settings/damage/armor_settings')

local SharedUtils = {}

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

local function _cell_text(cell)
    if type(cell) == 'table' then
        return cell.text or ''
    end
    return tostring(cell or '')
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
        if wt == 'header' or wt == 'header_icon' then
            lines[#lines + 1] = '## ' .. (e.text or '')
        elseif wt == 'subtext' then
            lines[#lines + 1] = (e.text or '')
        elseif wt == 'section' then
            lines[#lines + 1] = ''
            lines[#lines + 1] = '### ' .. (e.text or '')
        elseif wt == 'stat' or wt == 'substat' then
            local label = e.label or ''
            local value = e.value or ''
            lines[#lines + 1] = string.format('- **%s**: %s', label, value)
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
            lines[#lines + 1] = string.format('- **%s**: %s', label, value)
        end
    end
    return table.concat(lines, '\n')
end

-- Returns the terminal-style {255, r, g, b} color for an armor type, keyed by
-- either the string name (e.g. "unarmored") or the ArmorSettings.types value.
function SharedUtils.armor_color(armor_key)
    if armor_key == nil then
        return nil
    end
    local name = armor_key
    if type(armor_key) == 'number' then
        for k, v in pairs(ArmorSettings.types) do
            if v == armor_key then
                name = k
                break
            end
        end
    end
    local colors = {
        unarmored = { 90, 195, 90 },
        armored = { 215, 150, 50 },
        super_armor = { 150, 155, 175 },
        berserker = { 210, 70, 70 },
        resistant = { 160, 95, 195 },
        disgustingly_resilient = { 150, 185, 70 },
        player = { 90, 195, 90 },
        void_shield = { 80, 165, 240 },
    }
    local rgb = colors[name]
    if not rgb then
        return nil
    end
    return { 255, rgb[1], rgb[2], rgb[3] }
end

return SharedUtils
