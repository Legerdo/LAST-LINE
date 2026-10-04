"""Balance pass v4.

v3 findings: damage per loop jumps at loop 5 (seeded ruin + infection evolve together, elites
every loop), exponential enemy growth outpaces the train after loop 6, and the AI force-placed
hostile cards whenever its hand was full.
"""
import pathlib

root = pathlib.Path(__file__).resolve().parent.parent
defs = root / "src" / "core" / "defs.gd"
sim = root / "src" / "core" / "sim.gd"
ai = root / "sim" / "ai_player.gd"


def rep(src, a, b, count=1):
    assert src.count(a) == count, (a, src.count(a))
    return src.replace(a, b)


s = defs.read_text(encoding="utf-8")
s = rep(s, 'const ENEMY_HP_GROWTH := 1.12', 'const ENEMY_HP_GROWTH := 1.10')
s = rep(s, 'const ENEMY_DMG_GROWTH := 1.06', 'const ENEMY_DMG_GROWTH := 1.045')
s = rep(s, '"hp": 150.0, "spd": 0.0,\n\t\t"dmg": 7.0', '"hp": 120.0, "spd": 0.0,\n\t\t"dmg": 6.0')
s = rep(s, '"elite": "horror", "elite_every": 1}', '"elite": "horror", "elite_every": 2}')
s = rep(s, '"elite": "warrig", "elite_every": 1}', '"elite": "warrig", "elite_every": 2}')
s = rep(s, '"dmg": 2.0, "cd": 1.8, "mass": 1, "r": 5.0, "scrap": 5', '"dmg": 2.0, "cd": 2.0, "mass": 1, "r": 5.0, "scrap": 5')
s = rep(s, '"desc": "통과 시 많은 고철, 유물 12%.\\n스토커와 쥐떼, 매 바퀴 터널 괴물."',
        '"desc": "통과 시 많은 고철, 유물 12%.\\n스토커와 쥐떼, 2바퀴마다 터널 괴물."')
s = rep(s, '"desc": "약탈자 대군, 매 바퀴 전투 트럭."', '"desc": "약탈자 대군, 2바퀴마다 전투 트럭."')
defs.write_text(s, encoding="utf-8", newline="\n")

t = sim.read_text(encoding="utf-8")
# seeded sites start "younger" so they do not evolve in the same loop as the player's first ones
t = rep(t, '''		_place_fac("ruin", far[0], false)''', '''		var rf := _place_fac("ruin", far[0], false)
		rf.age = -1''')
t = rep(t, '''				_place_fac("infection", far[k], false)''', '''				var inf := _place_fac("infection", far[k], false)
				inf.age = -2''')
sim.write_text(t, encoding="utf-8", newline="\n")

a = ai.read_text(encoding="utf-8")
a = rep(a, '''	if best_i >= 0 and (best_v >= threshold or sim.hand.size() >= Defs.HAND_MAX - 1):''',
        '''	if best_i >= 0 and (best_v >= threshold or (sim.hand.size() >= Defs.HAND_MAX - 1 and best_v >= threshold - 2.5)):''')
ai.write_text(a, encoding="utf-8", newline="\n")
print("v4 applied")
