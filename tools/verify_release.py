"""Validate the actual player ZIP against source and the previous public icon assets.

Requires lupa for Lua 5.1 compilation. This checks packaging, not live gameplay or F9 rendering.
Run from the repository root: python -B tools/verify_release.py <zip>
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import sys
import zipfile
import uuid

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


def textures(z, data, rows):
    # By id: its header and its pixels. (Where they sit changes with the Lua body and the icons before them.)
    gpu = z.read('Addon/9ba626afa44a3aa3.patch_0.gpu_resources')
    assert all(r[4] + r[9] <= len(gpu) for r in rows if r[1] == build.TEXTURE_TYPE)
    return {r[0]: (data[r[2]:r[2] + r[7]], gpu[r[4]:r[4] + r[9]]) for r in rows if r[1] == build.TEXTURE_TYPE}


def validate_manager_manifest(manifest, files):
    """Independent checks against Arsenal's published V1 manifest/path contract."""
    assert manifest.get('Version') == 1, 'Manager manifest Version must be 1'
    uuid.UUID(manifest['Guid'])
    assert isinstance(manifest.get('Name'), str) and manifest['Name'].strip(), 'Missing mod name'
    assert isinstance(manifest.get('Description'), str), 'Missing description string'
    names = set(files)

    def relative(value):
        assert isinstance(value, str) and value, 'Empty manager path'
        assert '\\' not in value and not value.startswith('/') and not value.endswith('/'), 'Use relative / paths'
        assert all(part not in ('', '.', '..') for part in value.split('/')), 'Unsafe relative path'
        assert ':' not in value, 'Absolute manager path'
        return value

    def image(value):
        if value:
            assert relative(value) in names, 'Missing manager image: ' + value

    def option(row):
        assert isinstance(row, dict), 'Invalid option object'
        assert isinstance(row.get('Name'), str) and row['Name'].strip(), 'Missing option name'
        assert isinstance(row.get('Description'), str), 'Missing option description'
        includes = row.get('Include', [])
        assert isinstance(includes, list), 'Include must be a list'
        for value in includes:
            prefix = relative(value) + '/'
            assert any(name.startswith(prefix) for name in names), 'Include folder missing or wrong case: ' + value
        image(row.get('Image'))
        for sub in row.get('SubOptions', []):
            option(sub)

    image(manifest.get('IconPath'))
    assert isinstance(manifest.get('Options', []), list), 'Options must be a list'
    for row in manifest.get('Options', []):
        option(row)
    assert any('.patch_' in name and not name.endswith(('.gpu_resources', '.stream')) for name in names), 'No patch data'


def verify(path, allow_test=False):
    path = Path(path).resolve()
    baseline = ROOT / 'release/Extended Pickup Icons Range v2.6.1.zip'   # the last public one
    icon_assets, build.ICON_TABLE = build.icon_textures()
    expected = build.built_source().encode('utf-8')
    version = build.version_of(expected.decode('utf-8'))
    pattern = r'\d+\.\d+\.\d+(?:-test\.\d+)?' if allow_test else r'\d+\.\d+\.\d+'
    assert re.fullmatch(pattern, version), 'Not a release version; test builds require --allow-test'
    with zipfile.ZipFile(path) as z, zipfile.ZipFile(baseline) as old:
        assert z.testzip() is None
        expected_files = {
            'manifest.json', 'README.txt', 'icon.png', 'Addon/9ba626afa44a3aa3.patch_0',
            'Addon/9ba626afa44a3aa3.patch_0.gpu_resources', 'Addon/9ba626afa44a3aa3.patch_0.stream',
        }
        assert len(z.namelist()) == len(expected_files) and set(z.namelist()) == expected_files, 'Unexpected or duplicate ZIP contents'
        data, rows = archive_rows(z)
        old_data, old_rows = archive_rows(old)
        assert len(rows) == 1 + len(icon_assets)
        assert all(r[1] in (build.LUA_TYPE, build.TEXTURE_TYPE) for r in rows)
        lua_rows = [r for r in rows if r[1] == build.LUA_TYPE]
        assert len(lua_rows) == 1
        row = lua_rows[0]
        size, flag = struct.unpack_from('<2I', data, row[2])
        source = data[row[2] + 8:row[2] + 8 + size]
        assert flag == 2 and row[7] == size + 8 and source == expected
        assert source.startswith(('-- HD2-Addon: ' + build.RESOURCE + '\n').encode('ascii'))
        assert b'\n-- HD2-Requires: chef-shared-loader >= 1.4.0\n' in source[:1200], 'Missing early Chef handoff declaration'
        assert row[0] == build.murmur64(build.RESOURCE.encode('ascii'))
        assert not re.search(rb'"@[A-Z_]+@"', source)
        for removed in (b'position-diagnostic:', b'hellbomb timing:', b'STATUS_EVERY_S', b'function P.diagnostics'):
            assert removed not in source, removed
        now, before = textures(z, data, rows), textures(old, old_data, old_rows)
        assert set(now) == {build.murmur64(name.encode('ascii')) for name, *_ in icon_assets}
        assert all(now.get(k) == v for k, v in before.items()), 'A public icon changed or went'
        new_icons = sorted(name for name, *_ in icon_assets if build.murmur64(name.encode('ascii')) not in before)
        assert z.read('Addon/9ba626afa44a3aa3.patch_0.stream') == b''
        assert z.read('icon.png') == old.read('icon.png')
        manifest = json.loads(z.read('manifest.json'))
        validate_manager_manifest(manifest, z.namelist())
        assert manifest == build.MANIFEST
        assert manifest['Guid'] == json.loads(old.read('manifest.json'))['Guid']
        readme = z.read('README.txt').decode('utf-8')
        assert readme == build.README.format(version=version).replace('\n', '\r\n')
        lua = LuaRuntime(unpack_returned_tuples=True)
        check = lua.eval('function(s) local f,e=loadstring(s); return f~=nil,e end')
        ok, error = check(source.decode('utf-8'))
        assert ok, error
        for arg in (None, build.RESOURCE):
            runtime = LuaRuntime(unpack_returned_tuples=True)
            mod = runtime.execute(source.decode('utf-8'), arg)
            assert mod.status == 'no Chef Shared Loader'
        return dict(version=version, zip=path.name, zip_files=len(z.namelist()), resources=len(rows),
                    textures=len(now), new_icons=new_icons, lua51_compiles=True, embedded_source_matches=True,
                    public_icons_unchanged=True, manifest_guid_unchanged=True,
                    experimental_measurements_absent=True, sha256=hashlib.sha256(path.read_bytes()).hexdigest())


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('zip', help='Player ZIP to verify against the current source')
    parser.add_argument('--allow-test', action='store_true', help='Explicitly permit a -test.N build')
    args = parser.parse_args()
    print(json.dumps(verify(args.zip, allow_test=args.allow_test), indent=2))
