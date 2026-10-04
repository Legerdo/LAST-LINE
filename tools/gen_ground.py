"""Bake the world ground (640x272): ruined-city ground, both rail lines, tunnel floors,
flat props; plus the tunnel roof overlay and a list of tall props placed as live sprites.
Reads art_src/map.json (exported by sim/export_map.gd) and processed sprites.
usage: python tools/gen_ground.py
"""
import json
import random
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SPR = ROOT / "assets" / "sprites"
M = json.loads((ROOT / "art_src" / "map.json").read_text())
T = M["tile"]
W, H = M["cols"] * T, M["rows"] * T
rng = np.random.default_rng(7)
rnd = random.Random(7)


def value_noise(w, h, cell, seed):
    g = np.random.default_rng(seed).random((h // cell + 3, w // cell + 3))
    ys = np.arange(h) / cell
    xs = np.arange(w) / cell
    y0 = ys.astype(int)
    x0 = xs.astype(int)
    fy = ys - y0
    fx = xs - x0
    fy = fy * fy * (3 - 2 * fy)
    fx = fx * fx * (3 - 2 * fx)
    a = g[y0][:, x0]
    b = g[y0][:, x0 + 1]
    c = g[y0 + 1][:, x0]
    d = g[y0 + 1][:, x0 + 1]
    top = a + (b - a) * fx[None, :]
    bot = c + (d - c) * fx[None, :]
    return top + (bot - top) * fy[:, None]


def fbm(w, h, seed, cells=(48, 24, 12, 6)):
    out = np.zeros((h, w))
    amp = 1.0
    tot = 0
    for i, c in enumerate(cells):
        out += value_noise(w, h, c, seed + i) * amp
        tot += amp
        amp *= 0.5
    return out / tot


# ------------------------------------------------------------------ base ground
MAT = {
    # shades dark -> light
    "asphalt": [(24, 24, 36), (30, 30, 44), (36, 36, 52), (44, 44, 60)],
    "dirt": [(30, 24, 28), (38, 30, 32), (46, 36, 36), (56, 44, 40)],
    "rubble": [(34, 30, 40), (44, 40, 50), (56, 52, 60), (72, 66, 72)],
    "grass": [(22, 30, 28), (28, 38, 32), (34, 46, 36), (42, 56, 40)],
}
mat_n = fbm(W, H, 11, (64, 32, 16))
mat_m = fbm(W, H, 29, (80, 40, 20))
detail = fbm(W, H, 5, (8, 4, 2))
speck = rng.random((H, W))

ground = np.zeros((H, W, 3), np.uint8)
mat_id = np.zeros((H, W), np.int8)
mat_id[:] = 0
mat_id[mat_n > 0.56] = 1
mat_id[(mat_n < 0.40)] = 3
mat_id[(mat_m > 0.62) & (mat_id != 3)] = 2
names = ["asphalt", "dirt", "rubble", "grass"]
for i, nm in enumerate(names):
    shades = np.array(MAT[nm])
    m = mat_id == i
    v = detail * 0.8 + speck * 0.35
    lvl = np.clip((v - 0.2) * 3.2, 0, 3).astype(int)
    ground[m] = shades[lvl[m]]

# asphalt road remnants: faded lane dashes on a few long rows / cols
for row in (1, 9, 16):
    y = row * T + 8
    for x in range(0, W, 12):
        if mat_id[y, x] == 0 and rnd.random() < 0.7:
            ground[y, x:x + 6] = (88, 78, 50)


def crack(x, y, n):
    for _ in range(n):
        if 0 <= x < W and 0 <= y < H:
            ground[y, x] = (16, 14, 24)
        x += rnd.choice([-1, 0, 1, 1])
        y += rnd.choice([-1, 0, 1])


for _ in range(70):
    crack(rnd.randrange(W), rnd.randrange(H), rnd.randrange(8, 30))

# puddles reflecting neon
for _ in range(9):
    cx, cy = rnd.randrange(20, W - 20), rnd.randrange(12, H - 12)
    rx, ry = rnd.randrange(5, 11), rnd.randrange(2, 4)
    tint = rnd.choice([(40, 60, 96), (70, 40, 90), (40, 80, 90)])
    for y in range(cy - ry, cy + ry + 1):
        for x in range(cx - rx, cx + rx + 1):
            if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1 and 0 <= x < W and 0 <= y < H:
                ground[y, x] = (18, 20, 34)
                if y == cy - ry + 1 and (x + y) % 3:
                    ground[y, x] = tint

img = Image.fromarray(ground, "RGB").convert("RGBA")

# ------------------------------------------------------------------ rail lines
atlas = Image.open(SPR / "tiles" / "track.png")
KIND_COL = {"h": 0, "v": 1, "ne": 2, "nw": 3, "se": 4, "sw": 5}
EDGE = {(1, 0): "e", (-1, 0): "w", (0, 1): "s", (0, -1): "n"}


def tile_kind(din, dout):
    if din == dout:
        return "h" if din[0] != 0 else "v"
    edges = {EDGE[(-din[0], -din[1])], EDGE[dout]}
    ns = "n" if "n" in edges else "s"
    ew = "e" if "e" in edges else "w"
    return ns + ew


tunnel = {(x, y) for x, y in M["tunnel"]}
floor = Image.new("RGBA", (T, T), (14, 12, 22, 255))
for key, dead in (("cells", False), ("gcells", True)):
    for x, y, dix, diy, dox, doy in M[key]:
        if (x, y) in tunnel:
            img.alpha_composite(floor, (x * T, y * T))
        k = tile_kind((dix, diy), (dox, doy))
        row = (2 if dead else 0) + rnd.randrange(2)
        t = atlas.crop((KIND_COL[k] * T, row * T, KIND_COL[k] * T + T, row * T + T))
        img.alpha_composite(t, (x * T, y * T))

# soft shadow band beside the main line so it sits in the ground
arr = np.array(img)
track_mask = np.zeros((H, W), bool)
for x, y, *_ in M["cells"] + M["gcells"]:
    track_mask[y * T:(y + 1) * T, x * T:(x + 1) * T] = True

# ------------------------------------------------------------------ props
blocked = set()
for x, y, *_ in M["cells"] + M["gcells"]:
    blocked.add((x, y))
for x, y in M["tunnel"]:
    blocked.add((x, y))
for l in M["lots"]:
    for dx in range(l["w"]):
        for dy in range(l["h"]):
            blocked.add((l["x"] + dx, l["y"] + dy))
dx0, dy0, dw, dh = M["depot"]
for dx in range(-1, dw + 1):
    for dy in range(-1, dh):
        blocked.add((dx0 + dx, dy0 + dy))

FLAT = ["rubble_s", "bricks", "trash", "weeds", "bush", "tires", "crates", "barrels", "bones", "car_wreck",
        "burnt_car", "cart", "wheelchair", "sandbags", "barrier", "fence", "sign", "hydrant", "manhole"]
FLAT_W = [8, 6, 6, 8, 7, 5, 5, 5, 3, 4, 4, 2, 1, 3, 3, 3, 2, 2, 2]
TALL = ["lamp", "dead_tree", "pole", "billboard", "vending", "campfire"]
TALL_W = [6, 5, 2, 2, 2, 2]
sprites = {}


def spr(name):
    if name not in sprites:
        sprites[name] = Image.open(SPR / "prop" / f"{name}.png")
    return sprites[name]


free = [(x, y) for x in range(M["cols"]) for y in range(M["rows"]) if (x, y) not in blocked]
rnd.shuffle(free)
placed = []
tall_out = []
shadow = Image.new("RGBA", (1, 1))


def far_enough(px, py, d):
    return all((px - a) ** 2 + (py - b) ** 2 >= d * d for a, b in placed)


for (cx, cy) in free:
    px = cx * T + rnd.randrange(2, 14)
    py = cy * T + rnd.randrange(10, 16)
    if not far_enough(px, py, 21):
        continue
    if rnd.random() < 0.3:
        continue
    if rnd.random() < 0.2:
        name = rnd.choices(TALL, TALL_W)[0]
        tall_out.append({"name": name, "x": px, "y": py})
        placed.append((px, py))
        continue
    if rnd.random() < 0.18:
        continue
    name = rnd.choices(FLAT, FLAT_W)[0]
    s = spr(name)
    wide = s.width > 16
    if wide and ((cx + 1, cy) in blocked or cx + 1 >= M["cols"]):
        continue
    x = px - s.width // 2
    y = py - s.height
    # contact shadow
    sh = np.array(img)
    for yy in range(py - 2, py + 1):
        for xx in range(x + 1, x + s.width - 1):
            if 0 <= xx < W and 0 <= yy < H:
                sh[yy, xx, :3] = (sh[yy, xx, :3] * 0.6).astype(np.uint8)
    img = Image.fromarray(sh, "RGBA")
    img.alpha_composite(s, (max(0, x), max(0, y)))
    placed.append((px, py))

# gentle vignette toward the map edges
arr = np.array(img).astype(float)
yy, xx = np.mgrid[0:H, 0:W]
vx = np.minimum(xx, W - 1 - xx) / 40.0
vy = np.minimum(yy, H - 1 - yy) / 30.0
v = np.clip(np.minimum(vx, vy), 0, 1) * 0.35 + 0.65
arr[..., :3] *= v[..., None]
img = Image.fromarray(arr.astype(np.uint8), "RGBA")
(SPR / "world").mkdir(parents=True, exist_ok=True)
img.save(SPR / "world" / "ground.png")

# ------------------------------------------------------------------ tunnel roofs
# one continuous concrete slab per tunnel: noise texture, seams, outline, lit top edge, vents
tmask = np.zeros((H, W), bool)
for (x, y) in tunnel:
    tmask[y * T:(y + 1) * T, x * T:(x + 1) * T] = True
tex_n = fbm(W, H, 77, (6, 3, 2))
ra = np.zeros((H, W, 4), np.uint8)
shades = np.array([(46, 44, 60), (54, 52, 68), (62, 60, 76), (72, 70, 86)])
lvl = np.clip((tex_n - 0.25) * 6.0, 0, 3).astype(int)
ra[tmask, :3] = shades[lvl[tmask]]
ra[tmask, 3] = 255
yy, xx = np.nonzero(tmask)
# seams every 2 tiles along the tunnel direction
for x0 in range(0, W, 32):
    col = tmask[:, x0]
    ra[col, x0, :3] = (34, 32, 46)
for y0 in range(0, H, 32):
    row = tmask[y0, :]
    ra[y0, row, :3] = (34, 32, 46)
# outline + top light
edge = tmask & ~np.roll(tmask, 1, 0) | tmask & ~np.roll(tmask, -1, 0) | tmask & ~np.roll(tmask, 1, 1) | tmask & ~np.roll(tmask, -1, 1)
ra[edge, :3] = (18, 16, 26)
top_edge = tmask & ~np.roll(tmask, 1, 0)
below_top = np.roll(top_edge, 1, 0) & tmask
ra[below_top, :3] = (104, 100, 120)
left_edge = np.roll(tmask & ~np.roll(tmask, 1, 1), 1, 1) & tmask
ra[left_edge, :3] = (88, 84, 104)
# vents with warm light every few cells
for (x, y) in sorted(tunnel):
    if (x * 7 + y * 3) % 5 == 0:
        cx, cy = x * T + 5, y * T + 6
        ra[cy:cy + 5, cx:cx + 6, :3] = (12, 10, 20)
        for k in range(cy + 1, cy + 5, 2):
            ra[k, cx + 1:cx + 5, :3] = (232, 146, 60)
# portals: dark lip on roof edges that face open track
for (x, y) in tunnel:
    for (dx, dy) in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        n = (x + dx, y + dy)
        if n in tunnel:
            continue
        on_track = any(c[0] == n[0] and c[1] == n[1] for c in M["cells"] + M["gcells"])
        if not on_track:
            continue
        if dx == 1:
            ra[y * T:(y + 1) * T, x * T + 13:x * T + 16] = (20, 16, 26, 255)
            ra[y * T:(y + 1) * T, x * T + 12] = (110, 104, 120, 255)
        elif dx == -1:
            ra[y * T:(y + 1) * T, x * T:x * T + 3] = (20, 16, 26, 255)
            ra[y * T:(y + 1) * T, x * T + 3] = (110, 104, 120, 255)
        elif dy == 1:
            ra[y * T + 13:y * T + 16, x * T:(x + 1) * T] = (20, 16, 26, 255)
            ra[y * T + 12, x * T:(x + 1) * T] = (110, 104, 120, 255)
        else:
            ra[y * T:y * T + 3, x * T:(x + 1) * T] = (20, 16, 26, 255)
            ra[y * T + 3, x * T:(x + 1) * T] = (110, 104, 120, 255)
Image.fromarray(ra, "RGBA").save(SPR / "world" / "tunnel_roof.png")
(ROOT / "assets" / "data").mkdir(parents=True, exist_ok=True)
(ROOT / "assets" / "data" / "props.json").write_text(json.dumps(tall_out))
print("ground baked; tall props:", len(tall_out), "flat placed:", len(placed) - len(tall_out))
