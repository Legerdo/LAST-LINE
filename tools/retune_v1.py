"""Balance pass v1 (after baseline v0: every persona died by loop ~4, boss arrived at loop 4).

- Horde noise per facility roughly halved, base per loop 6 -> 5
- Starting hull 70 -> 80, max cars 4 -> 5, gun car slightly stronger
- Raider chip damage and elite burst lowered (bullets / horrors were the top killers)
- Hostile evolutions take one more loop
"""
import re
import pathlib

p = pathlib.Path(__file__).resolve().parent.parent / "src" / "core" / "defs.gd"
s = p.read_text(encoding="utf-8")

noise = {"station": 1, "transfer": 1, "ruin": 1, "ghost": 2, "market": 1, "blackmarket": 2,
         "hospital": 0.5, "medhub": 1, "ward": 2, "factory": 2, "assembly": 3, "checkpoint": 0.5,
         "mercpost": 1, "bastion": 1, "infection": 1, "hive": 2.5, "raiders": 1, "fortress": 2.5,
         "shelter": 0.5, "commune": 1, "power": 2.5, "radio": 5, "greenhouse": 0, "sporefarm": 1.5,
         "armory": 1, "purge": 0}
for k, v in noise.items():
    pat = r'("%s": \{"name": "[^"]+", "cat": "[a-z]+", "tags": \[[^\]]*\], "noise": )[0-9.]+' % k
    s, n = re.subn(pat, lambda m: m.group(1) + str(float(v)), s)
    assert n == 1, k


def rep(a, b):
    global s
    assert a in s, a
    s = s.replace(a, b)


rep('const HORDE_BASE_PER_LOOP := 6.0', 'const HORDE_BASE_PER_LOOP := 5.0')
rep('const BASE_HULL := 70.0', 'const BASE_HULL := 80.0')
rep('const BASE_MAX_CARS := 4', 'const BASE_MAX_CARS := 5')
rep('"weapon": {"kind": "gun", "dmg": 4.0, "rate": 2.4, "range": 66.0}}',
    '"weapon": {"kind": "gun", "dmg": 5.0, "rate": 2.5, "range": 68.0}}')
rep('"dmg": 3.0, "cd": 1.5, "mass": 1, "r": 5.0, "scrap": 5, "card": 0.20, "range": 62.0}',
    '"dmg": 2.0, "cd": 1.8, "mass": 1, "r": 5.0, "scrap": 5, "card": 0.20, "range": 62.0}')
rep('"dmg": 7.0, "cd": 2.8, "mass": 1, "r": 5.0, "scrap": 6, "card": 0.22, "range": 52.0, "splash": 16.0}',
    '"dmg": 5.0, "cd": 3.0, "mass": 1, "r": 5.0, "scrap": 6, "card": 0.22, "range": 52.0, "splash": 16.0}')
rep('"ai": "horror", "hp": 260.0, "spd": 0.0,\n\t\t"dmg": 12.0', '"ai": "horror", "hp": 150.0, "spd": 0.0,\n\t\t"dmg": 8.0')
rep('"ai": "rig", "hp": 240.0, "spd": 50.0,\n\t\t"dmg": 18.0', '"ai": "rig", "hp": 160.0, "spd": 50.0,\n\t\t"dmg": 12.0')
rep('"range": 70.0, "gun": 3.0, "elite": true}', '"range": 70.0, "gun": 2.0, "elite": true}')
rep('"ai": "brood", "hp": 180.0', '"ai": "brood", "hp": 140.0')
rep('"3바퀴 방치 → 망령역 / 피난처 인접 → 역 복구"', '"4바퀴 방치 → 망령역 / 피난처 인접 → 역 복구"')
rep('"3바퀴 → 둥지 (공장 인접 시 2바퀴)"', '"4바퀴 → 둥지 (공장 인접 시 3바퀴)"')
rep('"3바퀴 또는 시장 2곳 인접 → 요새"', '"4바퀴 또는 시장 2곳 인접 → 요새"')
p.write_text(s, encoding="utf-8", newline="\n")
print("defs retuned")
