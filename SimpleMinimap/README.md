# SimpleMinimap

A clean, simple minimap for Warhammer 40,000: Darktide.

## Features

- **Teammates** - See your squad on the minimap with optional class icons
- **Objectives** - Mission and expedition objectives automatically shown
- **Pings** - Player pings and threat markers
- **Enemy Radar** - Optional radar showing nearby enemies

## Architecture

SimpleMinimap uses a simple marker system where each marker type is a single file that handles both data collection and rendering.

```
SimpleMinimap/
├── SimpleMinimap.mod
└── scripts/mods/SimpleMinimap/
    ├── SimpleMinimap.lua                  # Main mod file
    ├── SimpleMinimap_data.lua             # Settings
    ├── SimpleMinimap_localization.lua     # Strings
    ├── hud_element_simple_minimap.lua     # Core minimap HUD element
    └── markers/                           # Marker types
        ├── teammates.lua                  # Shows teammates
        ├── objectives.lua                 # Shows mission objectives
        ├── pings.lua                      # Shows pings
        └── enemies.lua                    # Shows enemies (radar)
```

## How It Works

### Marker System

Each marker file in `markers/` exports:

- `init(hud_element)` - Creates the widget(s) for rendering
- `draw(hud_element, ui_renderer, dt, t)` - Collects data and draws markers

The HUD element provides:
- `hud_element._world_markers_list` - Access to Darktide's world markers
- `hud_element:world_to_minimap(world_pos)` - Convert world position to minimap position

### Adding New Markers

To add a new marker type:

1. Create `markers/my_marker.lua`:

```lua
local mod = get_mod('SimpleMinimap')
local UIWidget = require('scripts/managers/ui/ui_widget')

local marker = {}

function marker.init(hud_element)
    -- Create your widget
    marker._widget = UIWidget.create_definition({ ... }, 'minimap')
    marker._widget = UIWidget.init('my_marker', marker._widget)
end

function marker.draw(hud_element, ui_renderer, dt, t)
    -- Collect data
    -- Convert positions with hud_element:world_to_minimap(world_pos)
    -- Draw with UIWidget.draw(marker._widget, ui_renderer)
end

return marker
```

2. Register in `hud_element_simple_minimap.lua`:

```lua
self:_register_marker('my_marker', require('SimpleMinimap/scripts/mods/SimpleMinimap/markers/my_marker'))
```

That's it!

## Data Sources

- **World Markers** - Teammates and pings come from Darktide's world marker system
- **Mission Objective System** - Objectives come from `mission_objective_system:active_objectives()`
- **Broadphase** - Enemy radar uses broadphase spatial queries

## License

MIT
