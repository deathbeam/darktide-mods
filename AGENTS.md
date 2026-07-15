# Agent Guidelines for Darktide Mods

This document provides comprehensive guidelines for coding agents working in this Warhammer 40,000: Darktide mod repository.

## Project Overview

- **Language:** Lua (5.1 compatible)
- **Framework:** Darktide Mod Framework
- **Testing:** Manual in-game testing only
- **Formatting:** StyLua
- **License:** MIT

## Build/Lint/Test Commands

### Formatting
```bash
# Format all Lua files with StyLua
stylua .

# Format specific file
stylua path/to/file.lua

# Check formatting without modifying
stylua --check .
```

### Testing
**No automated testing framework.** All testing is done manually in-game by:
1. Loading Darktide with the Darktide Mod Framework
2. Enabling the mod via the in-game mod manager
3. Testing functionality during gameplay

### Release
```bash
# Releases are automated via GitHub Actions
# Trigger manually from: Actions > Release Mods > Run workflow
# Input: version (e.g., 1.0.0), changelog, and NexusMods upload flag
```

## Code Style Guidelines

### Formatting Configuration (.stylua.toml)
- **Line width:** 120 characters
- **Indentation:** 4 spaces (no tabs)
- **Quote style:** Single quotes preferred (auto)
- **Line endings:** Unix (LF)
- **Function calls:** Always use parentheses

### Naming Conventions

```lua
-- SCREAMING_SNAKE_CASE for constants
local ACTION_STAGES = { NONE = 0, SWITCH_TO = 1 }
local CHECK_INTERVAL = 0.5
local SLOT_POCKETABLE = 'slot_pocketable'

-- snake_case for local functions (prefix with _)
local function _get_player_unit()
    -- ...
end

local function _is_weapon_switching()
    -- ...
end

-- snake_case for local variables
local current_stage = ACTION_STAGES.NONE
local target_slot = nil
local stage_start_time = 0

-- PascalCase for classes
local CombatStatsTracker = class('CombatStatsTracker')
local HudElementCombatStats = class('HudElementCombatStats')
```

### Module Structure

Each mod follows this consistent structure:
```
ModName/
├── ModName.mod                           # Mod manifest (registers with framework)
└── scripts/mods/ModName/
    ├── ModName.lua                       # Main mod logic and hooks
    ├── ModName_data.lua                  # Settings/configuration UI
    ├── ModName_localization.lua          # Localized strings
    └── [additional modules...]           # Utilities, views, HUD elements
```

### Import Patterns

```lua
-- Get mod instance (always first line)
local mod = get_mod('ModName')

-- Load game engine modules
local UIWidget = require('scripts/managers/ui/ui_widget')
local PlayerUnitVisualLoadout = require('scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout')

-- Load mod-internal modules (use io_dofile)
local CombatStatsTracker = mod:io_dofile('CombatStats/scripts/mods/CombatStats/combat_stats_tracker')
local CombatStatsUtils = mod:io_dofile('CombatStats/scripts/mods/CombatStats/combat_stats_utils')
```

### Code Organization

Keep file layout ordered: imports first, then constants, then state, then functions. **Constants belong at the top of the file** (after imports and class definition), never scattered mid-file between functions. A lookup table that reads like a constant (`GAME_STAT_LABELS`, `ARMOR_COLOR`) is a constant — promote it to the constants block, not inline above the first function that uses it.
```lua
-- Constants
local CHECK_INTERVAL = 0.5
local ACTION_STAGES = { NONE = 0, SWITCH_TO = 1 }

-- State variables
local current_stage = ACTION_STAGES.NONE
local target_slot = nil
```

### Type Safety and Defensive Programming

**Always use nil checks and safe access patterns:**

```lua
-- Safe manager access
local player = Managers.player and Managers.player:local_player_safe(1)
local player_unit = player and player.player_unit

-- Safe extension access with has_extension
local unit_data_ext = ScriptUnit.has_extension(player_unit, 'unit_data_system')
if not unit_data_ext then
    return nil
end

-- Protected calls for potentially failing operations
local success, weapon_template = pcall(function()
    return visual_loadout_ext:weapon_template_from_slot(slot_name)
end)
if not success then
    return nil
end

-- Chain nil checks
local inventory_component = unit_data_ext and unit_data_ext:read_component('inventory')
if not inventory_component then
    return nil
end
```

### Hook Patterns

```lua
-- Standard hook (can modify behavior, return early, or call original)
mod:hook(CLASS.StateGameplay, 'on_enter', function(func, self, parent, params, ...)
    -- Custom logic before
    local mission_name = params.mission_name
    
    if should_skip then
        return -- Skip original
    end
    
    -- Call original function
    local result = func(self, parent, params, ...)
    
    -- Custom logic after
    mod.tracker:start(mission_name)
    
    return result
end)

-- Safe hook (always calls original, cannot return early or modify return value)
mod:hook_safe(CLASS.PlayerUnitHealth, 'add_damage', function(self, attacker_unit, damage_amount, ...)
    -- Custom logic (original already called)
    mod.tracker:record_damage(damage_amount)
end)
```

### Class Definition Pattern

```lua
local ClassName = class('ClassName')

function ClassName:init()
    self._tracking = false
    self._data = {}
    self:reset()
end

function ClassName:reset()
    self._data = {}
end

function ClassName:public_method()
    return self._tracking
end

return ClassName
```

