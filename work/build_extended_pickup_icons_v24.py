"""Build one Arsenal mod ZIP with three independent feature options."""
from io import BytesIO
import json
from pathlib import Path
import struct
import sys
import zipfile

root = Path(__file__).resolve().parent.parent
work = root / "work"
outputs = root / "outputs"
sys.path.insert(0, str(work / "vendor" / "BingusSharedLoader-main" / "scripts"))
from archive import ARCHIVE, make_archive, resource_hash
from build_addon import entry_source

family = ARCHIVE.split(".patch_")[0]
options = (
    ("Samples", 1, "mods/codex/pickup_icon_range_samples", "extended_pickup_icons_samples.lua"),
    ("Supplies", 2, "mods/codex/pickup_icon_range_supplies", "extended_pickup_icons_supplies.lua"),
    ("Equipment", 3, "mods/codex/pickup_icon_range_equipment", "extended_pickup_icons_equipment.lua"),
)
core_name = "mods/codex/pickup_icon_range_test"
core_source = entry_source(core_name, (work / "extended_pickup_icons_v24.lua").read_bytes())
core_body = struct.pack("<II", len(core_source), 2) + core_source

files = {}
for folder, number, resource_name, script_name in options:
    source = entry_source(resource_name, (work / script_name).read_bytes())
    body = struct.pack("<II", len(source), 2) + source
    archive = make_archive({resource_hash(core_name): core_body,
                            resource_hash(resource_name): body})
    stem = f"{family}.patch_{number}"
    path = f"{folder}/{stem}"
    files[path] = archive
    files[path + ".stream"] = b""
    files[path + ".gpu_resources"] = b""

manifest = {
    "Version": 1,
    "Guid": "453493d3-ffa7-4148-9b30-d6e4ab32b9d1",
    "Name": "Extended Pickup Icons Range",
    "Description": "Vanilla pickup icons: internal ViewDistance 35 for samples/gear, 20 for supplies, 15 for carry-ammo/warhead/SEAF shells. Build 25480438; Bingus Shared Loader v15+ required.",
    "IconPath": "icon.png",
    "Options": [
        {"Name": "Samples", "Description": "Common, rare, super and packaged samples: internal ViewDistance 35.", "Include": ["Samples"]},
        {"Name": "Supplies", "Description": "Ammo, stims, grenade boxes and resupply packs: internal ViewDistance 20.", "Include": ["Supplies"]},
        {"Name": "Equipment & Mission Items", "Description": "Non-primary weapons/backpacks: 35; carry-ammo, warhead and SEAF shells: 15; ordinary barrel/canister unchanged.", "Include": ["Equipment"]},
    ],
}
files["manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")
files["icon.png"] = (outputs / "Extended_Pickup_Icons_thumbnail.png").read_bytes()
for output_name, zip_name in (
    ("README_v24_KO.md", "README_KO.md"),
    ("PUBLISH_GALLERY_v24_KO.md", "PUBLISH_GALLERY_KO.md"),
    ("PUBLISH_NEXUS_v24_EN.md", "PUBLISH_NEXUS_EN.md"),
):
    files[zip_name] = (outputs / output_name).read_bytes()

package = outputs / "Extended_Pickup_Icons_Range_v2.4_build25480438.zip"
buffer = BytesIO()
with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    for name, data in sorted(files.items()):
        info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = 0o100644 << 16
        archive.writestr(info, data)
package.write_bytes(buffer.getvalue())
print(package)
