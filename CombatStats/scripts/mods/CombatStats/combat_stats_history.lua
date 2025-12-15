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

function CombatStatsHistory:create_history_entry_path(mission_name, class_name)
    local timestamp = tostring(_os.time(_os.date('*t')))
    local file_name = timestamp .. '_' .. class_name .. '_' .. mission_name .. '.json'
    return self:appdata_path() .. file_name, file_name
end

function CombatStatsHistory:parse_filename(file_name)
    -- Parse format: timestamp_class_missionname.json
    -- Mission name can contain underscores, so we need to be careful
    local name_without_ext = file_name:match('(.+)%.json$')
    if not name_without_ext then
        return nil
    end

    -- Extract timestamp (first segment)
    local timestamp_str = name_without_ext:match('^(%d+)_')
    if not timestamp_str then
        return nil
    end

    -- Extract class (second segment after first underscore)
    local after_timestamp = name_without_ext:match('^%d+_(.+)$')
    if not after_timestamp then
        return nil
    end

    local class_name, mission_name = after_timestamp:match('^([^_]+)_(.+)$')
    if not class_name or not mission_name then
        return nil
    end

    local timestamp = tonumber(timestamp_str)
    local date_str = timestamp and _os.date('%Y-%m-%d %H:%M:%S', timestamp)
    if not timestamp or not date_str then
        return nil
    end

    return {
        timestamp = timestamp,
        date = date_str,
        mission_name = mission_name,
        class_name = class_name,
    }
end

function CombatStatsHistory:save_history_entry(tracker_data, mission_name, class_name)
    self:create_history_directory()

    local path, file_name = self:create_history_entry_path(mission_name, class_name)

    local data = {
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

    local file_name = path:match('([^/\\]+)$')
    local file_info = self:parse_filename(file_name)

    if file_info then
        data.file = file_name
        data.file_path = path
        data.date = file_info.date
        data.timestamp = file_info.timestamp
        data.mission_name = file_info.mission_name
        data.class_name = file_info.class_name
    end

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
        if file:match('%.json$') then
            local file_info = self:parse_filename(file)
            if file_info then
                -- Add basic info from filename without loading file
                file_info.file = file
                file_info.file_path = appdata .. file
                entries[#entries + 1] = file_info
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
