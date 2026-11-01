# Loader and called-in Hellbomb investigation — 2026-11-01

Scope: inspect compatibility without installing another loader, changing the game, or porting the addon.
Current target is the unchanged Chef helper contract in test.11. A mod appearing in a manager or being
discovered as Lua is distinct from running and drawing its markers correctly.

## MDL3 preview dev 27

Official release and updates:

- https://ayakamods.com/mods/mdl3-preview-%E9%BA%A6%E5%BD%93%E5%8A%B33-%E9%A2%84%E8%A7%88%E7%89%88%EF%BC%81.5710/
- https://ayakamods.com/mods/mdl3-preview-%E9%BA%A6%E5%BD%93%E5%8A%B33-%E9%A2%84%E8%A7%88%E7%89%88%EF%BC%81.5710/updates

The latest visible release is dev 27. Importantly, its update list explicitly adds **CSL mods support**;
the overview's older BSL-only compatibility section is not the whole current compatibility statement.
This makes the existing addon a reasonable unchanged-package test candidate. It is not evidence that this
specific addon, every current Chef helper, native crash-key behavior or network reads work identically.

The addon declares `-- HD2-Addon: mods/codex/extended_pickup_icons_range` and uses the usual source-Lua
archive envelope/manager manifest. It checks for an argument table exposing camera, call, call_kind,
unit_alive, unit_position, unit_node, in_mission, screen, color, rect, triangle, bitmap, text and text_width.
Optional world/session/network functions also affect current death identity and world-state behavior.
MDL3 must actually supply these rather than merely list the package. The explicit runtime check will
report missing required helpers. Network build identifiers are still validated independently by this mod.

The package contains 135 icon textures as well as Lua. MDL3's guide says resource parts of mixed mods must
be deployed through a manager and restarted; script-only hot loading is not sufficient for this package.
The guide also warns against deploying competing loaders together. No coexistence recipe is asserted.

Public download requires an Ayaka account and the preview is closed source. No archive/API documentation
was obtained in this audit, so discovery/execution was not tested under MDL3. Do not patch our addon or
add an FFI dependency on the strength of a speculative mismatch. First test the existing ZIP with the
author's CSL-compatible release, then fix only a demonstrated small contract gap. No port is enabled here.

## Bingus Shared Loader v20 and HellForge

Reviewed pinned v20 author guide, discovery and startup sources:

- https://github.com/CowboyBingus/BingusSharedLoader/blob/v20/docs/AUTHORING.md
- https://github.com/CowboyBingus/BingusSharedLoader/blob/v20/src/discover.lua
- https://github.com/CowboyBingus/BingusSharedLoader/blob/v20/src/shared_loader.lua
- https://github.com/CowboyBingus/BingusSharedLoader/blob/v20/README.md

The archive/header format and resource-name/hash match v20's declared-addon discovery contract. Therefore
the current Lua entry is structurally discoverable; a new filename, GUID or manifest tag is not needed.
But v20 starts modules with `pcall(require, name)` and does not inject the Chef helper table. Replaying
the current packaged entry with the conventional resource-name argument, or no helpers, exits with
`no Chef Shared Loader`. Successful discovery or require alone must not be advertised as functional support.
V20 also gates startup to Steam build 25480438; it does not launch third-party addons on an unsupported
current live build. Do not disable that gate.

Upstream HellForge documentation:

- https://github.com/SkyeShade/HellForge/blob/main/README.md
- https://github.com/SkyeShade/HellForge/blob/main/docs/mods.md
- https://github.com/SkyeShade/HellForge/blob/main/docs/lua-bridge.md

HellForge accepts/stages Lua patch mods and documents Bingus/HD2Runtime support on its older supported
game build. That does not supply a Chef-compatible helper contract to this mod. HD2Runtime's bridge is
another API, not an automatically interchangeable Chef argument. Its documented custom stratagem-image
limitation does not prove whether this addon's packaged game textures would render through a future adapter;
the texture path must be verified separately rather than claiming all images are unsupported.

An adapter would need guarded unit/world access, the current camera/projection and draw/texture path,
settings, logging and lifecycle handling; death/network behavior must be validated for the older build.
No evidence supports calling that a trivial metadata change or a few-line port. No adapter, installation,
build-gate bypass, loader replacement or feature reduction was performed. Current unchanged package:
structurally recognizable, not functionally supported by plain Bingus v20.

## Called-in Hellbomb

The current installed game's Filediver listing distinguishes three resources:

| Resource under content/fac_helldivers/hellpod/ | Resource id | Current role evidence |
| --- | --- | --- |
| hellbomb/hellbomb | c6a87c428fd3c7a3 | Present in packages/generated/loadout/hellbomb (681275af9e93cb2c): called-in candidate |
| hellbomb/hellbomb_prop | f195ffb780ee43b7 | Different ship/prop package fc5b6bff0db90aab; do not include |
| hellbomb_defunct/hellbomb_defunct | 861e970f512b7bed | Map-placed target already supported |

Listing and raw unit metadata were re-extracted read-only into the workspace research folder. The called-in
unit main blob is 13,472 bytes, SHA-256
`1a4e2e4c76c8a472968144fd24af7e8b3bf71ca3a7ddbde24481eb46f5fe3550`.
It contains the full expected resource path. No extracted game assets are included in the repository/package.

Adding a marker for this separate unit appears feasible using the existing resource discovery, loaded/alive
guards, Hellbomb icon and range controls. No new icon artwork or loader port is inherently required. This
is a feasibility conclusion, not gameplay validation. In particular, the current terminal no-visible-mesh
rule is verified for defunct bombs, not for the called-in bomb's pod/deployment/activation animation.
Applying it blindly could permanently hide a bomb during an initially hidden animation.

Recommended small implementation, after current stability testing: a separate target and optional default-off
called-in-bomb toggle so the existing map-bomb behavior remains unchanged. Suppress the ship prop, observe
deployment and explosion/removal transitions, and reuse only verified lifecycle evidence. Validate intact,
activating, armed, destroyed and despawned states before claiming support. No target/toggle was added by
this investigation, and no activation/countdown/interaction network flag was guessed.

## Owner's current priorities

Test.10 and test.11 implement the requested sinking-recurrence and vehicle-node timing guards. Color is
deferred; multiplayer death validation awaits public feedback; a separate map-open range is not planned.
MDL3 unchanged-package validation is the smallest next compatibility step. A Bingus/HellForge adapter or
new called-in Hellbomb feature remains separate from the current stability package.

## Follow-up: offline analysis instead of owner runtime tests

The owner does not want to install/test alternative loaders. Prioritize archive/API inspection and isolated
mock execution instead. The official MDL3 archive is account-gated; the owner offered to download it and
attach it here. Request the complete official ZIP, including any API docs and Data Hub; no installation is
needed. Inspect helpers, entry arguments, texture loading, lifecycle and network reads before proposing a
port. Static/mocked analysis can establish concrete mismatches, though it cannot prove native gameplay.

Downloaded the official Bingus v20 binary and source archives to the separate workspace research folder:

- Binary SHA-256: `a42e43e7afe520d0ccd23fe25f9ac5d818c00419d9401de51e59553c87866742`
- Source SHA-256: `fa6f49e682bdd1979bdaba4397fa9ba21b5ecc70e0448791ce8ec67911630cd0`
- Both match the hashes on the official v20 release assets page.
- Binary contains one Lua resource, `7251fdd9bb62480a`, 64,495-byte LuaJIT body, envelope version 2.
- Released source confirms `pcall(require, name)` at src/shared_loader.lua:521; no Chef argument injection.
  The packaged readme targets Steam build 25480438. No installer or downloaded loader code was run.

Source: https://github.com/CowboyBingus/BingusSharedLoader/releases/tag/v20

## Clarification: standard mission Hellbomb versus portable backpack

The previously investigated `hellbomb/hellbomb` target is the standard fixed mission Hellbomb, not the
warbond B-100 Portable Hellbomb. Game resources list the portable item separately as
`content/fac_helldivers/equipment/backpacks/bomb_backpack/bomb_backpack` (`9ace8638421abc8e`), in
`packages/generated/loadout/hellbomb_backpack` (`346d785d6ca13ff4`). Thus testing the warbond backpack does
not validate the fixed bomb's target, deployment/activation or removal behavior.

Arrowhead's warbond announcement identifies B-100 as a backpack:
https://blog.playstation.com/2025/02/04/helldivers-2-servants-of-freedom-warbond-launches-february-6/

Some missions instead grant a free B-100; the wiki distinguishes that case and its alternate call-in code:
https://helldivers.wiki.gg/wiki/B-100_Portable_Hellbomb

That is the same portable equipment category as the warbond item, so the warbond version is a sensible
portable-marker test, not a substitute for standard fixed Hellbomb testing. Exact mission-specific spawn
bindings have not been traced here, and mission-granted call-in availability/code/cleanup behavior still
requires its own validation. No portable or fixed called-in target was enabled by this clarification.
