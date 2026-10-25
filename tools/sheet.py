"""Contact sheet of PNGs: each scaled to a TILE x TILE cell (nearest), alpha shown over dark grey."""
import os, struct, sys, zlib

def load(path):
    d = open(path, "rb").read()
    pos, idat = 8, b""
    while pos < len(d):
        n, t = struct.unpack(">I4s", d[pos:pos + 8]); c = d[pos + 8:pos + 8 + n]; pos += 12 + n
        if t == b"IHDR": w, h, bd, ct, _, _, il = struct.unpack(">IIBBBBB", c)
        elif t == b"IDAT": idat += c
    bpp = {2: 3, 6: 4, 0: 1, 4: 2}[ct]
    raw = zlib.decompress(idat); stride = w * bpp
    rows, prev, i = [], bytearray(stride), 0
    for y in range(h):
        f = raw[i]; line = bytearray(raw[i + 1:i + 1 + stride]); i += 1 + stride
        if f:
            for x in range(stride):
                a = line[x - bpp] if x >= bpp else 0; b = prev[x]; cc = prev[x - bpp] if x >= bpp else 0
                if f == 1: line[x] = (line[x] + a) & 255
                elif f == 2: line[x] = (line[x] + b) & 255
                elif f == 3: line[x] = (line[x] + (a + b) // 2) & 255
                elif f == 4:
                    pa, pb, pc = abs(b - cc), abs(a - cc), abs(a + b - 2 * cc)
                    line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else cc)) & 255
        rows.append(line); prev = line
    def px(x, y):
        r = rows[y]; o = x * bpp
        if bpp == 4: a = r[o + 3]; return tuple(40 + (r[o + k] - 40) * a // 255 for k in range(3))
        if bpp == 3: return (r[o], r[o + 1], r[o + 2])
        return (r[o],) * 3
    return w, h, px

def png(w, h, px):
    raw = b"".join(b"\x00" + bytes(px[y * w * 3:(y + 1) * w * 3]) for y in range(h))
    ch = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
    return b"\x89PNG\r\n\x1a\n" + ch(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + ch(b"IDAT", zlib.compress(raw)) + ch(b"IEND", b"")

if __name__ == "__main__":
    out, tile, cols = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    files = sys.argv[4:]
    rows_n = (len(files) + cols - 1) // cols
    W, H = cols * (tile + 4), rows_n * (tile + 4)
    buf = bytearray([90, 0, 90] * W * H)
    for k, f in enumerate(files):
        try:
            w, h, px = load(f)
        except Exception as e:
            print("skip", f, e); continue
        s = max(w, h) / tile
        ox, oy = (k % cols) * (tile + 4) + 2, (k // cols) * (tile + 4) + 2
        for y in range(tile):
            for x in range(tile):
                sx, sy = int(x * s), int(y * s)
                c = px(sx, sy) if sx < w and sy < h else (90, 0, 90)
                o = ((oy + y) * W + ox + x) * 3
                buf[o:o + 3] = bytes(c)
    open(out, "wb").write(png(W, H, buf))
    for k, f in enumerate(files):
        print(k // cols, k % cols, os.path.basename(f))
