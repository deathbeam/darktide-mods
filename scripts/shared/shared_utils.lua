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

-- Patch mod:localize to resolve entries from `game_loc` via the game's Localize first,
-- falling back to the mod's own localization table. `game_loc` maps mod loc keys to
-- game loc keys (e.g. { stat_damage = 'loc_weapon_stats_display_base_damage' }).
function SharedUtils.apply_game_loc(mod, game_loc)
    local _orig_localize = mod.localize

    function mod:localize(text_id, ...)
        local loc_id = game_loc and game_loc[text_id]
        if loc_id then
            local s = SharedUtils.safe_localize(loc_id)
            if s then
                return s
            end
        end
        return _orig_localize(self, text_id, ...)
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

return SharedUtils
