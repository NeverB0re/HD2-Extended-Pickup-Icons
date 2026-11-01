# 2.6.0 release review — 2026-11-02

Status: **2.6.0 approved for GitHub publication**. The owner confirmed satisfactory gameplay with
2.5.1-test.14. Cleanup and native settings changes pass offline checks. On 2026-11-02 the owner also
confirmed that the new settings display correctly in game and authorized the GitHub upload. Nexus
publication will be handled by the owner.

## Changes reviewed

- Kept the confirmed own-death sample-container snapshot, guarded local-player identity/health reads,
  world-ID resets, vehicle destruction tracking and fixed mission Hellbomb warning.
- Removed periodic resource summaries, hot/discovery/draw counters used only for logging, vehicle
  position diagnostics and the Hellbomb activation-to-removal timing experiment. Removed the extra
  existence polling used only by that experiment. The functional five-Hz guarded activation reader stays.
- Retained basic startup, state-change and bounded error logs for support. No test toggles, timing
  calibration mode, developer files or research assets are shipped in the ZIP.
- Added native Chef options with seven foldable headings, a mission-objective subheading, independent
  type visibility/distances and a Hellbomb-warning toggle. Category masters preserve child choices;
  explicit bulk distance sliders affect only their named category. Per-target effective ranges refresh
  on settings changes, and are used for both visibility and distance-dependent size/fading.
- Fixed child option defaults independently of saved bulk-slider values, so a restart does not silently
  overwrite custom/default type distances. No settings-backend reads are added to frames.
- The owner explicitly approved starting preferences at defaults after the backend transition. Old
  `ModOptionsMenu` settings are not imported. Native IDs are `epir.*`. No loader files are read to
  bypass this boundary. Older interfaces retain flat native options or the old category-only fallback.

Chef API reference checked against current official MODDING.md and services.lua on 2026-11-02:
[options/capabilities](https://github.com/Th3chef/Chef-Shared-Loader/blob/main/docs/MODDING.md).
The compatibility ModOptionsMenu has 32 options per mod/heading and does not forward heading fields;
native options support headings/folds. Chef 1.4.0+ is documented for the folded UI; latest recommended.

## Checks completed

- **220 tests passed** on PUC Lua 5.1 through lupa, including 13 new native-settings cases.
- Tests cover actual marker visibility/range changes, independent sample/vehicle/Hellbomb controls,
  all supported target classifications, master switches, bulk range boundaries, saved-value restoration,
  default child restoration after a bulk edit, invalid values, flat fallback, and no per-frame settings
  polling. Disabling the Hellbomb warning keeps its marker and stops activation animation reads.
- Existing tests cover stale/deleted units, unloaded resources, world changes, death identity/snapshots,
  vehicle destruction/node timing, geometry visibility, warning timing/late observation and rendering.
- `tools/verify_release.py` checked the actual ZIP: six player files; one Lua plus 135 textures; Lua 5.1
  compiles; embedded source equals current source; declaration/resource hash matches; no placeholders
  or removed experimental measurements; unchanged GUID, icon, texture metadata/pixels and GPU/stream
  assets relative to public 2.5.0 after accounting for the tested addon resource rename.
- A normal require-style string argument and missing Chef helpers both fail closed as expected.
- Whitespace/diff checks passed. Historical release/test ZIPs and unrelated files were left intact.

## Efficiency comparison

`python -B tools/compare_discovery_reads.py`, 240 simulated frames, baseline `483270b`:

| Scenario | Enumerations before → after | Position reads before → after | Marker count |
| --- | --- | --- | --- |
| Nearby items | 2,640 → 540 | 2,640 → 2,640 | 10 → 10 |
| Far items | 540 → 540 | 540 → 540 | 0 → 0 |
| Nearby items + vehicle | 3,120 → 1,020 | 3,120 → 3,120 | 11 → 11 |

These are fake-engine native-call counts, **not FPS or frame-time measurements**. Nearby positions
continue to refresh; vehicle, weapon and wreck observations remain together. Settings processing adds
cached Lua configuration reads to marker collection, with no extra engine calls or per-frame callbacks.

## Release files

- `release/Extended Pickup Icons Range v2.6.0.zip`
- SHA-256: `7700895dbe1f602c87f34911c2fe782ea90e50d8aef22c5b470a4256b6d20966`
- `release/Extended Pickup Icons Range v2.6.0.zip.sha256`
- `PUBLISH_NEXUS.txt`: full English/Korean Nexus BBCode page.
- `docs/nexus-release-2.6.0.txt`: bilingual changelog, upload description and announcement draft.

## Live confirmation and remaining limits

The owner confirmed the new settings display correctly and approved publication. Native option
application and save/restore behavior passed offline tests; this does not separately claim a reported
live restart/persistence test. Death, vehicle, mission Hellbomb and revised warning gameplay behavior
was confirmed by the owner in preceding tests.

Multiplayer edge cases, including a reinforced teammate leaving the session, still await player feedback
by the owner's decision. The warning observes the bomb rather than local input, and simulated remote
activation passes; this is not a claim that every live teammate/late-join case has been tested. Color
validation remains deferred. Do not describe intermittent native crashes as conclusively eliminated.

The 15-second warning is a local visual-transition estimate, not a replicated explosion deadline. Unknown
game builds disable the unverified animation reader and retain ordinary markers. Missing/ambiguous
network data does not prove death. Existing vehicle/item heuristics remain; there is no universal filter
for still-visible sinking objects, valve completion state or portable backpack Hellbomb support.

No new-loader port, separate map-open range, automatic fuse learning or network vehicle-state replacement
is included. Other loaders must supply Chef compatibility. The review itself did not deploy the game files or publish externally. The owner subsequently authorized
GitHub upload after confirming the settings screen. Nexus upload remains with the owner.
