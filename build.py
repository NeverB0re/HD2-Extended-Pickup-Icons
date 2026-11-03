"""Build Extended Pickup Icons Range into a mod zip (Modocracy, HD2 Arsenal, HD2MM).

    python build.py            -> dist/Extended Pickup Icons Range v<version>.zip (a test version, e.g.
                                  2.1.0-test.1: copy it to test-builds/; a release: to release/)

The mod is one plain-text Lua resource, mods/codex/extended_pickup_icons_range, in
9ba626afa44a3aa3.patch_0, which Chef Shared Loader finds and starts, and (2.4.0) its icons as textures of that patch
(tools/bake_icons.py), which the loader's chef.bitmap draws.
The archive writer below (SCAFFOLD, murmur64, write_module) is taken from
Boot Mod Loader's build.py, https://github.com/pat-pat-patrick/boot-mod-loader (MIT); the texture rows are ours.
"""
import json
import shutil
import os
import re
import struct
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(HERE, "src", "extended_pickup_icons_range.lua")
TARGETS = os.path.join(HERE, "src", "targets.lua")
LOCAL_PLAYER = os.path.join(HERE, "src", "local_player.lua")
HELLBOMB_WARNING = os.path.join(HERE, "src", "hellbomb_warning.lua")
ICON = os.path.join(HERE, "src", "icon.png")   # the Nexus mod's icon
DIST = os.path.join(HERE, "dist")
NAME = "Extended Pickup Icons Range"
FOLDER = "Addon"
RESOURCE = "mods/codex/extended_pickup_icons_range"
LUA_SOURCE_FLAG = 2
ICON_TABLE = "{}"   # the baked icons' Lua table (icon_textures), set by build()

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
                   "Rebuilt to work again after the 2026-10-20 game update. Requires Chef Shared Loader.",
    "IconPath": "icon.png",
    "Options": [{"Name": NAME, "Description": "Requires Chef Shared Loader.", "Include": [FOLDER]}],
}

