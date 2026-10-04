"""Sim refactor for the playable build (keeps balance behaviour):
- 60 Hz fixed step; weapon cooldowns carry remainder so fire rate is step-size independent
- evolution rules in one function (used by loop end AND by UI previews)
- replace_car / discard_card for the hand UI
- ambient wanderers scale with the horde gauge (visible danger stages)
"""
import pathlib

p = pathlib.Path(__file__).resolve().parent.parent / "src" / "core" / "sim.gd"
t = p.read_text(encoding="utf-8")


def rep(a, b, count=1):
    global t
    assert t.count(a) == count, (a[:80], t.count(a))
    t = t.replace(a, b)


rep("const DT := 1.0 / 30.0", "const DT := 1.0 / 60.0")
rep("c.cd = 1.0 / float(c.w.rate)", "c.cd += 1.0 / float(c.w.rate)", 5)
rep("f.turret_cd = 1.0 / float(tu.rate)", "f.turret_cd += 1.0 / float(tu.rate)")

# ---- evolution rules
start = t.index("\t# evolutions\n")
end = t.index("\t# the horde grows with every sign of life on the line")
t = t[:start] + '''	# evolutions
	for lot_id in order:
		if not facs.has(lot_id):
			continue
		var to := evo_target(lot_id, 0)
		if to != "":
			_transform(lot_id, to, "evolve")
			stats.evolved[to] = int(stats.evolved.get(to, 0)) + 1
''' + t[end:]

rep('''func _transform(lot_id: int, to: String, why: String) -> void:''', '''## What a facility turns into at the end of the loop, or "".
## age_bonus = 1 lets the UI ask "what happens at the next depot stop".
func evo_target(lot_id: int, age_bonus := 1) -> String:
	if not facs.has(lot_id):
		return ""
	var f: Fac = facs[lot_id]
	var age := f.age + age_bonus
	var faster := 1 if has_relic("oldmap") else 0
	match f.type:
		"station":
			if adj_count(lot_id, ["market", "blackmarket"]) > 0:
				return "transfer"
		"ruin":
			if adj_count(lot_id, ["shelter", "commune"]) > 0:
				return "station"
			if age >= 4 - faster and adj_count(lot_id, ["station", "transfer"]) == 0:
				return "ghost"
		"market":
			if adj_count(lot_id, ["raiders", "fortress"]) > 0:
				return "blackmarket"
		"hospital":
			if adj_count(lot_id, ["station", "transfer"]) > 0:
				return "medhub"
		"factory":
			if adj_count(lot_id, ["power"]) > 0:
				return "assembly"
		"checkpoint":
			if adj_count(lot_id, ["raiders", "fortress"]) > 0:
				return "mercpost"
			if adj_count(lot_id, ["armory"]) > 0:
				return "bastion"
		"infection":
			var need_age := 4 - faster - (1 if adj_count(lot_id, ["factory", "assembly"]) > 0 else 0)
			if age >= need_age:
				return "hive"
		"raiders":
			if age >= 4 - faster or adj_count(lot_id, ["market", "blackmarket"]) >= 2:
				return "fortress"
		"shelter":
			if adj_count(lot_id, ["greenhouse"]) > 0:
				return "commune"
	return ""


## loops until a timed evolution (ruin/infection/raiders) for UI countdowns, -1 if none
func evo_countdown(lot_id: int) -> int:
	if not facs.has(lot_id):
		return -1
	var f: Fac = facs[lot_id]
	var faster := 1 if has_relic("oldmap") else 0
	var need := -1
	match f.type:
		"ruin":
			if adj_count(lot_id, ["station", "transfer"]) == 0:
				need = 4 - faster
		"infection":
			need = 4 - faster - (1 if adj_count(lot_id, ["factory", "assembly"]) > 0 else 0)
		"raiders":
			need = 4 - faster
	if need < 0:
		return -1
	return maxi(1, need - f.age)


func _transform(lot_id: int, to: String, why: String) -> void:''')

# ---- hand helpers
rep('''func can_use_train_card(hand_idx: int) -> bool:''', '''func discard_card(hand_idx: int) -> bool:
	if hand_idx < 0 or hand_idx >= hand.size() or state != "running":
		return false
	var id: String = hand[hand_idx]
	hand.remove_at(hand_idx)
	scrap += 2
	stats.discarded += 1
	emit({"t": "discard", "card": id, "manual": true})
	return true


## swap a car (index >= 1) for the one on the card; the old car is scrapped
func replace_car(hand_idx: int, car_idx: int) -> bool:
	if hand_idx < 0 or hand_idx >= hand.size() or state != "running":
		return false
	var id: String = hand[hand_idx]
	if not id.begins_with("car:") or car_idx < 1 or car_idx >= cars.size():
		return false
	hand.remove_at(hand_idx)
	var old: String = cars[car_idx].type
	var c := Car.new()
	c.type = id.substr(4)
	c.length = Defs.CAR_LEN
	if Defs.CARS[c.type].has("weapon"):
		c.w = (Defs.CARS[c.type].weapon as Dictionary).duplicate()
		if c.type == "flame" and mod_count("napalm") > 0:
			c.w.range = float(c.w.range) + 6.0 * mod_count("napalm")
	cars[car_idx] = c
	_layout_cars()
	var ratio := hull / max_hull
	max_hull = _calc_max_hull()
	hull = clampf(max_hull * ratio, 1.0, max_hull)
	scrap += 10
	emit({"t": "car_replaced", "car": c.type, "old": old, "index": car_idx})
	return true


func can_use_train_card(hand_idx: int) -> bool:''')

# napalm on cars added later keeps the range bonus
rep('''	c.length = Defs.LOCO_LEN if t == "loco" else Defs.CAR_LEN
	if t != "loco" and Defs.CARS[t].has("weapon"):
		c.w = (Defs.CARS[t].weapon as Dictionary).duplicate()''', '''	c.length = Defs.LOCO_LEN if t == "loco" else Defs.CAR_LEN
	if t != "loco" and Defs.CARS[t].has("weapon"):
		c.w = (Defs.CARS[t].weapon as Dictionary).duplicate()
		if t == "flame" and mod_count("napalm") > 0:
			c.w.range = float(c.w.range) + 6.0 * mod_count("napalm")''')

# ---- danger stages
rep('''	wander_cd = maxf(3.5, 8.0 - 0.35 * loop) * rng.randf_range(0.8, 1.2)''',
    '''	wander_cd = maxf(3.0, 8.0 - 0.35 * loop - 1.2 * danger_stage()) * rng.randf_range(0.8, 1.2)''')
rep('''	if alive >= 3 + loop:
		return''', '''	if alive >= 3 + loop + danger_stage():
		return''')
rep('''func enemy_hp_mult() -> float:''', '''## 0 calm, 1 uneasy (horde 35+), 2 alarm (70+), 3 the Black Train (100+ or active)
func danger_stage() -> int:
	if boss_active or horde >= 100.0:
		return 3
	if horde >= 70.0:
		return 2
	if horde >= 35.0:
		return 1
	return 0


func enemy_hp_mult() -> float:''')
p.write_text(t, encoding="utf-8", newline="\n")
print("sim patched")
