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

## Requested sample-container death position — 2.5.1-test.9

The player requested using the sample container at the instant their death is confirmed. Local identity and
death confirmation still use the typed/owned network player and positive-to-zero health transition. The
position now prefers the previously linked own sample container's current guarded world position, copied
once when death is confirmed. Later corpse/container movement cannot update that numeric mark.

Container association happens while alive, not by selecting the nearest box after death. Initially the
network position must match one world avatar within 1 m. That avatar and the candidate container must move
together at least 0.75 m, within 0.35 m of the same displacement, while the container is within the existing
2.5 m worn reach. A nearer/ambiguous other avatar blocks the candidate. This is a conservative spatial/motion
association, not a newly discovered authoritative sample-owner field. Camera/spectator selection is unused.

Once linked, follow that exact owner and container unit. A dropped/left-behind container loses its binding;
it is not rediscovered at death. A teammate carrying the linked container cannot supply the new death point.
If the unit disappears just as death is confirmed, the last confirmed container point may bridge at most
0.5 s. Otherwise use the existing fresh last-known position. If no unambiguous container was linked, the old
position fallback remains and the vehicle case is not claimed fixed for that circumstance.

The established owner unit also supplies live world position, avoiding the boarding-point network value
without the unavailable UnitSynchronizer mapping. A lost owner association cannot adopt a different avatar.
Each new avatar/session/world discards it. No new network fields or scene-node calls are introduced.

All 167 tests pass, including vehicle death without any avatar mapping, moved/sinking boxes after death,
boxes dropped and left behind, stationary ground boxes, teammate-carried boxes, overlapping avatars and
teammate death. Live testing of the new sample association remains necessary. The test.8 diagnostic drive
is no longer required before trying this requested method.

## Live sample-container confirmation — 2026-11-01

The player tested test.9 and confirmed the death marker stayed at the actual vehicle-death location.
The local log independently records `own sample container at death` at 17:24:42, reinforcement with a new
avatar, a fresh own-container association at 17:24:55, and removal after the local player reached the mark
at 17:25:00. The session shut down normally at 17:25:20. This verifies this vehicle-death scenario; it does
not establish all multiplayer/departure cases or the elimination of intermittent native crashes.

The next priorities remain category-specific despawn/sinking prevention and multiplayer death ownership
validation. See `nexus-comment-audit-2026-11-01.md` for the full public-comment review and outstanding requests.

## Despawn recurrence guards — 2.5.1-test.10

Confirmed vehicle destruction now survives a temporary resource/search-membership gap while that exact
engine unit remains alive. Previously a missing entry in found[] cleared wrecked[], allowing the same
alive sinking wreck to reappear. Cleanup now requires a failed alive check or a world reset. The old
handle-reuse fixture now models an actual engine-dead interval rather than equating search absence with
destruction. A distinct new vehicle near a wreck still keeps its own history.

For samples, supplies, movable mission items, carried loads and vehicles, probe the visible-mesh Unit.box
through Chef at most twice per second per in-range unit. Only a previously nonempty model becoming empty
hides its marker. A refused/invalid read preserves the last confirmed display state. Positive visible
geometry restores a valid temporarily hidden item. Static controls/drop-offs and picked-up-code rules
are excluded; existing verified terminal hellbomb/wreck/taken states stay terminal. All unit caches reset
with the world, and dead handles release visibility history. Death coordinates remain numeric snapshots.

This is a reversible geometry-display guard, not an authoritative generic gameplay removal flag. It does
not classify initially empty models or still-visible sinking objects as despawned. No terrain-height or
falling-motion cutoff is introduced. Those limits preserve valid falls, caves and reversible visibility.
Runtime behavior of the new category probes still needs verification; no universal sinking fix is claimed.

Five new replay cases failed before the fix. All 176 tests now pass, including invalid/refused reads,
visibility restoration, below-zero falling samples, streaming gaps, new items at old positions, world
reset and the two-probes/s bound. The test.10 ZIP was built without changing target resources or icons.

## Vehicle node timing — 2.5.1-test.11

