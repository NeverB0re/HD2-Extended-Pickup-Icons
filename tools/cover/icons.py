"""The cover's icons (Nexus): every icon the mod draws, white on clear, 128 px along its longer side, into
tools/cover/icons (the same pictures bake_icons.py bakes; the supply crate's from icons/supply.png)."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
sys.path.insert(0, TOOLS)
import bake_icons as b  # noqa: E402

OUT = os.path.join(HERE, "icons")
SIZE = 128


def supply():
    """The supply crate's icon: its picture's brightness (as raster_icons.py reads it), cropped."""
    w, h, bpp, rows = b.decode(os.path.join(TOOLS, "icons", "supply.png"))
    grid = [[max(0.0, min(1.0, (sum(rows[y][x * bpp:x * bpp + 3]) / 3 - 40) / 120)) for x in range(w)] for y in range(h)]
    return [[(a, a, a, a) for a in line] for line in b.crop(grid)]


os.makedirs(OUT, exist_ok=True)
pictures = {name: b.icon_pixels(os.path.join(b.GAME, f), mode, framed) for name, (f, mode, framed) in b.ICONS.items()}
pictures["supply"] = supply()
for name, px in sorted(pictures.items()):
    w, h, rgba = b.shrink(px, SIZE)
    with open(os.path.join(OUT, name + ".png"), "wb") as f:
        f.write(b.encode(w, h, rgba))
print(len(pictures), "icons ->", OUT)
