"""The game's icons (tools/icons/game, extracted with filediver) as the mod's own textures: each cut to its shape,
coloured as the mod draws it, and shrunk to every size in SIZES along its longer side (box filter, as a mip would), as RGBA8 pixels.
build.py packs them into the mod's patch; Chef Shared Loader's chef.bitmap draws a texture shipped there.

ICONS: name -> (file, how its pixels give the icon, framed):
  'alpha'   white, see-through by the image's alpha (white icons)
  'red'     white, see-through by its red channel (white icons on black, a blue outline in the other channels)
  'green'   white, its green part only (a stratagem icon's picture, without its red frame)
  'body'    white, its red part only (a vehicle stratagem icon's vehicle, without what it carries)
framed: inside the red corner frame of the game's stratagem icons (FRAME), fitted to where their picture sits.
All white: the mod tints them as it draws them (ICON_RGB)."""
import os
import struct
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.join(HERE, "icons", "game")
SIZES = (12, 16, 20, 24, 28, 32, 40, 48, 64)   # pixels along the longer side; the mod draws the smallest that is
                                                # at least as big as it needs

ICONS = {
    "ammo": ("ammo.png", "alpha", False),
    "grenade": ("grenade.png", "red", False),
    "stim": ("stim.png", "red", False),
    "egg": ("egg.png", "red", False),
    "tube": ("tube.png", "red", False),
    "common": ("sample_common.png", "alpha", False),
    "rare": ("sample_rare.png", "alpha", False),
    "super": ("sample_super.png", "alpha", False),
    "package": ("package.png", "alpha", True),
    "larva": ("larva.png", "green", True),
    "hellbomb": ("hellbomb.png", "green", True),
    "tank": ("vehicle_bastion_tank.png", "body", True),      # the tank's, for both tanks
    "car": ("vehicle_frv_hmg.png", "body", True),            # the FRV's, for every FRV
    "walker": ("vehicle_combatwalker.png", "body", True),    # the exosuit's, for every exosuit
    "skull": ("skull.png", "alpha", False),                  # ours, the death screen's skull (draw_skull.py)
}
FRAME = "hellbomb.png"   # its red corners (256 x 256 frame, corners at 24..231)
PICTURE = (150, 160)     # the picture fitted into this, centred in the frame (the hellbomb's is 144 x 160)


def decode(path):
    """A PNG's width, height, bytes per pixel and rows (8-bit, not interlaced)."""
    d = open(path, "rb").read()
    pos, idat = 8, b""
    while pos < len(d):
        n, t = struct.unpack(">I4s", d[pos:pos + 8])
        c = d[pos + 8:pos + 8 + n]
        pos += 12 + n
        if t == b"IHDR":
            w, h, bd, ct = struct.unpack(">IIBB", c[:10])
        elif t == b"IDAT":
            idat += c
    bpp = {2: 3, 6: 4, 0: 1, 4: 2}[ct]
    raw = zlib.decompress(idat)
    stride = w * bpp
    rows, prev, i = [], bytearray(stride), 0
    for _ in range(h):
        f = raw[i]
        line = bytearray(raw[i + 1:i + 1 + stride])
        i += 1 + stride
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if f == 1:
                line[x] = (line[x] + a) & 255
            elif f == 2:
                line[x] = (line[x] + b) & 255
            elif f == 3:
                line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append(line)
        prev = line
    return w, h, bpp, rows


def encode(w, h, rgba):
    """RGBA8 pixels (rows top down) as a PNG."""
    raw = b"".join(b"\x00" + bytes(rgba[y * w * 4:(y + 1) * w * 4]) for y in range(h))
    chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def alpha_grid(path, mode):
    """How much each pixel shows (0..1) by this mode, as rows."""
    w, h, bpp, rows = decode(path)
    out = []
    for y in range(h):
        r = rows[y]
        line = []
        for x in range(w):
            p = [r[x * bpp + k] for k in range(bpp)]
            if mode == "alpha":
                a = p[3] / 255 if bpp == 4 else max(p[:3]) / 255
            elif mode == "red":
                a = p[0] / 255
            elif mode == "green":
                a = max(0, p[1] - p[0]) / 255
            elif mode == "body":
                a = max(0, p[0] - p[1]) / 255
            else:   # the frame: the red corners
                a = max(0, p[0] - p[1]) / 255
            line.append(a)
        out.append(line)
    return out


def crop(grid):
    """Cut to where it shows."""
    h, w = len(grid), len(grid[0])
    ys = [y for y in range(h) if any(v > 0.04 for v in grid[y])]
    xs = [x for x in range(w) if any(grid[y][x] > 0.04 for y in range(h))]
    return [line[min(xs):max(xs) + 1] for line in grid[min(ys):max(ys) + 1]]


