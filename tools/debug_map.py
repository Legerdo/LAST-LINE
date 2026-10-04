"""Quick layout check: draws track, dead line, tunnels, lots and depot from art_src/map.json."""
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
m = json.loads((ROOT / "art_src" / "map.json").read_text())
T = m["tile"]
S = 3
im = Image.new("RGB", (m["cols"] * T * S, m["rows"] * T * S), (30, 30, 40))
d = ImageDraw.Draw(im)
for x, y, *_ in m["cells"]:
    d.rectangle([x * T * S, y * T * S, (x + 1) * T * S - 1, (y + 1) * T * S - 1], fill=(160, 150, 120))
for x, y, *_ in m["gcells"]:
    d.rectangle([x * T * S, y * T * S, (x + 1) * T * S - 1, (y + 1) * T * S - 1], fill=(110, 60, 60))
for x, y in m["tunnel"]:
    d.rectangle([x * T * S + 6, y * T * S + 6, (x + 1) * T * S - 7, (y + 1) * T * S - 7], outline=(0, 0, 0), width=3)
for l in m["lots"]:
    col = (60, 140, 200) if l["side"] == 1 else (200, 140, 60)
    d.rectangle([l["x"] * T * S, l["y"] * T * S, (l["x"] + l["w"]) * T * S - 1, (l["y"] + l["h"]) * T * S - 1], outline=col, width=3)
    d.text((l["x"] * T * S + 8, l["y"] * T * S + 8), str(l["id"]), fill=(255, 255, 255))
dx, dy, dw, dh = m["depot"]
d.rectangle([dx * T * S, dy * T * S, (dx + dw) * T * S - 1, (dy + dh) * T * S - 1], fill=(90, 160, 90))
im.save(ROOT / "art_src" / "preview" / "map_debug.png")
print(im.size)
