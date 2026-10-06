# Extended Pickup Icons Range

![Extended Pickup Icons Range](outputs/Extended_Pickup_Icons_thumbnail.png)

Lore-friendly pickup visibility for **HELLDIVERS 2** (tested on Steam build 25480438). Extends the game's native floating icons without adding light pillars or glowing textures. Requires **Bingus Shared Loader v15+** and Arsenal.

**[Download v2.5](https://github.com/NeverB0re/HD2-Extended-Pickup-Icons/releases/tag/v2.5)** · [한국어 설치 및 상세 설명](outputs/README_v25_KO.md)

| Independent Arsenal option | Targets | Internal ViewDistance |
| --- | --- | ---: |
| Samples | Common, rare, super, packaged and intel samples | 35 |
| Supplies | Ammo, stims, grenade boxes and resupply pod packs | 20 |
| Equipment & Mission Items | Support/secondary/melee weapons, backpacks, dropped sample carriers and most mission carryables | 35 |
| Equipment: carry ammunition and warheads | SEAF shells, carry-ammo and warheads | 15 |

Ordinary fuel barrels and Illuminate canisters retain their vanilla settings. Primary firearms and five ambiguous weapon records are excluded; Stalwart remains included as a support weapon. The Supplies option also enables the existing stim ping icon automatically.

These numbers are **internal settings, not guaranteed measured meters**: fading, item position and the game's display rules affect when an icon becomes visible. Pickup Radius and InteractType are unchanged.

## Install

1. Completely close the game and disable earlier Extended Pickup Icons Range versions.
2. Enable a compatible Bingus Shared Loader v15+.
3. Import the release ZIP into Arsenal and select any of the three options.
4. Purge, Deploy and restart the game.

The ZIP is the Arsenal mod; GitHub's automatic source-code ZIP is not an installable mod.

## Compatibility and validation

v2.5 no longer locks itself to one exact game build. It finds the game's item data by its header and each item by its resource ID. Before writing, it checks the item's zone name, Radius, interaction type, original ViewDistance and memory protection. Any item that does not match, for example because another mod or a game update changed it, is skipped and named in the log. Every other item still applies. After a successful application, its repeated checks stop.

v2.5 applied all 251 zones in game on build 25480438. Synthetic protected-memory tests (`work/test_extended_pickup_icons_v25.py`, needs `pip install lupa`) cover relocated and reordered data, a mismatched item, missing stim data, duplicate tables and late loading. v2.4 fixed six SEAF shell variants that remained at 35 in v2.3. **The SEAF shells' visible distance still requires in-game verification.** No benchmark claim is made.

Log: `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\CodexPickupIconRangeTest.log`.
With all options enabled: `samples=30 supplies=8 equipment=213; skipped 0 unmatched` (251 zones).

## Source and build

`work/extended_pickup_icons_v25.lua` is the v2.5 core script; the three option scripts are unchanged since v2.4. The v2.4 core script and build script are kept for reference. `work/release_v24_verified_targets.json` records the selected resources and expected values. Game binaries, extracted game databases, personal logs and the loader itself are not distributed here.

The original build script is preserved. It requires Python 3 and the Bingus Shared Loader authoring helpers `archive.py` and `build_addon.py` in `work/vendor/BingusSharedLoader-main/scripts/`. Obtain compatible helpers from the loader's authoring source. This repository neither forks nor bundles Shared Loader. Run:

```console
python work/build_extended_pickup_icons_v24.py
python verify_release.py
```

v2.5 needs no extra helpers. It reuses the v2.4 release ZIP and replaces only the core script:

```console
python work/build_extended_pickup_icons_v25.py
python verify_release.py
```

Building changes no Lua behavior. The verifier checks the archived SHA-256, ZIP structure, target counts, and exact embedded source entries. It uses only Python's standard library. Different helper or compression implementations may require reviewing a changed checksum rather than assuming an identical release.

## Credits

CowboyBingus / Bingus Shared Loader for independent addon discovery and archive authoring tools; Filediver for the type/data parsing references used during investigation. This is an independent addon, not an official Arrowhead release. The dependency is installed separately.
