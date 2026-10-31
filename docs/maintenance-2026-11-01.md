# 2.5.1-test.1: cached-unit access guards

The crash report identified `mods/codex/pickup_dots|Unit.has_node:cc21c7ffd3ebefb9` on Chef 1.3.1.
The id is the Murmur64 hash of `content/fac_helldivers/vehicles/frv/frv`. Pickup Dots asks Chef for
that vehicle's `gun_mount` node to detect a detached gun. Chef's `unit_node` helper calls `Unit.has_node`.

## Change

- Recheck cached target handles through `chef.unit_alive` before drawing or asking about their nodes/meshes.
- Check again after node discovery and between mesh reads, since a unit can disappear between calls.
- Clear node indices when a cached target is known gone, when there is no world, and on a world change.
- Keep Chef's guarded helpers and per-kind crash keys. No direct native-call bypass is introduced.

`Unit.alive` indicates an existing engine object, not a living soldier or an undamaged vehicle. All target groups,
icons, ranges, settings, detached-gun detection and the existing death-marker behavior remain in place.

## Validation

Three new regressions failed on 2.5.0: a despawned cached FRV reached `unit_node`, a unit that disappeared during
mesh inspection reached `Unit.mesh`, and a reused handle retained its node index across worlds. They pass with
the fix. A fourth regression covers disappearance between node discovery and node-position access.
All 113 fake-engine / Lua 5.1 / archive tests pass. The built package is checked separately against the generated
Lua and the 2.5.0 texture data. The test ZIP is in `test-builds/`, not `release/`.

This is prevention for a reproduced stale-handle path, not reproduction or proof of elimination of the reported
native crash. No in-game test or frame-time benchmark has been run for this version. The reported user's logs
are not required for these guards. Game installation, loader state and existing release ZIPs are not changed.

## Death-marker investigation (proposal, not implemented)

The existing camera/reinforcement heuristic can adopt a spectated teammate as `own`, then record that teammate's
position as the next death. Tracking a corpse until reinforcement also permits later ragdoll/despawn motion to
affect the position selected. A corpse is not an engine-dead unit merely because its soldier has died.

A stronger candidate exists: resolve the local session peer to its player object, read that player's avatar
reference, and monitor that avatar's `health` and `position`. Save numeric coordinates once on a positive-to-zero
health transition; stop following the old corpse/container. Observe the new avatar through the same player
object on reinforcement. Camera changes and another player's reinforcement/leaving must not change ownership.

Evidence (read 2026-11-01):

- Chef documents read-only Network/GameSession/UnitSynchronizer access and the need for guarded calls:
  <https://github.com/Th3chef/Chef-Shared-Loader/blob/main/docs/MODDING.md>.
- NarrowHUD's player/avatar resolution and death/health reads, inspected at commit
  `597968c2b9e556812e0376b8a6627926df1f2524`:
  <https://github.com/luka189/NarrowHUD/blob/597968c2b9e556812e0376b8a6627926df1f2524/src/modules/04_objects.lua>,
  <https://github.com/luka189/NarrowHUD/blob/597968c2b9e556812e0376b8a6627926df1f2524/src/modules/12_markers.lua>,
  <https://github.com/luka189/NarrowHUD/blob/597968c2b9e556812e0376b8a6627926df1f2524/src/modules/12_vitals.lua>.
- Its generated network data is for Steam build 26251122. Player type `803159b3` (`un6y1d`) points through
  `u4d1h9a` to avatar type `5d9752f9` (`vvhx8ga`). These are build-specific evidence, not permanent API names.
- Autodesk documents that network ownership is migratable, not necessarily player control:
  <https://help.autodesk.com/cloudhelp/ENU/Stingray-Help/lua_ref/obj_stingray_GameSession.html>.

Before using that path here, validate fields against the running build/schema and validate object existence/type
before reads. Do not copy NarrowHUD's ambiguous fallback to the host's player object; an unresolved local player
must remain unresolved. Never treat a missing/refused health read as health zero or infer death from an avatar
disappearing alone (ship transitions, disconnects and temporary reads can do that too).

Host, guest, spectating, simultaneous reinforcement, teammate departure, instant death, ragdoll/despawn, and
mission transitions need live validation. A health transition can be missed between polls or object replacement;
those cases need explicit treatment before claiming reliable detection. Do not silently fall back to the same
camera heuristic when identity is ambiguous. Keeping the latest mark until the real local player reaches it
should retain the mod's current behavior; NarrowHUD's timeout and clear distances are not a proposed change.

No NarrowHUD code was copied into the mod. This note records an implementation direction for review.
