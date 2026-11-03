# Chef/Boot settings and Arsenal import reports — 2026-11-03

Public mod reviewed: **2.6.1**, SHA-256
`1206cc8dade7d6ac1b6483524df408ec157ca682333046505b368e4d29951335`.
This matches the GitHub release asset's published digest and the local ZIP. The reporter's exact Nexus
download bytes and Arsenal version are unavailable; latest versions are the working assumption.

Local candidate: **2.6.2-test.1**, on `fix-loader-package-2.6.2`. Not published or pushed.

## Report 1: RUN BY BOOT MOD LOADER, no Chef options

**Confirmed addon declaration defect.** The 2.6.1 header does not declare Chef as a requirement. It also
uses upper-case `CHEF` and checks whether its argument is a helper table. Boot 0.13.4's heuristic does
not classify that structure as Chef-only, so it tries to start the addon itself with a resource-name
argument. The addon returns `no Chef Shared Loader`, while Boot has already claimed the name; Chef
does not start it a second time and shows the other-loader status instead of native settings.

The exact **Boot 0.13.4** classifier, extracted from the author's tagged source, returns:

| Source | Classified for Chef |
| --- | --- |
| Public 2.6.1 inlined Lua | false |
| Same Lua with explicit Chef requirement | true |

The fix adds, immediately after `HD2-Addon`:

```lua
-- HD2-Requires: chef-shared-loader >= 1.4.0
```

NarrowHUD **2.2.0** already has the equivalent declaration (minimum 1.2.3). Its different behavior is
consistent with the actual loader rule; it does not imply that users must never install Chef and Boot
together. Boot's README explicitly documents hosting Chef and handing Chef-only addons to it. Chef's
own documentation describes the same handoff. This is a specific supported arrangement with Boot's
`boot` active; it is not a guarantee for arbitrary deployment orders or every other loader.

The candidate's inlined Lua is identical to 2.6.1 after removing only this new header and restoring the
version string. No gameplay, timing, graphics, settings IDs, resource identity or manifest GUID changes.
The three regression cases use the real MIT-licensed Boot classifier and a simulated Chef helper table,
including saved native settings. Full dual-loader gameplay/menu rendering is still unverified.

Sources:

- [Boot 0.13.4 README](https://github.com/pat-pat-patrick/boot-mod-loader/blob/v0.13.4/README.md#other-loaders-and-boots)
- [Boot classifier](https://github.com/pat-pat-patrick/boot-mod-loader/blob/v0.13.4/src/boot_mod_loader.lua)
- [Chef 1.5.1 handoff contract](https://github.com/Th3chef/Chef-Shared-Loader/blob/v1.5.1/docs/MODDING.md#for-other-loaders)
- [NarrowHUD 2.2.0 header](https://github.com/luka189/NarrowHUD/blob/v2.2.0/src/narrowhud.lua)

## Report 2: Arsenal says imported 1/1 but no mod is shown

**No invalid ZIP/manifest reproduced; a matching Library/profile path was found.** Public 2.6.1 has a
valid V1 manifest, UUID, option include `Addon`, matching case/relative paths, root icon and patch data.
Missing explicit ZIP directory records do not violate the contract: the actual import code validates
the extracted filesystem. There is no evidence for changing the GUID, flattening options or rebuilding
the archive with arbitrary folder entries as a fix.

The latest official Arsenal release checked is **0.37.2**. Its installer was downloaded only into a
temporary directory, never installed or run. The embedded application archive and selected JavaScript
import functions were inspected. Installer SHA-256:
`8b29f9a75e171a6b3059b0e4f673c12e099d09bfe349b5dcb5e70736ecbdcc57`, matching the release asset.

Selected actual metadata/list import functions were run against temporary extractions of our public ZIP:

| Controlled scenario | Library entries | Profile entries | Result |
| --- | ---: | ---: | --- |
| Empty Library and empty profile | 1 | 1 | Proper UUID, name and Addon option registered |
| Same ZIP already in shared Library; new empty profile | 1 | 0 | Existing content replaced successfully, profile insertion never called |

The identical-content replacement branch calls the reimport helper, but that helper returns immediately
when old and new UUIDs are equal. The existing-UUID branch similarly refreshes the Library without
inserting the item into the new target profile. The surrounding archive-import handler can still count
the import as successful. This can explain why a new **profile** does not resolve the report: profiles
share the same Library. It does not prove this is the reporter's exact situation, particularly if the mod
is genuinely absent from the Library too.

Scope: the functions controlling metadata, content hash and list membership were actual extracted
functions. Icon processing, database/header scanning, old-folder deletion and exact profile placement
were stubbed; Electron UI, extraction executable, persistence and deployment were not run. No user
Arsenal data or game install was read or modified by the probe. Proprietary application code is retained
only in local research, not in this repository or player packages. Large installer/application downloads
and fixture directories were removed automatically after inspection.

### Minimal support step

Ask the reporter to open **Library**, clear search/tag filters, and search for the name or UUID:

`453493d3-ffa7-4148-9b30-d6e4ab32b9d1`

If found, use **Add to Profiles**, or in the target profile **Add Mod → select existing mods from your
library**. Reimporting the same ZIP may only refresh the existing Library entry. Do not tell the user to
delete profiles, saved settings, the entire Library, or assign this mod a new GUID.

If absent from Library as well, the reproduced replacement path does not explain it. Obtain the actual
Arsenal version and import error/log details before claiming an importer fix or a packaging diagnosis.
The mod's manifest/archive structure is intentionally unchanged in this candidate.

Sources:

- [Arsenal 0.37.2 release](https://github.com/Orbit-Studios/hd2arsenal-release/releases/tag/v0.37.2)
- [Official V1 manifest contract](https://docs.rsnl.gg/mod-builder/manifest)
- [Library and profiles](https://docs.rsnl.gg/mod-management)
- [Adding/importing mods](https://docs.rsnl.gg/mod-management/adding-mods)

## Verification and next step

**238 tests pass**, including three real-Boot-classifier cases and four independent packaging-contract
cases. The test ZIP passes current-source, Lua 5.1, manifest/GUID, all 144 texture assets, removed-debug
code and explicit early Chef dependency checks. No textures or manifest identity changed from 2.6.1.

Have the first reporter confirm that Chef's F9 options appear under the documented Boot+Chef setup
with the test ZIP. This does not require changing the owner's current loader installation. Keep the
candidate local until that execution path is verified; do not present the Arsenal case as fixed by it.
