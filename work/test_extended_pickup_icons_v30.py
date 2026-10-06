"""Synthetic protected-memory tests for the v3.0 core script. Requires: pip install lupa (LuaJIT with ffi), Windows x64."""
import re, struct, random, sys, time
import lupa.luajit21 as L

import os
S = os.path.dirname(os.path.abspath(__file__)) + "/"
OLD = open(S + 'extended_pickup_icons_v24.lua', encoding='utf-8').read()
NEW = open(S + (sys.argv[1] if len(sys.argv) > 1 else "extended_pickup_icons_v30.lua"), encoding='utf-8').read()
H = bytes.fromhex
rows = [dict(name=m[0], feature=m[1], id=H(m[2]), slot=int(m[3]), index=int(m[4]), zone=int(m[5]),
             zone_name=int(m[6], 16), radius=H(m[7]), before=H(m[8]), after=H(m[9]), itype=int(m[10]))
        for m in re.findall(r"\{name='([^']+)', feature='(\w+)', id=unhex\('(\w+)'\), slot=(\d+), index=(\d+), zone=(\d+), zone_name=(0x\w+), radius=unhex\('(\w+)'\), before=unhex\('(\w+)'\), after=unhex\('(\w+)'\), interact_type=(\d+)\}", OLD)]
assert len(rows) == 251
REGION = 46616576
R, RB, SR, SB = 557, 1104, 693, 72

def interaction(shuffle):
    rng = random.Random(7)
    slots = {r['id']: r['slot'] for r in rows}; idx = {r['id']: r['index'] for r in rows}
    if shuffle:
        ids = list(slots); s = rng.sample(range(2 * R), len(ids)); i = rng.sample(range(R), len(ids))
        slots = dict(zip(ids, s)); idx = dict(zip(ids, i))
    mapb = 2 * R * 16
    d = bytearray(mapb + R * RB)
    for id_, s in slots.items():
        d[s*16:s*16+8] = id_; struct.pack_into('<I', d, s*16+8, idx[id_])
    for r in rows:
        rec = mapb + idx[r['id']] * RB; z = rec + 8 + r['zone'] * 136
        d[rec:rec+4] = H('01010100')
        struct.pack_into('<I', d, z, r['zone_name']); d[z+4:z+8] = r['radius']; d[z+8:z+12] = r['before']
        struct.pack_into('<I', d, z+40, r['itype'])
    return header(0xFCCA29DB, d), {r['name']: (mapb + idx[r['id']]*RB + 8 + r['zone']*136) for r in rows}

def spottable(shuffle):
    hs, hi, rs, ri = (961, 70, 1382, 85) if not shuffle else (5, 600, 1000, 3)
    mapb = 2 * SR * 16
    d = bytearray(mapb + SR * SB)
    for s, i, id_ in ((hs, hi, '65792f925b4ccab4'), (rs, ri, 'a829a746c6168d3b')):
        d[s*16:s*16+8] = H(id_); struct.pack_into('<I', d, s*16+8, i)
    for i, t in ((hi, 0), (ri, 10)):
        a = mapb + i * SB
        struct.pack_into('<I', d, a+20, t); d[a+32] = 1; d[a+56:a+68] = H('847193dcb7d27cb0') + b'ABCD'
    return header(0x0A5E53DB, d), mapb + hi * SB + 20

def header(magic, d):
    return struct.pack('<I4sIII', magic, b'LDLD', 1, magic, len(d)) + b'\x01' + b'\0' * 7 + bytes(d)

