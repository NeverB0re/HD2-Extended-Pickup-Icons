# Extended Pickup Icons Range

A **HELLDIVERS 2** mod that marks samples, supplies, mission items, drop-off points, valves and vehicles
from farther away, using the game's own icons. Since 2.0.0 (numbered as on Nexus) it runs on
**Boot Mod Loader** (Nexus 17754) and draws its own on-screen markers; the older Bingus Shared Loader
versions (released here as v2.4, v2.5 and v3.0) are in this repository's history and releases.

Player-facing description and install steps: [PUBLISH_NEXUS.txt](PUBLISH_NEXUS.txt) (Nexus BBCode).

## Layout

| Path | What |
| --- | --- |
| `src/pickup_dots.lua` | The mod (PUC Lua 5.1, runs inside Boot Mod Loader). `VERSION` is set here. |
| `src/targets.lua` | Which game units get a marker: group, icon and distances per unit. |
| `src/icon.png` | Mod manager icon. |
| `build.py` | Builds `dist/Extended Pickup Icons Range v<VERSION>.zip` (Arsenal-importable). |
| `tests/test_pickup_dots.py` | Runs the mod against a fake engine (needs `lupa`). |
| `tools/raster_icons.py` | Turns `tools/icons/*.png` (game textures, extracted with filediver) into the `ICON_PIXELS` table. |
| `release/` | The released ZIP. |

## Working on it

```bash
python -m venv .venv
.venv/Scripts/python -m pip install lupa
.venv/Scripts/python -m unittest tests.test_pickup_dots
.venv/Scripts/python build.py
```

To change an icon, edit or replace its PNG in `tools/icons/`, run `python tools/raster_icons.py`
and paste the printed tables into `ICON_PIXELS` in `src/pickup_dots.lua`.

Unit names come from filediver's resource listing (https://github.com/xypwn/filediver).
Sample rarity: rare samples are Crystallized E-710, Legendarium and Black Saffron; the super sample
is Super Uranium.
