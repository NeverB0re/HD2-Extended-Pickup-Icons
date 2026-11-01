"""Validate the actual player ZIP against source and the previous public icon assets.

Requires lupa for Lua 5.1 compilation. This checks packaging, not live gameplay or F9 rendering.
Run from the repository root: python -B tools/verify_release.py <zip>
"""
import hashlib
import json
from pathlib import Path
import re
import struct
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import build
from lupa.lua51 import LuaRuntime


def archive_rows(z):
    data = z.read('Addon/9ba626afa44a3aa3.patch_0')
    magic, kinds, count = struct.unpack_from('<3I', data)
    assert magic == 0xF0000011
    offset = 0x48 + kinds * 32
    assert offset + count * 80 <= len(data)
    rows = [struct.unpack_from('<7Q6I', data, offset + i * 80) for i in range(count)]
    assert len({(r[0], r[1]) for r in rows}) == count
    for r in rows:
        assert r[2] + r[7] <= len(data)
    return data, rows


def textures(data, rows, renamed=None):
    # The Lua body changes the following metadata offsets; all other fields and bytes stay identical.
    return {(renamed or {}).get(r[0], r[0]): (r[1:2] + r[3:], data[r[2]:r[2] + r[7]])
            for r in rows if r[1] == build.TEXTURE_TYPE}


def verify(path):
    path = Path(path).resolve()
    baseline = ROOT / 'release/Extended Pickup Icons Range v2.5.0.zip'
    icon_assets, build.ICON_TABLE = build.icon_textures()
    expected = build.built_source().encode('utf-8')
    version = build.version_of(expected.decode('utf-8'))
    assert re.fullmatch(r'\d+\.\d+\.\d+', version), 'Not a release version'
    with zipfile.ZipFile(path) as z, zipfile.ZipFile(baseline) as old:
        assert z.testzip() is None
        assert set(z.namelist()) == {
            'manifest.json', 'README.txt', 'icon.png', 'Addon/9ba626afa44a3aa3.patch_0',
            'Addon/9ba626afa44a3aa3.patch_0.gpu_resources', 'Addon/9ba626afa44a3aa3.patch_0.stream',
        }, 'Unexpected player ZIP contents'
        data, rows = archive_rows(z)
        old_data, old_rows = archive_rows(old)
        assert len(rows) == 136
        assert all(r[1] in (build.LUA_TYPE, build.TEXTURE_TYPE) for r in rows)
        lua_rows = [r for r in rows if r[1] == build.LUA_TYPE]
        assert len(lua_rows) == 1
        row = lua_rows[0]
        size, flag = struct.unpack_from('<2I', data, row[2])
        source = data[row[2] + 8:row[2] + 8 + size]
        assert flag == 2 and row[7] == size + 8 and source == expected
        assert source.startswith(('-- HD2-Addon: ' + build.RESOURCE + '\n').encode('ascii'))
        assert row[0] == build.murmur64(build.RESOURCE.encode('ascii'))
        assert not re.search(rb'"@[A-Z_]+@"', source)
        for removed in (b'position-diagnostic:', b'hellbomb timing:', b'STATUS_EVERY_S', b'function P.diagnostics'):
            assert removed not in source, removed
        assert len(textures(data, rows)) == 135
        old_lua = next(r for r in old_rows if r[1] == build.LUA_TYPE)
        old_source = old_data[old_lua[2] + 8:old_lua[2] + old_lua[7]]
        old_resource = re.match(rb'-- HD2-Addon: ([^\r\n]+)', old_source)[1].decode('ascii')
        # 2.5.0 used pickup_dots; texture IDs changed with the addon rename in the tested builds.
        rename = {build.murmur64(name.replace(build.RESOURCE, old_resource, 1).encode('ascii')):
                  build.murmur64(name.encode('ascii')) for name, *_ in icon_assets}
        assert {r[0] for r in rows if r[1] == build.TEXTURE_TYPE} == set(rename.values())
        assert set(textures(old_data, old_rows)) == set(rename)
        assert textures(data, rows) == textures(old_data, old_rows, rename)
        for suffix in ('.gpu_resources', '.stream'):
            name = 'Addon/9ba626afa44a3aa3.patch_0' + suffix
            assert z.read(name) == old.read(name), name
        assert z.read('icon.png') == old.read('icon.png')
        manifest = json.loads(z.read('manifest.json'))
        assert manifest == build.MANIFEST
        assert manifest['Guid'] == json.loads(old.read('manifest.json'))['Guid']
        readme = z.read('README.txt').decode('utf-8')
        assert readme == build.README.format(version=version).replace('\n', '\r\n')
        assert 'Marker preferences\r\nstart at defaults' in readme
        lua = LuaRuntime(unpack_returned_tuples=True)
        check = lua.eval('function(s) local f,e=loadstring(s); return f~=nil,e end')
        ok, error = check(source.decode('utf-8'))
        assert ok, error
        for arg in (None, build.RESOURCE):
            runtime = LuaRuntime(unpack_returned_tuples=True)
            mod = runtime.execute(source.decode('utf-8'), arg)
            assert mod.status == 'no Chef Shared Loader'
        return dict(version=version, zip=path.name, zip_files=len(z.namelist()), resources=len(rows),
                    textures=135, lua51_compiles=True, embedded_source_matches=True,
                    texture_and_gpu_assets_unchanged=True, manifest_guid_unchanged=True,
                    experimental_measurements_absent=True, sha256=hashlib.sha256(path.read_bytes()).hexdigest())


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('Usage: python -B tools/verify_release.py <player.zip>')
    print(json.dumps(verify(sys.argv[1]), indent=2))
