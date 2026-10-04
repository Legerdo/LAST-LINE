"""Build a contact sheet from sequential QA screenshots around the region that changes most.
usage: python tools/contact_sheet.py <dir> <out.png> [count] [crop_w] [crop_h]
"""
import glob
import sys

from PIL import Image, ImageChops, ImageDraw

d, out = sys.argv[1], sys.argv[2]
count = int(sys.argv[3]) if len(sys.argv) > 3 else 12
cw = int(sys.argv[4]) if len(sys.argv) > 4 else 160
ch = int(sys.argv[5]) if len(sys.argv) > 5 else 110
fs = sorted(glob.glob(d + "/shot_*.png"))[:count]
ims = [Image.open(f).convert("RGB") for f in fs]
acc = Image.new("L", ims[0].size, 0)
for a, b in zip(ims, ims[1:]):
    df = ImageChops.difference(a, b).convert("L").point(lambda v: 255 if v > 50 else 0)
    acc = ImageChops.lighter(acc, df)
# ignore the HUD strips
acc.paste(0, (0, 0, 640, 26))
acc.paste(0, (0, 294, 640, 360))
bbox = acc.getbbox() or (0, 0, cw, ch)
cx = (bbox[0] + bbox[2]) // 2
cy = (bbox[1] + bbox[3]) // 2
x0 = max(0, min(640 - cw, cx - cw // 2))
y0 = max(0, min(360 - ch, cy - ch // 2))
cols = 4
rows = (len(ims) + cols - 1) // cols
sc = 2
sheet = Image.new("RGB", (cols * cw * sc, rows * ch * sc), (0, 0, 0))
for i, im in enumerate(ims):
    crop = im.crop((x0, y0, x0 + cw, y0 + ch)).resize((cw * sc, ch * sc), Image.NEAREST)
    sheet.paste(crop, ((i % cols) * cw * sc, (i // cols) * ch * sc))
    ImageDraw.Draw(sheet).text(((i % cols) * cw * sc + 4, (i // cols) * ch * sc + 4), fs[i][-10:-4], fill=(255, 255, 0))
sheet.save(out)
print("region", (x0, y0), "sheet", sheet.size)
