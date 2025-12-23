local mod = get_mod('CombatStats')
local _os = Mods.lua.os

local MAX_HISTORY_ENTRIES = 100

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

--- Clean a filename by converting to lowercase and replacing punctuation, control, and whitespace with underscores
---@param filename string
---@return string, integer
local function clean_filename(filename)
    return filename:lower():gsub('[%p%c%s]', '_')
end

local CombatStatsHistory = class('CombatStatsHistory')

function CombatStatsHistory:init()
    self._save_queue = {}
end

--- Wait for a load operation to complete, either from queue or by starting new load
---@param file_name string The file name to load
---@return table|nil The loaded data or nil on error
function CombatStatsHistory:_wait_for_load(file_name)
    -- Wait for completion
    local token = SaveSystem.auto_load(clean_filename(file_name))
    local max_wait = 1000
    local progress
    for i = 1, max_wait do
        progress = SaveSystem.progress(token)
        mod:echo('Got progress for ' .. file_name .. ': ' .. cjson.encode(progress))
        if progress and progress.done then
            mod:echo('Loaded history entry: ' .. file_name)
            break
        elseif progress and progress.error then
            mod:echo('Error loading history entry: ' .. tostring(progress.error))
            break
        end
    end

    if not progress or not progress.done then
        mod:echo('Timeout loading: ' .. file_name)
        return nil
    end

    if progress.error then
        return nil
    end

    return progress.data
end

--- Process save queue to check for completed async saves
function CombatStatsHistory:process_queue()
    for i = #self._save_queue, 1, -1 do
        local save_item = self._save_queue[i]
        local progress = SaveSystem.progress(save_item.token)
        if progress and progress.done then
            if progress.error then
                mod:echo('Failed to save: ' .. tostring(progress.error))
            end

            SaveSystem.close(save_item.token)
            table.remove(self._save_queue, i)
            mod:echo('Saved history entry: ' .. save_item.file_name)
        end
    end
end

function CombatStatsHistory:parse_filename(file_name)
    -- Extract timestamp (first segment)
    local timestamp_str = file_name:match('^(%d+)_')
    if not timestamp_str then
        return nil
    end

    -- Extract class (second segment after first underscore)
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

function CombatStatsHistory:save_history_entry(tracker_data, mission_name, class_name)
    local timestamp = tostring(_os.time(_os.date('*t')))
    local file_name = string.format('%s_%s_%s', timestamp, class_name, mission_name)

    local data = {
        duration = tracker_data.duration,
        buffs = tracker_data.buffs,
        engagements = tracker_data.engagements,
    }

    local filtered_data = filter_table(data)

    table.insert(self._save_queue, {
        token = SaveSystem.auto_save(clean_filename(file_name), filtered_data),
        file_name = file_name,
    })

    local index = mod:get('history_index') or {}
    table.insert(index, 1, file_name)
    while #index > MAX_HISTORY_ENTRIES do
        table.remove(index)
    end
    mod:set('history_index', index)
    return file_name
end

function CombatStatsHistory:load_history_entry(file_name)
    local data = self:_wait_for_load(file_name)
    if not data then
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

function CombatStatsHistory:get_history_entries()
    local index = mod:get('history_index') or {}
    local entries = {}

    for _, file_name in ipairs(index) do
        local file_info = self:parse_filename(file_name)
        if file_info then
            entries[#entries + 1] = file_info
        end
    end

    return entries
end

function CombatStatsHistory:delete_history_entry(file_name)
    local index = mod:get('history_index') or {}
    local new_index = {}

    for _, name in ipairs(index) do
        if name ~= file_name then
            new_index[#new_index + 1] = name
        end
    end

    mod:set('history_index', new_index)
    return true
end

return CombatStatsHistory