Vehicle mount lookup and node-position access now require the existing three-second parked interval.
Weapon membership is tested first; missing weapons, already confirmed wrecks, nearby exosuit wrecks and
fully hidden geometry bypass the mount call. A large already-observed change in root-to-weapon distance
also bypasses it. This reduces calls in falling/driving/destruction paths; no polling guard can guarantee
that the engine cannot start destruction between the final alive check and a native call.

Moving vehicles retain same-frame weapon-loss and detached-nearby-weapon detection from root positions.
Root and mount distances have separate per-unit baselines, so switching to the stationary mount coordinate
system cannot itself flag a normal vehicle destroyed. The existing fallback remains when a mount call is
refused. No vehicle type, marker, setting or destruction check was removed.

All four new timing/detection cases failed before the fix. All 180 tests now pass: falling and newly seen
vehicles make no early mount calls, parked vehicles query once, moving vehicles read no mount positions,
and lost/detached weapons still suppress wreck markers. Test.11 integrates test.10 and the previously
gameplay-confirmed sample-container death fix. New node timing/geometry guards still need gameplay checks.

The owner has deferred color changes and multiplayer validation (await user feedback), excluded separate
map-open ranges, and requested read-only loader compatibility/called-in Hellbomb investigation. No loader
port, game deployment or additional target is enabled by this test build.

## Fixed mission Hellbomb — 2.5.1-test.12

At the owner's request, add `content/fac_helldivers/hellpod/hellbomb/hellbomb` to the existing Hellbomb
group. It uses the same red icon, height, size, distance text, visibility toggle and range (100 m default).
The group label now includes mission call-ins; persisted setting keys and all 20 settings are unchanged.
Neither `hellbomb_prop` nor the portable `bomb_backpack` is a target. The new mission-only target is
suppressed on the ship without changing map-bomb behavior. There are 87 target resources, still within
the existing eight-frame full discovery sweep.

Two removal conditions apply: an engine-deleted unit is removed through the existing guarded unit access,
and a previously nonempty visible-mesh box becoming empty suppresses the marker through the reversible
visibility guard (at most two box checks/s for an in-range unit). Positive geometry restores it; refused
reads retain the last confirmed state. Initial deployment invisibility does not permanently remove a bomb.
No fuse timer or animation/network field is guessed. Existing map-placed defunct bombs retain their
previous verified terminal all-mesh-hidden behavior.

All 189 offline tests pass. Nine new cases cover matching icon/tint/range and shared settings, engine
deletion with cached membership, complete geometry loss and recovery, initially hidden deployment,
refused reads after hiding, new units at an old hidden location, ship behavior, and prop/backpack exclusion.
The new marker did not exist in the previous module (seven new tests fail there at their marker assertions).

This implements the requested conservative removal design, not a verified native destruction mapping.
If the bomb explodes but leaves its unit alive with visible remnant geometry, these two signals may not
identify that state. Current game data does not establish that path. Gameplay validation remains unrun;
no additional experiment is required of the owner before receiving this test build.

## Owner gameplay confirmation and countdown investigation — 2026-11-01

The owner confirms vehicle markers disappear after destruction and do not reappear underground after
despawn, and the new mission Hellbomb marker appears correctly and disappears after destruction. Record
those scenarios as gameplay-confirmed. This is not proof of eliminating every random native crash or
all multiplayer death-marker edge cases. The inspected current local log identifies test.12 and a clean
shutdown; it does not itself contain the specific Hellbomb destruction event, so do not manufacture a
log-derived destruction timestamp.

New request: assess per-Hellbomb activation/countdown display, equally when activated by the local player
or a teammate. No keyboard/input/proximity heuristic is acceptable as authoritative activation. A player
may approach or join after another player arms the bomb, so first observation cannot restart a full fuse.
Prefer a verified replicated remaining duration or detonation deadline. If only an armed transition can
be observed, a locally estimated timer requires a verified duration/transition and must handle initially
armed objects as unknown rather than freshly armed. Early explosion/removal must cancel any display.

Offline evidence:

- The fixed bomb's animation graph has top_retracted -> top_extend via raise_top; top_extend uses
  hellbomb_activate and emits top_done. That is an activation-related visual candidate, not proof of the
  exact gameplay fuse start. Live animation-state reads remain excluded after the prior native crash.
