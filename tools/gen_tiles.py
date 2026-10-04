"""Procedural pixel art: track tiles, tunnel roofs, lot pads, UI frames, icons, light textures.
Everything is drawn pixel by pixel so it stays crisp at 1x.
usage: python tools/gen_tiles.py
"""
import math
import random
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "sprites"

C = {
    "k": (12, 10, 20), "d1": (22, 20, 33), "d2": (34, 31, 48), "d3": (48, 44, 64), "d4": (66, 62, 86),
    "g1": (98, 94, 116), "g2": (138, 134, 158), "g3": (190, 186, 206), "w": (236, 232, 244),
    "rust1": (74, 38, 28), "rust2": (118, 62, 38), "rust3": (170, 96, 52), "or": (232, 146, 60),
    "y": (255, 204, 102), "y2": (255, 236, 170), "br1": (46, 32, 30), "br2": (70, 50, 42), "br3": (96, 72, 58),
    "ol1": (34, 44, 32), "ol2": (52, 70, 42), "ol3": (84, 110, 58),
    "cy": (96, 212, 236), "cy2": (180, 244, 255), "pk": (255, 86, 170), "rd": (214, 52, 62), "rd2": (255, 110, 90),
    "lime": (190, 240, 100), "pu": (150, 70, 210), "bl": (58, 110, 180),
}


def img(w, h):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def put(im, x, y, col, a=255):
    if 0 <= x < im.width and 0 <= y < im.height:
        im.putpixel((x, y), (*col, a))


# ------------------------------------------------------------------ track tiles
def track_tile(kind, dead=False, seed=0):
    """kind: 'h', 'v', or corner 'ne','nw','se','sw' (which two edges it connects)."""
    rnd = random.Random(seed)
    im = img(16, 16)
    ball = [C["d3"], C["d4"], C["br2"], C["d3"]] if not dead else [C["d2"], C["br1"], C["d3"], C["ol1"]]
    sleeper = C["br2"] if not dead else C["br1"]
    sleeper_hi = C["br3"] if not dead else C["br2"]
    rail = C["g3"] if not dead else C["rust2"]
    rail_hi = C["w"] if not dead else C["rust3"]
    rail_lo = C["d1"]

    def ballast(x, y):
        put(im, x, y, rnd.choice(ball))

    if kind in ("h", "v"):
        for a in range(16):
            for b in range(2, 14):
                x, y = (a, b) if kind == "h" else (b, a)
                ballast(x, y)
        for a in range(0, 16, 4):
            if dead and rnd.random() < 0.3:
                continue
            for b in range(3, 13):
                for t in (1, 2):
                    x, y = (a + t, b) if kind == "h" else (b, a + t)
                    put(im, x, y, sleeper_hi if t == 1 else sleeper)
        for a in range(16):
            if dead and rnd.random() < 0.08:
                continue
            for off, col in ((4, rail), (11, rail)):
                x, y = (a, off) if kind == "h" else (off, a)
                put(im, x, y, col)
                x2, y2 = (a, off + 1) if kind == "h" else (off + 1, a)
                put(im, x2, y2, rail_lo)
            if not dead and a % 5 == 0:
                x, y = (a, 4) if kind == "h" else (4, a)
                put(im, x, y, rail_hi)
    else:
        # corner center at the shared corner of the two connected edges
        cx = 0 if "w" in kind else 16
        cy = 0 if "n" in kind else 16
        for y in range(16):
            for x in range(16):
                px, py = x + 0.5, y + 0.5
                r = math.hypot(px - cx, py - cy)
                if 2 <= r <= 14:
                    ballast(x, y)
        for k in range(0, 5):
            ang = (k + 0.5) / 5 * (math.pi / 2)
            if dead and rnd.random() < 0.3:
                continue
            for y in range(16):
                for x in range(16):
                    px, py = x + 0.5 - cx, y + 0.5 - cy
                    r = math.hypot(px, py)
                    a = math.atan2(abs(py), abs(px))
                    if 3 <= r <= 13 and abs(a - ang) * r < 1.0:
                        put(im, x, y, sleeper)
        for y in range(16):
            for x in range(16):
                px, py = x + 0.5 - cx, y + 0.5 - cy
                r = math.hypot(px, py)
                for rr in (4.5, 11.5):
                    if abs(r - rr) < 0.55:
                        if dead and rnd.random() < 0.08:
                            continue
                        put(im, x, y, rail)
                    elif abs(r - (rr + 1)) < 0.5:
                        put(im, x, y, rail_lo)
    if dead:
        for _ in range(6):
            put(im, rnd.randrange(16), rnd.randrange(16), rnd.choice([C["ol2"], C["ol3"], C["rust1"]]))
    return im


