# Stability improvements

## Stage 1 — 2.5.1-test.2: Chef world identity

Use `chef.world()` and `chef.world_id()` together when both helpers exist. A nil, refused or inconsistent
snapshot waits without bypassing Chef through the raw engine API. Older Chef versions retain the existing
world-comparison path. Startup and world-settle grace periods are unchanged.

Clear unit-dependent state while a world is unavailable. A stable Chef id with a new wrapper does not clear
mission state; a new id clears it even if the engine reuses the same world handle. Returning from a temporary
unavailable state with the same id preserves the numeric death mark, but drops unit handles and waits again.
Near-vehicle refresh state is cleared as well. No icons, distances, settings or death-detection rules change.

Validation: all 118 tests pass, including five new loader-world regressions and the earlier crash guards.
The first sandbox test attempts could not start a process (`CreateProcessSecurityEnvironment`, 0x8007000A);
the same tests passed in the approved normal execution environment. No gameplay validation yet.

## Stage 2 — 2.5.1-test.3: confirmed local health and frozen death coordinates

`src/local_player.lua` is an independent observer, inlined by the builder into the same Lua resource. It uses
Chef's per-call guarded reads, never writes game/session state, and never uses batched reads. The network
path is enabled only for the engine identifiers corresponding to Steam builds 26088801 and 26251122. Other
builds retain the existing camera heuristic and log the legacy mode; they are not claimed to have the new fix.

Before reading fields it checks the declared player/avatar schema through `Network.object_info`. Field
ids are the upper 32 bits of the engine's Murmur64 strings: player avatar reference `0f27c68e`, avatar
health `cb0453ea`, avatar position `8bbeb160`. Both numeric and hexadecimal string ids are supported.

The owned-object scan checks at most 32 candidates per frame and requires exactly one player-type object
owned by the local peer. There is no substitute-host-player or camera fallback within the network path.
The selected player is cached while its existence/type/owner remain valid. Every field read checks object
existence and type again. A new session, world or unavailable world discards observations.

A positive-to-zero health transition freezes a copy of the last living coordinates. A maximum 0.5-second
observation gap bounds stale history. A missing read is not zero. If the player explicitly clears/replaces its
avatar reference, one guarded read may confirm the old local avatar's terminal health before it is forgotten.
If the old object/health is already gone there is no confirmed death; the code does not guess a new mark.

The last mark persists until the actual local, living avatar approaches within the existing horizontal
4 m / vertical 3 m clear condition. Teammate proximity and spectator-camera changes cannot clear it.
Only the latest confirmed death is kept. The skull, distance setting, edge arrows and defaults are unchanged.
The camera still controls general-marker distance/appearance as before; changing that spectator behavior is
not bundled into this stage. The old death heuristic remains for unsupported builds.

Validation: all 144 tests pass (113 prior tests, five world-lifetime cases, 26 network/integration cases). Cases include
teammate death/reinforcement/departure, corpse sinking, reinforcement reference replacement, identity
ambiguity, missing/refused reads, changed ownership/session, object-id reuse, frame gaps and repeat deaths.
The build also checks the actual packed Lua 5.1 and preservation of the 135 icon textures and GPU data.

Runtime limitations: schema and object validation do not make native calls atomic. Host/guest ownership,
live field representations, instant death and immediate avatar removal still need gameplay validation. A
missed/unavailable death sample can leave no new mark; guessing from spectator changes would reintroduce
the reported problem. No game deployment, loader upgrade or remote push has been performed.

Evidence: Chef source/docs at `400cc03aa558f30b5f84c6c0e7f840b4fb8e92ba`; game identifiers and network-reading
examples in NarrowHUD `597968c2b9e556812e0376b8a6627926df1f2524`. No NarrowHUD implementation was copied.

Next gate: validate this pair of test builds in-game before changing discovery/refresh cadence or replacing
vehicle and carryable heuristics. Timing changes and unverified object fields are intentionally deferred.

## Local gameplay feedback and naming — 2.5.1-test.4

