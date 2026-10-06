"""Build the v3.0 Arsenal ZIP: one patch holding only the core Lua, no Arsenal options.

Needs only Python 3. Settings live in the in-game Mod Options Menu, so the package has no
option folders. The patch is a one-file Stingray archive written from scratch.
"""
from io import BytesIO
import json
from pathlib import Path
import struct
import zipfile

root = Path(__file__).resolve().parent.parent
work = root / "work"
outputs = root / "outputs"
package = outputs / "Extended_Pickup_Icons_Range_v3.0.zip"
LUA_TYPE = 0xA14E8DFA2CD117E2
CORE_NAME = 0xF4764F94D03A5BB8  # resource hash of mods/codex/pickup_icon_range_test (same as v2.x)


def lua_archive(name_hash, source):
    """A patch archive with one Lua resource: header, one type entry, one file entry, data."""
    body = struct.pack("<II", len(source), 2) + source
    data_offset = (0x48 + 32 + 80 + 15) // 16 * 16
    out = bytearray(data_offset)
    struct.pack_into("<III", out, 0, 0xF0000011, 1, 1)
    struct.pack_into("<QQQII", out, 0x48, 0, LUA_TYPE, 1, 16, 16)
    struct.pack_into("<QQQQQQQIIIIII", out, 0x68, name_hash, LUA_TYPE, data_offset, 0, 0, 0, 0,
                     len(body), 0, 0, 16, 16, 0)
    out += body
    out += b"\0" * (-len(out) % 16)
    struct.pack_into("<I", out, 0x20, len(out))
    return bytes(out)


if __name__ == "__main__":
    with zipfile.ZipFile(outputs / "Extended_Pickup_Icons_Range_v2.5.zip") as source:
        v25 = {name: source.read(name) for name in source.namelist()}
    stem = "9ba626afa44a3aa3.patch_0"
    files = {
        stem: lua_archive(CORE_NAME, (work / "extended_pickup_icons_v30.lua").read_bytes()),
        stem + ".stream": b"",
        stem + ".gpu_resources": b"",
        "icon.png": v25["icon.png"],
    }
    manifest = json.loads(v25["manifest.json"])
    manifest["Description"] = ("Longer-range vanilla pickup icons for samples, supplies and equipment. "
                               "Set each distance (default to 100) and switch in game on the Escape menu's MODS tab. "
                               "Needs Bingus Shared Loader v15+; Mod Options Menu recommended.")
    del manifest["Options"]
    files["manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")
    for output_name, zip_name in (
        ("README_v30_KO.md", "README_KO.md"),
        ("PUBLISH_NEXUS_v30.md", "PUBLISH_NEXUS.md"),
    ):
        files[zip_name] = (outputs / output_name).read_bytes()

    buffer = BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in sorted(files.items()):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, data)
    package.write_bytes(buffer.getvalue())
    print(package)
