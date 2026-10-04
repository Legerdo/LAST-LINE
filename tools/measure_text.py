"""QA: measure dispatcher / tutorial / help lines with the in-game fonts.

Neither the focus box nor the help reference auto-wraps (Korean would break mid-word),
so each explicit line must fit on its own. Prints the widest lines, flags overflows.
usage: python tools/measure_text.py
"""
import re
import sys
from pathlib import Path

from PIL import ImageFont

ROOT = Path(__file__).resolve().parent.parent
BB = re.compile(r"\[/?[a-zA-Z_]+(=[^\]]*)?\]")
STR = re.compile(r'"((?:[^"\\]|\\.)*)"')
HANGUL = re.compile(r"[\uac00-\ud7a3]")


def plain_lines(s: str):
    s = s.replace('\\"', '"')
    for part in s.split("\\n"):
        # longest names that realistically fill the placeholders
        yield BB.sub("", part).replace("%s", "용병 초소").replace("%d", "8")


def check(title, font, limit, lines, show=12):
    rows = sorted(((font.getlength(t), t) for t in lines), reverse=True)
    bad = [r for r in rows if r[0] > limit]
    print(f"== {title}: {len(rows)} lines, {len(bad)} over {limit}px")
    for w, t in rows[:show]:
        print(f"{w:6.0f}{'  <-- TOO WIDE' if w > limit else ''}  {t}")
    return len(bad)


def main() -> int:
    box_font = ImageFont.truetype(str(ROOT / "assets/fonts/Galmuri11.ttf"), 12)
    help_font = ImageFont.truetype(str(ROOT / "assets/fonts/Galmuri9.ttf"), 10)
    box_lines = []
    for f in ["src/game/tutorial.gd", "src/ui/hub.gd"]:
        for m in STR.finditer((ROOT / f).read_text(encoding="utf-8")):
            s = m.group(1)
            if HANGUL.search(s) and ("\\n" in s or len(s) >= 12):
                box_lines += list(plain_lines(s))
    src = (ROOT / "src/ui/panels.gd").read_text(encoding="utf-8")
    block = src[src.index("const HELP"):src.index("static func help(")]
    help_lines = []
    for m in STR.finditer(block):
        s = m.group(1)
        if HANGUL.search(s) and "/" not in s[:12]:
            help_lines += list(plain_lines(s))
    bad = check("focus box (Galmuri11 12px)", box_font, 330, box_lines)
    bad += check("help panel (Galmuri9 10px)", help_font, 378, help_lines, 40)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