The player reported correct death markers and other icons in the test. The local 2.5.1-test.3 log confirms
Chef world-ID mode, confirmed local-player identity, two network-health death events, and normal shutdown.
No `failed`, `FATAL` or `disabled` line was present in that log. This is one local session, not coverage of
every host/guest/instant-death case or a frame-time benchmark.

Naming is aligned with Extended Pickup Icons Range:

- Main source/test: `src/extended_pickup_icons_range.lua`, `tests/test_extended_pickup_icons_range.py`.
- Loader resource and texture namespace: `mods/codex/extended_pickup_icons_range`.
- Per-environment singleton: `ExtendedPickupIconsRange`; optional Chef title: `Extended Pickup Icons Range`.
- Logs: `ExtendedPickupIconsRange.log` / `ExtendedPickupIconsRange.previous.log`. On the first renamed launch,
  the old log is read as the previous launch if there is no current log. Original historical logs are untouched.

The package GUID and saved `pickup_dots.*` option keys are preserved. Chef's ModOptionsMenu get API only
returns registered rows, so renaming those keys without a migration would reset saved settings. They are
compatibility identifiers, not the loader/display name. Historical release/test ZIPs and quoted crash reports
retain their original names. This naming-only build still needs a post-rename launch check before publishing.

Validation: all 147 tests pass, including legacy-log migration and current-log precedence. The packaged Lua
compiles on Lua 5.1; its addon id and all 135 texture ids use the new namespace. Texture headers/pixels, GPU
and stream data, mod-manager icon and manifest/GUID are byte-identical to test.3. Local-player logic and the
target table are unchanged. The settings-prefix local stays inside `register_settings` to respect Lua 5.1's
200-local limit in the main chunk.

## Stage 3 — 2.5.1-test.5: separate membership discovery from position refresh

The complete resource sweep is unchanged (12 of 86 keys per frame; one pass in eight frames). Nearby
non-vehicle resource groups refresh the positions of their known units between sweeps instead of calling
`World.units_by_resource` again. New members are discovered within that full-sweep bound. A member of an
already-hot resource can therefore appear later than the former every-frame hot discovery, by up to seven
frames; no range, icon, category or setting is removed. Known moving units still update every frame, and
gone units are dropped on the next refresh. Loaded-resource checks and the crash guards remain in force.

Vehicles, weapons and wrecks retain their same-frame membership discovery: the disappearance of a gun must
still hide a rolling wreck immediately. Native position reads have not been throttled. The flying-item
fixture now moves one stable unit handle; replacement handles are covered separately as discovery.

All 151 tests pass. `tools/compare_discovery_reads.py` compares 240 frames with baseline `483270b`:

| Fixture | Resource/avatar enumerations before → after | Position reads before → after | Markers before → after |
| --- | --- | --- | --- |
| 10 nearby item resources | 2640 → 540 | 2640 → 2640 | 10 → 10 |
| 10 far item resources | 540 → 540 | 540 → 540 | 0 → 0 |
| Nearby items plus FRV/gun | 3120 → 1020 | 3120 → 3120 | 11 → 11 |

These are deterministic fake-engine call counts, not measured gameplay time or FPS improvements.

## Vehicle death position — 2.5.1-test.6

The player reported a death inside a vehicle leaving the skull at its boarding point. The current test.4
log confirms the renamed addon/logs run and local health detection is active; it does not contain a second
position source with which to prove the engine-side cause. A stale replicated avatar `position` is the
reproduced model of this report, not a directly measured vehicle-network trace.

For the already-confirmed local avatar id, ask `GameSession.unit_synchronizer` and
`UnitSynchronizer.game_object_id_to_unit` for its exact unit, then obtain its root world position through
Chef's current-world/alive guards. Do not select a unit by camera proximity or substitute a teammate.
Keep a confirmed association through a transient missing map; discard it on avatar/session/world change.

