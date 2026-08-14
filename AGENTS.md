# Agent Guidelines — Darktide Mods

Lua 5.1 · Darktide Mod Framework · StyLua · Busted · MIT. Repository-level tests cover pure module behavior; game integration and rendering still require in-game verification.

## Commands

```bash
make sync-shared   # copy scripts/shared/*.lua into each mod's shared/ folder (run before testing/committing)
make format        # stylua .
make check         # stylua --check .
make test            # run repository-level Busted tests with Lua 5.1
make clean         # remove copied shared files from mod folders
make publish       # sync-shared -> upload to NexusMods -> clean (see scripts/ci/publish_mods.js)
```

Don't edit shared files inside a mod's `shared/` folder — those are generated copies (gitignored). Edit `scripts/shared/` then `make sync-shared`. CI (`.github/workflows/ci.yml`) syncs shared files, checks formatting, runs tests, and gates releases; releases trigger via Actions > CI > Run workflow.

## Testing

Tests live in the repository-level `tests/` directory and are never shipped inside mods. Use the shared Darktide mock in `tests/shared/darktide_mock.lua` so tests exercise the real module files without requiring the game.

When adding or fixing behavior, add or update a focused Busted regression test when practical. Run `make test`, `make check`, and `git diff --check` before committing. Tests cannot replace in-game checks for hooks, managers, rendering, materials, or other engine behavior.
## Formatting (.stylua.toml)

120 cols · 4 spaces · single quotes · LF · always call with parens.

## Naming

- `SCREAMING_SNAKE_CASE` — constants
- `snake_case` — locals and functions; prefix private helpers with `_`
- `PascalCase` — classes

## File layout

Imports → constants → state → functions. Promote constant-shaped lookup tables (`GAME_STAT_LABELS`, `ARMOR_COLOR`) to the constants block at the top, never inline above the first function that uses them.

## Imports

```lua
local mod = get_mod('ModName')                  -- always first
local UIWidget = require('scripts/...')          -- game modules
local Tracker = mod:io_dofile('ModName/scripts/mods/ModName/tracker')  -- mod-internal
```

`require` paths are relative to game root — never `cd` first.

## Module structure

```
ModName/
├── ModName.mod
└── scripts/mods/ModName/
    ├── ModName.lua              # logic + hooks
    ├── ModName_data.lua         # settings UI
    ├── ModName_localization.lua # strings
    └── [tracker/utils/view/hud modules...]
```

Split large mods into modules; don't let one file grow unbounded.

## Simplification

Inline simple single-use logic at its call site. Extract a helper when it is reused, captures a distinct domain concept, or provides a meaningful seam; shortening a function alone is not sufficient.

## Defensive access

Managers, units, and extensions may not exist. Always guard:

```lua
local player = Managers.player and Managers.player:local_player_safe(1)
local ext = ScriptUnit.has_extension(unit, 'unit_data_system')
if not ext then return nil end
local comp = ext and ext:read_component('inventory')
```

Wrap fragile lookups in `pcall`; return `nil` / early-exit on invalid state. Don't modify game state without checking the player is in valid gameplay.

## Hooks

```lua
-- can modify behavior, return early, or skip the original
mod:hook(CLASS.StateGameplay, 'on_enter', function(func, self, parent, params, ...)
    if should_skip then return end
    local result = func(self, parent, params, ...)
    mod.tracker:start(params.mission_name)
    return result
end)

-- always calls original; cannot return early or alter the return value
mod:hook_safe(CLASS.PlayerUnitHealth, 'add_damage', function(self, attacker, amount, ...)
    mod.tracker:record_damage(amount)
end)
```

## Lifecycle

`on_enabled` / `on_disabled` / `on_all_mods_loaded` / `update(dt)` / `on_game_state_changed(status, state_name)` / `on_setting_changed(id)`.

## Logging (DMF)

| call | default output | use for |
|---|---|---|
| `mod:info()` | log file only | **diagnostics** — default-on, no chat spam |
| `mod:debug()` | disabled (user must enable) | verbose/conditional dev traces only |
| `mod:echo()` / `mod:warning()` | log + chat | transient dev visibility (spams chat) |
| `mod:error()` | log + chat + notification | real errors |

Logs land in `AppData/Roaming/Fatshark/Darktide/console_logs/console-*.log`, prefixed `[MOD][ModName][INFO]`. Tag temporary logs with a unique prefix (e.g. `[DEBUG-adm]`) and grep them out before commit.

## Comments

Explain **why**, not **what**. One short line; delete comments that restate the line below. Section headers (`-- Constants`, `-- Hooks`) are welcome. Don't narrate control flow, don't describe removed approaches, no `→` arrows, no `// NOTE:`/`// FIXME:` walls. Localization helpers and data-derived lookups need no comments — the code is the source of truth.

## Pitfalls

- Don't `cd` before `require` — paths are relative to game root.
- Don't assume managers/units/extensions exist — guard with `and` chains and `has_extension`.
- Don't use globals — keep everything local or on `mod`.

## References

- **Darktide Source Code:** https://github.com/Aussiemon/Darktide-Source-Code — cloned at `../Darktide-Source-Code`. The authoritative reference for game APIs, managers, and extension systems; read it before touching damage/stagger/power-level math.
- **Darktide Mod Framework:** https://github.com/Aussiemon/Darktide-Mod-Framework — cloned at `../Darktide-Mod-Framework`. Reference for the DMF API (`mod:hook`, `mod:io_dofile`, `get_mod`, lifecycle callbacks, logging, view registration).
- **StyLua:** https://github.com/JohnnyMorganz/StyLua