README = """Extended Pickup Icons Range v{version}
=======================================

See samples, supplies, mission items and vehicles from farther away, using the game's icons.

2.6.2-test.1: declares Chef Shared Loader as a requirement so Boot Mod Loader can hand
this addon to Chef. Gameplay, icon assets, manifest GUID and saved settings are unchanged.

Requires Chef Shared Loader 1.4.0 or newer (Nexus mod 17760); the latest is recommended.
With Chef as your only loader, give it the highest priority. Boot Mod Loader 0.13.4 also
documents a setup where Boot hosts Chef and delegates Chef-only addons. Follow that loader
setup when using both. This is a Chef addon; other loaders need compatible Chef support.
Remove the previous version before importing and deploying this ZIP. Do not run both.

SETTINGS: preferences from 2.6.0 are preserved. Only updates from versions older than
2.6.0 start with default settings after the native Chef backend change. Press F9 and select
Extended Pickup Icons Range. No separate Mod Options Menu mod is required.

What gets a marker (default distance):
- Samples (50 m): common, rare, super, sample containers and Terminid eggs.
- Supplies (25 m): ammo, grenades, stims and resupply crates.
- Mission items (50 m): SSSDs/data, black boxes, larva containers, launch codes/keycards,
  cameras, briefcases, chemical containers, artillery shells, warheads and fusion batteries.
- Objective interactions (50 m): drop-off points, cargo containers, valves and cranks.
- Hellbombs (100 m): damaged map bombs and fixed mission call-ins. Portable backpacks excluded.
- Vehicles (100 m): exosuits, FRV variants and tanks. Off-screen markers have direction arrows.
- Your last death (500 m): a red skull, also with an off-screen arrow, cleared within 4 m.

F9 settings use folded categories: Samples, Supplies, Mission items and objectives,
Hellbombs, Vehicles, Death marker and Common appearance. Open a category to configure
individual type visibility and distance. Master switches keep individual choices intact.
Changing "Set all ... distances (m)" overwrites the type distances in that category.
Sample/supply fading is in its category. Common settings include distance text, opacity,
size at range and hiding our markers where vanilla icons appear. A warning toggle is in
Hellbombs. Older Chef interfaces without headings display the same native options flat;
loaders without the native option API retain only the previous category-level controls.

Mission Hellbomb warning:
- Observes the bomb's activation, rather than local button input.
- Large 15:00 -> 00:00 display in seconds:hundredths, with an accelerating yellow-to-red pulse.
- First observed already active: ARMED, without a guessed new countdown.
- This is a local estimate, not a replicated explosion deadline or hundredth-second accuracy.
  Damage may destroy the bomb earlier. Zero keeps warning until the marker disappears.
- Only fixed mission Hellbombs on the verified game build have this warning. Other builds
  retain ordinary markers. Damaged map bombs and portable backpacks have no countdown.

Behavior and limits:
- At most 40 markers are drawn: your last death first, then vehicles/Hellbombs, then the
  nearest other markers. Markers scale with distance/resolution, follow
  the camera and scopes, and hide in menus. Mission markers are hidden on the ship.
- Near vanilla icons, our markers normally hide: samples 9 m, eggs/Automaton super samples
  20 m, sample containers 15 m, ammo/grenades 4 m. Stims keep their marker, solid within 5 m.
- Carried/delivered items and destroyed vehicles use guarded position/geometry heuristics;
  detection can be imperfect. Deleted units and confirmed vanished geometry are suppressed.
  There is no universal height cutoff for underground targets. Valves/cranks stay marked
  after use. Occupied/moving vehicles are suppressed using nearby-player observations.
- On supported builds, local health reaching zero confirms death. The position is frozen
  from the previously linked own sample container, else a fresh last-known position; it
  does not follow the corpse or container afterward. Missing/ambiguous data is not death.
  Unknown builds retain the earlier camera-based death method. Only the last death is shown.
- Experimental position/timing/statistics logs are removed. Basic support information and
  errors remain in ExtendedPickupIcons.log in Chef's log folder (launches follow one another,
  so one that crashed stays readable). No debug panel, calibration mode or test files are shipped.
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
TEXTURE_TYPE = murmur64(b"texture")
ICONS_PREFIX = RESOURCE + "/icons/"   # a texture's resource name: this, the icon's name and its size


def texture_part(width, height):
    """A texture resource's main part for width x height RGBA8 pixels, one mip, the pixels in .gpu_resources: the
    engine's 192-byte texture header (no streaming), then a DDS header with the DX10 extension (R8G8B8A8_UNORM, 2D)."""
    engine = struct.pack("<III", 0, 0, 0xFFFFFFFF) + bytes(180)
    flags = 0x1 | 0x2 | 0x4 | 0x8 | 0x1000          # caps, height, width, pitch, pixel format
    dds = b"DDS " + struct.pack("<7I", 124, flags, height, width, width * 4, 0, 1) + bytes(44)
    dds += struct.pack("<2I4s5I", 32, 0x4, b"DX10", 0, 0, 0, 0, 0)   # pixel format: FourCC DX10
    dds += struct.pack("<5I", 0x1000, 0, 0, 0, 0)                   # caps: texture
    dds += struct.pack("<5I", 28, 3, 0, 1, 0)                       # DXGI R8G8B8A8_UNORM, a 2D texture, one of it
    return engine + dds


def write_module(out_dir, resource_name, source, flag=LUA_SOURCE_FLAG, archive="9ba626afa44a3aa3.patch_0",
                 textures=()):
    """One Lua resource as a patch archive (plus its .gpu_resources and .stream); textures: (resource name, width,
    height, RGBA8 pixels) after it (write_with_textures). Without textures, the Lua-only archive."""
    encoded = source if isinstance(source, bytes) else source.encode("utf-8")
    payload = struct.pack("<2I", len(encoded), flag) + encoded
    if textures:
        return write_with_textures(out_dir, resource_name, payload, textures, archive)
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


def write_with_textures(out_dir, resource_name, payload, textures, archive):
    """The Lua row as in SCAFFOLD (its header bytes 12..72 too), then a texture type row and a row per texture, their
    pixels in .gpu_resources (64-byte aligned)."""
    n = 1 + len(textures)
    head = struct.pack("<III", 0xF0000011, 2, n) + SCAFFOLD[12:72]
    head += struct.pack("<QQQII", 0, LUA_TYPE, 1, 16, 64)
    head += struct.pack("<QQQII", 0, TEXTURE_TYPE, len(textures), 16, 64)
    cursor = len(head) + 80 * n
    rows, body, gpu = b"", b"", bytearray()
    rows += struct.pack("<7Q6I", murmur64(resource_name.encode("utf-8")), LUA_TYPE, cursor, 0, 0, 0, 0,
                        len(payload), 0, 0, 16, 64, 1)
    body += payload
    cursor += len(payload)
    for k, (name, width, height, pixels) in enumerate(textures, 2):
        pad = -cursor % 16
        body += bytes(pad)
        cursor += pad
        part = texture_part(width, height)
        gpu += bytes(-len(gpu) % 64)
        rows += struct.pack("<7Q6I", murmur64(name.encode("utf-8")), TEXTURE_TYPE, cursor, 0, len(gpu), 0, 0,
                            len(part), 0, len(pixels), 16, 64, k)
        gpu += pixels
        body += part
        cursor += len(part)
    out = head + rows + body
    out += bytes(-len(out) % 16)
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, archive)
    with open(path, "wb") as f:
        f.write(out)
    with open(path + ".gpu_resources", "wb") as f:
        f.write(bytes(gpu))
    open(path + ".stream", "wb").close()
    return path


