local mod = get_mod('CombatStats')

local Save = require('scripts/managers/save/utilities/save')

local _os = Mods.lua.os

local MAX_HISTORY_ENTRIES = 100

--- Clean a filename by converting to lowercase and replacing punctuation, control, and whitespace with underscores
---@param filename string
---@return string
local function clean_filename(filename)
    return filename:lower():gsub('[%p%c%s]', '_')
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

-- Managers.token drives SaveSystem callbacks each frame in StateGame, but may be
-- nil during very early mod lifecycle hooks. Guard so we never crash.
local function token_manager_ready()
    return Managers and Managers.token ~= nil
end

local function safe_auto_save(file_name, data, callback)
    if not token_manager_ready() then
        if callback then
            callback({ done = true, error = 'token manager unavailable' })
        end
        return nil
    end
    return Save.auto_save(file_name, data, callback)
end

local function safe_auto_load(file_name, callback)
    if not token_manager_ready() then
        if callback then
            callback({ done = true, error = 'token manager unavailable' })
        end
        return nil
    end
    return Save.auto_load(file_name, callback)
end

local CombatStatsHistory = class('CombatStatsHistory')

function CombatStatsHistory:init()
    self._index = nil -- ordered list of file names, newest first; nil until loaded
    self._entries_cache = nil
    self._pending_saves = {}
    self._index_loading = false
    self._index_waiters = {}
end

function CombatStatsHistory:_index_slot()
    return 'combat_stats_history_index'
end

--- Load the history index asynchronously. Idempotent: concurrent callers queue until the load completes
---@param on_loaded function|nil Called as on_loaded(entries) once available
function CombatStatsHistory:load_index(on_loaded)
    if self._index ~= nil then
        if on_loaded then
            on_loaded(self._index)
        end
        return
    end

    if on_loaded then
        self._index_waiters[#self._index_waiters + 1] = on_loaded
    end

    if self._index_loading then
        return
    end

    self._index_loading = true

    safe_auto_load(self:_index_slot(), function(info)
        self._index_loading = false

        local loaded = {}
        if info and info.done and not info.error and type(info.data) == 'table' then
            local data = info.data
            if data.entries and type(data.entries) == 'table' then
                loaded = data.entries
            end
        end

        self._index = loaded
        self._entries_cache = nil

        local waiters = self._index_waiters
        self._index_waiters = {}
        for i = 1, #waiters do
            waiters[i](loaded)
        end
    end)
end

---@return boolean
function CombatStatsHistory:is_index_loaded()
    return self._index ~= nil
end

function CombatStatsHistory:_save_index()
    safe_auto_save(self:_index_slot(), { entries = self._index or {} })
end

function CombatStatsHistory:parse_filename(file_name)
    local timestamp_str = file_name:match('^(%d+)_')
    if not timestamp_str then
        return nil
    end

    local after_timestamp = file_name:match('^%d+_(.+)$')
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

--- Queue a history entry to be saved asynchronously. Returns the file name immediately
---@param tracker_data table
---@param mission_name string
---@param class_name string
---@return string file_name
function CombatStatsHistory:save_history_entry(tracker_data, mission_name, class_name)
    local timestamp = tostring(_os.time(_os.date('*t')))
    local file_name = string.format('%s_%s_%s', timestamp, class_name, mission_name)

    local data = {
        duration = tracker_data.duration,
        buffs = tracker_data.buffs,
        engagements = tracker_data.engagements,
    }

    local filtered_data = filter_table(data)

    local token = safe_auto_save(clean_filename(file_name), filtered_data, function(info)
        if token then
            self._pending_saves[token] = nil
        end
        if info and info.error then
            mod:echo('Failed to save history entry: ' .. tostring(info.error))
        end
    end)

    if token then
        self._pending_saves[token] = file_name
    end

    if self._index ~= nil then
        self:_apply_index_insert(file_name)
        self:_save_index()
    else
        self:load_index(function()
            self:_apply_index_insert(file_name)
            self:_save_index()
        end)
    end

    return file_name
end

--- Insert a file name at the head of the index, evicting (and clearing) the oldest over the cap
function CombatStatsHistory:_apply_index_insert(file_name)
    local index = self._index or {}
    table.insert(index, 1, file_name)

    while #index > MAX_HISTORY_ENTRIES do
        local evicted = table.remove(index)
        -- SaveSystem has no delete API; overwrite with an empty table to free the slot
        safe_auto_save(clean_filename(evicted), {})
    end

    self._index = index
    self._entries_cache = nil
end

--- Load a single history entry asynchronously
---@param file_name string
---@param callback function Called as callback(data|nil)
function CombatStatsHistory:load_history_entry(file_name, callback)
    if not callback then
        return
    end

    safe_auto_load(clean_filename(file_name), function(info)
        if not info or not info.done or info.error or type(info.data) ~= 'table' then
            if info and info.error then
                mod:echo('Failed to load history entry: ' .. tostring(info.error))
            end
            callback(nil)
            return
        end

        local data = info.data
        local file_info = self:parse_filename(file_name)
        if file_info then
            data.file = file_name
            data.date = file_info.date
            data.timestamp = file_info.timestamp
            data.mission_name = file_info.mission_name
            data.class_name = file_info.class_name
        end

        callback(data)
    end)
end

--- Return parsed history summaries (newest first). Empty until the index has loaded
---@return table
function CombatStatsHistory:get_history_entries()
    if self._index == nil then
        return {}
    end

    if self._entries_cache == nil then
        local entries = {}
        for _, file_name in ipairs(self._index) do
            local file_info = self:parse_filename(file_name)
            if file_info then
                entries[#entries + 1] = file_info
            end
        end

        table.sort(entries, function(a, b)
            return a.timestamp > b.timestamp
        end)

        self._entries_cache = entries
    end

    return self._entries_cache
end

--- Remove a history entry from the index and clear its saved blob
---@param file_name string
---@return boolean removed
function CombatStatsHistory:delete_history_entry(file_name)
    if self._index == nil then
        return false
    end

    local found = false
    local new_index = {}
    for _, name in ipairs(self._index) do
        if name == file_name then
            found = true
        else
            new_index[#new_index + 1] = name
        end
    end

    if not found then
        return false
    end

    self._index = new_index
    self._entries_cache = nil

    safe_auto_save(clean_filename(file_name), {})
    self:_save_index()

    return true
end

---@return number
function CombatStatsHistory:pending_save_count()
    local count = 0
    for _ in pairs(self._pending_saves) do
        count = count + 1
    end
    return count
end

return CombatStatsHistory
