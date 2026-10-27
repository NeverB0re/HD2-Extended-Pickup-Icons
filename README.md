# Extended Pickup Icons Range

A **HELLDIVERS 2** mod that marks samples, supplies, mission items, drop-off points, valves and vehicles
from farther away, using the game's own icons. Since 2.0.0 (numbered as on Nexus) it runs on
**Chef Shared Loader** (Nexus 17760) and draws its own on-screen markers; the older Bingus Shared Loader
versions (released here as v2.4, v2.5 and v3.0) are in this repository's history and releases.

Player-facing description and install steps: [PUBLISH_NEXUS.txt](PUBLISH_NEXUS.txt) (Nexus BBCode).

## Layout

| Path | What |
| --- | --- |
| `src/pickup_dots.lua` | The mod (PUC Lua 5.1, runs inside Chef Shared Loader). `VERSION` is set here. |
| `src/targets.lua` | Which game units get a marker: group, icon and distances per unit. |
| `src/icon.png` | Mod manager icon. |
| `build.py` | Builds `dist/Extended Pickup Icons Range v<VERSION>.zip` (Arsenal-importable). |
| `tests/test_pickup_dots.py` | Runs the mod against a fake engine (needs `lupa`). |
| `tools/bake_icons.py` | Bakes `tools/icons/game/*.png` (game icons, extracted with filediver) into the mod's own textures; `build.py` packs them into the patch. |
| `tools/raster_icons.py` | Turns `tools/icons/supply.png` into the `ICON_PIXELS` table (the supply crate's pixel icon). |
| `release/` | The released ZIP. |

## Working on it

```bash
python -m venv .venv
.venv/Scripts/python -m pip install lupa
.venv/Scripts/python -m unittest tests.test_pickup_dots
.venv/Scripts/python build.py
```

To change an icon, replace its PNG in `tools/icons/game/` (its entry in `ICONS` in `tools/bake_icons.py`
says how it is cut out) and rebuild; `python tools/bake_icons.py` writes a preview of every icon and size.
The supply crate is still a pixel icon: edit `tools/icons/supply.png`, run `python tools/raster_icons.py`
and paste the printed table into `ICON_PIXELS` in `src/pickup_dots.lua`.

Unit names come from filediver's resource listing (https://github.com/xypwn/filediver).
Sample rarity: rare samples are Crystallized E-710, Legendarium and Black Saffron; the super sample
is Super Uranium.
