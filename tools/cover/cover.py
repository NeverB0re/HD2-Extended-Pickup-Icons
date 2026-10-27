"""The Nexus cover (2560 x 1440): cover.html from the icons tools/cover/icons.py made, then a PNG of it through
Microsoft Edge's headless screenshot, into nexus_cover.png in the mod's folder (not in the repository)."""
import base64
import os
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.dirname(os.path.dirname(HERE))
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"

TEAL = "#35d4bc"
WHITE = "#f2f4f5"
BLUE = "rgb(110,205,255)"      # VEHICLE_RGB
RED = "rgb(255,90,70)"         # HELLBOMB_RGB
SKULL = "rgb(235,50,40)"       # DEATH_RGB


def uri(name):
    with open(os.path.join(HERE, "icons", name + ".png"), "rb") as f:
        return "data:image/png;base64," + base64.b64encode(f.read()).decode()


def icon(name, color, size, extra=""):
    """An icon as a box masked by its picture, in this colour."""
    return ('<span class="ic" style="width:%dpx;height:%dpx;background:%s;-webkit-mask-image:url(%s);%s"></span>'
            % (size, size, color, uri(name), extra))


def diamond(size, color=WHITE):
    return ('<span class="dia" style="width:%dpx;height:%dpx;border-color:%s"><i style="background:%s"></i></span>'
            % (size, size, color, color))


def at(x, y, inner, cls="pin"):
    return '<div class="%s" style="left:%dpx;top:%dpx">%s</div>' % (cls, x, y, inner)


def marker(x, y, inner, dist=None, color=WHITE, vee=False):
    """A marker on the map: its distance above it (vehicles, hellbombs, where you died), a V under a vehicle's."""
    parts = []
    if dist:
        parts.append('<div class="dist" style="color:%s">%s</div>' % (color, dist))
    parts.append(inner)
    if vee:
        parts.append('<div class="vee" style="border-color:%s"></div>' % color)
    return at(x, y, "".join(parts))


ROWS = [  # icon, name, default distance, new
    (icon("common", WHITE, 54), "SAMPLES", "50 M", False),
    (icon("ammo", WHITE, 54), "SUPPLIES", "25 M", False),
    (icon("package", BLUE, 58), "MISSION ITEMS", "50 M", False),
    (diamond(34), "OBJECTIVES", "50 M", False),
    (icon("hellbomb", RED, 58), "HELLBOMBS", "100 M", False),
    (icon("walker", BLUE, 60), "VEHICLES", "100 M", False),
    (icon("skull", SKULL, 52), "WHERE YOU DIED", "500 M", True),
]

CX, CY, R, R_IN = 1890, 760, 600, 215   # the map: you in the middle, the game's own icon range inside

MAP = [
    marker(1600, 500, icon("common", WHITE, 62)),
    marker(2170, 1010, icon("rare", WHITE, 62)),
    marker(2300, 560, icon("super", WHITE, 62)),
    marker(1470, 930, icon("ammo", WHITE, 62)),
    marker(2040, 400, icon("grenade", WHITE, 62)),
    marker(1730, 1170, icon("stim", WHITE, 66)),
    marker(2330, 820, icon("supply", WHITE, 60)),
    marker(1990, 1215, diamond(40)),
    marker(1560, 300, icon("package", BLUE, 78)),
    marker(2210, 260, icon("hellbomb", RED, 82), "88M", RED),
    marker(1400, 640, icon("walker", BLUE, 92), "62M", BLUE, vee=True),
    marker(1440, 1170, icon("skull", SKULL, 74), "214M", SKULL),
]

