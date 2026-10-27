"""The death mark's icon (2.5.0): the skull of the game's death screen, redrawn from the outline measured on a
screenshot of it, white on clear, into icons/game/skull.png (bake_icons.py bakes it like the game's own icons)."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bake_icons as b  # noqa: E402

# in the screenshot's pixels (the skull's middle at x 107)
OUTLINE = [(107, 34), (172, 57), (172, 125), (190, 145), (164, 177), (148, 169), (142, 176), (136, 196), (122, 201),
           (107, 205), (92, 201), (78, 196), (72, 176), (66, 169), (50, 177), (24, 145), (42, 125), (42, 57)]
EYES = [(71, 134, 16.5), (143, 134, 16.5)]
NOSE = [(107, 150), (119, 169), (112, 173), (107, 167), (102, 173), (95, 169)]


def inside(poly, x, y):
    c = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            c = not c
        j = i
    return c


def shows(x, y):
    if not inside(OUTLINE, x, y) or inside(NOSE, x, y):
        return False
    return all((x - ex) ** 2 + (y - ey) ** 2 > r * r for ex, ey, r in EYES)


K, SS = 2, 4                              # 2 output pixels per screenshot pixel, 4 x 4 samples each
X0, Y0, X1, Y1 = 20, 30, 194, 209
W, H = (X1 - X0) * K, (Y1 - Y0) * K
rgba = bytearray(W * H * 4)
for j in range(H):
    for i in range(W):
        n = sum(shows(X0 + (i + (a + 0.5) / SS) / K, Y0 + (j + (c + 0.5) / SS) / K) for a in range(SS) for c in range(SS))
        if n:
            o = (j * W + i) * 4
            rgba[o:o + 4] = bytes((255, 255, 255, round(255 * n / (SS * SS))))
open(os.path.join(HERE, "icons", "game", "skull.png"), "wb").write(b.encode(W, H, rgba))
print(W, H)
