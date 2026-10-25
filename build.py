"""Build Extended Pickup Icons Range (Pickup Dots) into a mod zip (Modocracy, HD2 Arsenal, HD2MM).

    python build.py            -> dist/Extended Pickup Icons Range v<version>.zip (a test version, e.g.
                                  2.1.0-test.1: copy it to test-builds/; a release: to release/)

The mod is one plain-text Lua resource, mods/codex/pickup_dots, in
9ba626afa44a3aa3.patch_0, which Boot Mod Loader finds and starts.
The archive writer below (SCAFFOLD, murmur64, write_module) is taken from
Boot Mod Loader's build.py, https://github.com/pat-pat-patrick/boot-mod-loader (MIT).
"""
import json
import shutil
import os
import re
import struct
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(HERE, "src", "pickup_dots.lua")
TARGETS = os.path.join(HERE, "src", "targets.lua")
ICON = os.path.join(HERE, "src", "icon.png")   # the Nexus mod's icon
DIST = os.path.join(HERE, "dist")
NAME = "Extended Pickup Icons Range"
FOLDER = "Addon"
RESOURCE = "mods/codex/pickup_dots"
LUA_SOURCE_FLAG = 2

SCAFFOLD = bytes.fromhex(
    "110000f0010000000100000000000000ce09f5f4000000006e0b41bab993fecf0040170300000000"
    "00cc5600000000000000000000000000000000000000000000000000000000000000000000000000"
    "e217d12cfa8d4ea101000000000000001000000040000000b1d0e27de00d175ce217d12cfa8d4ea1"
    "b8000000000000000000000000000000000000000000000000b000000000000000c1070000000000"
    "f3af00000000000000000000100000004000000001000000")

MANIFEST = {
    "Version": 1,
    "Guid": "453493d3-ffa7-4148-9b30-d6e4ab32b9d1",   # the Nexus mod's own: an update of it, not a new mod
    "Name": NAME,
    "Description": "Shows the game's icons over samples, supplies, mission items and vehicles from farther away. "
                   "Rebuilt to work again after the 2026-10-20 game update. Requires Boot Mod Loader.",
    "IconPath": "icon.png",
    "Options": [{"Name": NAME, "Description": "Requires Boot Mod Loader.", "Include": [FOLDER]}],
}

README = """Extended Pickup Icons Range v{version}
=======================================

See samples, supplies, mission items and vehicles from farther away, marked with the
game's own icons.

What gets a marker (default distance):
- Samples (40 m): common, rare and super samples, sample containers, Terminid eggs.
- Supplies (25 m): ammo boxes, grenade boxes, stims and resupply pod crates.
- Mission items (40 m): SSSDs, data drives, black boxes, larva containers, launch codes,
  keycards, video cameras and more.
- Shells, warheads and batteries you carry (25 m).
- Drop-off points and cargo containers (40 m), and valves and cranks you turn (40 m).
- Vehicles (100 m): exosuits, FRVs and tanks.
- Mission terminals (40 m): off by default; turn on in the settings.

Markers get a little smaller farther away and hide while a menu is open. Items someone is
carrying, and the vehicle you or a teammate are driving, get no marker. Items close enough
for the game to show its own icon get none either: samples within 9 m (Terminid eggs and
Automaton super samples 20 m, sample containers 15 m) and ammo and grenade boxes within
4 m. Stims have no icon of the game's and keep theirs.

Settings: turn each kind on or off and set its distance with HD2 Mod Setting GUI
(Nexus mod 17756). It can also keep markers on up close, and change their smallest size,
and opacity, and fade them with distance (on by default).
Without it, the defaults above are used.

Requires Boot Mod Loader (Nexus mod 17754). In your mod manager's load order, Boot Mod
Loader must be above this mod (Arsenal may put it below by default: move it up).

Good to know:
- Drop-off points and valves stay marked after you use them.
- Destroyed exosuits and FRVs lose their marker. Destroyed tanks and supply FRVs keep it
  until the wreck disappears from the map.
- While aiming down sights, markers may sit slightly off the item.
"""