def icon_textures():
    """The baked icons as textures, and the Lua table the mod reads them from: icon name -> its sizes, smallest first,
    each {size along the longer side, texture id (hex), width, height}."""
    sys.path.insert(0, os.path.join(HERE, "tools"))
    import bake_icons
    textures, table = [], {}
    for name, size, width, height, rgba in bake_icons.baked():
        resource = "%s%s_%d" % (ICONS_PREFIX, name, size)
        textures.append((resource, width, height, rgba))
        table.setdefault(name, []).append("{%d, '%016x', %d, %d}" % (size, murmur64(resource.encode("utf-8")), width, height))
    lua = "{\n" + "".join("    %s = {%s},\n" % (name, ", ".join(rows)) for name, rows in sorted(table.items())) + "}"
    return textures, lua


def built_source():
    """The mod's Lua with the target table put in its "@TARGETS@" slot, checked for Lua 5.1."""
    with open(SOURCE, encoding="utf-8") as f:
        source = f.read()
    with open(TARGETS, encoding="utf-8") as f:
        targets = f.read()
    if source.count('"@TARGETS@"') != 1:
        raise SystemExit("extended_pickup_icons_range.lua has no single \"@TARGETS@\" slot")
    if not source.startswith("-- HD2-Addon: " + RESOURCE + "\n"):
        raise SystemExit("the first line must declare " + RESOURCE)
    source = source.replace('"@TARGETS@"', "(function()\n" + targets + "end)()")
    with open(LOCAL_PLAYER, encoding="utf-8") as f:
        local_player = f.read()
    if source.count('"@LOCAL_PLAYER@"') != 1:
        raise SystemExit("extended_pickup_icons_range.lua has no single local-player slot")
    source = source.replace('"@LOCAL_PLAYER@"', "(function()\n" + local_player + "\nend)()")
    with open(HELLBOMB_WARNING, encoding="utf-8") as f:
        warning = f.read()
    if source.count('"@HELLBOMB_WARNING@"') != 1:
        raise SystemExit("extended_pickup_icons_range.lua has no single Hellbomb warning slot")
    source = source.replace('"@HELLBOMB_WARNING@"', "(function()\n" + warning + "\nend)()")
    with open(os.path.join(HERE, "src", "settings.lua"), encoding="utf-8") as f:
        settings = f.read()
    if source.count('"@SETTINGS@"') != 1:
        raise SystemExit("extended_pickup_icons_range.lua has no single settings slot")
    source = source.replace('"@SETTINGS@"', "(function()\n" + settings + "\nend)()")
    if source.count('"@ICONS@"') != 1:
        raise SystemExit("extended_pickup_icons_range.lua has no single \"@ICONS@\" slot")
    source = source.replace('"@ICONS@"', ICON_TABLE)
    for banned in ("require('ffi')", 'require("ffi")', "ffi.", "bit.", "jit.", "popen", "os.execute", "goto "):
        if banned in source:
            raise SystemExit("the mod names %r" % banned)
    if any(ord(ch) > 127 for ch in source.splitlines()[0]):
        raise SystemExit("keep the HD2-Addon declaration line ASCII")
    return source


def version_of(source):
    match = re.search(r"local VERSION = '([0-9A-Za-z.-]+)'", source)
    if not match:
        raise SystemExit("no VERSION in extended_pickup_icons_range.lua")
    return match.group(1)


def build():
    global ICON_TABLE
    textures, ICON_TABLE = icon_textures()
    source = built_source()
    version = version_of(source)
    out_dir = os.path.join(DIST, "%s v%s" % (NAME, version))
    if os.path.exists(out_dir):
        raise SystemExit("%s exists: bump VERSION or delete it" % out_dir)
    write_module(os.path.join(out_dir, FOLDER), RESOURCE, source, textures=textures)
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