def tunnel_roof(seed=0, vent=False):
    rnd = random.Random(seed)
    im = img(16, 16)
    for y in range(16):
        for x in range(16):
            col = rnd.choice([C["d3"], C["d3"], C["d4"], C["d2"]])
            put(im, x, y, col)
    for x in range(16):
        put(im, x, 0, C["g1"])
        put(im, x, 15, C["d1"])
    for y in range(16):
        put(im, 0, y, C["d4"])
        put(im, 15, y, C["d1"])
    # rivets / cracks
    for _ in range(3):
        put(im, rnd.randrange(2, 14), rnd.randrange(2, 14), C["g1"])
    if vent:
        for y in range(5, 11):
            for x in range(4, 12):
                put(im, x, y, C["k"])
        for y in (6, 8):
            for x in range(5, 11):
                put(im, x, y, C["or"] if (x + y) % 3 else C["y"])
    return im


def lot_pad(seed=0):
    rnd = random.Random(seed)
    im = img(32, 32)
    for y in range(2, 30):
        for x in range(2, 30):
            if rnd.random() < 0.55:
                put(im, x, y, rnd.choice([C["d2"], C["d3"]]), 150)
    # hazard corners
    for i in range(6):
        for (x0, y0, dx, dy) in ((1, 1, 1, 1), (30, 1, -1, 1), (1, 30, 1, -1), (30, 30, -1, -1)):
            put(im, x0 + dx * i, y0, C["y"] if i % 2 == 0 else C["k"], 200)
            put(im, x0, y0 + dy * i, C["y"] if i % 2 == 0 else C["k"], 200)
    return im


# ------------------------------------------------------------------ UI frames (9-slice sources)
def frame(w, h, face, edge_hi, edge_lo, border=C["k"], rivets=True):
    im = img(w, h)
    for y in range(h):
        for x in range(w):
            put(im, x, y, face)
    for x in range(w):
        put(im, x, 0, border)
        put(im, x, h - 1, border)
        put(im, x, 1, edge_hi)
        put(im, x, h - 2, edge_lo)
    for y in range(h):
        put(im, 0, y, border)
        put(im, w - 1, y, border)
        put(im, 1, y, edge_hi)
        put(im, w - 2, y, edge_lo)
    for (x, y) in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        im.putpixel((x, y), (0, 0, 0, 0))
    if rivets:
        # keep rivets inside the 4px 9-slice margins so the stretched centre stays flat
        for (x, y) in ((2, 2), (w - 4, 2), (2, h - 4), (w - 4, h - 4)):
            put(im, x, y, edge_hi)
            put(im, x + 1, y + 1, edge_lo)
    return im


def card_frame(band):
    w, h = 48, 62
    im = frame(w, h, C["d2"], C["d4"], C["d1"], rivets=False)
    dark = tuple(int(v * 0.55) for v in band)
    for y in range(2, 12):
        for x in range(2, w - 2):
            put(im, x, y, dark if y > 9 else band if y < 4 else dark)
    for x in range(2, w - 2):
        put(im, x, 2, band)
        put(im, x, 3, band)
        put(im, x, 12, C["k"])
    # art window
    for y in range(13, 47):
        for x in range(3, w - 3):
            put(im, x, y, C["d1"] if (x + y) % 7 else C["d2"])
    for x in range(3, w - 3):
        put(im, x, 47, C["d4"])
    for y in range(13, 47):
        put(im, 3, y, C["k"])
        put(im, w - 4, y, C["k"])
    # corner accents in the band color
    for (x, y) in ((2, h - 3), (w - 3, h - 3), (3, h - 3), (w - 4, h - 3)):
        put(im, x, y, band)
    return im


