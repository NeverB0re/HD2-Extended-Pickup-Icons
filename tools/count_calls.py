"""Engine and Chef calls per frame in a busy mission, on the fake engine: counts, not milliseconds.

Run from anywhere with lupa installed: python tools/count_calls.py
"""
import argparse
import json
import os
import struct
import sys
import unittest
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tests"))
sys.path.insert(0, ROOT)
import test_extended_pickup_icons_range as T  # noqa: E402

FRV = "content/fac_helldivers/vehicles/frv/frv"
GUN = "content/fac_helldivers/vehicles/frv/armaments/frv_mg/frv_mg"
AMMO = "content/fac_helldivers/discoverables/ammo_box_discoverable_01/ammo_box_discoverable_01"
CRATE = "content/fac_helldivers/hellpod/ammo_rack/ammo_box"
STIM = "content/fac_helldivers/discoverables/health_pack_discoverable_01/health_pack_discoverable_01"
BOMB = "content/fac_helldivers/hellpod/hellbomb_defunct/hellbomb_defunct"
CODES = "content/objectives/obj_common/generic_intel/generic_intel"
BOX = "hex:a9936cbe561e8180"
NET = """local fake = ...
stingray.IdString64 = { from_hex = function(hex) return { hex = hex } end }
fake.loaded["hex:4d1c334d294dfa97"] = true
"""
COUNT = """local fake = ...
fake.count = {}
local function wrap(t, prefix, skip)
  for k, f in pairs(t) do
    if type(f) == 'function' and not (skip and skip[k]) then
      t[k] = function(...)
        fake.count[prefix .. k] = (fake.count[prefix .. k] or 0) + 1
        return f(...)
      end
    end
  end
end
local inner = fake.chef.call_kind
fake.chef.call_kind = function(name, kind, ...)
  fake.count['call:' .. name] = (fake.count['call:' .. name] or 0) + 1
  return inner(name, kind, ...)
end
wrap(fake.chef, 'chef.', {call_kind = true, screen = true, color = true, call = true})
stingray.Application.can_get = (function(f) return function(...)
  fake.count['raw.can_get'] = (fake.count['raw.can_get'] or 0) + 1
  return f(...) end end)(stingray.Application.can_get)
"""


class Bench(T.ScreenTests, T.NetworkIdentityTests):
    def runTest(self):
        if not self.network:
            self.fake.net.build = 'unverified-benchmark-build'
        self.lua.execute(NET, self.fake)
        self.fake.textures_loaded = True
        self.set_units(T.AVATAR, [T.unit(0, -8, 0), T.unit(20, 0, 0), T.unit(-30, 5, 0), T.unit(60, 60, 0)], loaded=False)
        self.fake.loaded["hex:a9936cbe561e8180"] = True
        self.set_units(BOX, [T.unit(0.3, -8.2, 1.2)])
        self.set_units(T.SAMPLE, [T.unit(-30 + 2 * k, 30 + (k % 5), 0) for k in range(30)])     # 30 samples ahead
        self.set_units(AMMO, [T.unit(-200 + 8 * k, 150, 0) for k in range(52)])                  # 52 boxes far off
        self.set_units(CRATE, [T.unit(2 + k, 8, 0) for k in range(4)])                           # a supply pod near
        self.set_units(STIM, [T.unit(-3 - k, 9, 0) for k in range(3)])
        codes = [T.unit(8, 12, 0)]
        codes[0].update(meshes=6)
        self.set_units(CODES, codes)
        self.set_units(BOMB, [T.unit(12, 40, 0)])
        if self.vehicle:
            self.set_units(FRV, [T.unit(-10, 30, 0)])
            self.set_units(GUN, [T.unit(-10, 30, 1.5)])
        if self.source_override is not None:
            self.source = self.source_override
        self.load()
        self.settle()
        self.frames(120, start=40.0)
        self.lua.execute(COUNT, self.fake)
        n = 600
        self.frames(n, start=50.0)
        got = {k: v / n for k, v in self.fake.count.items()}
        if 'chef.rect' in got:   # the fake's rect draws two triangles; the loader's does not
            got['chef.triangle'] = got.get('chef.triangle', 0) - 2 * got['chef.rect']
        self.result = {'calls_per_frame': round(sum(got.values()), 2), 'markers': self.dots(),
                       'calls': dict(sorted(got.items()))}


def source_from_zip(path):
    with zipfile.ZipFile(path) as z:
        data = z.read('Addon/9ba626afa44a3aa3.patch_0')
    _, kinds, count = struct.unpack_from('<3I', data)
    lua_type = T.build.murmur64(b'lua')
    for index in range(count):
        row = struct.unpack_from('<7Q6I', data, 0x48 + kinds * 32 + index * 80)
        if row[1] == lua_type:
            size, flag = struct.unpack_from('<2I', data, row[2])
            if flag != 2:
                raise ValueError('Baseline is not plain Lua source')
            return data[row[2] + 8:row[2] + 8 + size].decode('utf-8')
    raise ValueError('Baseline has no Lua resource')


def measure(network, vehicle, source=None):
    b = Bench('runTest')
    b.network, b.vehicle, b.source_override = network, vehicle, source
    with open(os.devnull, 'w') as quiet:
        result = unittest.TextTestRunner(verbosity=0, stream=quiet).run(b)
    if not result.wasSuccessful():
        raise RuntimeError('\n'.join(trace for _, trace in result.errors + result.failures))
    return b.result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', help='Compare with the embedded Lua from a previous player ZIP')
    args = parser.parse_args()
    baseline = source_from_zip(args.baseline) if args.baseline else None
    report = {'frames': 600, 'measurement': 'simulated Chef/engine API calls, not FPS or milliseconds', 'scenarios': {}}
    for network in (False, True):
        for vehicle in (False, True):
            label = ('network' if network else 'legacy') + ('_frv' if vehicle else '_no_vehicle')
            row = {'current': measure(network, vehicle)}
            if baseline is not None:
                row['baseline'] = measure(network, vehicle, baseline)
                assert row['current']['markers'] == row['baseline']['markers'], label
            report['scenarios'][label] = row
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
