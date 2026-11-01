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
