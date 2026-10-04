"""Balance pass v3.

Trace findings (economy persona, seed 2000):
- Boss fight: hull 226 -> 22 in 10 s. Area attacks damaged every car in range and the hull is a
  shared pool, so one shell counted 2-5 times. -> area damage now hits the pool once, scaled by
  1 + 0.3 per extra car caught.
- Scrap: 1313 by loop 7 (3 cargo cars, ram kills, market chains). -> cargo +15%, kill scrap growth
  5%/loop, market/salvage values lowered, ram damage lowered.
- ~40 cards per run with 5-10 discarded -> drop chances about -30%.
"""
import pathlib

root = pathlib.Path(__file__).resolve().parent.parent
defs = root / "src" / "core" / "defs.gd"
sim = root / "src" / "core" / "sim.gd"
s = defs.read_text(encoding="utf-8")
t = sim.read_text(encoding="utf-8")


def rep(src, a, b, count=1):
    assert src.count(a) == count, (a, src.count(a))
    return src.replace(a, b)


# ---- defs
s = rep(s, '"loot": 0.25, "keep": 0.05, "desc": "고철 획득 +25%, 파괴 시 보존 +5%."',
        '"loot": 0.15, "keep": 0.05, "desc": "고철 획득 +15%, 파괴 시 보존 +5%."')
s = rep(s, 'const ENEMY_SCRAP_GROWTH := 0.10', 'const ENEMY_SCRAP_GROWTH := 0.05')
drops = [
    ('"scrap": 2, "card": 0.20},\n\t"runner"', '"scrap": 2, "card": 0.14},\n\t"runner"'),
    ('"mass": 1, "r": 4.0, "scrap": 2, "card": 0.16}', '"mass": 1, "r": 4.0, "scrap": 2, "card": 0.10}'),
    ('"mass": 1, "r": 4.0, "scrap": 3, "card": 0.15}', '"mass": 1, "r": 4.0, "scrap": 3, "card": 0.10}'),
    ('"scrap": 6, "card": 0.35, "blast": 24.0}', '"scrap": 6, "card": 0.25, "blast": 24.0}'),
    ('"scrap": 4, "card": 0.25, "stealth": true', '"scrap": 4, "card": 0.18, "stealth": true'),
    ('"scrap": 1, "card": 0.06}', '"scrap": 1, "card": 0.04}'),
    ('"scrap": 5, "card": 0.20, "range": 62.0}', '"scrap": 5, "card": 0.15, "range": 62.0}'),
    ('"scrap": 6, "card": 0.22, "range": 52.0', '"scrap": 6, "card": 0.16, "range": 52.0'),
    ('"scrap": 8, "card": 0.30}', '"scrap": 8, "card": 0.20}'),
]
for a, b in drops:
    s = rep(s, a, b)
s = rep(s, '"hp": 150.0, "spd": 0.0,\n\t\t"dmg": 8.0', '"hp": 150.0, "spd": 0.0,\n\t\t"dmg": 7.0')
defs.write_text(s, encoding="utf-8", newline="\n")

# ---- sim: pooled area damage
t = rep(t, '''	for i in cars.size():
		if cars[i].pos.distance_to(p) < e.blast:
			_damage_train(e.dmg, i, "infected", "bloater")''',
        '''	_area_damage_train(p, e.blast, e.dmg, "infected", "bloater")''')
t = rep(t, '''				for i in cars.size():
					if cars[i].pos.distance_to(cars[pr.car].pos if pr.car < cars.size() else pr.to) < pr.radius + 10.0:
						_damage_train(pr.dmg, i, pr.faction, "bomb")''',
        '''				var bp_at: Vector2 = cars[pr.car].pos if pr.car < cars.size() else pr.to
				_area_damage_train(bp_at, pr.radius + 10.0, pr.dmg, pr.faction, "bomb")''')
t = rep(t, '''				for i in cars.size():
					if cars[i].pos.distance_to(pr.to) < pr.radius + 10.0:
						_damage_train(pr.dmg, i, "boss", "boss_mortar")''',
        '''				_area_damage_train(pr.to, pr.radius + 10.0, pr.dmg, "boss", "boss_mortar")''')
t = rep(t, '''				var hit_any := false
				for i in cars.size():
					var c: Car = cars[i]
					var d := c.pos.distance_to(head.pos)
					if d < 70.0:
						_damage_train(dmg * (1.0 - d / 140.0), i, "boss", "boss_ram")
						c.cd = maxf(c.cd, 1.2)
						hit_any = true''',
        '''				var hit_any := _area_damage_train(head.pos, 70.0, dmg, "boss", "boss_ram") > 0
				for c: Car in cars:
					if c.pos.distance_to(head.pos) < 70.0:
						c.cd = maxf(c.cd, 1.2)''')
t = rep(t, 'func _damage_train(dmg: float, car_i: int, faction: String, src: String) -> void:',
        '''## Area attacks hit the shared hull once; extra cars caught add 30% each.
func _area_damage_train(p: Vector2, radius: float, dmg: float, faction: String, src: String) -> int:
	var caught: Array = []
	for i in cars.size():
		if cars[i].pos.distance_to(p) < radius:
			caught.append(i)
	if caught.is_empty():
		return 0
	var mult := 1.0 + 0.3 * (caught.size() - 1)
	_damage_train(dmg * mult, caught[0], faction, src)
	for i in caught:
		cars[i].flash = 0.15
	return caught.size()


func _damage_train(dmg: float, car_i: int, faction: String, src: String) -> void:''')
# ---- sim: economy
t = rep(t, 'var base := 5 + 2 * loop if f.type == "ruin" else 10 + 3 * loop',
        'var base := 4 + loop if f.type == "ruin" else 8 + 2 * loop')
t = rep(t, '''			var inc := 8 if f.type == "market" else 10
			inc += 4 * adj_count(f.lot, ["factory", "assembly"]) + 2 * adj_tag(f.lot, "transit")''',
        '''			var inc := 6 if f.type == "market" else 8
			inc += 3 * adj_count(f.lot, ["factory", "assembly"]) + 2 * adj_tag(f.lot, "transit")''')
t = rep(t, 'var rd := (20.0 + speed * 0.4) * (2.0 if mod_count("plow") > 0 else 1.0)',
        'var rd := (14.0 + speed * 0.3) * (2.0 if mod_count("plow") > 0 else 1.0)')
sim.write_text(t, encoding="utf-8", newline="\n")
print("v3 applied")