HARNESS = r'''
local ffi = require('ffi')
ffi.cdef[[
void *VirtualAlloc(void *address, size_t size, uint32_t kind, uint32_t protect);
int VirtualFree(void *address, size_t size, uint32_t kind);
int VirtualProtect(void *address, size_t size, uint32_t new_protect, uint32_t *old_protect);
size_t VirtualQuery(const void *address, void *region, size_t size);
]]
local k = ffi.load('kernel32')
local H = {}
local old = ffi.new('uint32_t[1]')
function H.map(size)
  local ro = k.VirtualAlloc(nil, size, 0x3000, 0x04)
  k.VirtualProtect(ro, size, 0x02, old)
  return {ro=ro, size=size}
end
function H.put(v, off, s)
  k.VirtualProtect(v.ro, v.size, 0x04, old)
  ffi.copy(ffi.cast('uint8_t *', v.ro) + off, s, #s)
  k.VirtualProtect(v.ro, v.size, 0x02, old)
end
function H.get(v, off, n) return ffi.string(ffi.cast('const uint8_t *', v.ro) + off, n) end
function H.protect(v, off)
  local r = ffi.new('uint8_t[48]')
  k.VirtualQuery(ffi.cast('const uint8_t *', v.ro) + off, r, 48)
  return ffi.cast('uint32_t *', r + 36)[0]
end
function H.free(v) k.VirtualFree(v.ro, 0, 0x8000) end
return H
'''

MENU = r"""
return function(store)
  local api = {ids = {}, specs = {}, callbacks = {}}
  function api.register_option(id, spec)
    api.ids[#api.ids + 1] = id; api.specs[id] = spec
    if store[id] == nil then store[id] = spec.default end
    return true
  end
  function api.get(id) return store[id] end
  function api.on_change(id, cb) api.callbacks[id] = cb; return true end
  function api.change(id, v) store[id] = v; api.callbacks[id](v, id) end
  return api
end
"""
ID = 'codex.extended_pickup_icons.'


def run(layouts, menu=None, late=None, frames=400, language=None):
    lua = L.LuaRuntime(encoding=None)
    h = lua.execute(HARNESS)
    log = []
    g = lua.globals()
    g.CowboyBingusModLoader = lua.eval(b'function(w) return {open_log=function() return {write=function(_, s) w(s) end, close=function() end} end} end')(lambda s: log.append(s.decode()))
    api = None
    if menu is not None:
        api = lua.execute(MENU.encode())(lua.table_from({(ID + k).encode(): v for k, v in menu.items()}))
        g.ModOptionsMenu = api
    if language:
        g.BingusTranslations = lua.table_from({b'game_language': language.encode()})
    views = []

    def place(spec):
        v = h.map(REGION); views.append(v)
        for off, blob in spec: h.put(v, off, blob)
        return v
    for spec in layouts: place(spec)
    lua.execute(NEW.encode())
    t = time.perf_counter(); n = 0
    while n < frames and g.CodexPickupIconRangeTest.status.startswith((b'pending', b'waiting')):
        if late and n == 5: place(late)
        g.update(0.016); n += 1
        if late and n > 5: time.sleep(0.02)
    return lua, h, api, views, log, time.perf_counter() - t, n


def check(name, cond, detail=''):
    print(('PASS ' if cond else 'FAIL ') + name, detail)
    if not cond: check.failed = True
check.failed = False


def last(log):
    return log[-1].split('\n')[1] if log else ''


F = lambda x: struct.pack('<f', x)


def group(r):
    if r['feature'] == 'samples': return 'samples'
    if r['feature'] == 'equipment' and r['after'] == F(15.0): return 'carry'
    return r['feature']


SWITCH = {'samples': 'samples', 'supplies': 'supplies', 'equipment': 'equipment', 'carry': 'equipment'}
DEFAULT = {'samples': 35, 'supplies': 20, 'equipment': 35, 'carry': 15}


def expect(settings):
    s = dict(DEFAULT); s.update({k: v for k, v in settings.items() if not isinstance(v, bool)})
    on = {k: settings.get(k, True) if isinstance(settings.get(k, True), bool) else True
          for k in ('samples', 'supplies', 'equipment')}
    return {r['name']: (F(s[group(r)]) if on[SWITCH[group(r)]] else r['before']) for r in rows}, on['supplies']


