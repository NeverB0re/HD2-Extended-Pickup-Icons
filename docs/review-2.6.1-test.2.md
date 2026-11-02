# Interrupted review completed — 2026-11-02

Branch: `test-2.6.1`. Public baseline: `757ccd1` / 2.6.0. Reviewed input: Claude's staged
2.6.1-test.1 changes and `audit-2.6.0-and-update-plan.md`. Output: **2.6.1-test.2**, local only,
pending gameplay validation. No game deployment, remote push or Nexus publication was performed.

Release follow-up, 2026-11-02: the owner confirmed resupply fading, vehicle-death placement and vehicle
destruction and authorized 2.6.1 release. The pending checks above describe the original review snapshot;
see [release-audit-2.6.1.md](release-audit-2.6.1.md) for the stable promotion and exact artifact verification.

## Review findings and corrections

1. **Death confirmation was throttled to 15 Hz.** A regression test failed when death occurred on the
   next frame after a successful health read: no marker was saved at that instant, allowing subsequent
   blast motion to change the sample-container coordinate before observation. Restored per-frame local
   identity/health observations. The new test freezes the correct container coordinate before later
   motion. Restored the previously weakened exact last-position assertion too.
2. **Cached liveness from earlier frames could draw a deleted FRV.** The existing stale-FRV test exposed
   this under a different sweep phase. Reuse a successful existence check only when performed in the
   current frame; otherwise validate liveness before drawing the cached point. Node/mesh guards remain.
3. **Discovery latency had doubled.** Restored 12 resources/frame, preserving the public eight-frame full
   sweep over 87 definitions. A new test verifies that every named resource is visited within this bound.
4. **A last-death marker could still be displaced by 40 closer priority markers.** Gave the single death
   marker higher retention priority than vehicles/Hellbombs. A new crowded-scene test verifies retention.
5. **Verification refused test builds.** Added explicit `--allow-test` support without changing the default
   release-only requirement. Also reject duplicate ZIP entries and out-of-bounds GPU texture slices.
6. **Benchmark coverage was incomplete.** The original count tool exercised the legacy death path only.
   Added network and legacy cases and direct comparison against the actual public ZIP's embedded Lua.
   Benchmark failures now fail the process rather than merely printing errors with a successful exit.
7. **Documentation mismatches.** Corrected settings-reset scope, marker retention order, texture count,
   deleted-tool references and the historical changelog link. Existing `epir.*` settings are unchanged.

## Retained reviewed improvements

- Use `chef.own_log` / `chef.log`, avoiding the prohibited old-log reads. The actual 2.6.0 Chef log confirms
  two blocked reads on startup. Basic support logs use `ExtendedPickupIcons.log`; the loader manages
  the file. Failure to select an own log falls back to Chef's log; a failing log helper does not stop markers.
- Render the resupply icon with one texture instead of about 55 rectangles per crate. The source image
  is retained at `tools/icons/game/supply.png`. GPU filtering is different from the former pixel-rectangle
  path, so identical source art is not a claim of pixel-identical on-screen rendering at every scale.
- Check code/keycard meshes at most four times/s and damaged-bomb geometry at most twice/s. Keep
  recoverable geometry visibility handling, build-gated mission warning reads, and all native guards.
- Refresh resting nearby roots every four frames, then every frame once motion is observed. Model/node
  reads remain guarded. Despawn liveness is checked each frame before drawing stale cached positions.
- Enumerate avatar membership every eight frames while refreshing known avatar positions every frame.
- Avoid per-frame same-frame vehicle/weapon/wreck enumeration after a vehicle is terminally destroyed.
- Handle a missing `Gui` table with the existing screen-resolution fallback.

## Validation

**231 tests passed** on PUC Lua 5.1 via lupa 2.8. Added actual death timing, liveness, complete-sweep,
crowded priority and logging fallback regressions. Existing native settings, world resets, vehicle
destruction, mission/damaged Hellbomb and warning tests pass. This does not prove native crash elimination.

600 simulated frames per scene, identical baseline/current inputs and equal marker counts:

| Scene | 2.6.0 API calls/frame | test.2 API calls/frame | Markers before/after |
| --- | ---: | ---: | ---: |
| Legacy, no nearby vehicle | 441.96 | 133.13 | 38 / 38 |
| Legacy, FRV nearby | 460.04 | 150.22 | 39 / 39 |
| Network, no nearby vehicle | 459.96 | 151.13 | 38 / 38 |
| Network, FRV nearby | 478.04 | 168.22 | 39 / 39 |

These count simulated engine/Chef API invocations, including rendering and helper calls; they do not
measure milliseconds, FPS or native work hidden inside Chef helpers. Per-frame health checks remain.

The player ZIP passed source/manifest/GUID/declaration checks, Lua 5.1 compilation and missing-Chef
failure handling. It contains six files, one Lua resource and **144 textures**. All 135 public textures'
headers and pixel bytes are preserved; only nine supply-icon sizes are added. No developer tools,
tests, logs or removed experimental statistics are shipped. SHA-256 is stored beside the test ZIP.

Reproduce from the repo root with an ASCII writable TEMP on Windows:

```powershell
.venv/Scripts/python -B -m unittest discover -s tests -p 'test*.py'
.venv/Scripts/python -B tools/count_calls.py --baseline 'release/Extended Pickup Icons Range v2.6.0.zip'
.venv/Scripts/python -B tools/verify_release.py --allow-test 'test-builds/Extended Pickup Icons Range v2.6.1-test.2.zip'
```

The small local `.venv` contains the Lua test dependency. No game-data extraction or large analysis
downloads were needed. The previous shared dependency directory had disappeared; this environment
is local to this project. Test temporary directories clean up automatically.

## Live check before a stable release

Use the new test ZIP: inspect resupply crate appearance/fading, a death while seated in a vehicle,
and marker removal after vehicle/Hellbomb destruction. Ordinary play can cover these together.
If checking performance, compare Chef's actual mission timings in `chef_loader.log`; offline API counts
do not establish the new frame budget. Existing F9 settings are unchanged and should be retained.

The old test.1 ZIP is preserved for comparison. The test.2 build is not copied into `release/` or pushed.
Prior unstaged deletions of historical releases/tools/changelog were present at handoff; they were not
restored, staged or included in the continuation commits. `HANDOFF.md` is preserved as an untracked
historical file; its old loader/validation/permission statements are not current instructions.

## Separate update-resilience proposals remain deferred

The six proposals in Claude's audit were marked awaiting approval. This continuation does not widen
the build allowlists, read unknown Hellbomb animation graphs, remove Keep-On-Crash, replace lifecycle
registration, add diagnostic telemetry, or add new target categories. A compatible schema/tuple alone
does not establish unchanged semantics or native safety on an unknown game build. In particular,
unknown graphs returning valid-looking `1 -> 0` values could produce a false countdown, not merely
no countdown. Prefer a separate patch-check workflow and verified build updates over guessing.

Official API reference checked on 2026-11-02:
[Chef MODDING.md](https://github.com/Th3chef/Chef-Shared-Loader/blob/main/docs/MODDING.md).
This confirms the managed-log API and current lifecycle/crash-recovery contracts; implementing the
deferred migration should be a separate reviewed change. Multiplayer edge cases and color checks
remain deferred according to the owner's earlier decisions.
