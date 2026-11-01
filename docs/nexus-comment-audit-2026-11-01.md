# Nexus comment audit — 2026-11-01

Source: https://www.nexusmods.com/helldivers2/mods/16554?tab=posts&BH=0

Read all three public comment pages, including replies: 48 comments. Dates below are the dates displayed
by Nexus; no timezone conversion was inferred. No comment was posted or edited. This audit compares the
public discussion with local test.9 at bb684d3; unpublished local fixes are not public-release fixes.

## Outstanding defects or verification

| Report | Evidence/status | Next action |
| --- | --- | --- |
| RagvardGrimclaw, Oct 31, comment 178726527: teammate death/reinforcement/departure leaves a red death marker underground | Local code now confirms the local player's health and freezes numeric coordinates. User confirmed test.9 vehicle-death placement, and the local log names the own-container source. The exact multiplayer departure sequence has not been verified live. No public reply is visible. | Test a teammate dying, reinforcing and leaving while the local player stays alive; verify spectating cannot create/clear an own mark. Keep generic sinking-target validation separate. |
| kleecels, Oct 28, comment 178465791: random native crash, FRV Unit.has_node key | Stale-handle guards and world lifecycle fixes are implemented locally with regressions. The reported intermittent native crash has not itself been reproduced or proven eliminated. The author reply 178468470 promises first node lookup only after landing/stopping. In current collect_dots, parked is computed but node_position is called unconditionally before the parked display decision: that promise is not implemented. | Assess a guarded first-lookup timing change while preserving weapon-loss detection; perform gameplay soak testing. Do not describe the crash as confirmed fixed. |
| RagvardGrimclaw, Oct 28, reply 178422435: supply/sample icons look whiter than vanilla | No later author response is visible. Current default ink remains RGB 255,255,255. The suggested vanilla value is a user's visual estimate, not a verified game tint. | Compare matching vanilla/modded icons in the same scene and inspect the original tint before changing colors. Low priority relative to stability. |
| RagvardGrimclaw, Oct 25–26, thread 178229154: underground diamonds, vanilla/modded alignment | Mission/ship/scope issues were reported fixed by the user in reply 178273383. Small alignment differences remain, especially at screen edges/odd camera angles; author explained the overlap tradeoff and user accepted it. The exact initial underground-diamond cause was not reproduced. | Retain as a watch item alongside current sinking/despawn reports; do not assume all underground markers share one cause. No new alignment change is promised. |

The project owner's additional generic sinking/despawn report is still open independently of the above.
Alive engine handles can remain after gameplay removal; filter verified state per category, preserve legitimate
falls and below-zero terrain, and retain confirmed removal by actual unit identity. This audit implements no
new removal heuristic.

## Unanswered or renewed feature/support requests

| Request | Discussion status | Scope recommendation |
| --- | --- | --- |
| JYZJQ, Nov 1, comment 178783788: Mod Dynamic Loader 3 support | No reply visible. This audit has not inspected MDL3 or established compatibility. | Reply with the currently supported Chef requirement; investigate MDL3's actual loader/API contract before any support claim or port. |
| kleecels, Oct 28, comment 178488612: HellForge / Bingus Shared Loader v20 port | No reply visible. Porting or loader coexistence is unverified. | Treat as a separate compatibility project after stability work; do not install or replace the existing loader as part of this audit. |
| Bogdanov89, Oct 28, comment 178417377: called-in Hellbomb markers; BoyoHoban, Oct 29, reply 178562025 expresses interest | Author explained that only map-placed unexploded Hellbombs are supported and invited interest. A subsequent positive response is unanswered. | Optional feature, not a broken existing marker. Discuss whether to add it after stability work. |
| Bogdanov89, Oct 15, comment 177525678: separate range while the map is open | Author rejected it for the old implementation's mission-load-only distance restriction. That explanation predates the current overlay, whose settings now apply during gameplay. | The old technical reason needs re-evaluation if revisiting the idea. Reliable map-open state and controller/remapped input support are unverified; do not silently substitute a raw TAB-held heuristic. |

## Already addressed or deliberately outside scope

- Bogdanov89, Nov 1, 178739220: dropped weapon/gear range. Author replied 178783908 that these are
  unsupported and the own death marker is the recovery aid. This is a feature request, not regression proof.
- Blexiss, Oct 27, 178379430: loader disables addon after crash. User confirmed 2.4.0 restored it in 178387764.
  Keep this separate from the later unresolved random native-crash report.
- Earlier scope/FOV and picked-up codes/delivered SSSD reports were explicitly confirmed fixed in 178273383.
- Close stim opacity, far-sample fade, far size/opacity controls, close-marker toggle and vehicle markers
  have corresponding implemented features and author replies. No additional failure report is visible.
- Icon grouping and medal/super-credit markers were deliberately declined; no reversal is inferred.
- ADS-only teammate nametag hiding was explained as outside this mod's current scope; the requester accepted
  the response. Terminals and weapon inventories were also declined with the requester acknowledging it.
- Old October 20 breakage and Chef support questions have follow-up confirmations. Praise-only comments
  contain no additional issue.

## Suggested order

Update after owner review: color work is deferred, multiplayer validation awaits comments, and separate
map-open ranges are not planned. Test.10/test.11 address the two selected stability tasks; see
`staged-improvements.md`. Loader and called-in Hellbomb feasibility is recorded in
`loader-and-hellbomb-audit-2026-11-01.md`; no new loader support or target is enabled yet.

1. Complete category-specific sinking/despawn prevention and verify the exact multiplayer own-death case.
2. Resolve the outstanding FRV first-node-lookup promise without losing vehicle destruction behavior;
   validate long-session stability. Prepare a stable release only after the required runtime checks.
3. Verify the small vanilla color difference and track residual overlap alignment as an accepted limitation.
4. Answer MDL3 and HellForge compatibility questions and the renewed Hellbomb request. Prioritize any actual
   port/new feature only after discussion with the project owner; no such change is authorized by this audit.
