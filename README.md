# Extended Pickup Icons Range

A HELLDIVERS 2 Chef Shared Loader addon that draws markers over samples, supplies, mission items,
objective interactions, Hellbombs, vehicles and your last death, using the game's icons.

The local **2.6.0 release candidate** includes the gameplay-tested changes from 2.5.1-test.14, removes
experimental measurements, and adds native Chef settings with folded categories and per-type ranges.
The final settings UI still needs an in-game display/navigation check before publication.

- [Nexus page text, English + Korean BBCode](PUBLISH_NEXUS.txt)
- [2.6.0 changelog, upload description and announcement, English + Korean](docs/nexus-release-2.6.0.txt)
- [Release audit and validation scope](docs/release-audit-2.6.0.md)
- [Development history](docs/staged-improvements.md)

## Player requirements

Chef Shared Loader 1.4.0 or newer for the folded interface; use the latest version. This is a Chef addon.
Other loaders must provide compatible Chef addon support. No independent loader port is claimed.
Remove the old mod before deploying the new ZIP, with Chef at the highest priority.

**2.6.0 starts marker settings at defaults.** The owner approved the new settings backend without
migration of legacy ModOptionsMenu values. Reconfigure in F9; subsequent changes persist normally.
Native setting IDs use `epir.*`. The previous `pickup_dots.*` IDs are retained only in the legacy
category-control fallback, for loaders without native option helpers. Older native interfaces without
headings show flat settings. These fallback paths do not create duplicate options on current Chef.

## Runtime behavior

Defaults: samples 50 m, supplies 25 m, mission items/objectives 50 m, Hellbombs and vehicles 100 m,
last death 500 m. At most 40 nearest markers are drawn. Folded sections contain individual type
visibility/range controls, master switches that preserve child choices, explicit bulk distance sliders,
and related appearance controls. Shared appearance settings stay together. Settings update cached
per-target ranges only on changes; frames do not poll the options backend.

Own death is confirmed from guarded typed local-player health on supported builds. A previously linked
own sample container supplies a fixed death coordinate, else a fresh last-known position is used. The
marker does not follow a moving/despawning corpse. Unknown game builds retain the earlier camera method.

Fixed mission Hellbombs share the red Hellbomb icon but have independent settings from damaged map
bombs. A guarded observed activation transition starts an estimated 15-second warning in seconds:hundredths,
with accelerating yellow-to-red pulsing. Late observations show ARMED. Zero remains an alert until removal.
This is a local estimate, not an authoritative explosion deadline. The animation reader is restricted to the
verified build/resource, and stops after activation. Portable backpacks have no marker/countdown support.

Deleted units and confirmed vanished geometry are suppressed. Destruction/in-use/ownership decisions
still include heuristics: no universal underground height filter or replicated vehicle-health replacement
is claimed. Valves/cranks remain marked after use. See the player page for behavior and limits.

## Layout and development

| Path | Purpose |
| --- | --- |
| `src/extended_pickup_icons_range.lua` | Runtime and VERSION; Lua 5.1 |
| `src/targets.lua` | 87 target/helper resource definitions |
| `src/local_player.lua` | Build-checked identity/death observations |
| `src/hellbomb_warning.lua` | Guarded activation observation and warning appearance |
| `src/settings.lua` | Native options and cached per-target settings |
| `build.py` | Inlines modules and packs one Lua plus 135 icon textures |
| `tests/` | Lua 5.1 fake-engine regression tests via lupa |
| `tools/compare_discovery_reads.py` | Native-read count comparison, not an FPS benchmark |
| `tools/bake_icons.py` | Bakes game icon PNGs into resource textures |
| `tools/verify_release.py` | Checks ZIP contents, Lua, texture compatibility and package hash |
| `release/` | Historical releases plus the local candidate; a ZIP here does not mean published |

```powershell
python -m venv .venv
.venv/Scripts/python -m pip install lupa
.venv/Scripts/python -B -m unittest discover -s tests -p 'test*.py'
.venv/Scripts/python -B build.py
.venv/Scripts/python -B tools/verify_release.py 'dist/Extended Pickup Icons Range v2.6.0.zip'
```

Lua 5.1 on Windows requires an ASCII writable TEMP path for file-I/O tests. Build refuses to overwrite
an existing version directory. Source asset changes are not needed for this update. Never push or
publish experimental changes or a candidate before its final in-game check.

Addon resource: `mods/codex/extended_pickup_icons_range`. Manifest GUID remains unchanged.
Logs: `ExtendedPickupIconsRange.log` and `ExtendedPickupIconsRange.previous.log` in Chef's log folder.
Only basic startup, state-change and error information remains; experimental position/timing/statistics
code and its extra bookkeeping are removed. Research assets, developer tools, tests and logs are not
included in the player ZIP.