HTML = """<!doctype html><html><head><meta charset="utf-8"><style>
html,body{margin:0;width:2560px;height:1440px;overflow:hidden;background:#0c1015}
body{position:relative;font-family:'Bahnschrift',sans-serif;color:%(white)s}
.mono{font-family:Consolas,monospace}
.eyebrow{position:absolute;left:128px;top:104px;font-size:32px;letter-spacing:9px;color:%(teal)s}
.title{position:absolute;left:120px;top:150px;font-weight:700;font-stretch:condensed;font-size:178px;line-height:.92;
 letter-spacing:2px}
.title b{display:block;color:%(teal)s}
.sub{position:absolute;left:128px;top:662px;font-weight:600;font-stretch:condensed;font-size:56px}
.ko{position:absolute;left:128px;top:732px;font-family:'Malgun Gothic';font-size:36px;color:#9aa6ad}
.label{position:absolute;left:128px;top:806px;font-size:26px;letter-spacing:7px;color:#aab4ba}
.rows{position:absolute;left:120px;top:846px;width:1090px}
.row{display:flex;align-items:center;height:60px;margin-bottom:8px;padding:0 28px;border:2px solid #222d35;
 border-radius:14px;background:#121a21}
.row .icwrap{width:70px;display:flex;justify-content:center}
.row .name{margin-left:18px;font-weight:600;font-stretch:condensed;font-size:40px;letter-spacing:1px;flex:1}
.row .m{font-size:30px;color:#9aa6ad}
.new{margin-left:18px;vertical-align:6px;font-size:22px;letter-spacing:4px;color:#0c1015;background:%(teal)s;border-radius:8px;
 padding:3px 10px 2px}
.pill{position:absolute;left:128px;top:1352px;font-size:24px;letter-spacing:6px;color:%(teal)s}
.ic{display:inline-block;-webkit-mask-size:contain;-webkit-mask-repeat:no-repeat;-webkit-mask-position:center}
.dia{display:inline-block;position:relative;transform:rotate(45deg) scale(.72);border:5px solid;box-sizing:border-box}
.dia i{position:absolute;left:-5px;bottom:-5px;width:calc(100%% + 10px);height:calc(100%% + 10px);
 clip-path:polygon(0 0,100%% 100%%,0 100%%)}
.map{position:absolute;left:%(mx)dpx;top:%(my)dpx;width:%(md)dpx;height:%(md)dpx;border-radius:50%%;background:#18232b}
.near{position:absolute;left:%(nx)dpx;top:%(ny)dpx;width:%(nd)dpx;height:%(nd)dpx;border-radius:50%%;background:#22303a}
.nearlabel{position:absolute;left:%(cx)dpx;top:%(nly)dpx;transform:translateX(-50%%);text-align:center;font-size:24px;
 letter-spacing:5px;color:#aab4ba;line-height:1.35}
.you{position:absolute;left:%(yx)dpx;top:%(yy)dpx;width:116px;height:116px;border-radius:50%%;background:%(white)s}
.you:before{content:'';position:absolute;left:41px;top:24px;width:34px;height:34px;border-radius:50%%;background:#0c1015}
.you:after{content:'';position:absolute;left:30px;top:64px;width:56px;height:28px;border-radius:28px 28px 6px 6px;
 background:#0c1015}
.pin{position:absolute;transform:translate(-50%%,-50%%);display:flex;flex-direction:column;align-items:center}
.dist{font-weight:700;font-size:30px;margin-bottom:6px;letter-spacing:1px}
.vee{width:34px;height:34px;border-right:6px solid;border-bottom:6px solid;transform:scaleX(1.6) rotate(45deg);
 margin-top:-4px}
.tag{position:absolute;left:%(cx)dpx;top:118px;transform:translateX(-50%%);background:%(white)s;color:#0c1015;
 border-radius:36px;padding:16px 40px 14px;font-size:30px;letter-spacing:6px}
</style></head><body>
<div class="eyebrow mono">HELLDIVERS 2 MOD &middot; QUALITY OF LIFE</div>
<div class="title">EXTENDED<br>PICKUP ICONS<b>RANGE</b></div>
<div class="sub">The game's own icons, seen from farther away.</div>
<div class="ko">게임 아이콘 그대로 &middot; 더 먼 거리에서</div>
<div class="label mono">WHAT GETS A MARKER &middot; DEFAULT DISTANCE</div>
<div class="rows">%(rows)s</div>
<div class="pill mono">CHEF SHARED LOADER &middot; F9: EACH KIND ON/OFF, ITS OWN DISTANCE</div>
<div class="map"></div><div class="near"></div>
<div class="tag mono">THE GAME'S ICONS, FARTHER</div>
<div class="you"></div>
<div class="nearlabel mono">THE GAME'S<br>OWN ICONS</div>
%(map)s
</body></html>
"""


def main():
    rows = "".join('<div class="row"><span class="icwrap">%s</span><span class="name">%s%s</span>'
                   '<span class="m mono">%s</span></div>' % (ic, name, '<span class="new mono">NEW</span>' if new else "", m)
                   for ic, name, m, new in ROWS)
    html = HTML % dict(white=WHITE, teal=TEAL, rows=rows, map="\n".join(MAP), cx=CX,
                       mx=CX - R, my=CY - R, md=2 * R, nx=CX - R_IN, ny=CY - R_IN, nd=2 * R_IN,
                       yx=CX - 58, yy=CY - 58 - 30, nly=CY + 70)
    page = os.path.join(HERE, "cover.html")
    with open(page, "w", encoding="utf-8") as f:
        f.write(html)
    out = os.path.join(MOD, "nexus_cover.png")
    subprocess.run([EDGE, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                    "--window-size=2560,1440", "--screenshot=" + out, "file:///" + page.replace("\\", "/")],
                   check=True, capture_output=True)
    print(out)


if __name__ == "__main__":
    main()