- In the current extracted schema, candidate name hashes active=b19ad128, is_armed=b0e87fae and
  timer=6bdd349b occur in 188, 71 and 2 types respectively. Timer occurs in 4d57c925 and 94408f1d;
  94408f1d also has position/active. No type has been tied to either Hellbomb unit and timer value
  semantics are unverified. Do not read guessed game-object fields or enable a countdown from these names.
- Fresh official Chef MODDING documentation has no built-in Hellbomb armed/shot event. Its event bus alone
  cannot create the missing game signal. https://github.com/Th3chef/Chef-Shared-Loader/blob/main/docs/MODDING.md
- Published gameplay descriptions of damaged map bombs distinguish a delayed light-damage trigger from
  immediate detonation by strong damage. Do not assume one fixed fuse for every damaged bomb. Exact live
  numeric fuse durations have not been established from the installed game's gameplay data in this audit.
  https://helldivers.wiki.gg/wiki/Damaged_Hellbomb

Conclusion: the renderer can display a per-unit countdown, but reliable teammate-independent activation
and remaining-time observation are not yet established. No countdown or additional engine read is enabled.

## Experimental mission Hellbomb warning — 2.5.1-test.13

The owner explicitly requests attempting a ten-second warning from activation, for fixed mission Hellbombs
only. An isolated factory observes the installed graph's second animation layer (top_retracted=1 to
top_extend=0) rather than local input, so a visible replicated teammate action follows the same path.
This is a graph-based experiment, not a verified network detonation deadline. It is gated to the engine
identifier for the extracted current graph (46805437.../Steam 26251122); other builds keep ordinary markers.

Only the exact fixed Hellbomb resource is queried, in range/in a mission, after a positively visible box.
Every observation goes through Chef's per-resource crash keys: alive, has_animation_state_machine, alive,
animation_get_state, alive. Require the expected three-layer tuple and at most five observations/s; refused
or malformed reads clear the transition baseline and back off. No call is made for damaged map bombs,
backpacks, vehicles or hidden/deleted units. Once activated, stop animation queries entirely for that unit.

These checks reduce known missing-state-machine/stale-unit paths, but cannot make a native call atomic.
Animation-state reads previously caused a vehicle crash in older versions. Their reintroduction here is
experimental and strictly resource-scoped; no native-crash elimination or live callback mapping is claimed.

A fresh observed 1->0 transition starts an estimated ten seconds. The label is `~10s` down to `~1s`, drawn
2.4 times the distance text size, with shadow/bold rendering. The icon enlarges/pulses and changes yellow
to red; flash rate increases smoothly from 1 to 4 Hz, opacity never reaching zero. Warning text stays solid
and works even when distance text is off. At estimated expiry show `!` until the actual marker disappears.
The timer is not used to delete a marker or indicate that the area is safe.

First observed activated or activated after an observation gap longer than 0.5 s: `ARMED` only, never a new
full timer. Leaving/returning preserves an existing deadline; new units/worlds discard old history. Earlier
destruction/visibility suppression removes the warning with its marker. All other marker behavior remains.

All 207 offline tests pass, including the previous 189, 12 factory cases and 6 renderer/lifecycle integration
cases. Simulated remote activation uses no local input. New tests verify missing/malformed states, guards,
poll bounds, build gating, late observations, size/color/pulse, distance-off display, early removal and
leaving/returning. The actual returned animation tuple and its timing relative to gameplay arming remain
unverified in a played mission. Build test.13 separately; do not publish/push it as a stable release.

## Countdown calibration and hundredths — 2.5.1-test.14

The owner played test.13: the countdown starts promptly with activation, confirming that this live
activation-layer read works in the tested scenario. The explosion occurs several seconds after the
ten-second display ends. Activation-to-detonation timing and the teammate case are not thereby fully
verified. Do not call the original ten-second start-to-explosion assumption correct.

