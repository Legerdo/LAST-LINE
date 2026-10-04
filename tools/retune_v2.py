"""Balance pass v2 (after v1: boss at loop 5 median, boss left at 80-95% hp on losses,
death kept ~65% of a return because of cargo cars, damage per loop climbing too fast).
"""
import re
import pathlib

root = pathlib.Path(__file__).resolve().parent.parent
p = root / "src" / "core" / "defs.gd"
s = p.read_text(encoding="utf-8")

noise = {"station": 0.5, "transfer": 1, "ruin": 0.5, "ghost": 1.5, "market": 1, "blackmarket": 1.5,
         "hospital": 0.5, "medhub": 1, "ward": 1.5, "factory": 1.5, "assembly": 2, "checkpoint": 0.5,
         "mercpost": 0.5, "bastion": 1, "infection": 1, "hive": 2, "raiders": 1, "fortress": 2,
         "shelter": 0.5, "commune": 0.5, "power": 2, "radio": 5, "greenhouse": 0, "sporefarm": 1,
         "armory": 1, "purge": 0}
for k, v in noise.items():
    pat = r'("%s": \{"name": "[^"]+", "cat": "[a-z]+", "tags": \[[^\]]*\], "noise": )[0-9.]+' % k
    s, n = re.subn(pat, lambda m: m.group(1) + str(float(v)), s)
    assert n == 1, k


def rep(a, b):
    global s
    assert a in s, a
    s = s.replace(a, b)


rep('const HORDE_BASE_PER_LOOP := 5.0', 'const HORDE_BASE_PER_LOOP := 4.0')
rep('const HORDE_PER_PLACE := 1.0', 'const HORDE_PER_PLACE := 0.5')
rep('const ENEMY_HP_GROWTH := 1.13', 'const ENEMY_HP_GROWTH := 1.12')
rep('const ENEMY_DMG_GROWTH := 1.08', 'const ENEMY_DMG_GROWTH := 1.06')
rep('"loot": 0.25, "keep": 0.10,', '"loot": 0.25, "keep": 0.05,')
rep('"화물차", "hull": 30, "loot": 0.25, "keep": 0.05, "desc": "고철 획득 +25%, 파괴 시 보존 +10%."',
    '"화물차", "hull": 30, "loot": 0.25, "keep": 0.05, "desc": "고철 획득 +25%, 파괴 시 보존 +5%."')
rep('"head_hp": 900.0, "car_hp": 300.0, "hp_per_loop": 0.07,', '"head_hp": 1200.0, "car_hp": 400.0, "hp_per_loop": 0.07,')
rep('"ram_dmg": 22.0, "shell_dmg": 7.0, "mortar_dmg": 9.0,', '"ram_dmg": 16.0, "shell_dmg": 3.0, "mortar_dmg": 6.0, "dmg_per_loop": 0.06,')
p.write_text(s, encoding="utf-8", newline="\n")

q = root / "src" / "core" / "sim.gd"
t = q.read_text(encoding="utf-8")


def rep2(a, b, count=1):
    global t
    assert t.count(a) == count, (a, t.count(a))
    t = t.replace(a, b)


rep2('return minf(0.8, k)', 'return minf(0.6, k)')
rep2('pct = 0.10 + 0.05 * adj_count(f.lot, ["hospital", "medhub"])', 'pct = 0.12 + 0.05 * adj_count(f.lot, ["hospital", "medhub"])', 2)
rep2('"hospital":\n\t\t\t\t\tpct = 0.08', '"hospital":\n\t\t\t\t\tpct = 0.10')
# boss damage uses its own gentler scaling
rep2('var dmg := float(Defs.BOSS.ram_dmg) * enemy_dmg_mult() * (1.2 if boss_enraged else 1.0)',
     'var dmg := float(Defs.BOSS.ram_dmg) * boss_dmg_mult() * (1.2 if boss_enraged else 1.0)')
rep2('pr.dmg = float(Defs.BOSS.shell_dmg) * enemy_dmg_mult()', 'pr.dmg = float(Defs.BOSS.shell_dmg) * boss_dmg_mult()')
rep2('pr.dmg = float(Defs.BOSS.mortar_dmg) * enemy_dmg_mult()', 'pr.dmg = float(Defs.BOSS.mortar_dmg) * boss_dmg_mult()')
rep2('\t\t\t\tbp.cd = 3.2\n', '\t\t\t\tbp.cd = 4.2\n')
rep2('\t\t\t\tbp.cd = 9.0\n\t\t\t\tfor k in 3:', '\t\t\t\tbp.cd = 10.0\n\t\t\t\tfor k in 2:')
rep2('\t\t\t\tbp.cd = 6.5\n', '\t\t\t\tbp.cd = 7.0\n')
rep2('func boss_hp_ratio() -> float:', 'func boss_dmg_mult() -> float:\n\treturn 1.0 + float(Defs.BOSS.dmg_per_loop) * (loop - 1)\n\n\nfunc boss_hp_ratio() -> float:')
q.write_text(t, encoding="utf-8", newline="\n")
print("v2 applied")
