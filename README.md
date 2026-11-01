# Extended Pickup Icons Range

A **HELLDIVERS 2** mod that marks samples, supplies, mission items, drop-off points, valves and vehicles
from farther away, using the game's own icons. Since 2.0.0 (numbered as on Nexus) it runs on
**Chef Shared Loader** (Nexus 17760) and draws its own on-screen markers; the older Bingus Shared Loader
versions (released here as v2.4, v2.5 and v3.0) are in this repository's history and releases.

Player-facing description and install steps: [PUBLISH_NEXUS.txt](PUBLISH_NEXUS.txt) (Nexus BBCode).

## Layout

| Path | What |
| --- | --- |
| `src/extended_pickup_icons_range.lua` | The mod (PUC Lua 5.1, runs inside Chef Shared Loader). `VERSION` is set here. |
| `src/targets.lua` | Which game units get a marker: group, icon and distances per unit. |
| `src/local_player.lua` | Build/schema-checked local player and death observations, inlined into the main Lua by `build.py`. |
| `src/icon.png` | Mod manager icon. |
| `build.py` | Builds `dist/Extended Pickup Icons Range v<VERSION>.zip` (Arsenal-importable). |
| `tests/test_extended_pickup_icons_range.py` | Runs the mod against a fake engine (needs `lupa`). |
| `tools/bake_icons.py` | Bakes `tools/icons/game/*.png` (game icons, extracted with filediver) into the mod's own textures; `build.py` packs them into the patch. |
| `tools/draw_skull.py` | Draws the death mark's skull (from the game's death screen) into `tools/icons/game/skull.png`. |
| `tools/raster_icons.py` | Turns `tools/icons/supply.png` into the `ICON_PIXELS` table (the supply crate's pixel icon). |
| `release/` | The released ZIP. |

## Working on it

```bash
python -m venv .venv
.venv/Scripts/python -m pip install lupa
.venv/Scripts/python -m unittest tests.test_extended_pickup_icons_range
.venv/Scripts/python build.py
```

To change an icon, replace its PNG in `tools/icons/game/` (its entry in `ICONS` in `tools/bake_icons.py`
says how it is cut out) and rebuild; `python tools/bake_icons.py` writes a preview of every icon and size.
The supply crate is still a pixel icon: edit `tools/icons/supply.png`, run `python tools/raster_icons.py`
and paste the printed table into `ICON_PIXELS` in `src/extended_pickup_icons_range.lua`.

Unit names come from filediver's resource listing (https://github.com/xypwn/filediver).
Sample rarity: rare samples are Crystallized E-710, Legendarium and Black Saffron; the super sample
is Super Uranium.

## Current local test builds

See [docs/staged-improvements.md](docs/staged-improvements.md). `2.5.1-test.2` isolates the Chef world-ID
change; `2.5.1-test.3` also uses guarded local-player health/position observations on the two supported game
builds. In a local gameplay session, its network identity and two death detections were confirmed in the log;
the player reported correct death and general markers. The renamed test.4 addon/logs were also seen running.
`2.5.1-test.7` integrates discovery optimization, vehicle identity tracking and a fix for vehicle-death position
using the mapped local avatar's world coordinates when available. Its live vehicle test failed: the log
still used the replicated network position. `2.5.1-test.8` adds bounded position diagnostics, not a new fix.
`2.5.1-test.9` instead prefers the prelinked own sample container's position when local health confirms
death, as requested. It includes the earlier improvements and needs a live vehicle-death check.
Existing icons, ranges, settings,
vehicle destruction detection and camera-relative general-marker behavior are preserved. `release/` and the
published Nexus description still describe the earlier public version.

Current loader resource: `mods/codex/extended_pickup_icons_range`. Current logs:
`ExtendedPickupIconsRange.log` and `ExtendedPickupIconsRange.previous.log`, in Chef's log folder.
The first renamed launch carries the old log into the new previous-log file without altering the original.
Only the persisted `pickup_dots.*` setting keys remain for compatibility with existing saved options.

Network vehicle/carryable-state replacement remains gated; see [the state audit](docs/object-state-audit.md).
The existing vehicle and mission-item decisions continue to operate for these unverified states.
