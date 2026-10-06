"""Synthetic protected-memory tests for the v2.5 core script. Requires: pip install lupa (LuaJIT with ffi), Windows x64."""
import re, struct, random, sys, time
import lupa.luajit21 as L

import os
S = os.path.dirname(os.path.abspath(__file__)) + "/"
OLD = open(S + 'extended_pickup_icons_v24.lua', encoding='utf-8').read()
NEW = open(S + (sys.argv[1] if len(sys.argv) > 1 else "extended_pickup_icons_v25.lua"), encoding='utf-8').read()
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

def run(choices, layouts, late=None, frames=400):
    lua = L.LuaRuntime(encoding=None)
    h = lua.execute(HARNESS)
    log = []
    g = lua.globals()
    g.CodexPickupIconChoices = lua.table_from({c.encode(): True for c in choices})
    g.CowboyBingusModLoader = lua.eval(b'function(w) return {open_log=function() return {write=function(_, s) w(s) end, close=function() end} end} end')(lambda s: log.append(s.decode()))
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
    return lua, h, views, ''.join(log), time.perf_counter() - t, n

def check(name, cond, detail=''):
    print(('PASS ' if cond else 'FAIL ') + name, detail)
    if not cond: check.failed = True
check.failed = False

def values(h, v, off_map, base):
    return {n: h.get(v, base + 28 + o + 8, 4) for n, o in off_map.items()}

for shuffle in (False, True):
    ib, offs = interaction(shuffle); sb, hoff = spottable(shuffle)
    io, so = (0x196AC68, 0x5A6668) if not shuffle else (0x123458, 0x40004)
    lua, h, (v,), log, sec, n = run(['samples', 'supplies', 'equipment'], [[(io, ib), (so, sb)]])
    vals = values(h, v, offs, io)
    ok = all(vals[r['name']] == r['after'] for r in rows) and h.get(v, so + 28 + hoff, 4) == H('0a000000')
    rad = all(h.get(v, io + 28 + offs[r['name']] + 4, 4) == r['radius'] for r in rows)
    check(f'all options shuffle={shuffle}', ok and rad and 'applied 251' in log and 'skipped 0' in log,
          f'{sec*1000:.0f}ms frames={n} | {log.strip()[:120]}')
    check(f'protection restored shuffle={shuffle}', h.protect(v, io + 28 + offs[rows[0]['name']]) == 0x02)
    h.free(v)

ib, offs = interaction(True); sb, hoff = spottable(True)
bad = bytearray(ib); o = 28 + offs[rows[5]['name']] + 8; bad[o:o+4] = H('00004040')
lua, h, (v,), log, *_ = run(['samples', 'supplies', 'equipment'], [[(0x123458, bytes(bad)), (0x40004, sb)]])
vals = values(h, v, offs, 0x123458)
check('one mismatched field is skipped, rest applied',
      vals[rows[5]['name']] == H('00004040') and sum(vals[r['name']] == r['after'] for r in rows) == 250 and 'skipped 1 unmatched: ' + rows[5]['name'] in log, log.strip()[:160])
h.free(v)

lua, h, (v,), log, *_ = run(['supplies'], [[(0x123458, ib)]])
vals = values(h, v, offs, 0x123458)
sup = [r for r in rows if r['feature'] == 'supplies']
check('supplies without spottable: marker skipped, 8 applied',
      all(vals[r['name']] == r['after'] for r in sup) and sum(vals[r['name']] != r['before'] for r in rows) == 8
      and 'skipped 1 unmatched: health_item_marker' in log, log.strip()[:160])
h.free(v)

lua, h, (v,), log, *_ = run([], [[(0x123458, ib)]])
check('no options: no change', all(h.get(v, 0x123458 + 28 + offs[r['name']] + 8, 4) == r['before'] for r in rows) and 'no range' in log)
h.free(v)

lua, h, (v1, v2), log, *_ = run(['samples'], [[(0x123458, ib)], [(0x200000, ib)]])
check('two interaction tables: fail closed, no change',
      'Expected one interaction data buffer; found 2' in log and all(h.get(v1, 0x123458 + 28 + offs[r['name']] + 8, 4) == r['before'] for r in rows), log.strip()[:120])
h.free(v1); h.free(v2)

lua, h, views, log, sec, n = run(['samples', 'equipment'], [], late=[(0x123458, ib)], frames=100000)
v = views[0]; vals = values(h, v, offs, 0x123458)
check('data mapped later: waits then applies',
      'waiting' in ''.join(log) and 'applied 243' in log and all(vals[r['name']] == r['after'] for r in rows if r['feature'] != 'supplies'), f'{sec:.1f}s frames={n}')
h.free(v)
sys.exit(1 if check.failed else 0)
