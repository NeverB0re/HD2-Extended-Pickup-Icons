"""Build the v2.5 Arsenal ZIP from the v2.4 release ZIP by replacing only the shared core Lua.

Needs only Python 3. The option scripts, archive layout, icon and file names are reused from
the v2.4 package; the core script entry, the patch size fields, manifest and documents change.
"""
from io import BytesIO
import json
from pathlib import Path
import struct
import zipfile

root = Path(__file__).resolve().parent.parent
work = root / "work"
outputs = root / "outputs"
template = outputs / "Extended_Pickup_Icons_Range_v2.4_build25480438.zip"
package = outputs / "Extended_Pickup_Icons_Range_v2.5.zip"
core = (work / "extended_pickup_icons_v25.lua").read_bytes()


def replace_core(patch):
    data = bytearray(patch)
    assert struct.unpack_from("<III", data) == (0xF0000011, 1, 2), "unexpected patch header"
    for entry in (0x68, 0x68 + 80):
        offset = struct.unpack_from("<Q", data, entry + 16)[0]
        if data[offset + 8:offset + 55] == b"-- HD2-Addon: mods/codex/pickup_icon_range_test":
            break
    else:
        raise AssertionError("core script entry not found")
    assert entry == 0x68 + 80, "core script must be the last entry"
    body = struct.pack("<II", len(core), 2) + core
    out = data[:offset] + body
    out += b"\0" * (-len(out) % 16)
    struct.pack_into("<I", out, entry + 56, len(body))
    struct.pack_into("<I", out, 0x20, len(out))
    return bytes(out)


with zipfile.ZipFile(template) as source:
    files = {name: source.read(name) for name in source.namelist()}

for number, folder in enumerate(("Samples", "Supplies", "Equipment"), 1):
    path = f"{folder}/9ba626afa44a3aa3.patch_{number}"
    files[path] = replace_core(files[path])

manifest = json.loads(files["manifest.json"])
manifest["Description"] = manifest["Description"].replace(
    "Build 25480438;", "Verified on build 25480438;")
files["manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")
for output_name, zip_name in (
    ("README_v25_KO.md", "README_KO.md"),
    ("PUBLISH_GALLERY_v25_KO.md", "PUBLISH_GALLERY_KO.md"),
    ("PUBLISH_NEXUS_v25_EN.md", "PUBLISH_NEXUS_EN.md"),
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