def card_back():
    w, h = 48, 62
    im = frame(w, h, C["d1"], C["d3"], C["k"], rivets=False)
    for y in range(4, h - 4):
        for x in range(4, w - 4):
            if (x // 3 + y // 3) % 2 == 0:
                put(im, x, y, C["d2"])
    # a tiny train emblem
    for x in range(14, 34):
        for y in range(27, 35):
            put(im, x, y, C["or"] if y in (27, 28) else C["d4"])
    for x in (17, 21, 25, 29):
        put(im, x, 30, C["y"])
    return im


# ------------------------------------------------------------------ icons (ASCII)
ICONS = {
    "scrap": ("""
..kkk..
.kgggk.
kgwgggk
kgg.ggk
kggggdk
.kgddk.
..kkk..""", {"g": C["g2"], "w": C["w"], "d": C["g1"]}),
    "supplies": ("""
.kkkkk.
kyyyyyk
koooook
krrrrrk
koooook
kyyyyyk
.kkkkk.""", {"y": C["y"], "o": C["or"], "r": C["rust2"]}),
    "survivor": ("""
..kkk..
.kyyyk.
.kyyyk.
..kkk..
.kccck.
kccccck
kc.c.ck""", {"y": C["y2"], "c": C["cy"]}),
    "hull": ("""
kkkkkkk
kwgggdk
kgggggk
kgggggk
.kgggk.
..kgk..
...k...""", {"w": C["w"], "g": C["g2"], "d": C["g1"]}),
    "skull": ("""
.kkkkk.
kwwwwwk
kw.w.wk
kwwwwwk
.kwkwk.
.kkkkk.""", {"w": C["w"]}),
    "loop": ("""
..kkkk.
.kyyyyk
ky.kkyk
ky.k.kk
kyk....
.kyyyk.
..kkk..""", {"y": C["or"]}),
    "noise": ("""
...k....
..kk.k..
.kyk..k.
kyyk.k.k
.kyk..k.
..kk.k..
...k....""", {"y": C["pk"]}),
    "card": ("""
kkkkkk
kwwwwk
kwbbwk
kwbbwk
kwwwwk
kkkkkk""", {"w": C["g3"], "b": C["or"]}),
    "relic": ("""
...k...
..kyk..
kkkyykk
kyyyyyk
.kyyyk.
.kykyk.
.kk.kk.""", {"y": C["y"]}),
    "pause": ("""
kk.kk
kk.kk
kk.kk
kk.kk
kk.kk""", {}),
    "play": ("""
k....
kkk..
kkkkk
kkk..
k....""", {}),
    "train": ("""
.kkkkkkk.
kcwcwcwck
kgggggggk
kgggggggk
.kk...kk.""", {"c": C["cy"], "w": C["y"], "g": C["g2"]}),
    "danger": ("""
...k...
..kyk..
..kyk..
.ky.yk.
.kyyyk.
kyykyyk
kkkkkkk""", {"y": C["y"]}),
    # tutorial pointer (index finger up-left) and a chunky arrow pointing down
    "hand": ("""
..kk.......
.kwwk......
.kwwk......
.kwwkkkk...
.kwwkwwkkk.
kkwwwwwwwsk
kwkwwwwwwsk
kwwwwwwwwsk
.kwwwwwwwsk
..kwwwwwsk.
...kwwwwsk.
...kkkkkkk.""", {"w": (244, 240, 250), "s": (170, 166, 190)}),
    "arrow": ("""
...kkk...
...kyk...
...kyk...
...kyk...
kkkkykkkk
kyyyyyyyk
.kyyyyyk.
..kyyyk..
...kyk...
....k....""", {"y": C["y"]}),
    "help": ("""
.kkkkkk.
kwwwwwwk
kwkkkkwk
kkk..kwk
....kwwk
...kwkk.
...kwk..
...kkk..
...kwk..
...kkk..""", {"w": C["cy2"]}),
}


def icon(name):
    art, pal = ICONS[name]
    rows = [r for r in art.strip("\n").split("\n")]
    w = max(len(r) for r in rows)
    im = img(w, len(rows))
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch in (".", " "):
                continue
            if ch in ("k", "к"):
                col = C["k"] if name not in ("pause", "play") else C["w"]
            else:
                col = pal.get(ch)
                if col is None:
                    continue
            put(im, x, y, col)
    return im


# ------------------------------------------------------------------ light textures
def banded_radial(size=64, bands=5):
    im = img(size, size)
    c = (size - 1) / 2
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - c, y - c) / c
            if d >= 1:
                continue
            v = (1 - d) ** 1.4
            v = math.ceil(v * bands) / bands
            im.putpixel((x, y), (255, 255, 255, int(255 * v)))
    return im