### Lifecycle Callbacks

```lua
-- Called when mod is enabled
mod.on_enabled = function()
    -- Initialize state
end

-- Called when mod is disabled
mod.on_disabled = function()
    -- Cleanup state
end

-- Called after all mods finish loading
mod.on_all_mods_loaded = function()
    -- Load packages, register integrations
end

-- Called every frame
mod.update = function(dt)
    -- Update tracking, state machines
end

-- Called when game state changes
mod.on_game_state_changed = function(status, state_name)
    -- Handle state transitions
end

-- Called when a setting is changed
mod.on_setting_changed = function(id)
    -- Reload configuration
end
```

### Settings Pattern (ModName_data.lua)

```lua
local mod = get_mod('ModName')

return {
    name = mod:localize('mod_name'),
    description = mod:localize('mod_description'),
    is_togglable = true,
    options = {
        widgets = {
            {
                setting_id = 'some_checkbox',
                type = 'checkbox',
                default_value = false,
            },
            {
                setting_id = 'some_group',
                type = 'group',
                sub_widgets = {
                    {
                        setting_id = 'nested_setting',
                        type = 'numeric',
                        default_value = 5,
                        range = { 1, 10 },
                    },
                },
            },
        },
    },
}
```

### Localization Pattern (ModName_localization.lua)

```lua
return {
    mod_name = {
        en = 'My Mod',
    },
    mod_description = {
        en = 'A detailed description of what this mod does',
    },
    setting_label = {
        en = 'Setting Label',
    },
}
```

### Error Handling & Logging

- Use `pcall()` for operations that might fail
- Always validate inputs and state before operations
- Return `nil` or early exit on invalid state
- Log errors with `mod:error()` for debugging

**DMF logging API** (`scripts/mods/dmf/modules/core/logging.lua`):

- `mod:info()` / `mod:debug()` / `mod:echo()` / `mod:warning()` / `mod:error()`
- Each goes to a configurable output (log file, chat, notification) per the mod's DMF logging settings.
- **Default modes:** `info` = log-file only (mode 1), `debug` = disabled (mode 0), `echo`/`warning` = log + chat (mode 4), `error` = all (mode 7).
- **For diagnostic/debug logging, use `mod:info()`** — it writes to the game's console log file (no chat spam) and is enabled by default. Output lands in `AppData/Roaming/Fatshark/Darktide/console_logs/console-*.log`, prefixed `[MOD][ModName][INFO] ...`.
- `mod:debug()` requires the user to enable debug output in DMF settings (otherwise it no-ops) — only use for verbose/conditional dev traces.
- `mod:echo()` is fine for transient dev visibility but spams the chat window; prefer `mod:info()` for anything copyable.
- Tag temporary diagnostic logs with a unique prefix (e.g. `[DEBUG-adm]`) and `grep` them out at cleanup.

### Comment Style

- Comments should explain **why**, not **what** the code obviously does. If a comment just restates the line below it, delete it.
- Prefer one short line. Never write multi-line comments that restate a function's behavior, restate parameter shapes already evident from the call, or narrate straightforward control flow (`-- loop over marks`, `-- return the value`, etc.).
- Comments describe **what the code is**, never what it is **not**. Don't reference removed/alternate approaches (`-- not the raw weight`, `-- rather than dropping them`, `-- or X is wrong`). Say what the line does or returns; if that's obvious from the code, delete the comment. No `→`/ASCII arrows in prose — use the real function/field names.
- Section headers (`-- Constants`, `-- Hooks`, `-- State variables`) are welcome and stay one line.
- Never add `// NOTE:` / `// FIXME:` walls of text. If something genuinely needs a warning, one line max.
- **Localization helpers and data-derived lookups do not need comments** explaining how `mod:localize` works or how the fallback prettifies. The code is the source of truth.
## Best Practices

1. **Performance:** Cache extensions and components to reduce repeated lookups
2. **State Management:** Use explicit state variables and reset functions
3. **Separation of Concerns:** Split large mods into multiple modules (tracker, utils, view, HUD)
4. **Documentation:** Use comments for complex logic and simple section headers for organization — don't over-explain
5. **Compatibility:** Use safe access patterns to avoid crashes with other mods or game updates
6. **Testing:** Test in-game after any changes, especially with different classes and missions

## Common Pitfalls

- **Don't** use `cd` before `require()` - paths are relative to game root
- **Don't** assume managers exist - always check `Managers.foo and Managers.foo:method()`
- **Don't** assume units/extensions exist - use `has_extension()` and nil checks
- **Don't** modify game state without checking if player is in valid gameplay state
- **Don't** use global variables - keep everything in local scope or mod scope

## Development Workflow

1. Make changes to Lua files
2. Format with `stylua .` before committing
3. Test in-game by reloading the mod or restarting Darktide
4. Commit changes with descriptive commit messages
5. Create releases via GitHub Actions workflow

## References

- **Darktide Source Code:** https://github.com/Aussiemon/Darktide-Source-Code (may be cloned in parent directory as `../Darktide-Source-Code`)
  - Decompiled game source - use this to understand game APIs, classes, managers, and extension systems
  - Essential for finding correct function signatures and understanding game mechanics
- **Darktide Mod Framework:** https://github.com/Aussiemon/Darktide-Mod-Framework
- **StyLua:** https://github.com/JohnnyMorganz/StyLua
