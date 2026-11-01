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

Next: validate network schemas and resolve local-player identity without adopting a host or spectator fallback.