Read-only extraction of `hellbomb_activate.animation` gives header.length=5 (seconds). The state graph
enters this clip on the transition we observe and emits top_done at its end. A five-second activation clip
followed by the assumed ten-second fuse explains the reported late explosion; this remains a hypothesis
about gameplay sequencing, not a proven replicated deadline. Test.14 uses 15 seconds from the observed
transition as the next calibration value. Do not label fifteen seconds an exact measured game fuse.

At the owner's request, remove the tilde and render seconds:hundredths, `15:00 -> 14:99 -> ... -> 00:00`.
The right two digits are hundredths of a second, not minutes/seconds or a promise of hundredth-second
accuracy. Compute from the deadline each frame; do not accumulate frame-count drift. Keep 00:00 and the
red alert pulse until actual marker removal. Pulse/color progression now covers the full fifteen seconds,
retaining the 1-to-4-Hz ramp and readable solid warning text.

Log elapsed time from observed activation to positive geometry loss and/or unit deletion, separately.
These are removal observations, not proof of natural detonation (shots can cause early destruction).
Logging deduplicates each signal, performs no extra animation reads, and uses only the guarded existence
helper at most five times/s per started warning to catch deletion even after discovery drops the point or
the player leaves range. A world reset forgets measurements. No automatic fuse learning is enabled.

All 209 tests pass, adding hundredth-boundary/zero-clamp checks and deduplicated removal-timing checks;
the integrated early-deletion case confirms logging after hot discovery removes the dead point. Existing
guarded activation, late-observation handling, teammate-independent logic and all prior features remain.
The revised duration still needs comparison with an undisturbed natural explosion; new timing logs allow
that comparison without asking the owner to use a stopwatch or upload another player's files.

## Deferred until final release: finer, folded settings

Owner instruction: implement this when preparing the final version, not in the current experimental builds.
Make the first mod-options screen quiet: collapsible category headings, with individual type toggles and
distances inside. Consolidate scattered related settings instead of merely adding more top-level rows.

Planned organization:

- Samples: common, rare, super, sample containers and eggs; individual show/range controls. Keep sample
  fading in this group. Further resource variants only where they create a useful player-facing choice.
- Supplies: ammo, grenades, stims and supply crates; individual show/range controls, supply fading here.
- Mission: group current mission-item and objective settings under one heading, with subheadings for
  carried/data items, artillery loads and objective interactions. Individual supported type toggles/ranges.
- Vehicles: exosuits, FRVs and tanks; separate supported type/family visibility and ranges.
- Hellbombs: separate fixed mission call-ins and damaged map bombs, each with show/range. Put applicable
  warning/countdown display settings here. Do not add portable-backpack support merely to fill this menu.
- Death marker: its existing show/range and any applicable marker-specific display settings together.
- Common appearance: size, opacity and vanilla-icon handoff. Keep cross-category controls here only when
  their effect really is shared, and label any shared distance-text control with its affected categories.

Implementation constraints:

- Latest official Chef documentation supports heading folds from 1.4.0 via option_headings/option_folds.
  This is folding within the same options screen, not arbitrary nested pages; subheadings are not
  independently foldable. Detect actual capabilities and retain an accessible flat fallback if absent.
  https://github.com/Th3chef/Chef-Shared-Loader/blob/main/docs/MODDING.md#the-options-menu-and-key-bindings
- Preserve all current features and existing saved values. Initially inherit each old category's enabled
  state and range into its new type settings, then preserve independently saved choices on later launches.
  A group-level off must not erase child choices. Make any bulk overwrite explicit if provided.
- Existing settings use ModOptionsMenu compatibility registration; verify heading propagation and option
  count limits before choosing native Chef registration/bridging. Do not create one fake top-level mod per
  category to imitate submenus. Preserve the mod identity and persisted legacy setting keys/migration.
- Derive ranges/visibility from precomputed per-target configuration when settings change; avoid adding
  engine reads or per-frame settings polling. Keep discovery/range limits and immediate setting updates.
- Required checks at implementation: saved-value migration, independent per-type switches/ranges,
  folded menu rendering/navigation, old-capability fallback, and unchanged unrelated target behavior.

This is a recorded final-release work item only. No runtime/settings/package changes are made by this note.