def murmur64(data, seed=0):
    """MurmurHash64A, as the engine names resources."""
    m, r, mask = 0xc6a4a7935bd1e995, 47, 0xFFFFFFFFFFFFFFFF
    h = (seed ^ (len(data) * m)) & mask
    whole = len(data) - len(data) % 8
    for at in range(0, whole, 8):
        k = int.from_bytes(data[at:at + 8], "little")
        k = (k * m) & mask
        k ^= k >> r
        k = (k * m) & mask
        h = ((h ^ k) * m) & mask
    tail = data[whole:]
    if tail:
        h ^= int.from_bytes(tail, "little")
        h = (h * m) & mask
    h ^= h >> r
    h = (h * m) & mask
    h ^= h >> r
    return h


LUA_TYPE = murmur64(b"lua")


def write_module(out_dir, resource_name, source, flag=LUA_SOURCE_FLAG, archive="9ba626afa44a3aa3.patch_0"):
    """One Lua resource as a patch archive (plus its empty .gpu_resources and .stream)."""
    encoded = source if isinstance(source, bytes) else source.encode("utf-8")
    payload = struct.pack("<2I", len(encoded), flag) + encoded
    out = bytearray(SCAFFOLD)
    row = 0x48 + 32
    struct.pack_into("<3Q", out, row, murmur64(resource_name.encode("utf-8")), LUA_TYPE, len(SCAFFOLD))
    struct.pack_into("<I", out, row + 56, len(payload))
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, archive)
    with open(path, "wb") as f:
        f.write(bytes(out) + payload)
    open(path + ".gpu_resources", "wb").close()
    open(path + ".stream", "wb").close()
    return path


def built_source():
    """The mod's Lua with the target table put in its "@TARGETS@" slot, checked for Lua 5.1."""
    with open(SOURCE, encoding="utf-8") as f:
        source = f.read()
    with open(TARGETS, encoding="utf-8") as f:
        targets = f.read()
    if source.count('"@TARGETS@"') != 1:
        raise SystemExit("pickup_dots.lua has no single \"@TARGETS@\" slot")
    if not source.startswith("-- HD2-Addon: " + RESOURCE + "\n"):
        raise SystemExit("the first line must declare " + RESOURCE)
    source = source.replace('"@TARGETS@"', "(function()\n" + targets + "end)()")
    for banned in ("require('ffi')", 'require("ffi")', "ffi.", "bit.", "jit.", "popen", "os.execute", "goto "):
        if banned in source:
            raise SystemExit("the mod names %r" % banned)
    if any(ord(ch) > 127 for ch in source.splitlines()[0]):
        raise SystemExit("keep the HD2-Addon declaration line ASCII")
    return source


def version_of(source):
    match = re.search(r"local VERSION = '([0-9A-Za-z.-]+)'", source)
    if not match:
        raise SystemExit("no VERSION in pickup_dots.lua")
    return match.group(1)


def build():
    source = built_source()
    version = version_of(source)
    out_dir = os.path.join(DIST, "%s v%s" % (NAME, version))
    if os.path.exists(out_dir):
        raise SystemExit("%s exists: bump VERSION or delete it" % out_dir)
    write_module(os.path.join(out_dir, FOLDER), RESOURCE, source)
    with open(os.path.join(out_dir, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(MANIFEST, f, indent=2, ensure_ascii=False)
        f.write("\n")
    with open(os.path.join(out_dir, "README.txt"), "w", encoding="utf-8", newline="\r\n") as f:
        f.write(README.format(version=version))
    shutil.copyfile(ICON, os.path.join(out_dir, "icon.png"))
    zip_path = out_dir + ".zip"
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
        for base, _dirs, files in os.walk(out_dir):
            for name in sorted(files):
                full = os.path.join(base, name)
                z.write(full, os.path.relpath(full, out_dir))
    print("wrote %s" % zip_path)


if __name__ == "__main__":
    sys.exit(build())
