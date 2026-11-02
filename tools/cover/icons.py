"""The cover's icons (Nexus): every icon the mod draws, white on clear, 128 px along its longer side, into
tools/cover/icons (the same pictures bake_icons.py bakes)."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
sys.path.insert(0, TOOLS)
import bake_icons as b  # noqa: E402

OUT = os.path.join(HERE, "icons")
SIZE = 128


os.makedirs(OUT, exist_ok=True)
pictures = {name: b.icon_pixels(os.path.join(b.GAME, f), mode, framed) for name, (f, mode, framed) in b.ICONS.items()}
for name, px in sorted(pictures.items()):
    w, h, rgba = b.shrink(px, SIZE)
    with open(os.path.join(OUT, name + ".png"), "wb") as f:
        f.write(b.encode(w, h, rgba))
print(len(pictures), "icons ->", OUT)
