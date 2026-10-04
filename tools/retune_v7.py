"""Balance pass v7: make danger pay.
Card-impact report on v6 (within persona+meta): raiders -66 bank / -11% wins, infection -30 / -9%.
The risk cards were traps. Raider kills now pay more scrap, infected kills drop more cards.
"""
import pathlib

p = pathlib.Path(__file__).resolve().parent.parent / "src" / "core" / "defs.gd"
s = p.read_text(encoding="utf-8")


def rep(a, b):
    global s
    assert s.count(a) == 1, a
    s = s.replace(a, b)


rep('"scrap": 2, "card": 0.14},\n\t"runner"', '"scrap": 2, "card": 0.18},\n\t"runner"')
rep('"mass": 1, "r": 4.0, "scrap": 2, "card": 0.10}', '"mass": 1, "r": 4.0, "scrap": 2, "card": 0.13}')
rep('"mass": 1, "r": 4.0, "scrap": 3, "card": 0.10}', '"mass": 1, "r": 4.0, "scrap": 3, "card": 0.13}')
rep('"scrap": 6, "card": 0.25, "blast": 24.0}', '"scrap": 6, "card": 0.30, "blast": 24.0}')
rep('"scrap": 30, "card": 1.0, "relic": 0.20, "elite": true}', '"scrap": 30, "card": 1.0, "relic": 0.30, "elite": true}')
rep('"scrap": 5, "card": 0.15, "range": 62.0}', '"scrap": 7, "card": 0.15, "range": 62.0}')
rep('"scrap": 6, "card": 0.16, "range": 52.0', '"scrap": 8, "card": 0.16, "range": 52.0')
rep('"scrap": 8, "card": 0.20}', '"scrap": 10, "card": 0.20}')
rep('"scrap": 45, "card": 1.0, "relic": 0.30,', '"scrap": 60, "card": 1.0, "relic": 0.30,')
p.write_text(s, encoding="utf-8", newline="\n")
print("v7 applied")