The last living world position is frozen when local health confirms death. After a world-position source
has been established, a refused/gone unit must not overwrite that snapshot with a stale network/boarding
position. A fresh snapshot may bridge a brief gap, at most 0.5 s; after a longer gap there is no new guessed
mark. Engines that supply no avatar-unit mapping retain the network-position source, so the fix must still
be checked in the affected vehicle. Logs now identify which position source was used.

All 156 tests pass. The boarding-point case fails on the prior module and passes after the change. Tests
also cover spectator isolation, transient map gaps, gone units and stale snapshot rejection. This does not
establish that the affected live vehicle exposes a usable mapping; a live vehicle test remains necessary.

## Vehicle history — 2.5.1-test.7 (integrated test)

Vehicle motion/weapon history is matched by its actual unit identity. The old nearest-position match could
exchange different weapon-mount offsets when vehicles crossed, or give a fresh vehicle the destroyed state
of a nearby wreck. Both cases failed before this fix and pass after it. Existing parked/moving behavior,
weapon-loss checks, same-frame discovery and per-unit wreck memory remain in place.

All 158 tests pass. The integrated build includes naming, world management, network death observations,
discovery/refresh separation and the vehicle-death coordinate fix. See `object-state-audit.md` for why direct
network vehicle/carryable-state replacement is not enabled: specific type bindings and value meanings remain
unverified, so the existing features are preserved. No extra speculative native field reads were added.

## Next priorities after the integrated vehicle test

1. Inspect the live position-source log for the vehicle death. Verify the actual mapping is available and the
   mark stays at the death location, then validate recovery and spectator isolation in host/guest sessions.
2. Investigate the reported generic despawn/sinking marker recurrence before extending state heuristics.
   `Unit.alive` means the engine object exists, not that it remains a valid pickup/vehicle. A unit can remain
   listed while its removal animation sinks it underground. Do not treat alive handles as sufficient evidence
   for a persistent marker; use category-specific, verified removal/visibility/interaction signals.
3. Keep confirmed-removed state attached to the actual unit so cached points cannot re-create its marker.
   Forget unit state on world changes or genuine handle replacement. Keep death marks as numeric snapshots,
   never as a moving corpse/container reference. Preserve valid new items/vehicles near an old wreck.
4. Add regressions for alive-but-removed units, sinking while meshes disappear, stale discovery/position
   caches, a new unit at the old position, and leaving/returning to the area. Pair them with valid movement
   cases (falling vehicles, blasted samples, slopes/elevation changes) to prevent false removals. Absolute
   world height or downward movement alone is not a valid despawn criterion.
5. Validate gameplay cost and remaining crashes; only then replace verified network vehicle/carryable state
   decisions and prepare a stable package/docs/release. No frame-time gain or universal despawn fix is claimed
   from the existing offline tests.

This section records the next requested work; no new despawn-filter behavior is implemented by this note.

## Live vehicle failure and diagnostic test — 2.5.1-test.8

The player repeated the test in test.7 and the marker still stayed at the boarding point. Its local log
records `position source network position` throughout and the death event also names `network position`.
Thus the mapped-unit path did not produce usable world coordinates in this session. The test.6/test.7
offline case modeled an available mapping and did not establish that this game uses that map for avatars.
Do not call that vehicle bug fixed on the evidence of the offline case.

Test.8 is diagnostic, not a new vehicle-position fix. It retains the refusal/nil reason from the mapping
calls already made, and logs existing numeric snapshots once a second near a vehicle (within 40 m of the
camera, at most 120 lines per session/world). It includes the recorded position/source, camera position,
stable labels and positions of currently enumerated avatars, and nearby vehicle positions. It adds no
native calls or new guessed ownership/coordinate fallback. Dead-state tracking remains unchanged.

All 160 tests pass, including mapping-reason retention, the diagnostic line cap, no additional native reads
and no diagnostic output without a nearby vehicle. The next live capture only needs walking to the car,
boarding and moving away for 10–20 seconds, then a clean game exit; no further suicide is needed to compare
the available position sources. Any heuristic association or camera-based substitute requires discussion
before implementation, as requested by the project's instructions.
