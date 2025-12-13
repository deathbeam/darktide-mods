local mod = get_mod('CombatStats')
local DMF = get_mod('DMF')

local _io = DMF:persistent_table('_io')
_io.initialized = _io.initialized or false
if not _io.initialized then
    _io = DMF.deepcopy(Mods.lua.io)
end

local _os = DMF:persistent_table('_os')
_os.initialized = _os.initialized or false
if not _os.initialized then
    _os = DMF.deepcopy(Mods.lua.os)
end

local cjson = cjson

local CombatStatsHistory = class('CombatStatsHistory')

function CombatStatsHistory:init() end

local function exists(file)
    local ok, err, code = _os.rename(file, file)
    if not ok then
        if code == 13 then
            return true
        end
    end
    return ok, err
end

local function isdir(path)
    return exists(path .. '/')
end

local function file_exists(name)
    local f = _io.open(name, 'r')
    if f ~= nil then
        _io.close(f)
        return true
    else
        return false
    end
end

function CombatStatsHistory:appdata_path()
    local appdata = _os.getenv('APPDATA')
    return appdata .. '/Fatshark/Darktide/combat_stats_history/'
end

function CombatStatsHistory:create_history_directory()
    local path = self:appdata_path()
    if not isdir(path) then
        _os.execute('mkdir "' .. path .. '"')
    end
end

function CombatStatsHistory:create_history_entry_path()
    local file_name = tostring(_os.time(_os.date('*t'))) .. '.json'
    return self:appdata_path() .. file_name, file_name
end

function CombatStatsHistory:save_history_entry(tracker_data, mission_info)
    self:create_history_directory()

    local path, file_name = self:create_history_entry_path()

    local data = {
        mission = mission_info,
        duration = tracker_data.duration or 0,
        stats = tracker_data.stats,
        buffs = tracker_data.buffs,
        engagements = tracker_data.engagements,
    }

    local json_str = cjson.encode(data)
    local file = assert(_io.open(path, 'w'))
    file:write(json_str)
    file:close()

    local cache = mod:get('history_entries') or {}
    cache[#cache + 1] = file_name
    mod:set('history_entries', cache)

    return file_name
end

function CombatStatsHistory:load_history_entry(path)
    local file = _io.open(path, 'r')
    if not file then
        return nil
    end

    local json_str = file:read('*all')
    file:close()

    local data = cjson.decode(json_str)

    local file_name = path:match('([^/\\]+)%.json$')
    local date_str = file_name and tonumber(file_name)
    data.file = file_name
    data.file_path = path
    data.date = _os.date('%Y-%m-%d %H:%M:%S', tonumber(date_str))
    data.timestamp = tonumber(date_str)
    return data
end

function CombatStatsHistory:get_history_entries(scan_dir)
    local function scandir(directory)
        local i, t, popen = 0, {}, _io.popen
        local pfile = popen('dir "' .. directory .. '" /b')
        for filename in pfile:lines() do
            i = i + 1
            t[i] = filename
        end
        pfile:close()
        return t
    end

    local appdata = self:appdata_path()
    local cache = mod:get('history_entries') or {}
    local files = cache

    if scan_dir or not cache or #cache == 0 then
        files = scandir(appdata)
        mod:set('history_entries', files)
    end

    local entries = {}
    for _, file in pairs(files) do
        local file_path = appdata .. file
        if file_exists(file_path) and file:match('%.json$') then
            local entry = self:load_history_entry(file_path)
            if entry then
                entries[#entries + 1] = entry
            end
        end
    end

    table.sort(entries, function(a, b)
        return a.timestamp > b.timestamp
    end)

    return entries
end

function CombatStatsHistory:delete_history_entry(file_name)
    local file_path = self:appdata_path() .. file_name
    if file_exists(file_path) then
        if _os.remove(file_path) then
            local cache = mod:get('history_entries') or {}
            local new_cache = {}
            for _, c in pairs(cache) do
                if c ~= file_name then
                    new_cache[#new_cache + 1] = c
                end
            end
            mod:set('history_entries', new_cache)
            return true
        end
    end
    return false
end

return CombatStatsHistory
