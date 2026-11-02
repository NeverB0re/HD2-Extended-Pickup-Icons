# 2.6.1 release audit — 2026-11-02

Previous public version: **2.6.0**, GitHub commit `757ccd1`.
Gameplay-tested input: **2.6.1-test.2**, reviewed in `aa2c148`.
The owner confirmed resupply fading, vehicle-death placement and vehicle destruction, reported no
problems in those checks, and explicitly authorized release. Nexus upload remains with the owner.

## Release scope against 2.6.0

- Replace the resupply-crate rectangle renderer with a texture from the same source artwork; the owner
  confirmed that its fading issue is resolved. Add nine baked supply-icon sizes.
- Reduce repeated discovery, resting-root positions, code/keycard meshes and damaged-bomb geometry
  queries. Preserve per-frame local death confirmation and the eight-frame full discovery bound.
- Avoid unnecessary same-frame vehicle/weapon/wreck enumeration for terminally destroyed vehicles.
- Retain the last death marker first, vehicles/Hellbombs second, then the nearest remaining targets
  within the existing 40-marker cap.
- Use Chef-managed logging and avoid the two blocked old-log reads present in 2.6.0. Support log:
  `ExtendedPickupIcons.log`. No separate previous-launch file is promised.
- Fix missing-`Gui` resolution fallback. Preserve existing targets, ranges, appearance settings and IDs.
- Existing 2.6.0 preferences remain valid. Reset/reconfiguration applies only to pre-2.6.0 upgrades.

The 15-Hz death polling and stale liveness behavior corrected during test.1 review were **unreleased
regressions**. The public changelog does not present those corrections as new fixes to 2.6.0.
Superseded rectangle-rasterizer and older call-comparison tools are retired; the existing baker and
`tools/count_calls.py` provide their current replacements. Historical release ZIP deletions present
before this review are not staged or published as part of this release.

## Verified release artifacts

- `release/Extended Pickup Icons Range v2.6.1.zip` — **118,892 bytes**.
- SHA-256: `1206cc8dade7d6ac1b6483524df408ec157ca682333046505b368e4d29951335`.
- Checksum file beside the ZIP.
- `PUBLISH_NEXUS.txt`: English/Korean BBCode mod page updated for 2.6.1.
- `docs/nexus-release-2.6.1.txt`: bilingual changelog, file description and announcement.
- `docs/github-release-2.6.1.md`: bilingual GitHub release body.

**231 regression tests passed** with the stable version number. Actual ZIP verification passed without
`--allow-test`: six player files, one Lua plus 144 textures, expected addon declaration/hash and manifest
GUID, Lua 5.1 compilation, embedded source matching the worktree, no removed experimental measurements,
and graceful missing-Chef handling. All 135 textures from 2.6.0 preserve their headers/pixel bytes.

Direct comparison with the tested test.2 ZIP proves:

- The released Lua is byte-for-byte the same after replacing only its `VERSION` string.
- GPU data, stream data, mod-manager icon and manifest are identical.
- The package README adds the release summary. Tests, developer tools, research assets and logs are
  absent from the player ZIP.

## Efficiency evidence and its limits

600 simulated frames per scene; identical inputs and marker counts, comparing the actual 2.6.0 ZIP:

| Network identity mode | 2.6.0 API calls/frame | 2.6.1 API calls/frame | Markers |
| --- | ---: | ---: | ---: |
| No nearby vehicle | 459.96 | 151.13 | 38 / 38 |
| FRV nearby | 478.04 | 168.22 | 39 / 39 |

Legacy-mode results and detailed methodology remain in `docs/review-2.6.1-test.2.md`.
These count simulated Chef/engine invocations, including drawing helpers; they are **not FPS or
frame-time measurements**. No universal native-crash elimination is claimed.

## Preserved boundaries

No new targets, unknown-build network/animation reads, loader port, new diagnostic mode or lifecycle
migration are introduced by promotion to release. Mission Hellbomb countdown remains the previously
documented local estimate. Multiplayer edge cases, color checks and unknown-game-update resilience
proposals retain their earlier evidence/decision status. The owner did not separately report a new
mission-Hellbomb destruction test in this final message; its previous evidence and regression tests remain.

Runtime changes are committed separately from release promotion. Publish the exact final commit/tag
to GitHub with the ZIP and checksum. Nexus is prepared for manual owner upload; no Nexus publication
or comment posting is performed by the assistant.