def state_ok(h, v, offs, base, sb_off, hoff, settings, marker_present=True):
    want, marker_on = expect(settings)
    got = {n: h.get(v, base + 28 + o + 8, 4) for n, o in offs.items()}
    bad = [n for n in want if got[n] != want[n]]
    marker = not marker_present or h.get(v, sb_off + 28 + hoff, 4) == (H('0a000000') if marker_on else H('00000000'))
    rad = all(h.get(v, base + 28 + offs[r['name']] + 4, 4) == r['radius'] for r in rows)
    return not bad and marker and rad, f'bad={len(bad)} marker={marker} radius={rad}'


ib, offs = interaction(True); sb, hoff = spottable(True)
IO, SO = 0x123458, 0x40004
LAYOUT = [[(IO, ib), (SO, sb)]]

for shuffle in (False, True):
    ib2, offs2 = interaction(shuffle); sb2, hoff2 = spottable(shuffle)
    io, so = (0x196AC68, 0x5A6668) if not shuffle else (IO, SO)
    lua, h, api, (v,), log, sec, n = run([[(io, ib2), (so, sb2)]])
    ok, d = state_ok(h, v, offs2, io, so, hoff2, {})
    check(f'no menu: defaults applied shuffle={shuffle}', ok and 'menu not found; default settings' in last(log)
          and 'skipped 0' in last(log), f'{d} {sec*1000:.0f}ms | {last(log)[:120]}')
    check(f'protection restored shuffle={shuffle}', h.protect(v, io + 28 + offs2[rows[0]['name']]) == 0x02)
    h.free(v)

lua, h, api, (v,), log, *_ = run(LAYOUT, menu={})
ids = [x.decode() for x in api.ids.values()]
check('menu: 7 rows registered', ids == [ID + k for k in ('samples', 'samples_distance', 'supplies', 'supplies_distance',
                                                            'equipment', 'equipment_distance', 'carry_distance')], str(ids))
ok, d = state_ok(h, v, offs, IO, SO, hoff, {}); check('menu defaults equal v2.5 values', ok, d)
api.change((ID + 'samples_distance').encode(), 50)
ok, d = state_ok(h, v, offs, IO, SO, hoff, {'samples': 50})
check('slider: samples 50 applied live', ok and 'wrote 30 fields' in last(log), f'{d} | {last(log)[:100]}')
api.change((ID + 'equipment').encode(), False)
ok, d = state_ok(h, v, offs, IO, SO, hoff, {'samples': 50, 'equipment': False})
check('toggle: equipment off restores vanilla incl. carry', ok and 'wrote 213 fields' in last(log), d)
api.change((ID + 'carry_distance').encode(), 60)
ok, d = state_ok(h, v, offs, IO, SO, hoff, {'samples': 50, 'equipment': False, 'carry': 60})
check('carry slider while equipment off: no write', ok and 'wrote 0 fields' in last(log), d)
api.change((ID + 'equipment').encode(), True)
ok, d = state_ok(h, v, offs, IO, SO, hoff, {'samples': 50, 'carry': 60})
check('toggle: equipment on again with carry 60', ok, d)
api.change((ID + 'supplies').encode(), False)
ok, d = state_ok(h, v, offs, IO, SO, hoff, {'samples': 50, 'carry': 60, 'supplies': False})
check('toggle: supplies off restores stim marker', ok and 'wrote 9 fields' in last(log), d)
check('protection restored after live changes', h.protect(v, IO + 28 + offs[rows[0]['name']]) == 0x02)
h.free(v)

lua, h, api, (v,), log, *_ = run(LAYOUT, menu={'samples': False, 'equipment_distance': 50, 'supplies_distance': 80})
ok, d = state_ok(h, v, offs, IO, SO, hoff, {'samples': False, 'equipment': 50, 'supplies': 80})
check('saved settings honored at start', ok, f'{d} | {last(log)[:90]}')
h.free(v)

