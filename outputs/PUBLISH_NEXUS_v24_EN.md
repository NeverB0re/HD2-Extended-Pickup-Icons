# Title

Extended Pickup Icons Range

# Short description

Extend the game's existing pickup icons with three independent Arsenal toggles. No beams or glowing item textures.

# Description

Extended Pickup Icons Range adjusts the visibility range of vanilla in-world item icons while leaving pickup distance unchanged. Arsenal provides three independent options:

- **Samples:** common, rare, super, packaged and intel samples — internal `ViewDistance` **35**.
- **Supplies:** ammo boxes, grenade packs, stims and resupply packs — internal `ViewDistance` **20**. Stims use their existing ping icon as an automatic item marker.
- **Equipment & Mission Items:** support weapons, backpacks, dropped sample containers and most mission carryables — internal `ViewDistance` **35**. Six SEAF artillery shell variants, identified carry-ammo and the carried warhead use **15**. Ordinary primary firearms are excluded.

Version 2.4 uses fixed internal values instead of multiplying each item's original value. Both backpack zones receive 35. The ordinary explosive `habs_barrel_fuel` and `il_canister` are no longer patched. The existing `seaf_shell`, `seaf_gun_ammo`, `cy_orbital_cannon_ammo_carry` and `warhead_01` records receive 15. Version 2.3 missed the six separate SEAF artillery shell variant records, leaving their values at 35. Version 2.4 identifies them by their UnitComponent paths and changes regular, high-yield, mini-nuke, napalm, smoke and static-field shells to 15. Fifty-seven ordinary `primary_weapons` resources are no longer patched. Five unidentified single-zone dropped weapons are also excluded conservatively because they could be primary firearms. Stalwart remains because it is a support weapon despite its internal `primary_weapons/lmg_stalwart` path. Identified sidearms and melee weapons remain included. A separately loaded resupply-pickup unit and both `supply_box` zones receive 20 when Supplies is enabled.

The values 15, 20 and 35 are **game data settings, not guaranteed HUD measurements in metres**. The distance where an icon fades in or becomes fully visible may vary with the item and game UI rules. The on-screen result of the v2.4 SEAF correction awaits in-game verification. Pickup `Radius`, interaction type, icon textures and item models remain unchanged.

## Requirements and installation

- HELLDIVERS 2 Steam build **25480438**
- [Bingus Shared Loader](https://github.com/CowboyBingus/BingusSharedLoader) **v15 or newer**
- Arsenal or another manager that supports manifest V1 include-folder options

Import this ZIP directly, enable Bingus Shared Loader, select any combination of the three options, then Purge and Deploy. Disable or replace earlier Extended/Lore Friendly Pickup Icons versions and fully restart the game after changing options. If the game window has closed but `helldivers2.exe` remains in Task Manager, end that stale process before redeploying.

The addon checks the executable and game.dll fingerprints, loaded data tables, targeted records and memory protection before writing. It fails closed on a mismatch and rolls back failed writes. All eight option combinations were tested against synthetic copies of the verified build's data. The v2.3 addon applied in game; the v2.4 SEAF shell distance still requires live verification.

Log: `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\CodexPickupIconRangeTest.log`  
Source format reference: [Filediver InteractableComponent](https://github.com/xypwn/filediver/blob/master/datalibrary/interactable_component.go)
