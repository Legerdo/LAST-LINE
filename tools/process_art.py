"""Turn raw AI sprite sheets (art_src/*.png, flat magenta background) into game sprites.

Pipeline per sheet:
  1. key out the magenta background (connected components touching the border or large enough)
  2. split sprites by grid cell (component centroids)
  3. quantize to one shared master palette (keeps every asset in the same color world)
  4. mode-downsample to the in-game size, preferring bright emissive colors so lights survive
  5. add a 1px dark outline for readability on the night map
usage: python tools/process_art.py [sheet ...]
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "art_src"
OUT = ROOT / "assets" / "sprites"
PREVIEW = SRC / "preview"
PAL_FILE = SRC / "master_palette.json"

OUTLINE = (12, 10, 20)

# name, grid (cols, rows), cell names row-major, target size mode
SHEETS = {
    "facilities_a": ((4, 4), ["station", "ruin", "market", "hospital",
                              "factory", "checkpoint", "infection", "raiders",
                              "shelter", "power", "radio", "greenhouse",
                              "armory", "blackmarket", "ghost_alt", "depot"], "fac"),
    "facilities_b": ((4, 4), ["transfer", "medhub", "assembly", "hive",
                              "fortress", "ward", "commune", "bastion",
                              "sporefarm", "mercpost", "ghost", "power_over",
                              "lot_empty", "rubble", "bus_wreck", "crater"], "fac"),
    "enemies_a": ((4, 4), ["shambler", "runner", "bloater", "brood",
                           "raider", "bomber", "barricade", "warrig",
                           "stalker", "rat", "horror", "militia",
                           "survivor", "child", "spore", "dog"], "enemy"),
    "train_a": ((3, 3), ["loco", "gun", "flame", "mortar", "armor", "repair",
                         "passenger", "cargo", "tesla"], "car"),
    "boss_a": ((2, 2), ["head", "gun", "brood", "mortar"], "boss"),
    "props_a": ((5, 5), ["car_wreck", "rubble_s", "lamp", "dead_tree", "barrels", "barrier", "tires",
                         "crates", "sign", "bush", "cart", "trash", "pole", "campfire", "burnt_car",
                         "billboard", "bricks", "weeds", "fence", "hydrant", "wheelchair", "sandbags",
                         "bones", "vending", "manhole"], "prop"),
    "relics_a": ((4, 4), ["watch", "bell", "blackbox", "ledger", "oldmap", "token", "gasmask", "trophy",
                          "jammer", "lantern", "coupler", "fuelcell", "ammo", "plate", "napalm", "wrench"], "icon"),
    "modules_a": ((4, 4), ["scope", "mag", "engine", "plow", "shrapnel", "coil", "drill", "patch",
                           "crate", "scrapheap", "food", "water", "cardback", "blueprint", "mic", "skullcrack"], "icon"),
    "portraits_a": ((3, 2), ["dispatcher", "warlord", "refugee", "merchant", "mechanic", "unknown"], "portrait"),
}

# target widths (px) per sprite; defaults by mode
DEFAULT_W = {"fac": 40, "enemy": 20, "car": 30, "boss": 36, "prop": 16, "icon": 16, "portrait": 54}
SIZE_OVERRIDE = {
    "enemies_a": {"brood": 30, "bloater": 22, "warrig": 32, "barricade": 26, "horror": 30, "rat": 18,
                  "dog": 22, "stalker": 20, "spore": 22, "runner": 20, "militia": 16, "survivor": 15, "child": 12},
    "train_a": {"loco": 34},
    "boss_a": {"head": 40, "gun": 34, "brood": 34, "mortar": 34},
    "facilities_a": {"depot": 60},
    "facilities_b": {"hive": 46, "fortress": 46, "rubble": 40, "bus_wreck": 40, "crater": 40, "lot_empty": 36},
    "props_a": {"car_wreck": 22, "burnt_car": 22, "billboard": 20, "pole": 20, "fence": 18, "vending": 14,
                "barrier": 16, "lamp": 10, "hydrant": 8, "sign": 10, "manhole": 12, "weeds": 12, "bones": 14},
    "relics_a": {},
}
# sprites without legit purple/pink: strip any magenta-tinted leftovers from the key
DEKEY = {"barricade": 0.3, "warrig": 0.35, "raider": 0.35, "militia": 0.35, "survivor": 0.35,
         "loco": 0.35, "gun": 0.35, "cargo": 0.35, "armor": 0.35, "repair": 0.35, "mortar": 0.35,
         "cart": 0.25, "wheelchair": 0.25, "fence": 0.25, "billboard": 0.25, "pole": 0.25, "sign": 0.3,
         "dead_tree": 0.25, "lamp": 0.3, "car_wreck": 0.3, "burnt_car": 0.3, "tires": 0.3, "barrels": 0.3,
         "crates": 0.3, "bricks": 0.3, "rubble_s": 0.3, "trash": 0.3, "bones": 0.3, "hydrant": 0.3,
         "sandbags": 0.3, "barrier": 0.3, "manhole": 0.3}
FOLDER = {"fac": "fac", "enemy": "enemy", "car": "train", "boss": "boss", "prop": "prop", "icon": "icon",
          "portrait": "portrait"}


def magenta_score(rgb: np.ndarray) -> np.ndarray:
    """0..1, how much a pixel looks like the magenta key (including dark/blended fringe)."""
    r, g, b = rgb[..., 0].astype(float), rgb[..., 1].astype(float), rgb[..., 2].astype(float)
    rb = np.minimum(r, b)
    tint = (rb - g) / 255.0            # magenta = red & blue high, green low
    balance = 1.0 - np.abs(r - b) / 255.0
    return np.clip(tint * 1.6, 0, 1) * np.clip(balance * 1.4 - 0.3, 0, 1)


def background_mask(rgb: np.ndarray) -> np.ndarray:
    r, g, b = rgb[..., 0].astype(int), rgb[..., 1].astype(int), rgb[..., 2].astype(int)
    magenta = (r > 170) & (b > 170) & (g < 110) & (np.abs(r - b) < 80)
    # enclosed holes must be almost the exact key color; purple glows are not
    strict = ((r - 255) ** 2 + g ** 2 + (b - 255) ** 2) < 55 ** 2
    lab, n = ndimage.label(magenta)
    if n == 0:
        return magenta
    border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    keep = np.zeros(n + 1, bool)
    for i in border:
        keep[i] = True
    bg = keep[lab]
    lab2, n2 = ndimage.label(strict & ~bg)
    if n2:
        sizes2 = ndimage.sum(np.ones_like(lab2), lab2, range(1, n2 + 1))
        big = np.zeros(n2 + 1, bool)
        big[1:] = sizes2 > 60
        bg |= big[lab2]
    # blended fringe: strongly magenta-tinted pixels right next to the background
    score = magenta_score(rgb)
    near = ndimage.binary_dilation(bg, iterations=3)
    bg |= near & (score > 0.45)
    near2 = ndimage.binary_dilation(bg, iterations=1)
    bg |= near2 & (score > 0.3)
    return bg


ACCENTS = [(96, 228, 255), (190, 250, 255), (255, 70, 170), (255, 170, 220), (182, 255, 84),
           (255, 64, 64), (255, 214, 90), (255, 250, 230), (178, 96, 255), (255, 140, 40)]


def hsv_arrays(px):
    f = px.astype(float) / 255.0
    mx = f.max(1)
    mn = f.min(1)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    return sat, mx


def build_palette(names, n_colors=108):
    """k-means over every sheet's foreground pixels, with vivid pixels oversampled so
    neon lights and fire keep their own palette entries; then fixed accent colors."""
    from scipy.cluster.vq import kmeans2
    rng = np.random.default_rng(1)
    samples = []
    for nm in names:
        p = SRC / f"{nm}.png"
        if not p.exists():
            continue
        rgb = np.array(Image.open(p).convert("RGB"))
        bg = background_mask(rgb)
        px = rgb[~bg]
        if len(px) > 40000:
            px = px[rng.choice(len(px), 40000, replace=False)]
        sat, val = hsv_arrays(px)
        vivid = px[(sat > 0.45) & (val > 0.62)]
        if len(vivid):
            vivid = vivid[rng.choice(len(vivid), min(len(vivid) * 5, 30000), replace=True)]
        samples.append(px)
        samples.append(vivid)
    data = np.concatenate([s for s in samples if len(s)]).astype(float)
    cent, _ = kmeans2(data, n_colors, iter=25, minit="++", seed=3)
    pal = [tuple(int(round(v)) for v in np.clip(c, 0, 255)) for c in cent]
    pal += ACCENTS
    pal.append(OUTLINE)
    PAL_FILE.write_text(json.dumps(pal))
    return pal


def to_lab(rgb: np.ndarray) -> np.ndarray:
    c = rgb.astype(float) / 255.0
    c = np.where(c > 0.04045, ((c + 0.055) / 1.055) ** 2.4, c / 12.92)
    m = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = c @ m.T / np.array([0.9505, 1.0, 1.089])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    L = 116 * f[..., 1] - 16
    a = 500 * (f[..., 0] - f[..., 1])
    b = 200 * (f[..., 1] - f[..., 2])
    return np.stack([L, a, b], -1)


_PAL_LAB = {}


def quantize_to(rgb: np.ndarray, pal: np.ndarray) -> np.ndarray:
    key = pal.tobytes()
    if key not in _PAL_LAB:
        _PAL_LAB[key] = to_lab(pal.reshape(-1, 1, 3)).reshape(-1, 3)
    plab = _PAL_LAB[key]
    flat = to_lab(rgb.reshape(-1, 1, 3)).reshape(-1, 3)
    best = np.zeros(len(flat), np.int32)
    bestd = np.full(len(flat), np.inf)
    for i, c in enumerate(plab):
        d = ((flat - c) ** 2).sum(1)
        m = d < bestd
        bestd[m] = d[m]
        best[m] = i
    return best.reshape(rgb.shape[:2])


def color_lift(rgb: np.ndarray, bright=1.0, sat=1.0) -> np.ndarray:
    f = rgb.astype(float)
    grey = f.mean(-1, keepdims=True)
    f = grey + (f - grey) * sat
    f = 255.0 * (np.clip(f, 0, 255) / 255.0) ** (1.0 / bright)
    return np.clip(f, 0, 255).astype(np.uint8)


LIFT = {"enemy": (1.18, 1.2), "car": (1.08, 1.05), "boss": (1.05, 1.1), "prop": (1.05, 1.0),
        "fac": (1.06, 1.08), "icon": (1.05, 1.05), "portrait": (1.05, 1.05)}


def vivid_mask(px):
    sat, val = hsv_arrays(px.reshape(-1, 3))
    return (((sat > 0.5) & (val > 0.8)) | ((val > 0.93) & (sat < 0.3))).reshape(px.shape[:-1])


def downsample(rgb: np.ndarray, alpha: np.ndarray, pal, tw: int, th: int):
    """Area downsample to the master palette.
    - blocks with enough vivid (light-emitting) source pixels keep that light color
    - blocks with a clearly dominant palette color keep it (crisp edges)
    - the rest average, get a little contrast back, and snap to the palette
    Returns (rgba, glow_mask)."""
    h, w = alpha.shape
    pal_np = np.array(pal)
    idx = quantize_to(rgb, pal_np)
    viv = vivid_mask(rgb)
    out = np.zeros((th, tw, 4), np.uint8)
    glow = np.zeros((th, tw), bool)
    pending = []
    for ty in range(th):
        y0 = int(ty * h / th)
        y1 = max(int((ty + 1) * h / th), y0 + 1)
        for tx in range(tw):
            x0 = int(tx * w / tw)
            x1 = max(int((tx + 1) * w / tw), x0 + 1)
            a = alpha[y0:y1, x0:x1]
            if a.mean() < 0.5:
                continue
            out[ty, tx, 3] = 255
            block = rgb[y0:y1, x0:x1][a]
            vb = viv[y0:y1, x0:x1][a]
            if vb.mean() >= 0.28:
                pending.append((ty, tx, block[vb].mean(0), 1.0, True))
                continue
            ids = idx[y0:y1, x0:x1][a]
            cnt = np.bincount(ids, minlength=len(pal))
            top = int(cnt.argmax())
            if cnt[top] >= 0.5 * cnt.sum():
                out[ty, tx, :3] = pal[top]
            else:
                pending.append((ty, tx, block.mean(0), 1.15, False))
    if pending:
        arr = np.array([p[2] for p in pending]).reshape(-1, 1, 3)
        gain = np.array([p[3] for p in pending]).reshape(-1, 1, 1)
        mean = arr.mean()
        arr = np.clip((arr - mean) * gain + mean, 0, 255)
        q = quantize_to(arr, pal_np).reshape(-1)
        for (ty, tx, _, _, is_glow), qi in zip(pending, q):
            out[ty, tx, :3] = pal[int(qi)]
            glow[ty, tx] = is_glow
    return out, glow


def add_outline(img: np.ndarray, glow: np.ndarray):
    a = img[..., 3] > 0
    h, w = a.shape
    big = np.zeros((h + 2, w + 2, 4), np.uint8)
    big[1:-1, 1:-1] = img
    g = np.zeros((h + 2, w + 2), bool)
    g[1:-1, 1:-1] = glow
    ab = big[..., 3] > 0
    ring = ndimage.binary_dilation(ab, structure=[[0, 1, 0], [1, 1, 1], [0, 1, 0]]) & ~ab
    big[ring] = (*OUTLINE, 255)
    return big, g


def glow_image(img: np.ndarray, glow: np.ndarray) -> np.ndarray:
    out = np.zeros_like(img)
    out[glow] = img[glow]
    return out


# procedural frame animation ------------------------------------------------
ANIM = {
    "walker": ["shambler", "runner", "bloater", "brood", "raider", "bomber", "stalker", "dog",
               "militia", "survivor", "child"],
    "bounce": ["warrig", "rat"],
    "stretch": ["horror"],
}


def _shift_rows(img, y0, y1, dx):
    out = img.copy()
    band = img[y0:y1].copy()
    out[y0:y1] = 0
    w = img.shape[1]
    if dx >= 0:
        out[y0:y1, dx:] = band[:, : w - dx]
    else:
        out[y0:y1, : w + dx] = band[:, -dx:]
    return out


def _shift_all(img, dx, dy):
    out = np.zeros_like(img)
    h, w = img.shape[:2]
    ys = slice(max(0, dy), min(h, h + dy))
    yd = slice(max(0, -dy), min(h, h - dy))
    xs = slice(max(0, dx), min(w, w + dx))
    xd = slice(max(0, -dx), min(w, w - dx))
    out[ys, xs] = img[yd, xd]
    return out


def make_frames(img, kind):
    """4 frames: idle, step A, step B, attack. Frames are padded by 2 px on each side."""
    h, w = img.shape[:2]
    pad = np.zeros((h + 3, w + 4) + img.shape[2:], img.dtype)
    pad[3:, 2:-2] = img
    H = pad.shape[0]
    legs = int(H * 0.62)
    if kind == "walker":
        a = _shift_all(_shift_rows(pad, legs, H, 1), 0, -1)
        b = _shift_rows(pad, legs, H, -1)
        atk = _shift_rows(pad, 0, int(H * 0.55), 2)
        atk = _shift_rows(atk, int(H * 0.55), legs, 1)
    elif kind == "bounce":
        a = _shift_all(pad, 0, -1)
        b = pad.copy()
        atk = _shift_all(pad, 1, -2)
    elif kind == "stretch":
        # duplicate middle rows to stretch the worm up
        mid = int(H * 0.5)
        a = np.concatenate([pad[1:mid + 1], pad[mid:]], 0)[:H]
        a = np.concatenate([pad[2:mid + 1], pad[mid - 1:mid], pad[mid:]], 0)[:H]
        b = pad.copy()
        atk = np.concatenate([pad[3:mid + 1], np.repeat(pad[mid:mid + 1], 2, 0), pad[mid:]], 0)[:H]
    else:
        a = b = atk = pad
    return np.concatenate([pad, a, b, atk], 1)


def process_sheet(name, pal):
    (cols, rows), names, mode = SHEETS[name]
    path = SRC / f"{name}.png"
    if not path.exists():
        print("missing", path)
        return []
    rgb = np.array(Image.open(path).convert("RGB"))
    H, W = rgb.shape[:2]
    bg = background_mask(rgb)
    fg = ~bg
    fg = ndimage.binary_opening(fg, iterations=1)
    lab, n = ndimage.label(fg, structure=np.ones((3, 3)))
    sizes = ndimage.sum(fg, lab, range(1, n + 1))
    coms = ndimage.center_of_mass(fg, lab, range(1, n + 1))
    cell_w, cell_h = W / cols, H / rows
    groups = {}
    for i in range(n):
        if sizes[i] < 40:
            continue
        cy, cx = coms[i]
        c = min(cols - 1, int(cx / cell_w))
        r = min(rows - 1, int(cy / cell_h))
        groups.setdefault(r * cols + c, []).append(i + 1)
    folder = OUT / FOLDER[mode]
    folder.mkdir(parents=True, exist_ok=True)
    made = []
    for k, nm in enumerate(names):
        if k not in groups:
            print(f"  {name}: no sprite for cell {k} ({nm})")
            continue
        mask = np.isin(lab, groups[k])
        ys, xs = np.nonzero(mask)
        y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        crop = color_lift(rgb[y0:y1, x0:x1], *LIFT.get(mode, (1.0, 1.0)))
        m = mask[y0:y1, x0:x1]
        if nm in DEKEY:
            m = m & (magenta_score(rgb[y0:y1, x0:x1]) < DEKEY[nm])
        tw = SIZE_OVERRIDE.get(name, {}).get(nm, DEFAULT_W[mode])
        th = max(1, int(round(tw * (y1 - y0) / (x1 - x0))))
        small, glow = downsample(crop, m, pal, tw, th)
        # key leaks sit on the silhouette edge: peel magenta-tinted edge pixels
        cross = [[0, 1, 0], [1, 1, 1], [0, 1, 0]]
        for _ in range(2):
            a = small[..., 3] > 0
            edge = a & ndimage.binary_dilation(~a, structure=cross)
            kill = edge & (magenta_score(small[..., :3]) > 0.45)
            small[kill] = 0
            glow[kill] = False
        if mode != "portrait":
            small, glow = add_outline(small, glow)
        Image.fromarray(small, "RGBA").save(folder / f"{nm}.png")
        if mode == "portrait":
            sw = 26
            sh = max(1, int(round(sw * (y1 - y0) / (x1 - x0))))
            s2, _ = downsample(crop, m, pal, sw, sh)
            Image.fromarray(s2, "RGBA").save(folder / f"{nm}_s.png")
        g = glow_image(small, glow)
        if g[..., 3].any():
            Image.fromarray(g, "RGBA").save(folder / f"{nm}_glow.png")
        elif (folder / f"{nm}_glow.png").exists():
            (folder / f"{nm}_glow.png").unlink()
        if mode == "enemy":
            kind = next((kk for kk, v in ANIM.items() if nm in v), None)
            if kind:
                Image.fromarray(make_frames(small, kind), "RGBA").save(folder / f"{nm}_anim.png")
                if g[..., 3].any():
                    Image.fromarray(make_frames(g, kind), "RGBA").save(folder / f"{nm}_anim_glow.png")
        made.append((nm, small))


    # preview contact sheet at 4x
    if made:
        pad = 4
        cw = max(s.shape[1] for _, s in made) + pad
        ch = max(s.shape[0] for _, s in made) + pad
        per = min(8, len(made))
        sheet = Image.new("RGBA", (cw * per, ch * ((len(made) + per - 1) // per)), (40, 44, 60, 255))
        for i, (_, s) in enumerate(made):
            im = Image.fromarray(s, "RGBA")
            sheet.alpha_composite(im, ((i % per) * cw + pad // 2, (i // per) * ch + pad // 2))
        PREVIEW.mkdir(exist_ok=True)
        sheet = sheet.resize((sheet.width * 4, sheet.height * 4), Image.NEAREST)
        if sheet.width > 1900:
            f = 1900 / sheet.width
            sheet = sheet.resize((int(sheet.width * f), int(sheet.height * f)), Image.NEAREST)
        sheet.save(PREVIEW / f"{name}_preview.png")
    print(f"{name}: {len(made)} sprites")
    return made


def process_backdrop(name, out_name, crop_top=0.5):
    """Full-screen illustrations: crop to 16:9, box-downsample to 640x360, 96-color palette."""
    p = SRC / f"{name}.png"
    if not p.exists():
        return
    im = Image.open(p).convert("RGB")
    w, h = im.size
    th = int(w * 9 / 16)
    top = int((h - th) * crop_top)
    im = im.crop((0, top, w, top + th))
    small = im.resize((640, 360), Image.BOX)
    q = small.quantize(colors=96, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    (OUT / "ui").mkdir(parents=True, exist_ok=True)
    q.save(OUT / "ui" / f"{out_name}.png")
    print(out_name, "done")


def main():
    names = sys.argv[1:] or list(SHEETS.keys()) + ["keyart", "hub_bg"]
    if PAL_FILE.exists():
        pal = [tuple(c) for c in json.loads(PAL_FILE.read_text())]
    else:
        pal = build_palette(["facilities_a", "facilities_b", "enemies_a", "train_a", "boss_a"])
    print("palette", len(pal))
    for nm in names:
        if nm == "keyart":
            process_backdrop("keyart", "keyart", 0.5)
        elif nm == "hub_bg":
            process_backdrop("hub_bg", "hub_bg", 0.3)
        elif nm in SHEETS:
            process_sheet(nm, pal)


if __name__ == "__main__":
    main()
