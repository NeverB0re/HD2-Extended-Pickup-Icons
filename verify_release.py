"""Verify the archived release without game files or third-party libraries."""
from collections import Counter
from pathlib import Path
import hashlib, json, struct, zipfile
root = Path(__file__).resolve().parent
sums = dict(reversed(line.split()) for line in (root / 'SHA256SUMS.txt').read_text().splitlines() if line.strip())
for name, digest in sums.items():
    assert hashlib.sha256((root / name).read_bytes()).hexdigest() == digest, 'Release checksum mismatch: '+name
package = root / 'outputs/Extended_Pickup_Icons_Range_v3.0.zip'
rows = json.loads((root / 'work/release_v24_verified_targets.json').read_text())
assert Counter(x['feature'] for x in rows) == {'samples':30,'supplies':8,'equipment':213}
assert Counter(x['view_after'] for x in rows) == {35.0:233,20.0:8,15.0:10}
assert len({(x['resource'],x['zone']) for x in rows}) == 251
core = (root/'work/extended_pickup_icons_v30.lua').read_bytes()
assert core.count(b"\n    {name='") == 251, 'core target table must list 251 zones'
with zipfile.ZipFile(package) as z:
    assert z.testzip() is None
    manifest = json.loads(z.read('manifest.json'))
    assert manifest['Version'] == 1 and 'Options' not in manifest
    stem = '9ba626afa44a3aa3.patch_0'
    assert set(z.namelist()) == {'manifest.json','icon.png','README_KO.md','PUBLISH_NEXUS.md',
                                 stem, stem+'.stream', stem+'.gpu_resources'}
    data = z.read(stem)
    assert struct.unpack_from('<III',data) == (0xF0000011,1,1)
    values = struct.unpack_from('<7Q6I',data,104)
    offset, length = values[2], values[7]
    body = data[offset:offset+length]
    source_length, version = struct.unpack_from('<II',body)
    assert version == 2 and source_length == len(body)-8
    assert body[8:] == core, 'Embedded source mismatch'
    assert z.read(stem+'.stream') == z.read(stem+'.gpu_resources') == b''
print('PASS: checksums, exact embedded v3.0 Lua, manifest, 251 targets and ZIP structure')
