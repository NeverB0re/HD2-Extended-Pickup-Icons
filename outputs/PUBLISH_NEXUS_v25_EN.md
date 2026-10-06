# Title

Extended Pickup Icons Range

# Short description

Extend the game's existing pickup icons with three independent Arsenal toggles. No beams or glowing item textures.

# Description

Extended Pickup Icons Range adjusts the visibility range of vanilla in-world item icons while leaving pickup distance unchanged. Arsenal provides three independent options:

- **Samples:** common, rare, super, packaged and intel samples — internal `ViewDistance` **35**.
- **Supplies:** ammo boxes, grenade packs, stims and resupply packs — internal `ViewDistance` **20**. Stims use their existing ping icon as an automatic item marker.
- **Equipment & Mission Items:** support weapons, backpacks, dropped sample containers and most mission carryables — internal `ViewDistance` **35**. Six SEAF artillery shell variants, identified carry-ammo and the carried warhead use **15**. Ordinary primary firearms are excluded.

## What's new in 2.5

- **Survives more game updates.** The mod no longer locks itself to one exact game version. It finds each item by its ID, so small game patches should not break it.
- **Plays nicer with other mods.** If another mod or a game update has changed an item, only that item is skipped. The rest of the mod still works.
- **Options no longer affect each other.** A problem with the stim marker no longer turns off Samples or Equipment.
- **Smoother startup.** The large file check at game start is gone, and the data search is spread over the loading screen.
- **Same icons, same distances.** Nothing changes in what you see compared with 2.4.

Version 2.4 uses fixed internal values instead of multiplying each item's original value. Both backpack zones receive 35. The ordinary explosive `habs_barrel_fuel` and `il_canister` are no longer patched. The existing `seaf_shell`, `seaf_gun_ammo`, `cy_orbital_cannon_ammo_carry` and `warhead_01` records receive 15. Version 2.3 missed the six separate SEAF artillery shell variant records, leaving their values at 35. Version 2.4 identifies them by their UnitComponent paths and changes regular, high-yield, mini-nuke, napalm, smoke and static-field shells to 15. Fifty-seven ordinary `primary_weapons` resources are no longer patched. Five unidentified single-zone dropped weapons are also excluded conservatively because they could be primary firearms. Stalwart remains because it is a support weapon despite its internal `primary_weapons/lmg_stalwart` path. Identified sidearms and melee weapons remain included. A separately loaded resupply-pickup unit and both `supply_box` zones receive 20 when Supplies is enabled.

The values 15, 20 and 35 are **game data settings, not guaranteed HUD measurements in metres**. The distance where an icon fades in or becomes fully visible may vary with the item and game UI rules. The on-screen result of the v2.4 SEAF correction awaits in-game verification. Pickup `Radius`, interaction type, icon textures and item models remain unchanged.

## Requirements and installation

- HELLDIVERS 2 (tested on Steam build **25480438**)
- [Bingus Shared Loader](https://github.com/CowboyBingus/BingusSharedLoader) **v15 or newer**
- Arsenal or another manager that supports manifest V1 include-folder options

Import this ZIP directly, enable Bingus Shared Loader, select any combination of the three options, then Purge and Deploy. Disable or replace earlier Extended/Lore Friendly Pickup Icons versions and fully restart the game after changing options. If the game window has closed but `helldivers2.exe` remains in Task Manager, end that stale process before redeploying.

Before changing an item, the mod checks that it still has the original game value. Anything that does not match is left alone and listed in the log. If a write fails, the mod puts the original value back. Version 2.5 applied all 251 items in game on build 25480438. The on-screen distance of SEAF shells still needs in-game confirmation.

**After a big game update:** open the log below. If it says `skipped 0 unmatched`, everything applied. If many items are listed as skipped, that update changed them and the mod needs an update.

Log: `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\CodexPickupIconRangeTest.log`  
Source format reference: [Filediver InteractableComponent](https://github.com/xypwn/filediver/blob/master/datalibrary/interactable_component.go)