def cone(w=96, h=64, bands=5):
    im = img(w, h)
    cy = (h - 1) / 2
    for y in range(h):
        for x in range(w):
            t = x / (w - 1)
            spread = 0.12 + 0.88 * t
            dy = abs(y - cy) / (cy * spread + 0.001)
            if dy >= 1:
                continue
            v = (1 - dy) * (1 - t) ** 0.7
            v = math.ceil(v * bands) / bands
            im.putpixel((x, y), (255, 255, 255, int(255 * v)))
    return im


def soft_dot(size=16):
    im = img(size, size)
    c = (size - 1) / 2
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - c, y - c) / c
            if d < 1:
                im.putpixel((x, y), (255, 255, 255, int(255 * (1 - d) ** 2)))
    return im


def main():
    (OUT / "tiles").mkdir(parents=True, exist_ok=True)
    (OUT / "ui").mkdir(parents=True, exist_ok=True)
    (OUT / "icon").mkdir(parents=True, exist_ok=True)
    (OUT / "fx").mkdir(parents=True, exist_ok=True)
    # track atlas: rows = main / dead, cols = h, v, ne, nw, se, sw (3 variants each for straights)
    kinds = ["h", "v", "ne", "nw", "se", "sw"]
    atlas = img(16 * 6, 16 * 4)
    for row, dead in enumerate([False, True]):
        for col, k in enumerate(kinds):
            for var in range(2):
                t = track_tile(k, dead, seed=row * 100 + col * 10 + var)
                atlas.alpha_composite(t, (col * 16, (row * 2 + var) * 16))
    atlas.save(OUT / "tiles" / "track.png")
    roof = img(16 * 4, 16)
    for i in range(4):
        roof.alpha_composite(tunnel_roof(i, vent=(i == 3)), (i * 16, 0))
    roof.save(OUT / "tiles" / "tunnel.png")
    lot_pad(3).save(OUT / "tiles" / "lot.png")
    frame(16, 16, C["d2"], C["d4"], C["d1"]).save(OUT / "ui" / "panel.png")
    frame(16, 16, C["d1"], C["d3"], C["k"], rivets=False).save(OUT / "ui" / "panel_dark.png")
    frame(12, 12, C["d3"], C["g1"], C["d2"], rivets=False).save(OUT / "ui" / "button.png")
    frame(12, 12, C["d4"], C["g2"], C["d3"], rivets=False).save(OUT / "ui" / "button_hover.png")
    frame(12, 12, C["rust2"], C["or"], C["rust1"], rivets=False).save(OUT / "ui" / "button_hot.png")
    frame(12, 12, C["d2"], C["d3"], C["d1"], rivets=False).save(OUT / "ui" / "button_off.png")
    bands = {"civil": C["cy"], "industry": C["or"], "hostile": C["rd"], "military": C["ol3"],
             "special": C["pu"], "train": C["y"], "action": C["pk"]}
    for k, v in bands.items():
        card_frame(v).save(OUT / "ui" / f"card_{k}.png")
    card_back().save(OUT / "ui" / "card_back.png")
    for name in ICONS:
        icon(name).save(OUT / "icon" / f"i_{name}.png")
    banded_radial(64, 6).save(OUT / "fx" / "light.png")
    cone().save(OUT / "fx" / "cone.png")
    soft_dot().save(OUT / "fx" / "dot.png")
    print("tiles/ui/icons/fx generated")


if __name__ == "__main__":
    main()
