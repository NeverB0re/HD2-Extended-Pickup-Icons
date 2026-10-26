"""Game icon images -> screen-pixel rectangles (Lua), so the mod draws them pixel for pixel at their size.

Each image's shape (a channel, 0..1) is cropped, scaled to `height` screen pixels, and each cell given its
coverage in quarters (drawn that see-through, like the game's scaled icon). Cells of the same coverage are
merged into rectangles: runs along a row, stacked while the next row has the same run. Prints Lua (paste into
ICON_PIXELS in src/pickup_dots.lua) and writes a preview PNG.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from sheet import load, png

ICON = lambda name: os.path.join(HERE, "icons", name + ".png")   # the game's images (filediver)
RED_ONLY = lambda c: max(0.0, min(1.0, (c[0] - 70) / 150)) if c[1] < 120 else 0.0
GREEN_ONLY = lambda c: max(0.0, min(1.0, (c[1] - 70) / 150)) if c[0] < 120 else 0.0
ICONS = [  # name, file, coverage of a pixel (0..1), screen height in pixels
    ("ammo", ICON("ammo"), lambda c: max(0.0, min(1.0, (c[0] - 70) / 150)), 19),
    ("grenade", ICON("grenade"), lambda c: max(0.0, min(1.0, (c[0] - 70) / 150)), 22),
    ("stim", ICON("stim"), lambda c: max(0.0, min(1.0, (c[0] - 70) / 150)), 9),
    ("supply", ICON("supply"), lambda c: max(0.0, min(1.0, (sum(c) / 3 - 40) / 120)), 18),
    ("package", ICON("package"), lambda c: max(0.0, min(1.0, (c[0] - 70) / 150)), 22),
    ("larva", ICON("larva"), lambda c: max(0.0, min(1.0, (c[1] - 60) / 150)), 24),
    ("egg", ICON("egg"), lambda c: max(0.0, min(1.0, (c[0] - 70) / 150)), 20),
    ("tube", ICON("tube"), lambda c: max(0.0, min(1.0, (sum(c) / 3 - 60) / 140)), 20),
    # vehicles: the stratagem icons' red channel is the vehicle (green marks its weapons)
    ("tank", ICON("tank"), RED_ONLY, 16),
    ("walker", ICON("walker"), RED_ONLY, 28),
    ("car", ICON("car"), RED_ONLY, 20),
    # the hellbomb: the hellbomb backpack's stratagem icon, its green part (red is the backpack)
    ("hellbomb", ICON("hellbomb"), GREEN_ONLY, 22),
]


def raster(path, cover, height, long=None):
    w, h, px = load(path)
    mask = [[cover(px(x, y)) for x in range(w)] for y in range(h)]
    ys = [y for y in range(h) if any(v > 0.5 for v in mask[y])]
    xs = [x for x in range(w) if any(mask[y][x] > 0.5 for y in range(h))]
    x0, x1, y0, y1 = min(xs), max(xs) + 1, min(ys), max(ys) + 1
    bw, bh = x1 - x0, y1 - y0
    H = height
    W = max(1, round(bw * H / bh))
    if long is not None:   # this many pixels along the longest side instead
        if bw >= bh:
            W, H = long, max(1, round(bh * long / bw))
        else:
            W, H = max(1, round(bw * long / bh)), long
    cells = []
    for j in range(H):
        row = []
        sy0, sy1 = y0 + j * bh / H, y0 + (j + 1) * bh / H
        for i in range(W):
            sx0, sx1 = x0 + i * bw / W, x0 + (i + 1) * bw / W
            total = weight = 0.0
            y = int(sy0)
            while y < sy1:
                hy = min(sy1, y + 1) - max(sy0, y)
                x = int(sx0)
                while x < sx1:
                    wx = min(sx1, x + 1) - max(sx0, x)
                    a = wx * hy
                    weight += a
                    total += a * mask[y][x]
                    x += 1
                y += 1
            row.append(int(round(4 * total / weight)) if weight else 0)
        cells.append(row)
    return W, H, cells


def rects(W, H, cells):
    runs = []
    for j in range(H):
        r, i = [], 0
        while i < W:
            if cells[j][i]:
                k = i
                while k < W and cells[j][k] == cells[j][i]:
                    k += 1
                r.append((i, k, cells[j][i]))
                i = k
            else:
                i += 1
        runs.append(r)
    out, open_ = [], {}
    for j in range(H + 1):
        here = set(runs[j]) if j < H else set()
        for run in list(open_):
            if run not in here:
                out.append((run[0], open_.pop(run), run[1], j, run[2]))
        for run in here:
            if run not in open_:
                open_[run] = j
    ox, oy = W // 2, H // 2
    return sorted((i0 - ox, oy - j1, i1 - ox, oy - j0, level) for i0, j0, i1, j1, level in out)


lua, preview = [], []
SMALLEST = 0.7   # every whole-pixel height from full size down to this share of it
for name, path, cover, height in ICONS:
    sizes = []
    W0, H0, _ = raster(path, cover, height)
    full = max(W0, H0)
    for k, n in enumerate(range(full, round(full * SMALLEST) - 1, -1)):   # one pixel at a time
        W, H, cells = raster(path, cover, height, long=n)
        rs = rects(W, H, cells)
        sizes.append("{%s}" % ", ".join("{%d, %d, %d, %d, %d}" % r for r in rs))
        if k == 0:
            preview.append((W, H, cells))
            print("-- %s: %dx%d px, %d rects" % (name, W, H, len(rs)), file=sys.stderr)
    nl = chr(10)
    lua.append("    %s = {" % name + nl + "        " + ("," + nl + "        ").join(sizes) + "," + nl + "    },")
print("\n".join(lua))

S8 = 8
PW = sum(W + 4 for W, _, _ in preview) * S8
PH = (max(H for _, H, _ in preview) + 4) * S8
buf = bytearray([40, 44, 40] * PW * PH)
ox = 2
for W, H, cells in preview:
    for j in range(H):
        for i in range(W):
            if cells[j][i]:
                v = 40 + (255 - 40) * cells[j][i] // 4
                for yy in range((j + 2) * S8, (j + 3) * S8):
                    for xx in range((ox + i) * S8, (ox + i + 1) * S8):
                        o = (yy * PW + xx) * 3
                        buf[o:o + 3] = bytes((v, v, v))
    ox += W + 4
open(os.path.join(HERE, "raster_preview.png"), "wb").write(png(PW, PH, buf))
