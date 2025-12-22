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

--- Check if file or directory exists
---@param file string
---@return boolean
local function exists(file)
    local ok, _, code = _os.rename(file, file)
    if not ok then
        if code == 13 then
            return true
        end
    end
    return ok
end

--- Check if path is a directory
---@param path string
---@return boolean
local function isdir(path)
    return exists(path .. '/')
end

--- Scan directory and return list of filenames
---@param directory string
---@return string[]
local function scandir(directory)
    local i, file_names, popen = 0, {}, _io.popen
    local pfile = popen('dir "' .. directory .. '" /b')
    for filename in pfile:lines() do
        i = i + 1
        file_names[i] = filename
    end
    pfile:close()
    return file_names
end

--- Create directory if it does not exist
---@param path string
local function mkdir(path)
    if not isdir(path) then
        _os.execute('mkdir "' .. path .. '"')
    end
end

--- Recursively filter a table to remove nil, 0, and empty string values
---@param tbl table
---@return table
local function filter_table(tbl)
    local result = {}
    for k, v in pairs(tbl) do
        if type(v) == 'table' then
            local filtered = filter_table(v)
            if next(filtered) ~= nil then
                result[k] = filtered
            end
        elseif v ~= nil and v ~= 0 and v ~= '' then
            result[k] = v
        end
    end
    return result
end

local CombatStatsHistory = class('CombatStatsHistory')

function CombatStatsHistory:init()
    self._history_entries_cache = nil
end

function CombatStatsHistory:get_path()
    return string.format('%s/Fatshark/Darktide/combat_stats_history/', _os.getenv('APPDATA'))
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
        file = file_name,
        timestamp = timestamp,
        date = date_str,
        mission_name = mission_name,
        class_name = class_name,
    }
end

function CombatStatsHistory:save_history_entry(tracker_data, mission_name, class_name)
    mkdir(self:get_path())

    local timestamp = tostring(_os.time(_os.date('*t')))
    local file_name = string.format('%s_%s_%s.json', timestamp, class_name, mission_name)
    local path = self:get_path() .. file_name

    local data = {
        duration = tracker_data.duration,
        buffs = tracker_data.buffs,
        engagements = tracker_data.engagements,
    }

    local ok, json_str = pcall(cjson.encode, filter_table(data))
    if not ok then
        mod:echo('Failed to encode history entry: ' .. tostring(json_str))
        return nil
    end

    local file, err = _io.open(path, 'w')
    if not file then
        mod:echo('Failed to open file for writing: ' .. tostring(err))
        return nil
    end
    file:write(json_str)
    file:close()

    -- Only add to cache if it was actually fully loaded before
    if self._history_entries_cache ~= nil then
        self._history_entries_cache[#self._history_entries_cache + 1] = file_name
    end

    return file_name
end

function CombatStatsHistory:load_history_entry(file_name)
    local path = self:get_path() .. file_name
    local file, err = _io.open(path, 'r')
    if not file then
        mod:echo('Failed to open file for reading: ' .. tostring(err))
        return nil
    end

    local json_str = file:read('*all')
    file:close()

    local ok, data = pcall(cjson.decode, json_str)
    if not ok then
        mod:echo('Failed to decode history entry: ' .. tostring(data))
        return nil
    end

    local file_info = self:parse_filename(file_name)
    if file_info then
        data.file = file_name
        data.date = file_info.date
        data.timestamp = file_info.timestamp
        data.mission_name = file_info.mission_name
        data.class_name = file_info.class_name
    end

    return data
end

function CombatStatsHistory:get_history_entries(scan_dir)
    if scan_dir or self._history_entries_cache == nil then
        self._history_entries_cache = scandir(self:get_path())
    end

    local entries = {}
    for _, file in ipairs(self._history_entries_cache) do
        if file:match('%.json$') then
            local file_info = self:parse_filename(file)
            if file_info then
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
    local path = self:get_path() .. file_name

    if _os.remove(path) then
        -- Only remove from cache if it was actually fully loaded before
        if self._history_entries_cache ~= nil then
            local new_cache = {}
            for _, c in ipairs(self._history_entries_cache) do
                if c ~= file_name then
                    new_cache[#new_cache + 1] = c
                end
            end
            self._history_entries_cache = new_cache
        end

        return true
    end

    return false
end

return CombatStatsHistory