def resample(grid, W, H):
    """Area average to W x H."""
    h, w = len(grid), len(grid[0])
    out = []
    for j in range(H):
        sy0, sy1 = j * h / H, (j + 1) * h / H
        line = []
        for i in range(W):
            sx0, sx1 = i * w / W, (i + 1) * w / W
            total = weight = 0.0
            y = int(sy0)
            while y < sy1:
                hy = min(sy1, y + 1) - max(sy0, y)
                x = int(sx0)
                while x < sx1:
                    k = (min(sx1, x + 1) - max(sx0, x)) * hy
                    total += grid[min(y, h - 1)][min(x, w - 1)] * k
                    weight += k
                    x += 1
                y += 1
            line.append(total / weight)
        out.append(line)
    return out


def icon_pixels(path, mode, framed=False):
    """The icon as premultiplied white (a, a, a, a), 0..1 per pixel, cut to where it shows; framed: its picture
    fitted inside the stratagem icons' red corner frame."""
    grid = crop(alpha_grid(path, mode))
    if framed:
        frame = alpha_grid(os.path.join(GAME, FRAME), "frame")
        h, w = len(grid), len(grid[0])
        k = min(PICTURE[0] / w, PICTURE[1] / h)
        W, H = max(1, round(w * k)), max(1, round(h * k))
        pic = resample(grid, W, H)
        size = len(frame)
        x0, y0 = (size - W) // 2, (size - H) // 2
        for y in range(H):
            for x in range(W):
                frame[y0 + y][x0 + x] = max(frame[y0 + y][x0 + x], pic[y][x])
        grid = crop(frame)
    return [[(a, a, a, a) for a in line] for line in grid]


def shrink(px, size):
    """Box filter to this size along the longer side (the other in proportion), back to straight RGBA8."""
    h, w = len(px), len(px[0])
    if w >= h:
        W, H = size, max(1, round(h * size / w))
    else:
        W, H = max(1, round(w * size / h)), size
    out = bytearray(W * H * 4)
    for j in range(H):
        sy0, sy1 = j * h / H, (j + 1) * h / H
        for i in range(W):
            sx0, sx1 = i * w / W, (i + 1) * w / W
            acc = [0.0, 0.0, 0.0, 0.0]
            weight = 0.0
            y = int(sy0)
            while y < sy1:
                hy = min(sy1, y + 1) - max(sy0, y)
                x = int(sx0)
                while x < sx1:
                    k = (min(sx1, x + 1) - max(sx0, x)) * hy
                    p = px[min(y, h - 1)][min(x, w - 1)]
                    for c in range(4):
                        acc[c] += p[c] * k
                    weight += k
                    x += 1
                y += 1
            a = acc[3] / weight
            o = (j * W + i) * 4
            if a > 0:
                out[o:o + 4] = bytes((min(255, round(acc[0] / weight / a * 255)), min(255, round(acc[1] / weight / a * 255)),
                                      min(255, round(acc[2] / weight / a * 255)), min(255, round(a * 255))))
    return W, H, bytes(out)


def baked():
    """[(icon name, size, width, height, RGBA8 pixels)] for every icon and size."""
    out = []
    for name, (file, mode, framed) in sorted(ICONS.items()):
        px = icon_pixels(os.path.join(GAME, file), mode, framed)
        for size in SIZES:
            w, h, rgba = shrink(px, size)
            out.append((name, size, w, h, rgba))
    return out


if __name__ == "__main__":   # a preview: every icon at every size, over dark grey
    items = baked()
    W = sum(w + 4 for _, size, w, h, _ in items if size == SIZES[-1])
    rows = []
    for size in SIZES:
        line = [(w, h, rgba) for _, s, w, h, rgba in items if s == size]
        rows.append((size, line))
    H = sum(size + 4 for size, _ in rows)
    canvas = bytearray([40, 40, 40, 255] * W * H)
    oy = 0
    for size, line in rows:
        ox = 0
        for w, height, rgba in line:
            for y in range(height):
                for x in range(w):
                    s = (y * w + x) * 4
                    a = rgba[s + 3] / 255
                    o = ((oy + y) * W + ox + x) * 4
                    for c in range(3):
                        canvas[o + c] = round(40 * (1 - a) + rgba[s + c] * a)
            ox += w + 4
        oy += size + 4
    open(os.path.join(HERE, "baked_preview.png"), "wb").write(encode(W, H, canvas))
    print("%d textures" % len(items))
