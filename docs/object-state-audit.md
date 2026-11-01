# Vehicle and carryable network-state audit — 2026-11-01

The installed Steam manifest reports build 26251122. Filediver extracted `generated.network_config`
into the workspace research folder; its main-part SHA-256 is
`1c49360016a54b682cc3604a9fb10aef4d97a189529a4c485d92454102ffebed`.
The parsed contiguous type block contains 1884 records, offsets `0x52b42..0xb6da2`.
These are observations of the extracted installation, not a claim that all fields have been interpreted.

| Field | Thin hash | Number of declaring types |
| --- | --- | ---: |
| health | cb0453ea | 45 |
| destroyed | 42f29da2 | 11 |
| carry-state field used by NarrowHUD | 788b9753 | 562 |
| owner field used by NarrowHUD | 3ccffa7f | 550 |

References: Filediver (<https://github.com/xypwn/filediver>); network record layout and known field roles
described by NarrowHUD's tools at commit `597968c2b9e556812e0376b8a6627926df1f2524`:
<https://github.com/luka189/NarrowHUD/blob/597968c2b9e556812e0376b8a6627926df1f2524/tools/parse_netcfg.py>,
<https://github.com/luka189/NarrowHUD/blob/597968c2b9e556812e0376b8a6627926df1f2524/tools/make_data.py>.

FRV, SSSD (`carry_data`) and regular SEAF-shell unit model metadata were extracted and compared. The
network type ids do not occur directly as aligned values in those model files. The installation's 307
exported entity resources were also checked without establishing a specific unit-to-network-type binding.
No game files were edited, and extracted game data is not included in the mod repository/package.

Consequently a generic field named `health`, `destroyed`, `owner` or `carry` is not enough evidence to
replace this mod's vehicle/mission-item decisions. In particular, network ownership does not prove
occupancy, and a field value must not be interpreted using weapon-specific carry rules for every item.

## Applied and gated work

- Applied: exact vehicle-unit identity for frame-to-frame history. Nearby or crossing vehicles must not
  exchange destroyed/weapon-offset/parked state.
- Preserved: same-frame discovery of vehicles, weapons and wrecks; existing gun-loss and wreck detection.
- Preserved: carried-item, drop-off/rack and picked-up-code heuristics, including all target types.
- Gated: direct vehicle health/occupant and mission-item carry/delivery reads. Before enabling one, establish
  the exact unit → game-object → type binding, validate its declared fields on the running build, and observe
  the relevant transitions (alive/destroyed, boarded/empty, held/dropped/delivered) with known gameplay state.

The local-avatar unit mapping used for the vehicle-death position fix is an exact mapping of an already
typed and owned player/avatar object. It does not require interpreting an unknown vehicle/item type.

This investigation supports retaining the existing behavior for unverified states. It does not establish
that the game lacks those states or that further investigation is impossible.
