"""Balance pass v6: exploit fixes found while reviewing v5.

1. Kill farming: militia turrets did free work (farmer persona bank/min 176 vs ~110). Turret kills now
   give half scrap and half card chance ("the militia keeps a cut").
2. Transfer stations: every transfer handed out a free reward pick per loop -> stacking stations was a
   reward fountain. Now one transfer bonus per loop in total.
3. Risk vs reward: quitting after loop 1-2 was as efficient per minute as a deep run. Returned scrap now
   gets a haul multiplier 0.5 + 0.1 * loops (60% after loop 1, 100% at loop 5, capped 150%).
   Death still keeps a flat share of the raw scrap.
4. Heat: every boss win raises the threat grade for later runs (+10% enemy hp/dmg and +10% scrap each, max 5).
"""
import pathlib

root = pathlib.Path(__file__).resolve().parent.parent
p = root / "src" / "core" / "sim.gd"
t = p.read_text(encoding="utf-8")


def rep(a, b, count=1):
    global t
    assert t.count(a) == count, (a[:90], t.count(a))
    t = t.replace(a, b)


rep('''			if f.type == "transfer" and f.used_loop != loop:
				f.used_loop = loop''', '''			if f.type == "transfer" and transfer_loop != loop:
				transfer_loop = loop''')
rep('''var loop_dmg := 0.0''', '''var loop_dmg := 0.0
var transfer_loop := -1
var heat := 0''')
rep('''	var sc := e.scrap
	if e.faction == "raider" and has_relic("trophy"):
		sc += 3
	_gain_scrap(sc, e.pos)
	var chance := e.card + (0.06 if has_relic("token") else 0.0)''', '''	var sc := e.scrap
	if e.faction == "raider" and has_relic("trophy"):
		sc += 3
	var turret := src == "turret" or src == "mortar_t"
	if turret:
		sc = int(ceil(sc * 0.5))
	_gain_scrap(sc, e.pos)
	var chance := e.card + (0.06 if has_relic("token") else 0.0)
	if turret:
		chance *= 0.5''')
# turret shells are tagged so their kills count as militia kills
rep('''		pr.kind = "turret_shell"''', '''		pr.kind = "turret_shell"
		pr.faction = "militia"''')
rep('''			"shell", "turret_shell":
				for e: Enemy in enemies:
					if not e.dead and e.pos.distance_to(pr.to) <= pr.radius + e.r:
						_damage_enemy(e, pr.dmg, "mortar", false)''', '''			"shell", "turret_shell":
				var src_tag := "mortar_t" if pr.kind == "turret_shell" else "mortar"
				for e: Enemy in enemies:
					if not e.dead and e.pos.distance_to(pr.to) <= pr.radius + e.r:
						_damage_enemy(e, pr.dmg, src_tag, false)''')
# heat scaling
rep('''func enemy_hp_mult() -> float:
	return pow(Defs.ENEMY_HP_GROWTH, loop - 1)


func enemy_dmg_mult() -> float:
	return pow(Defs.ENEMY_DMG_GROWTH, loop - 1)''', '''func enemy_hp_mult() -> float:
	return pow(Defs.ENEMY_HP_GROWTH, loop - 1) * (1.0 + 0.1 * heat)


func enemy_dmg_mult() -> float:
	return pow(Defs.ENEMY_DMG_GROWTH, loop - 1) * (1.0 + 0.1 * heat)''')
rep('''	var v := int(round(n * mult))''', '''	mult *= 1.0 + 0.1 * heat
	var v := int(round(n * mult))''')
rep('''	max_cars = Defs.BASE_MAX_CARS + int(mods.get("max_cars", 0))''', '''	max_cars = Defs.BASE_MAX_CARS + int(mods.get("max_cars", 0))
	heat = clampi(int(mods.get("heat", 0)), 0, 5)''')
# haul multiplier
rep('''func _survivor_score() -> int:''', '''## scrap multiplier applied when the player returns: deeper runs are worth more per loop
func haul_mult() -> float:
	return clampf(0.5 + 0.1 * loop, 0.6, 1.5)


func _survivor_score() -> int:''')
rep('''		"returned":
			res.scrap = scrap
''', '''		"returned":
			res.scrap = int(round(scrap * haul_mult()))
''')
rep('''		"victory":
			res.scrap = scrap
''', '''		"victory":
			res.scrap = int(round(scrap * 1.5))
''')
p.write_text(t, encoding="utf-8", newline="\n")

# ---- AI: add a "sprint" persona that cashes out after two loops
a = root / "sim" / "ai_player.gd"
s = a.read_text(encoding="utf-8")
assert '"random":\n\t\t\tgo_home = sim.loop >= 3 and rng.randf() < 0.25' in s
s = s.replace('"random":\n\t\t\tgo_home = sim.loop >= 3 and rng.randf() < 0.25',
              '"random":\n\t\t\tgo_home = sim.loop >= 3 and rng.randf() < 0.25\n\t\t"sprint":\n\t\t\tgo_home = sim.loop >= 2')
s = s.replace('''	var persona_base := persona''', '''	var persona_base := persona''')
# sprint places like economy
s = s.replace('''func _card_value(id: String) -> float:
	match persona:''', '''func _card_value(id: String) -> float:
	var pp := "economy" if persona == "sprint" else persona
	match pp:''')
a.write_text(s, encoding="utf-8", newline="\n")
print("v6 applied")
