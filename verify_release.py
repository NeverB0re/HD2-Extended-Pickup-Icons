"""Verify the archived release without game files or third-party libraries."""
from collections import Counter
from pathlib import Path
import hashlib, json, struct, zipfile
root = Path(__file__).resolve().parent
package = root / 'outputs/Extended_Pickup_Icons_Range_v2.4_build25480438.zip'
expected = (root / 'SHA256SUMS.txt').read_text().split()[0]
assert hashlib.sha256(package.read_bytes()).hexdigest() == expected, 'Release checksum mismatch'
rows = json.loads((root / 'work/release_v24_verified_targets.json').read_text())
assert Counter(x['feature'] for x in rows) == {'samples':30,'supplies':8,'equipment':213}
assert Counter(x['view_after'] for x in rows) == {35.0:233,20.0:8,15.0:10}
assert len({(x['resource'],x['zone']) for x in rows}) == 251
with zipfile.ZipFile(package) as z:
    assert z.testzip() is None
    manifest = json.loads(z.read('manifest.json'))
    assert manifest['Version'] == 1 and len(manifest['Options']) == 3
    expected_names = {'manifest.json','icon.png','README_KO.md','PUBLISH_GALLERY_KO.md','PUBLISH_NEXUS_EN.md'}
    for number, folder in enumerate(('Samples','Supplies','Equipment'), 1):
        stem = f'{folder}/9ba626afa44a3aa3.patch_{number}'
        expected_names.update((stem,stem+'.stream',stem+'.gpu_resources'))
        data = z.read(stem)
        assert struct.unpack_from('<III',data) == (0xF0000011,1,2)
        embedded = []
        for i in range(2):
            values = struct.unpack_from('<7Q6I',data,104+80*i)
            offset, length = values[2], values[7]
            body = data[offset:offset+length]
            source_length, version = struct.unpack_from('<II',body)
            assert version == 2 and source_length == len(body)-8
            embedded.append(body[8:])
        core = (root/'work/extended_pickup_icons_v24.lua').read_bytes()
        option = (root/f'work/extended_pickup_icons_{folder.lower()}.lua').read_bytes()
        assert set(embedded) == {core,option}, f'Embedded source mismatch: {folder}'
        assert z.read(stem+'.stream') == z.read(stem+'.gpu_resources') == b''
    assert set(z.namelist()) == expected_names
print('PASS: checksum, exact embedded Lua, manifest, 251 targets and ZIP structure')