bad = bytearray(ib); o = 28 + offs[rows[5]['name']] + 8; bad[o:o+4] = H('00004040')
lua, h, api, (v,), log, *_ = run([[(IO, bytes(bad)), (SO, sb)]], menu={})
check('mismatched item skipped, others applied', 'skipped 1 unmatched: ' + rows[5]['name'] in last(log)
      and h.get(v, IO + o, 4) == H('00004040'), last(log)[:100])
api.change((ID + 'equipment').encode(), False)
check('skipped item untouched by live change', h.get(v, IO + o, 4) == H('00004040'))
h.free(v)

lua, h, api, (v,), log, *_ = run([[(IO, ib)]])
ok, d = state_ok(h, v, offs, IO, SO, hoff, {}, marker_present=False)
check('no stim data: marker skipped, rest applied', ok and 'skipped 1 unmatched: health_item_marker' in last(log)
      and 'failed' not in last(log), d)
h.free(v)

lua, h, api, (v1, v2), log, *_ = run([[(IO, ib)], [(0x200000, ib)]])
check('two tables: fail closed, no change', 'Expected one interaction data buffer; found 2' in last(log)
      and all(h.get(v1, IO + 28 + offs[r['name']] + 8, 4) == r['before'] for r in rows), last(log)[:100])
h.free(v1); h.free(v2)

lua, h, api, views, log, sec, n = run([], late=[(IO, ib), (SO, sb)], frames=100000)
ok, d = state_ok(h, views[0], offs, IO, SO, hoff, {})
check('late load: waits then applies', ok and any('waiting' in x for x in log), f'{d} {sec:.1f}s')
h.free(views[0])

for tag, want in (('ko', '샘플 거리'), ('zh-Hant', '樣本距離'), ('zh-Hans', '样本距离'), ('ja', 'サンプルの距離'),
                  ('pt-BR', 'Distância amostras'), ('es-419', 'Distancia muestras'), ('ru', 'Дальность образцов'),
                  ('xx', 'Sample distance'), (None, 'Sample distance')):
    lua, h, api, views, log, *_ = run([], menu={}, frames=1, language=tag)
    specs = api.specs
    label = specs[(ID + 'samples_distance').encode()].label().decode()
    longest = max(len(specs[i].description().decode()) for i in specs.keys())
    widest = max(len(specs[i].label().decode()) for i in specs.keys())
    check(f'translation {tag}', label == want and longest <= 400 and widest <= 64, f'{label} (desc<={longest}, label<={widest})')

lua, h, api, views, log, *_ = run([], menu={}, frames=1)
ranges = {k: (api.specs[(ID + k + '_distance').encode()].min, api.specs[(ID + k + '_distance').encode()].max) for k in DEFAULT}
check('slider ranges: mod default to 100', ranges == {k: (v, 100) for k, v in DEFAULT.items()}, str(ranges))
BAD = set('·・—–…’“”')
for tag in ('en', 'ko', 'ja', 'zh-Hans', 'zh-Hant', 'de', 'fr', 'es', 'it', 'pl', 'pt-BR', 'ru'):
    lua, h, api, views, log, *_ = run([], menu={}, frames=1, language=tag)
    shown = []
    for i in api.specs.keys():
        spec = api.specs[i]
        shown += [spec.label().decode(), spec.description().decode()]
    descs = [x for x in shown[1::2]]
    marks = sorted({c for x in shown for c in x if c in BAD})
    check(f'texts {tag}: no unsupported marks, note present, <=400', not marks and all(len(d) <= 400 for d in descs)
          and len({d.split(' ', 1)[-1] for d in descs}) >= 1 and all(len(d) > 60 for d in descs), f'marks={marks} longest={max(map(len, descs))}')

sys.exit(1 if check.failed else 0)
