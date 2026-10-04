class_name Sim
extends RefCounted
## Deterministic simulation of one LAST LINE run. No Node dependencies, so the same
## code runs in the game and in the headless balance harness (sim/runner.gd).

const DT := 1.0 / 60.0

enum { LURK, ENGAGE, RETURN }


class Car:
	var type := ""
	var off := 0.0          # distance of the car center behind the head
	var length := 22.0
	var pos := Vector2.ZERO
	var angle := 0.0
	var cd := 0.0
	var aim := 0.0
	var flash := 0.0
	var recoil := 0.0
	var firing := 0.0       # flame visual timer
	var w: Dictionary = {}  # weapon def (copied), empty when unarmed


class Enemy:
	var id := 0
	var type := ""
	var faction := ""
	var ai := ""
	var pos := Vector2.ZERO
	var lurk := Vector2.ZERO
	var wander := Vector2.ZERO
	var wander_t := 0.0
	var hp := 1.0
	var max_hp := 1.0
	var dmg := 1.0
	var spd := 10.0
	var cd_max := 1.0
	var cd := 0.0
	var mass := 1
	var r := 5.0
	var scrap := 1
	var card := 0.0
	var relic := 0.0
	var elite := false
	var stealth := false
	var visible := true
	var state := 0
	var home := -1          # lot id or -1
	var s_track := -1.0     # for track-bound enemies (static / horror / rig), odometer-free wrapped s
	var odo := 0.0          # for rig
	var burn := 0.0
	var burn_t := 0.0
	var stun := 0.0
	var flash := 0.0
	var dead := false
	var emerge := 0.0
	var face := 1
	var anim := 0.0
	var ram_cd := 0.0
	var child_cd := 0.0
	var children := 0
	var parent := -1
	var range_ := 0.0
	var extra_gun := 0.0
	var splash := 0.0
	var blast := 0.0
	var lunge := 0.0
	var boss_minion := false


class Fac:
	var type := ""
	var lot := 0
	var age := 0
	var spawn_cd := 3.0
	var alive := 0
	var turret_cd := 0.0
	var turret_aim := 0.0
	var waiting := 0
	var used_loop := -1
	var flash := 0.0
	var disabled := false
	var elite_timer := 0
	var infected_adj_loops := 0
	var spawn_i := 0


class Proj:
	var kind := ""          # shell / bullet / bomb / boss_shell / boss_mortar / turret_shell
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	var t := 0.0
	var dur := 1.0
	var dmg := 0.0
	var radius := 0.0
	var friendly := true
	var car := -1
	var faction := ""


class BossPart:
	var kind := ""
	var hp := 1.0
	var max_hp := 1.0
	var alive := true
	var cd := 0.0
	var flash := 0.0
	var off := 0.0
	var length := 26.0
	var pos := Vector2.ZERO
	var angle := 0.0


# ------------------------------------------------------------------ state
var rng := RandomNumberGenerator.new()
var map: LineMap
var mods: Dictionary = {}          # meta-progression modifiers from the profile
var time := 0.0
var loop := 1
var odo := 0.0                     # unwrapped travel distance of the train head
var speed := 0.0
var cars: Array = []               # Array[Car]; index 0 = locomotive
var hull := 1.0
var max_hull := 1.0
var enemies: Array = []            # Array[Enemy]
var facs := {}                     # lot id -> Fac
var projs: Array = []
var hand: Array = []               # card ids ("market", "car:gun", "mod:ap")
var scrap := 0
var supplies := 10
var survivors := 0
var horde := 0.0
var relics: Array = []
var modc := {}                     # module id -> count
var blueprints: Array = []
var events: Array = []             # consumed by the view
var pending: Dictionary = {}
var state := "running"             # running / dead / returned / victory
var stop_t := 0.0
var blocked := false
var armory_buff := 0.0
var toll_paid_loop := -1
var wander_cd := 6.0
var next_id := 1
var boss_active := false
var boss_odo := 0.0
var boss_speed := 0.0
var boss_state := "enter"
var boss_t := 0.0
var boss_parts: Array = []
var boss_enraged := false
var boss_ram_cd := 10.0
var combat_t := 0.0                 # seconds since an enemy was near
var power_s: Array = []             # wrapped s of power plants (cache)
var stats := {}
var unlocked_cards: Array = []
var unlocked_cars: Array = []
var max_cars := Defs.BASE_MAX_CARS
var depot_extra := 0
var loop_dmg := 0.0
var transfer_loop := -1
var heat := 0
var push_t := 0.0


func _init(seed_value: int, profile_mods: Dictionary = {}) -> void:
	rng.seed = seed_value
	mods = profile_mods
	map = LineMap.build_default(seed_value)
	unlocked_cards = Defs.FAC_BASE_CARDS.duplicate()
	for c in mods.get("cards", []):
		if not unlocked_cards.has(c):
			unlocked_cards.append(c)
	unlocked_cards.append("purge")
	unlocked_cars = Defs.CAR_BASE_UNLOCKED.duplicate()
	for c in mods.get("cars", []):
		if not unlocked_cars.has(c):
			unlocked_cars.append(c)
	max_cars = Defs.BASE_MAX_CARS + int(mods.get("max_cars", 0))
	heat = clampi(int(mods.get("heat", 0)), 0, 5)
	depot_extra = int(mods.get("depot_options", 0))
	stats = {"kills": {}, "dmg_taken": 0.0, "dmg_by_loop": [], "scrap_earned": 0, "placed": {},
		"evolved": {}, "corrupted": 0, "cards_drawn": 0, "discarded": 0, "starved": 0,
		"boss_loop": -1, "boss_result": "", "hull_min": 1.0, "relics": 0, "events": 0,
		"survivors_gained": 0, "time_by_loop": [], "depot_picks": {}, "shop_buys": 0,
		"repairs": 0.0, "death_cause": ""}
	odo = map.depot_s
	# starting train
	cars.clear()
	_add_car("loco", false)
	_add_car("gun", false)
	if mods.get("extra_gun", false):
		_add_car("gun", false)
	_add_car("cargo", false)
	max_hull = _calc_max_hull()
	hull = max_hull
	supplies = 10 + int(mods.get("supplies", 0))
	survivors = int(mods.get("survivors", 0))
	# starting world: one abandoned station and one infection zone, away from the depot
	_seed_world()
	# starting hand
	var civil := ["station", "market", "hospital", "shelter"]
	var hostile := ["infection", "raiders", "ruin"]
	hand.append(civil[rng.randi() % civil.size()])
	hand.append(hostile[rng.randi() % hostile.size()])
	for i in 2 + int(mods.get("hand", 0)):
		hand.append(_draw_card_id())
	_update_cars()


# ================================================================== helpers
func has_relic(id: String) -> bool:
	return relics.has(id)


func mod_count(id: String) -> int:
	return int(modc.get(id, 0))


func train_length() -> float:
	var last: Car = cars[cars.size() - 1]
	return last.off + last.length * 0.5


func crew_cap() -> int:
	var cap := Defs.BASE_CREW_CAP
	for c: Car in cars:
		if c.type == "passenger":
			cap += 8
	if has_relic("ledger"):
		cap += 4
	return cap


func cars_behind() -> int:
	return cars.size() - 1


func max_cars_total() -> int:
	return max_cars + (1 if has_relic("coupler") else 0)


func _calc_max_hull() -> float:
	var h := Defs.BASE_HULL + float(mods.get("hull", 0))
	for c: Car in cars:
		if c.type != "loco":
			h += float(Defs.CARS[c.type].hull)
	h += 30.0 * mod_count("plate")
	return h


func armor_value() -> float:
	var a := 0.0
	for c: Car in cars:
		if c.type == "armor":
			a += 1.0
	return a


func ram_power() -> int:
	var p := 2
	for c: Car in cars:
		if c.type == "armor":
			p += 1
	p += 2 * mod_count("plow")
	return p


func max_speed() -> float:
	var v := Defs.TRAIN_SPEED * (1.0 + 0.10 * mod_count("engine") + (0.05 if has_relic("fuelcell") else 0.0))
	var s := map.wrap_s(odo)
	for ps in power_s:
		var d := absf(wrapf(s - float(ps), -map.length * 0.5, map.length * 0.5))
		if d < 44.0:
			v *= 1.25
			break
	return v


func rate_mult() -> float:
	var crew_bonus := Defs.CREW_RATE_BONUS + 0.01 * mod_count("drill")
	var m := 1.0 + crew_bonus * survivors + 0.15 * mod_count("mag")
	if has_relic("blackbox") and hull < max_hull * 0.35:
		m += 0.4
	return m


func range_mult() -> float:
	return 1.0 + 0.12 * mod_count("scope")


func dmg_mult() -> float:
	return 1.0 + armory_buff


## 0 calm, 1 uneasy (horde 35+), 2 alarm (70+), 3 the Black Train (100+ or active)
func danger_stage() -> int:
	if boss_active or horde >= 100.0:
		return 3
	if horde >= 70.0:
		return 2
	if horde >= 35.0:
		return 1
	return 0


func enemy_hp_mult() -> float:
	return pow(Defs.ENEMY_HP_GROWTH, loop - 1) * (1.0 + 0.1 * heat)


func enemy_dmg_mult() -> float:
	return pow(Defs.ENEMY_DMG_GROWTH, loop - 1) * (1.0 + 0.1 * heat)


func emit(ev: Dictionary) -> void:
	events.append(ev)


func fac_at(lot_id: int) -> Fac:
	return facs.get(lot_id, null)


func lot(lot_id: int) -> Dictionary:
	return map.lots[lot_id]


func neighbors_of(lot_id: int) -> Array:
	var out: Array = []
	for n in lot(lot_id).neighbors:
		if facs.has(n):
			out.append(facs[n])
	return out


func adj_count(lot_id: int, types: Array) -> int:
	var k := 0
	for f: Fac in neighbors_of(lot_id):
		if types.has(f.type):
			k += 1
	return k


func adj_tag(lot_id: int, tag: String) -> int:
	var k := 0
	for f: Fac in neighbors_of(lot_id):
		if (Defs.FACILITIES[f.type].tags as Array).has(tag):
			k += 1
	return k


func is_protected(lot_id: int) -> bool:
	return adj_tag(lot_id, "military") > 0


func fac_count(t: String) -> int:
	var k := 0
	for f: Fac in facs.values():
		if f.type == t:
			k += 1
	return k


# ================================================================== setup
func _add_car(t: String, recalc := true) -> void:
	var c := Car.new()
	c.type = t
	c.length = Defs.LOCO_LEN if t == "loco" else Defs.CAR_LEN
	if t != "loco" and Defs.CARS[t].has("weapon"):
		c.w = (Defs.CARS[t].weapon as Dictionary).duplicate()
		if t == "flame" and mod_count("napalm") > 0:
			c.w.range = float(c.w.range) + 6.0 * mod_count("napalm")
	cars.append(c)
	_layout_cars()
	if recalc:
		var old := max_hull
		max_hull = _calc_max_hull()
		hull += max_hull - old


func _layout_cars() -> void:
	var off := 0.0
	for i in cars.size():
		var c: Car = cars[i]
		c.off = off + c.length * 0.5
		off += c.length + Defs.CAR_GAP


func _seed_world() -> void:
	var far: Array = []
	for l: Dictionary in map.lots:
		var d := map.ahead(map.depot_s, l.s)
		if d > 260.0 and d < map.length - 200.0:
			far.append(l.id)
	_shuffle(far)
	if far.size() >= 2:
		var rf := _place_fac("ruin", far[0], false)
		rf.age = -1
		# infection somewhere not adjacent to the ruin
		for k in range(1, far.size()):
			if not (lot(far[0]).neighbors as Array).has(far[k]):
				var inf := _place_fac("infection", far[k], false)
				inf.age = -2
				break


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp


func _place_fac(t: String, lot_id: int, noisy := true) -> Fac:
	var f := Fac.new()
	f.type = t
	f.lot = lot_id
	f.spawn_cd = rng.randf_range(1.0, 3.0)
	facs[lot_id] = f
	_refresh_power()
	if noisy:
		horde += Defs.HORDE_PER_PLACE
	return f


func _refresh_power() -> void:
	power_s.clear()
	for f: Fac in facs.values():
		if f.type == "power":
			power_s.append(lot(f.lot).s)


# ================================================================== cards
func _draw_card_id() -> String:
	var total := 0.0
	for id in unlocked_cards:
		total += float(Defs.CARD_WEIGHTS.get(id, 1))
	var r := rng.randf() * total
	for id in unlocked_cards:
		r -= float(Defs.CARD_WEIGHTS.get(id, 1))
		if r <= 0.0:
			return id
	return unlocked_cards[0]


func give_card(id: String, from_pos := Vector2(-1, -1)) -> void:
	if hand.size() >= Defs.HAND_MAX:
		var old: String = hand.pop_front()
		scrap += 2
		stats.discarded += 1
		emit({"t": "discard", "card": old})
	hand.append(id)
	stats.cards_drawn += 1
	emit({"t": "card", "card": id, "pos": from_pos})


func card_kind(id: String) -> String:
	if id.begins_with("car:"):
		return "car"
	if id.begins_with("mod:"):
		return "mod"
	if id == "purge":
		return "action"
	return "facility"


func can_place(hand_idx: int, lot_id: int) -> bool:
	if hand_idx < 0 or hand_idx >= hand.size() or lot_id < 0 or lot_id >= map.lots.size():
		return false
	if state != "running":
		return false
	var id: String = hand[hand_idx]
	match card_kind(id):
		"facility":
			return not facs.has(lot_id)
		"action":
			return facs.has(lot_id)
	return false


func place_card(hand_idx: int, lot_id: int) -> bool:
	if not can_place(hand_idx, lot_id):
		return false
	var id: String = hand[hand_idx]
	hand.remove_at(hand_idx)
	if id == "purge":
		var old: Fac = facs[lot_id]
		facs.erase(lot_id)
		_refresh_power()
		horde = maxf(0.0, horde - 4.0)
		for e: Enemy in enemies:
			if e.home == lot_id:
				e.home = -1
		emit({"t": "purge", "lot": lot_id, "from": old.type})
		return true
	_place_fac(id, lot_id)
	stats.placed[id] = int(stats.placed.get(id, 0)) + 1
	emit({"t": "place", "lot": lot_id, "fac": id})
	# instant feedback: hostile sites spawn their first enemy immediately
	var f: Fac = facs[lot_id]
	if Defs.FACILITIES[id].has("spawn"):
		f.spawn_cd = 0.6
	return true


func discard_card(hand_idx: int) -> bool:
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


func can_use_train_card(hand_idx: int) -> bool:
	if hand_idx < 0 or hand_idx >= hand.size() or state != "running":
		return false
	var id: String = hand[hand_idx]
	if id.begins_with("car:"):
		return cars_behind() < max_cars_total()
	return id.begins_with("mod:")


func use_train_card(hand_idx: int) -> bool:
	if not can_use_train_card(hand_idx):
		return false
	var id: String = hand[hand_idx]
	hand.remove_at(hand_idx)
	_apply_reward(id)
	return true


func _apply_reward(id: String) -> void:
	if id.begins_with("car:"):
		var t := id.substr(4)
		if cars_behind() < max_cars_total():
			_add_car(t)
			emit({"t": "car_added", "car": t, "index": cars.size() - 1})
	elif id.begins_with("mod:"):
		var m := id.substr(4)
		modc[m] = mod_count(m) + 1
		match m:
			"plate":
				var old := max_hull
				max_hull = _calc_max_hull()
				hull = minf(max_hull, hull + (max_hull - old))
			"patch":
				_repair(max_hull * 0.4)
			"napalm":
				for c: Car in cars:
					if c.type == "flame":
						c.w.range = float(c.w.range) + 6.0
		emit({"t": "module", "mod": m})
	elif id.begins_with("relic:"):
		_gain_relic(id.substr(6))
	elif id.begins_with("repair:"):
		_repair(max_hull * float(id.substr(7)) / 100.0)
	elif id.begins_with("supplies:"):
		supplies += int(id.substr(9))
		emit({"t": "supplies", "n": int(id.substr(9))})
	elif id.begins_with("cards:"):
		for c in id.substr(6).split(","):
			give_card(c)
	elif id.begins_with("card:"):
		give_card(id.substr(5))


func _gain_relic(r: String) -> void:
	if relics.has(r):
		scrap += 25
		return
	relics.append(r)
	stats.relics += 1
	if r == "coupler":
		pass
	emit({"t": "relic", "relic": r})


func _random_relic() -> String:
	var pool: Array = []
	for r in Defs.RELICS.keys():
		if not relics.has(r):
			pool.append(r)
	if pool.is_empty():
		return ""
	return pool[rng.randi() % pool.size()]


func _random_module() -> String:
	var pool: Array = ["ap", "mag", "plate", "scope", "engine", "plow", "patch", "drill"]
	var types := {}
	for c: Car in cars:
		types[c.type] = true
	if types.has("flame"):
		pool.append("napalm")
	if types.has("mortar"):
		pool.append("shrapnel")
	if types.has("tesla"):
		pool.append("coil")
	if not types.has("gun"):
		pool.erase("ap")
	return pool[rng.randi() % pool.size()]


func _random_car() -> String:
	return unlocked_cars[rng.randi() % unlocked_cars.size()]


func _try_blueprint(pos: Vector2) -> bool:
	var locked: Array = mods.get("locked", [])
	var pool: Array = []
	for b in locked:
		if not blueprints.has(b):
			pool.append(b)
	if pool.is_empty():
		return false
	var b: String = pool[rng.randi() % pool.size()]
	blueprints.append(b)
	emit({"t": "blueprint", "id": b, "pos": pos})
	return true


# ================================================================== main step
func step(dt: float) -> void:
	if state != "running" or not pending.is_empty():
		return
	time += dt
	_update_train(dt)
	if not pending.is_empty() or state != "running":
		return
	_update_cars()
	_update_facilities(dt)
	_update_wanderers(dt)
	_update_enemies(dt)
	_update_weapons(dt)
	_update_projectiles(dt)
	if boss_active:
		_update_boss(dt)
		stats.boss_time = float(stats.get("boss_time", 0.0)) + dt
	_cleanup()
	# passive repair
	var near := false
	for e: Enemy in enemies:
		if not e.dead and e.pos.distance_squared_to(cars[0].pos) < 140.0 * 140.0:
			near = true
			break
	if near or boss_active:
		combat_t = 0.0
	else:
		combat_t += dt
	if combat_t > 1.5:
		var regen := 0.0
		for c: Car in cars:
			if c.type == "repair":
				regen += float(Defs.CARS.repair.regen)
		if regen > 0.0 and hull < max_hull:
			hull = minf(max_hull, hull + regen * dt)
	stats.hull_min = minf(stats.hull_min, hull / max_hull)


# ------------------------------------------------------------------ train
func _update_train(dt: float) -> void:
	var vmax := max_speed()
	var target := vmax
	if stop_t > 0.0:
		stop_t -= dt
		target = 0.0
	# blockers ahead
	blocked = false
	var s_head := map.wrap_s(odo)
	var closest_block := INF
	var front := map.pos_at(odo)
	var fdir := map.dir_at(odo)
	var rp := ram_power()
	var blocker: Enemy = null
	for e: Enemy in enemies:
		if e.dead:
			continue
		if e.ai == "static" or e.ai == "horror":
			var d := map.ahead(s_head, e.s_track)
			if d < map.length * 0.5 and d - e.r < closest_block:
				closest_block = d - e.r
				blocker = e
		elif e.mass > rp and e.ai != "rig" and e.emerge <= 0.0:
			# heavy walkers standing on the rails stop the train
			var rel: Vector2 = e.pos - front
			var along := rel.dot(fdir)
			var side := absf(rel.cross(fdir))
			if along > -4.0 and along < 30.0 and side < e.r + 3.0 and along - e.r < closest_block:
				closest_block = along - e.r
				blocker = e
	if closest_block < 40.0:
		target = minf(target, maxf(0.0, (closest_block - 2.0) * 3.0))
		if closest_block <= 3.0:
			blocked = true
			target = 0.0
			# the locomotive keeps shoving: nothing can hold the line forever (no soft-locks
			# even with an unarmed train)
			if blocker != null and blocker.emerge <= 0.0:
				push_t -= dt
				_damage_enemy(blocker, (4.0 + 2.0 * rp) * dt * sqrt(enemy_hp_mult()), "push", false)
				if push_t <= 0.0:
					push_t = 0.5
					emit({"t": "push", "pos": blocker.pos})
	# depot arrival (not during the boss fight)
	var next_depot := map.depot_s + loop * map.length
	var dist := next_depot - odo
	if not boss_active:
		var brake_v := sqrt(maxf(0.0, 2.0 * 60.0 * dist))
		target = minf(target, maxf(brake_v, 5.0))
	# accelerate / brake
	if target < speed:
		speed = maxf(target, speed - Defs.TRAIN_BRAKE * dt)
	else:
		speed = minf(target, speed + Defs.TRAIN_ACCEL * dt)
	if blocked:
		speed = 0.0
	var old := odo
	odo += speed * dt
	if not boss_active and odo >= next_depot - 0.25:
		odo = next_depot
		speed = 0.0
		_check_triggers(old, odo)
		_arrive_depot()
		return
	_check_triggers(old, odo)
	if boss_active and odo >= next_depot:
		# the depot is sealed while the Black Train hunts us
		_loop_end()
		loop += 1
		emit({"t": "loop_pass", "loop": loop})
		_start_loop_spawns()


func _crossed(a: float, b: float, s: float) -> bool:
	return floor((b - s) / map.length) > floor((a - s) / map.length)


func _check_triggers(a: float, b: float) -> void:
	if b <= a:
		return
	for lot_id in facs.keys():
		var l: Dictionary = map.lots[lot_id]
		if _crossed(a, b, l.s):
			_on_pass(facs[lot_id])
			if not pending.is_empty():
				return


func _update_cars() -> void:
	for c: Car in cars:
		var s := odo - c.off
		c.pos = map.pos_at(s)
		var d := map.pos_at(s + c.length * 0.4) - map.pos_at(s - c.length * 0.4)
		c.angle = d.angle()
		c.flash = maxf(0.0, c.flash - DT)
		c.recoil = maxf(0.0, c.recoil - DT * 6.0)
		c.firing = maxf(0.0, c.firing - DT)


func _repair(amount: float) -> void:
	if amount <= 0.0:
		return
	var before := hull
	hull = minf(max_hull, hull + amount)
	stats.repairs += hull - before
	emit({"t": "repair", "n": hull - before})


# ------------------------------------------------------------------ passing facilities
func _on_pass(f: Fac) -> void:
	var l: Dictionary = map.lots[f.lot]
	var p: Vector2 = l.center
	f.flash = 0.6
	match f.type:
		"station", "transfer", "medhub", "hospital":
			var pct := 0.0
			match f.type:
				"station":
					pct = 0.12 + 0.05 * adj_count(f.lot, ["hospital", "medhub"])
				"transfer":
					pct = 0.12 + 0.05 * adj_count(f.lot, ["hospital", "medhub"])
				"hospital":
					pct = 0.10
				"medhub":
					pct = 0.20
			for c: Car in cars:
				if c.type == "repair":
					pct *= 1.5
					break
			_repair(max_hull * pct)
			if f.type == "station" or f.type == "transfer":
				stop_t = maxf(stop_t, 1.0 if f.type == "station" else 1.2)
				supplies += 1 if f.type == "station" else 2
				emit({"t": "station", "lot": f.lot})
				if has_relic("bell"):
					for e: Enemy in enemies:
						if not e.dead and not e.elite and e.pos.distance_to(cars[0].pos) < 70.0:
							e.stun = 2.0
							e.pos += (e.pos - cars[0].pos).normalized() * 18.0
					emit({"t": "bell", "pos": cars[0].pos})
			if f.type == "hospital" or f.type == "medhub":
				_pickup(f)
			if f.type == "transfer" and transfer_loop != loop:
				transfer_loop = loop
				pending = {"kind": "reward", "source": "transfer", "options": _gen_rewards(3, false)}
		"ruin", "ghost":
			var base := 4 + loop if f.type == "ruin" else 8 + 2 * loop
			_gain_scrap(base, p)
			if rng.randf() < (0.25 if f.type == "ruin" else 0.40):
				give_card(_draw_card_id(), p)
			if f.type == "ghost" and rng.randf() < 0.12:
				var r := _random_relic()
				if r != "":
					_gain_relic(r)
		"market", "blackmarket":
			var inc := 6 if f.type == "market" else 8
			inc += 3 * adj_count(f.lot, ["factory", "assembly"]) + 2 * adj_tag(f.lot, "transit")
			if adj_count(f.lot, ["raiders", "fortress"]) > 0 and not is_protected(f.lot):
				inc = int(inc * 0.5)
			_gain_scrap(inc, p)
			if f.type == "blackmarket" and f.used_loop != loop:
				var r := _random_relic()
				if r != "":
					f.used_loop = loop
					pending = {"kind": "blackmarket", "relic": r, "cost": 45 + 8 * loop}
		"shelter", "commune":
			_pickup(f)
		"armory":
			armory_buff += 0.25
			emit({"t": "armory", "lot": f.lot})
		"sporefarm":
			var dmg := 6.0 * enemy_dmg_mult()
			if has_relic("gasmask"):
				dmg *= 0.7
			_damage_train(dmg, rng.randi() % cars.size(), "infected", "spore")
			emit({"t": "spores", "lot": f.lot})
		"checkpoint", "mercpost", "bastion":
			pass


func _pickup(f: Fac) -> void:
	if f.waiting <= 0:
		return
	var room := crew_cap() - survivors
	var n := mini(room, f.waiting)
	if n <= 0:
		emit({"t": "full", "lot": f.lot})
		return
	f.waiting -= n
	survivors += n
	stats.survivors_gained += n
	emit({"t": "survivors", "n": n, "lot": f.lot, "pos": lot(f.lot).center})


func _gain_scrap(n: int, pos: Vector2) -> void:
	var mult := 1.0
	for c: Car in cars:
		if c.type == "cargo":
			mult += float(Defs.CARS.cargo.loot)
	mult *= 1.0 + 0.1 * heat
	var v := int(round(n * mult))
	scrap += v
	stats.scrap_earned += v
	emit({"t": "scrap", "n": v, "pos": pos})


# ------------------------------------------------------------------ depot / loop
func _arrive_depot() -> void:
	_loop_end()
	var boss_next := horde >= 100.0
	var opts := _gen_rewards(3 + depot_extra + (1 if has_relic("watch") else 0), true)
	var shop: Array = [
		{"id": "mod:" + _random_module(), "cost": 30 + 6 * loop, "sold": false},
		{"id": "repair:30", "cost": 15 + 3 * loop, "sold": false}]
	pending = {"kind": "depot", "options": opts, "picked": -1, "shop": shop, "boss_next": boss_next}
	emit({"t": "depot", "loop": loop})


func _loop_end() -> void:
	stats.dmg_by_loop.append(loop_dmg)
	stats.time_by_loop.append(time)
	loop_dmg = 0.0
	armory_buff = 0.0
	var order: Array = facs.keys()
	order.sort()
	# production & aging
	for lot_id in order:
		var f: Fac = facs[lot_id]
		f.age += 1
		match f.type:
			"factory":
				supplies += 3
				if f.age % 2 == 0:
					give_card("mod:" + _random_module(), lot(lot_id).center)
			"assembly":
				supplies += 3
				if rng.randf() < 0.5 and cars_behind() < max_cars_total():
					give_card("car:" + _random_car(), lot(lot_id).center)
				else:
					give_card("mod:" + _random_module(), lot(lot_id).center)
			"greenhouse":
				supplies += 3
			"commune":
				supplies += 2
				f.waiting = mini(6, f.waiting + 2)
			"sporefarm":
				supplies += 4
			"shelter":
				f.waiting = mini(4, f.waiting + 1)
			"hospital":
				f.waiting = mini(2, f.waiting + 1)
			"medhub":
				f.waiting = mini(3, f.waiting + 1)
	if has_relic("fuelcell"):
		supplies += 2
	# upkeep
	for lot_id in order:
		var f: Fac = facs[lot_id]
		var up := int(Defs.FACILITIES[f.type].get("upkeep", 0))
		if up > 0:
			if supplies >= up:
				supplies -= up
				f.disabled = false
			else:
				f.disabled = true
				emit({"t": "unpaid", "lot": lot_id})
	# crew rations
	var need := int(ceil(survivors / 3.0))
	if need > 0:
		if supplies >= need:
			supplies -= need
		else:
			var lost := need - supplies
			supplies = 0
			lost = mini(lost, survivors)
			survivors -= lost
			stats.starved += lost
			emit({"t": "starve", "n": lost})
	# infection spreads into unprotected civil neighbors
	var corrupt_map := {"hospital": "ward", "medhub": "ward", "shelter": "infection", "commune": "infection",
		"greenhouse": "sporefarm", "station": "ruin"}
	for lot_id in order:
		if not facs.has(lot_id):
			continue
		var f: Fac = facs[lot_id]
		if not (Defs.FACILITIES[f.type].tags as Array).has("infected"):
			continue
		if f.type == "sporefarm":
			continue
		var chance := 0.25 if f.type != "hive" else 0.4
		if rng.randf() >= chance:
			continue
		var victims: Array = []
		for n in lot(lot_id).neighbors:
			if facs.has(n) and corrupt_map.has(facs[n].type) and not is_protected(n):
				victims.append(n)
		if victims.is_empty():
			continue
		var v: int = victims[rng.randi() % victims.size()]
		var old: String = facs[v].type
		_transform(v, corrupt_map[old], "corrupt")
		stats.corrupted += 1
	# markets attract raiders
	for lot_id in order:
		if not facs.has(lot_id):
			continue
		var f: Fac = facs[lot_id]
		if f.type != "market":
			continue
		if adj_count(lot_id, ["raiders", "fortress"]) > 0:
			continue
		if rng.randf() < 0.18:
			var empty: Array = []
			for n in lot(lot_id).neighbors:
				if not facs.has(n):
					empty.append(n)
			if not empty.is_empty():
				var target: int = empty[rng.randi() % empty.size()]
				_place_fac("raiders", target, false)
				emit({"t": "raiders_arrive", "lot": target})
	# raider theft from shelters
	for lot_id in order:
		if not facs.has(lot_id):
			continue
		var f: Fac = facs[lot_id]
		if (f.type == "shelter" or f.type == "commune") and f.waiting > 0:
			if adj_count(lot_id, ["raiders", "fortress"]) > 0 and not is_protected(lot_id):
				f.waiting -= 1
				emit({"t": "theft", "lot": lot_id})
	# evolutions
	for lot_id in order:
		if not facs.has(lot_id):
			continue
		var to := evo_target(lot_id, 0)
		if to != "":
			_transform(lot_id, to, "evolve")
			stats.evolved[to] = int(stats.evolved.get(to, 0)) + 1
	# the horde grows with every sign of life on the line
	var noise := Defs.HORDE_BASE_PER_LOOP
	for lot_id in order:
		if not facs.has(lot_id):
			continue
		var f: Fac = facs[lot_id]
		var nz := float(Defs.FACILITIES[f.type].noise)
		if f.type == "factory" or f.type == "assembly":
			nz = maxf(0.0, nz - 2.0 * adj_count(lot_id, ["greenhouse"]))
		noise += nz
	if has_relic("jammer"):
		noise *= 0.75
	if not boss_active:
		horde += noise
	emit({"t": "loop_end", "loop": loop, "noise": noise})


## What a facility turns into at the end of the loop, or "".
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


func _transform(lot_id: int, to: String, why: String) -> void:
	var f: Fac = facs[lot_id]
	var from := f.type
	f.type = to
	f.age = 0
	f.spawn_cd = 2.0
	f.flash = 1.0
	f.elite_timer = 0
	_refresh_power()
	emit({"t": why, "lot": lot_id, "from": from, "to": to})


func _start_loop_spawns() -> void:
	# elites for evolved hostile sites, barricades from raiders
	for lot_id in facs.keys():
		var f: Fac = facs[lot_id]
		var d: Dictionary = Defs.FACILITIES[f.type]
		if d.has("elite"):
			f.elite_timer += 1
			if f.elite_timer >= int(d.elite_every):
				f.elite_timer = 0
				_spawn_elite(String(d.elite), f)
		if f.type == "raiders" or f.type == "fortress":
			if toll_paid_loop != loop and rng.randf() < (0.5 if f.type == "raiders" else 1.0):
				_spawn_barricade(f)


func _spawn_elite(t: String, f: Fac) -> void:
	var l: Dictionary = lot(f.lot)
	match t:
		"horror":
			# burrows under the track near the ghost station
			var e := _spawn(t, l.track_pt, f.lot)
			e.s_track = l.s
			e.pos = map.pos_at(l.s)
			e.emerge = 1.4
		"warrig":
			var e := _spawn(t, l.track_pt, f.lot)
			e.odo = odo - train_length() - 160.0
			e.pos = map.pos_at(e.odo)
		_:
			_spawn(t, l.track_pt + (l.normal as Vector2) * 6.0, f.lot)


func _spawn_barricade(f: Fac) -> void:
	var l: Dictionary = lot(f.lot)
	var s := map.wrap_s(float(l.s) + rng.randf_range(-24.0, 24.0))
	# never on top of the train
	if map.ahead(map.wrap_s(odo - train_length() - 10.0), s) < train_length() + 30.0:
		return
	var e := _spawn("barricade", map.pos_at(s), f.lot)
	e.s_track = s
	e.pos = map.pos_at(s)


# depot decisions ----------------------------------------------------------
func _gen_rewards(n: int, at_depot: bool) -> Array:
	var cats := {"cards": 3.0, "card": 2.0, "car": 2.4, "mod": 3.0, "repair": 1.4, "supplies": 1.3, "relic": 0.35}
	if cars_behind() >= max_cars_total():
		cats.erase("car")
	if hull < max_hull * 0.6:
		cats.repair = 3.0
	if hull >= max_hull * 0.95:
		cats.erase("repair")
	var out: Array = []
	var guard := 0
	while out.size() < n and guard < 50 and not cats.is_empty():
		guard += 1
		var total := 0.0
		for k in cats:
			total += float(cats[k])
		var r := rng.randf() * total
		var pick := ""
		for k in cats:
			r -= float(cats[k])
			if r <= 0.0:
				pick = k
				break
		if pick == "":
			pick = cats.keys()[0]
		cats.erase(pick)
		match pick:
			"cards":
				out.append("cards:%s,%s" % [_draw_card_id(), _draw_card_id()])
			"card":
				var c := _draw_card_id()
				out.append("card:" + c)
			"car":
				out.append("car:" + _random_car())
			"mod":
				out.append("mod:" + _random_module())
			"repair":
				out.append("repair:35")
			"supplies":
				out.append("supplies:8")
			"relic":
				var rr := _random_relic()
				if rr != "":
					out.append("relic:" + rr)
	return out


func depot_pick(i: int) -> bool:
	if pending.get("kind", "") != "depot" or int(pending.picked) >= 0:
		return false
	var opts: Array = pending.options
	if i < 0 or i >= opts.size():
		return false
	pending.picked = i
	var id: String = opts[i]
	var cat := id.split(":")[0]
	stats.depot_picks[cat] = int(stats.depot_picks.get(cat, 0)) + 1
	_apply_reward(id)
	return true


func depot_buy(i: int) -> bool:
	if pending.get("kind", "") != "depot":
		return false
	var shop: Array = pending.shop
	if i < 0 or i >= shop.size():
		return false
	var item: Dictionary = shop[i]
	if item.sold or scrap < int(item.cost):
		return false
	scrap -= int(item.cost)
	item.sold = true
	stats.shop_buys += 1
	_apply_reward(String(item.id))
	return true


func depot_continue() -> void:
	if pending.get("kind", "") != "depot":
		return
	var boss_next: bool = pending.boss_next
	pending = {}
	loop += 1
	emit({"t": "depart", "loop": loop})
	_start_loop_spawns()
	if boss_next and not boss_active:
		_spawn_boss()
	elif loop >= 2 and (fac_count("radio") > 0 or rng.randf() < 0.30):
		_start_event()


func depot_return() -> void:
	if pending.get("kind", "") != "depot":
		return
	pending = {}
	state = "returned"
	emit({"t": "returned"})


func reward_pick(i: int) -> void:
	if pending.get("kind", "") != "reward":
		return
	var opts: Array = pending.options
	pending = {}
	if i >= 0 and i < opts.size():
		_apply_reward(String(opts[i]))


func bm_choose(buy: bool) -> void:
	if pending.get("kind", "") != "blackmarket":
		return
	var p := pending
	pending = {}
	if buy and scrap >= int(p.cost):
		scrap -= int(p.cost)
		_gain_relic(String(p.relic))


# radio events ------------------------------------------------------------
func _start_event() -> void:
	var pool: Array = ["sos", "drop", "signal", "crew", "merchant"]
	if fac_count("raiders") + fac_count("fortress") > 0:
		pool.append("toll")
	if horde > 35.0:
		pool.append("sighting")
	if fac_count("shelter") + fac_count("commune") > 0:
		pool.append("outbreak")
	var id: String = pool[rng.randi() % pool.size()]
	stats.events += 1
	pending = {"kind": "event", "id": id}
	emit({"t": "event", "id": id})


func event_can(i: int) -> bool:
	if pending.get("kind", "") != "event":
		return false
	var id: String = pending.id
	if i == 1:
		return true
	match id:
		"toll":
			return scrap >= 30
		"crew":
			return supplies >= 5
		"sighting":
			return scrap >= 20
		"merchant":
			return scrap >= 35
	return true


func event_choose(i: int) -> void:
	if pending.get("kind", "") != "event":
		return
	if not event_can(i):
		i = 1
	var id: String = pending.id
	pending = {}
	var ahead_pt := map.pos_at(odo + 90.0)
	match id:
		"sos":
			if i == 0:
				var n := mini(3, crew_cap() - survivors)
				survivors += maxi(0, n)
				stats.survivors_gained += maxi(0, n)
				emit({"t": "survivors", "n": n, "pos": cars[0].pos})
				for k in 4:
					var e := _spawn("runner", ahead_pt + Vector2(rng.randf_range(-20, 20), rng.randf_range(-20, 20)), -1)
					e.state = ENGAGE
		"drop":
			if i == 0:
				supplies += 12
				horde += 8.0
				emit({"t": "supplies", "n": 12})
		"toll":
			if i == 0:
				scrap -= 30
				toll_paid_loop = loop
				for e: Enemy in enemies:
					if e.type == "barricade" and not e.dead:
						e.dead = true
			else:
				for k in 3:
					var e := _spawn("raider", ahead_pt + Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30)), -1)
					e.state = ENGAGE
		"signal":
			if i == 0:
				if rng.randf() < 0.55:
					var r := _random_relic()
					if r != "":
						_gain_relic(r)
				else:
					var s := map.wrap_s(odo + 120.0)
					var e := _spawn("horror", map.pos_at(s), -1)
					e.s_track = s
					e.emerge = 1.4
		"crew":
			if i == 0:
				supplies -= 5
				_repair(max_hull * 0.3)
		"sighting":
			if i == 0:
				scrap -= 20
				horde = maxf(0.0, horde - 15.0)
		"merchant":
			if i == 0:
				scrap -= 35
				give_card("mod:" + _random_module())
		"outbreak":
			if i == 0:
				_damage_train(12.0, 0, "event", "event")
				var n := mini(2, crew_cap() - survivors)
				survivors += maxi(0, n)
				stats.survivors_gained += maxi(0, n)
			else:
				for lot_id in facs.keys():
					var f: Fac = facs[lot_id]
					if f.type == "shelter" or f.type == "commune":
						_transform(lot_id, "infection", "corrupt")
						break


# ------------------------------------------------------------------ facilities tick
func _update_facilities(dt: float) -> void:
	for lot_id in facs.keys():
		var f: Fac = facs[lot_id]
		f.flash = maxf(0.0, f.flash - dt)
		var d: Dictionary = Defs.FACILITIES[f.type]
		if d.has("spawn"):
			_tick_spawner(f, d.spawn, dt)
		if d.has("turret") and not f.disabled:
			_tick_turret(f, d.turret, dt)
	# electrified track
	if not power_s.is_empty():
		var dps := 8.0 * dt
		for ps in power_s:
			var center := map.pos_at(float(ps))
			for e: Enemy in enemies:
				if e.dead:
					continue
				if e.pos.distance_squared_to(center) < 44.0 * 44.0:
					_damage_enemy(e, dps, "power", false)
			if boss_active:
				for bp: BossPart in boss_parts:
					if bp.alive and bp.pos.distance_squared_to(center) < 44.0 * 44.0:
						_damage_boss_part(bp, dps * 2.0, false)


func _tick_spawner(f: Fac, sp: Dictionary, dt: float) -> void:
	f.spawn_cd -= dt
	if f.spawn_cd > 0.0:
		return
	var period := float(sp.period)
	if (f.type == "infection" or f.type == "hive") and adj_count(f.lot, ["factory", "assembly"]) > 0:
		period *= 0.7
	if (f.type == "raiders" or f.type == "fortress"):
		if adj_count(f.lot, ["mercpost"]) > 0:
			period *= 2.0
		if toll_paid_loop == loop:
			f.spawn_cd = 5.0
			return
	f.spawn_cd = period * rng.randf_range(0.85, 1.15)
	var cap := int(sp.cap)
	if f.type == "raiders" or f.type == "fortress":
		cap += adj_count(f.lot, ["blackmarket"])
	if f.alive >= cap:
		return
	var types: Array = sp.types
	var t: String = types[f.spawn_i % types.size()]
	f.spawn_i += 1
	# runners and bombers only after the first loops
	if loop < 3 and (t == "runner" or t == "bomber" or t == "dog"):
		t = types[0]
	var l: Dictionary = lot(f.lot)
	var p: Vector2 = (l.center as Vector2) + Vector2(rng.randf_range(-8, 8), rng.randf_range(-8, 8))
	var e := _spawn(t, p, f.lot)
	# lurk near the track in front of the lot
	e.lurk = (l.track_pt as Vector2) + (l.normal as Vector2) * rng.randf_range(10.0, 22.0) \
		+ Vector2((l.normal as Vector2).y, -(l.normal as Vector2).x) * rng.randf_range(-20.0, 20.0)
	if t == "rat":
		for k in 2:
			var e2 := _spawn("rat", p + Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6)), f.lot)
			e2.lurk = e.lurk + Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6))


func _tick_turret(f: Fac, tu: Dictionary, dt: float) -> void:
	f.turret_cd -= dt
	if f.turret_cd > 0.0:
		return
	var p: Vector2 = lot(f.lot).center
	var rng_r := float(tu.range)
	var target: Enemy = _nearest_enemy(p, rng_r, 0.0)
	var boss_target: BossPart = null
	if target == null and boss_active:
		boss_target = _nearest_boss_part(p, rng_r)
	if target == null and boss_target == null:
		f.turret_cd = 0.2
		return
	f.turret_cd += 1.0 / float(tu.rate)
	var tp: Vector2 = target.pos if target != null else boss_target.pos
	f.turret_aim = (tp - p).angle()
	if tu.kind == "gun":
		if target != null:
			_damage_enemy(target, float(tu.dmg), "turret", true)
		else:
			_damage_boss_part(boss_target, float(tu.dmg), true)
		emit({"t": "tshot", "from": p + Vector2(0, -8), "to": tp, "lot": f.lot})
	else:
		var pr := Proj.new()
		pr.kind = "turret_shell"
		pr.faction = "militia"
		pr.from = p + Vector2(0, -8)
		pr.to = tp
		pr.dur = 1.0
		pr.dmg = float(tu.dmg)
		pr.radius = float(tu.radius)
		pr.friendly = true
		projs.append(pr)
		emit({"t": "tmortar", "from": pr.from, "to": tp, "lot": f.lot})


# ------------------------------------------------------------------ enemies
func _spawn(t: String, p: Vector2, home: int) -> Enemy:
	var d: Dictionary = Defs.ENEMIES[t]
	var e := Enemy.new()
	e.id = next_id
	next_id += 1
	e.type = t
	e.faction = d.faction
	e.ai = d.ai
	e.pos = p
	e.lurk = p
	e.wander = p
	var hpm := enemy_hp_mult()
	e.max_hp = float(d.hp) * hpm
	e.hp = e.max_hp
	e.dmg = float(d.dmg) * enemy_dmg_mult()
	e.spd = float(d.spd) * rng.randf_range(0.9, 1.1)
	e.cd_max = float(d.cd)
	e.cd = e.cd_max * rng.randf()
	e.mass = int(d.mass)
	e.r = float(d.r)
	e.scrap = int(round(float(d.scrap) * (1.0 + Defs.ENEMY_SCRAP_GROWTH * (loop - 1))))
	e.card = float(d.card)
	e.relic = float(d.get("relic", 0.0))
	e.elite = bool(d.get("elite", false))
	e.stealth = bool(d.get("stealth", false))
	e.visible = not e.stealth or has_relic("lantern")
	e.range_ = float(d.get("range", 0.0))
	e.extra_gun = float(d.get("gun", 0.0)) * enemy_dmg_mult()
	e.splash = float(d.get("splash", 0.0))
	e.blast = float(d.get("blast", 0.0))
	e.lunge = float(d.get("lunge", 0.0))
	e.home = home
	e.emerge = 0.5
	e.state = LURK
	if home >= 0 and facs.has(home):
		facs[home].alive += 1
	if e.faction == "raider" and home >= 0 and adj_count(home, ["armory"]) > 0:
		e.dmg *= 1.4
	enemies.append(e)
	emit({"t": "spawn", "id": e.id, "type": t, "pos": p, "elite": e.elite})
	return e


func _update_wanderers(dt: float) -> void:
	wander_cd -= dt
	if wander_cd > 0.0:
		return
	wander_cd = maxf(3.0, 8.0 - 0.35 * loop - 1.2 * danger_stage()) * rng.randf_range(0.8, 1.2)
	var alive := 0
	for e: Enemy in enemies:
		if not e.dead and e.home == -1 and not e.boss_minion:
			alive += 1
	if alive >= 3 + loop + danger_stage():
		return
	var s := map.wrap_s(odo + rng.randf_range(220.0, map.length - train_length() - 120.0))
	if map.is_tunnel_s(s):
		s = map.wrap_s(s + 140.0)
	var base := map.pos_at(s)
	var dir := map.dir_at(s)
	var nrm := Vector2(dir.y, -dir.x) * (1.0 if rng.randf() < 0.5 else -1.0)
	var r := rng.randf()
	var t := "shambler"
	if loop >= 2 and r < 0.3:
		t = "runner"
	elif r > 0.9:
		t = "rat"
	var p := base + nrm * rng.randf_range(12.0, 26.0)
	var e := _spawn(t, p, -1)
	e.lurk = base + nrm * rng.randf_range(8.0, 16.0)


func _nearest_car(p: Vector2) -> int:
	var best := INF
	var bi := 0
	for i in cars.size():
		var d := p.distance_squared_to(cars[i].pos)
		if d < best:
			best = d
			bi = i
	return bi


func _update_enemies(dt: float) -> void:
	var loco_front := map.pos_at(odo)
	var rp := ram_power()
	for e: Enemy in enemies:
		if e.dead:
			continue
		e.anim += dt
		e.flash = maxf(0.0, e.flash - dt)
		if e.emerge > 0.0:
			e.emerge -= dt
			continue
		if e.burn_t > 0.0:
			e.burn_t -= dt
			_damage_enemy(e, e.burn * dt, "burn", false)
			if e.dead:
				continue
		if e.stun > 0.0:
			e.stun -= dt
			continue
		match e.ai:
			"walker", "bloater", "brood":
				_ai_walker(e, dt)
			"ranged":
				_ai_ranged(e, dt)
			"static":
				pass
			"horror":
				_ai_horror(e, dt)
			"rig":
				_ai_rig(e, dt)
		if e.dead:
			continue
		# ramming: small things in front of the locomotive get flattened
		if e.ai != "static" and e.ai != "horror" and e.ai != "rig":
			var dd := e.pos.distance_to(loco_front)
			if dd < e.r + 6.0 and speed > 8.0:
				e.ram_cd -= dt
				if e.ram_cd <= 0.0:
					e.ram_cd = 0.5
					if e.mass <= rp:
						var rd := (14.0 + speed * 0.3) * (2.0 if mod_count("plow") > 0 else 1.0)
						var push := Vector2(-map.dir_at(odo).y, map.dir_at(odo).x)
						if push.dot(e.pos - loco_front) < 0.0:
							push = -push
						e.pos += push * 10.0
						if e.ai == "bloater":
							_explode_bloater(e)
							continue
						_damage_enemy(e, rd, "ram", true)
						_damage_train(e.dmg * 0.4, 0, e.faction, "ram")
						emit({"t": "ram", "pos": e.pos, "id": e.id})
	# light separation among engaged enemies so crowds read as crowds
	var eng: Array = []
	for e: Enemy in enemies:
		if not e.dead and e.state == ENGAGE and (e.ai == "walker" or e.ai == "ranged" or e.ai == "bloater" or e.ai == "brood"):
			eng.append(e)
	var n := eng.size()
	for i in n:
		var a: Enemy = eng[i]
		for j in range(i + 1, n):
			var b: Enemy = eng[j]
			var dv := a.pos - b.pos
			var min_d := a.r + b.r
			var d2 := dv.length_squared()
			if d2 < min_d * min_d and d2 > 0.0001:
				var dl := sqrt(d2)
				var push := dv / dl * (min_d - dl) * 0.5
				a.pos += push
				b.pos -= push


func _move_to(e: Enemy, target: Vector2, spd: float, dt: float) -> void:
	var dv := target - e.pos
	var d := dv.length()
	if d < 0.5:
		return
	var step_len := minf(d, spd * dt)
	e.pos += dv / d * step_len
	if absf(dv.x) > 0.5:
		e.face = 1 if dv.x > 0.0 else -1


func _ai_walker(e: Enemy, dt: float) -> void:
	var ci := _nearest_car(e.pos)
	var car: Car = cars[ci]
	var d := e.pos.distance_to(car.pos)
	if e.stealth:
		e.visible = has_relic("lantern") or d < 46.0
	match e.state:
		LURK:
			e.wander_t -= dt
			if e.wander_t <= 0.0:
				e.wander_t = rng.randf_range(1.5, 3.5)
				e.wander = e.lurk + Vector2(rng.randf_range(-8, 8), rng.randf_range(-8, 8))
			_move_to(e, e.wander, e.spd * 0.35, dt)
			var aggro := 84.0 if not e.stealth else 60.0
			if d < aggro:
				e.state = ENGAGE
		ENGAGE:
			if d > 170.0:
				e.state = RETURN
				return
			var lead := Vector2.from_angle(car.angle) * speed * 0.25
			var spd := e.spd
			if e.lunge > 0.0 and d < 50.0:
				spd = e.lunge
			_move_to(e, car.pos + lead, spd, dt)
			if d < e.r + 8.0:
				e.cd -= dt
				if e.cd <= 0.0:
					e.cd = e.cd_max
					if e.ai == "bloater":
						_explode_bloater(e)
						return
					_damage_train(e.dmg, ci, e.faction, e.type)
					emit({"t": "bite", "pos": e.pos, "car": ci, "id": e.id})
			if e.ai == "brood":
				e.child_cd -= dt
				if e.child_cd <= 0.0 and e.children < 4:
					e.child_cd = 3.5
					var c := _spawn("runner", e.pos + Vector2(rng.randf_range(-8, 8), rng.randf_range(-8, 8)), -1)
					c.state = ENGAGE
					c.parent = e.id
					c.boss_minion = true
					e.children += 1
		RETURN:
			_move_to(e, e.lurk, e.spd * 0.6, dt)
			if e.pos.distance_to(e.lurk) < 3.0:
				e.state = LURK
			elif d < 70.0:
				e.state = ENGAGE


func _ai_ranged(e: Enemy, dt: float) -> void:
	var ci := _nearest_car(e.pos)
	var car: Car = cars[ci]
	var d := e.pos.distance_to(car.pos)
	match e.state:
		LURK:
			e.wander_t -= dt
			if e.wander_t <= 0.0:
				e.wander_t = rng.randf_range(1.5, 3.5)
				e.wander = e.lurk + Vector2(rng.randf_range(-8, 8), rng.randf_range(-8, 8))
			_move_to(e, e.wander, e.spd * 0.35, dt)
			if d < e.range_ + 30.0:
				e.state = ENGAGE
		ENGAGE:
			if d > e.range_ + 90.0:
				e.state = RETURN
				return
			if d > e.range_ * 0.85:
				_move_to(e, car.pos, e.spd, dt)
			e.cd -= dt
			if e.cd <= 0.0 and d <= e.range_:
				e.cd = e.cd_max * rng.randf_range(0.9, 1.1)
				var pr := Proj.new()
				pr.kind = "bomb" if e.splash > 0.0 else "bullet"
				pr.from = e.pos + Vector2(0, -4)
				pr.to = car.pos
				pr.dur = maxf(0.12, d / (190.0 if pr.kind == "bullet" else 90.0))
				pr.dmg = e.dmg
				pr.radius = e.splash
				pr.friendly = false
				pr.car = ci
				pr.faction = e.faction
				projs.append(pr)
				e.face = 1 if car.pos.x > e.pos.x else -1
				emit({"t": "eshot", "from": pr.from, "to": pr.to, "kind": pr.kind, "id": e.id})
		RETURN:
			_move_to(e, e.lurk, e.spd * 0.6, dt)
			if e.pos.distance_to(e.lurk) < 3.0:
				e.state = LURK
			elif d < e.range_:
				e.state = ENGAGE


func _ai_horror(e: Enemy, dt: float) -> void:
	e.pos = map.pos_at(e.s_track)
	var d := map.ahead(map.wrap_s(odo), e.s_track)
	if d < e.r + 10.0 or d > map.length - 4.0:
		e.cd -= dt
		if e.cd <= 0.0:
			e.cd = e.cd_max
			_damage_train(e.dmg, 0, e.faction, e.type)
			emit({"t": "bite", "pos": e.pos, "car": 0, "id": e.id, "heavy": true})


func _ai_rig(e: Enemy, dt: float) -> void:
	var rear_odo := odo - train_length()
	var gap := rear_odo - e.odo
	var v := e.spd if gap > 14.0 else speed * 0.6
	e.ram_cd -= dt
	if gap <= 14.0 and e.ram_cd <= 0.0:
		e.ram_cd = 3.5
		_damage_train(e.dmg, cars.size() - 1, e.faction, "warrig")
		emit({"t": "rig_ram", "pos": e.pos})
		e.odo -= 34.0
	if gap < -40.0:
		e.odo = rear_odo - 40.0
	e.odo += v * dt
	e.pos = map.pos_at(e.odo)
	var ahead_pt := map.pos_at(e.odo + 4.0)
	e.face = 1 if ahead_pt.x >= e.pos.x else -1
	# mounted gun
	e.cd -= dt
	var ci := _nearest_car(e.pos)
	if e.cd <= 0.0 and e.pos.distance_to(cars[ci].pos) < e.range_:
		e.cd = e.cd_max
		var pr := Proj.new()
		pr.kind = "bullet"
		pr.from = e.pos
		pr.to = cars[ci].pos
		pr.dur = 0.25
		pr.dmg = e.extra_gun
		pr.friendly = false
		pr.car = ci
		pr.faction = e.faction
		projs.append(pr)
		emit({"t": "eshot", "from": pr.from, "to": pr.to, "kind": "bullet", "id": e.id})


func _explode_bloater(e: Enemy) -> void:
	var p := e.pos
	e.hp = 0.0
	_kill(e, "blast")
	_area_damage_train(p, e.blast, e.dmg, "infected", "bloater")
	for o: Enemy in enemies:
		if not o.dead and o != e and o.pos.distance_to(p) < e.blast:
			_damage_enemy(o, e.dmg * 1.5, "blast", false)
	emit({"t": "blast", "pos": p, "r": e.blast})


# ------------------------------------------------------------------ train weapons
func _nearest_enemy(p: Vector2, r: float, min_r: float) -> Enemy:
	var best: Enemy = null
	var bd := r * r
	var md := min_r * min_r
	for e: Enemy in enemies:
		if e.dead or not e.visible or e.emerge > 0.0:
			continue
		var d := p.distance_squared_to(e.pos)
		if d <= bd and d >= md:
			bd = d
			best = e
	return best


func _nearest_boss_part(p: Vector2, r: float) -> BossPart:
	var best: BossPart = null
	var bd := r * r
	for bp: BossPart in boss_parts:
		if not bp.alive:
			continue
		var d := p.distance_squared_to(bp.pos)
		if d <= bd:
			bd = d
			best = bp
	return best


func _update_weapons(dt: float) -> void:
	var rm := rate_mult()
	var rng_m := range_mult()
	for i in cars.size():
		var c: Car = cars[i]
		if c.w.is_empty():
			continue
		c.cd -= dt * rm
		if c.cd > 0.0:
			continue
		var kind: String = c.w.kind
		var r := float(c.w.range) * rng_m
		var min_r := float(c.w.get("min", 0.0))
		match kind:
			"gun":
				var t := _nearest_enemy(c.pos, r, 0.0)
				var bp: BossPart = null
				if t == null and boss_active:
					bp = _nearest_boss_part(c.pos, r)
				if t == null and bp == null:
					c.cd = 0.0
					continue
				c.cd += 1.0 / float(c.w.rate)
				var dmg := (float(c.w.dmg) + 2.0 * mod_count("ap")) * dmg_mult()
				var crit := rng.randf() < 0.1
				if crit:
					dmg *= 2.0
				var tp: Vector2 = t.pos if t != null else bp.pos
				c.aim = (tp - c.pos).angle()
				c.recoil = 1.0
				if t != null:
					_damage_enemy(t, dmg, "gun", true, crit)
				else:
					_damage_boss_part(bp, dmg, true, crit)
				emit({"t": "shot", "car": i, "from": c.pos, "to": tp, "crit": crit})
			"flame":
				var any := false
				var fr := r
				var dmg := float(c.w.dmg) * dmg_mult()
				var burn := float(c.w.burn) * (1.0 + 0.6 * mod_count("napalm")) * sqrt(enemy_hp_mult())
				var tgt := Vector2.ZERO
				for e: Enemy in enemies:
					if e.dead or e.emerge > 0.0:
						continue
					if e.pos.distance_squared_to(c.pos) <= fr * fr:
						_damage_enemy(e, dmg, "flame", false)
						e.burn = maxf(e.burn, burn)
						e.burn_t = 3.0
						any = true
						tgt = e.pos
				if boss_active:
					var bp2 := _nearest_boss_part(c.pos, fr + 8.0)
					if bp2 != null:
						_damage_boss_part(bp2, dmg, false)
						any = true
						tgt = bp2.pos
				if any:
					c.cd += 1.0 / float(c.w.rate)
					c.aim = (tgt - c.pos).angle()
					c.firing = 0.3
					emit({"t": "flame", "car": i, "from": c.pos, "to": tgt})
				else:
					c.cd = 0.0
			"mortar":
				var t := _nearest_enemy(c.pos, r, min_r)
				# prefer the densest target: sample a few candidates
				var best_t := t
				var best_n := 0
				for e: Enemy in enemies:
					if e.dead or not e.visible or e.emerge > 0.0:
						continue
					var d2 := e.pos.distance_squared_to(c.pos)
					if d2 > r * r or d2 < min_r * min_r:
						continue
					var cnt := 0
					for o: Enemy in enemies:
						if not o.dead and o.pos.distance_squared_to(e.pos) < 400.0:
							cnt += 1
					if cnt > best_n:
						best_n = cnt
						best_t = e
				var tp := Vector2.ZERO
				if best_t != null:
					tp = best_t.pos
				elif boss_active:
					var bp3 := _nearest_boss_part(c.pos, r)
					if bp3 == null:
						c.cd = 0.0
						continue
					tp = bp3.pos
				else:
					c.cd = 0.0
					continue
				c.cd += 1.0 / float(c.w.rate)
				c.aim = (tp - c.pos).angle()
				c.recoil = 1.0
				var pr := Proj.new()
				pr.kind = "shell"
				pr.from = c.pos
				pr.to = tp
				pr.dur = 0.9
				pr.dmg = (float(c.w.dmg) + 4.0 * mod_count("shrapnel")) * dmg_mult()
				pr.radius = float(c.w.radius) * (1.0 + 0.4 * mod_count("shrapnel"))
				pr.friendly = true
				projs.append(pr)
				emit({"t": "mortar", "car": i, "from": c.pos, "to": tp})
			"tesla":
				var t := _nearest_enemy(c.pos, r, 0.0)
				var dmg := float(c.w.dmg) * dmg_mult() * (1.3 if fac_count("power") > 0 else 1.0)
				if t == null:
					if boss_active:
						var bp4 := _nearest_boss_part(c.pos, r)
						if bp4 != null:
							c.cd += 1.0 / float(c.w.rate)
							_damage_boss_part(bp4, dmg * 1.5, true)
							emit({"t": "zap", "car": i, "pts": [c.pos, bp4.pos]})
							continue
					c.cd = 0.0
					continue
				c.cd += 1.0 / float(c.w.rate)
				var pts: Array = [c.pos, t.pos]
				var hit := {t.id: true}
				var cur := t
				var chains := int(c.w.chains) + 2 * mod_count("coil")
				_damage_enemy(cur, dmg, "tesla", true)
				for k in chains:
					var nxt: Enemy = null
					var bd := 48.0 * 48.0
					for e: Enemy in enemies:
						if e.dead or hit.has(e.id) or not e.visible:
							continue
						var d := e.pos.distance_squared_to(cur.pos)
						if d < bd:
							bd = d
							nxt = e
					if nxt == null:
						break
					hit[nxt.id] = true
					dmg *= 0.8
					_damage_enemy(nxt, dmg, "tesla", true)
					pts.append(nxt.pos)
					cur = nxt
				c.aim = (t.pos - c.pos).angle()
				emit({"t": "zap", "car": i, "pts": pts})


func _update_projectiles(dt: float) -> void:
	for pr: Proj in projs:
		pr.t += dt
		if pr.t < pr.dur:
			continue
		match pr.kind:
			"shell", "turret_shell":
				var src_tag := "mortar_t" if pr.kind == "turret_shell" else "mortar"
				for e: Enemy in enemies:
					if not e.dead and e.pos.distance_to(pr.to) <= pr.radius + e.r:
						_damage_enemy(e, pr.dmg, src_tag, false)
				if boss_active:
					for bp: BossPart in boss_parts:
						if bp.alive and bp.pos.distance_to(pr.to) <= pr.radius + 12.0:
							_damage_boss_part(bp, pr.dmg, false)
				emit({"t": "boom", "pos": pr.to, "r": pr.radius})
			"bullet":
				if pr.car >= 0 and pr.car < cars.size():
					_damage_train(pr.dmg, pr.car, pr.faction, "bullet")
			"bomb":
				var bp_at: Vector2 = cars[pr.car].pos if pr.car < cars.size() else pr.to
				_area_damage_train(bp_at, pr.radius + 10.0, pr.dmg, pr.faction, "bomb")
				emit({"t": "fireburst", "pos": cars[mini(pr.car, cars.size() - 1)].pos})
			"boss_shell":
				if pr.car >= 0 and pr.car < cars.size():
					_damage_train(pr.dmg, pr.car, "boss", "boss_shell")
				emit({"t": "boom", "pos": cars[mini(pr.car, cars.size() - 1)].pos, "r": 10.0, "enemy": true})
			"boss_mortar":
				_area_damage_train(pr.to, pr.radius + 10.0, pr.dmg, "boss", "boss_mortar")
				emit({"t": "boom", "pos": pr.to, "r": pr.radius, "enemy": true})
	projs = projs.filter(func(p): return p.t < p.dur)


# ------------------------------------------------------------------ damage
func _damage_enemy(e: Enemy, dmg: float, src: String, show: bool, crit := false) -> void:
	if e.dead:
		return
	if has_relic("lantern") and e.pos.distance_squared_to(cars[0].pos) < 3600.0:
		dmg *= 1.2
	e.hp -= dmg
	if show:
		e.flash = 0.12
		emit({"t": "hit", "id": e.id, "pos": e.pos, "dmg": dmg, "crit": crit, "src": src})
	if e.hp <= 0.0:
		_kill(e, src)


func _kill(e: Enemy, src: String) -> void:
	if e.dead:
		return
	e.dead = true
	if e.home >= 0 and facs.has(e.home):
		facs[e.home].alive = maxi(0, facs[e.home].alive - 1)
	if e.parent >= 0:
		for o: Enemy in enemies:
			if o.id == e.parent:
				o.children = maxi(0, o.children - 1)
	stats.kills[e.type] = int(stats.kills.get(e.type, 0)) + 1
	var sc := e.scrap
	if e.faction == "raider" and has_relic("trophy"):
		sc += 3
	var turret := src == "turret" or src == "mortar_t"
	if turret:
		sc = int(ceil(sc * 0.5))
	_gain_scrap(sc, e.pos)
	var chance := e.card + (0.06 if has_relic("token") else 0.0)
	if turret:
		chance *= 0.5
	if e.boss_minion:
		chance *= 0.3
	if rng.randf() < chance:
		give_card(_draw_card_id(), e.pos)
	if e.relic > 0.0 and rng.randf() < e.relic:
		if rng.randf() < 0.5 and _try_blueprint(e.pos):
			pass
		else:
			var r := _random_relic()
			if r != "":
				_gain_relic(r)
	emit({"t": "kill", "id": e.id, "type": e.type, "pos": e.pos, "src": src, "elite": e.elite})


## Area attacks hit the shared hull once; extra cars caught add 30% each.
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


func _damage_train(dmg: float, car_i: int, faction: String, src: String) -> void:
	if state != "running":
		return
	if faction == "infected" and has_relic("gasmask"):
		dmg *= 0.7
	if faction == "raider" and has_relic("trophy"):
		dmg *= 0.8
	var a := armor_value()
	var final_dmg := maxf(dmg * 0.25, dmg - a)
	hull -= final_dmg
	loop_dmg += final_dmg
	stats.dmg_taken += final_dmg
	car_i = clampi(car_i, 0, cars.size() - 1)
	cars[car_i].flash = 0.15
	emit({"t": "train_hit", "car": car_i, "dmg": final_dmg, "src": src, "pos": cars[car_i].pos})
	if hull <= 0.0:
		hull = 0.0
		state = "dead"
		stats.death_cause = src
		emit({"t": "dead", "src": src})


func _cleanup() -> void:
	if enemies.size() > 0:
		var alive: Array = []
		for e: Enemy in enemies:
			if not e.dead:
				alive.append(e)
		enemies = alive


# ================================================================== boss
func _spawn_boss() -> void:
	boss_active = true
	stats.boss_loop = loop
	var scale := maxf(0.8, 1.0 + float(Defs.BOSS.hp_per_loop) * (loop - 6))
	boss_parts.clear()
	var kinds := ["head", "gun", "brood", "mortar"]
	var off := 0.0
	for k in kinds:
		var bp := BossPart.new()
		bp.kind = k
		bp.length = 32.0 if k == "head" else 26.0
		bp.max_hp = (float(Defs.BOSS.head_hp) if k == "head" else float(Defs.BOSS.car_hp)) * scale
		bp.hp = bp.max_hp
		bp.off = off + bp.length * 0.5
		off += bp.length + 3.0
		bp.cd = rng.randf_range(2.0, 4.0)
		boss_parts.append(bp)
	# the Black Train wakes up on the dead line, well behind us
	boss_odo = map.main_to_ghost(odo) - train_length() - 260.0
	boss_speed = 70.0
	boss_state = "enter"
	boss_t = 0.0
	boss_ram_cd = 9.0
	_layout_boss()
	emit({"t": "boss_spawn", "loop": loop})


func _layout_boss() -> void:
	for bp: BossPart in boss_parts:
		var s := boss_odo - bp.off
		bp.pos = map.gpos_at(s)
		var dv := map.gpos_at(s + bp.length * 0.4) - map.gpos_at(s - bp.length * 0.4)
		bp.angle = dv.angle()


func boss_dmg_mult() -> float:
	return 1.0 + float(Defs.BOSS.dmg_per_loop) * (loop - 1)


func boss_hp_ratio() -> float:
	if boss_parts.is_empty():
		return 0.0
	var h := 0.0
	var m := 0.0
	for bp: BossPart in boss_parts:
		h += maxf(0.0, bp.hp)
		m += bp.max_hp
	return h / m


func _boss_cars_alive() -> int:
	var k := 0
	for bp: BossPart in boss_parts:
		if bp.kind != "head" and bp.alive:
			k += 1
	return k


func _damage_boss_part(bp: BossPart, dmg: float, show: bool, crit := false) -> void:
	if not bp.alive or not boss_active:
		return
	if bp.kind == "head" and _boss_cars_alive() > 0:
		dmg *= float(Defs.BOSS.armor_mult)
	bp.hp -= dmg
	bp.flash = 0.1
	if show:
		emit({"t": "bhit", "pos": bp.pos, "dmg": dmg, "crit": crit, "part": bp.kind})
	if bp.hp <= 0.0:
		bp.hp = 0.0
		bp.alive = false
		emit({"t": "bpart_dead", "part": bp.kind, "pos": bp.pos})
		if bp.kind == "head":
			_boss_defeated()
		elif not boss_enraged and _boss_cars_alive() == 0:
			boss_enraged = true
			emit({"t": "boss_enrage"})


func _boss_defeated() -> void:
	boss_active = false
	stats.boss_result = "win"
	for bp: BossPart in boss_parts:
		bp.alive = false
	for e: Enemy in enemies:
		if e.boss_minion:
			e.dead = true
	var bonus := 150 + 20 * loop
	scrap += bonus
	stats.scrap_earned += bonus
	state = "victory"
	emit({"t": "boss_dead", "pos": boss_parts[0].pos, "bonus": bonus})


func _update_boss(dt: float) -> void:
	boss_t += dt
	var head: BossPart = boss_parts[0]
	if head.hp <= head.max_hp * 0.5 and not boss_enraged:
		boss_enraged = true
		emit({"t": "boss_enrage"})
	var rate := 1.35 if boss_enraged else 1.0
	# keep pace with our train on the parallel dead line; drift forward and back
	# so different cars trade fire over time
	var sway := sin(time * 0.35) * 46.0
	var target := map.main_to_ghost(odo - train_length() * 0.5) + 30.0 + sway
	var cur := fposmod(boss_odo, map.glength)
	var gap := wrapf(target - cur, -map.glength * 0.5, map.glength * 0.5)
	var pace := speed * (map.glength / map.length)
	match boss_state:
		"enter":
			boss_speed = pace + 55.0
			if absf(gap) < 40.0:
				boss_state = "chase"
				emit({"t": "boss_alongside"})
		"chase":
			boss_speed = pace + clampf(gap * 1.4, -35.0, 40.0)
			boss_ram_cd -= dt * rate
			if boss_ram_cd <= 0.0:
				boss_state = "telegraph"
				boss_t = 0.0
				emit({"t": "boss_telegraph", "pos": head.pos})
		"telegraph":
			boss_speed = pace + clampf(gap * 1.4, -35.0, 40.0)
			if boss_t > 1.6:
				# the horn: a shockwave that slams every car near the head
				var dmg := float(Defs.BOSS.ram_dmg) * boss_dmg_mult() * (1.2 if boss_enraged else 1.0)
				var hit_any := _area_damage_train(head.pos, 70.0, dmg, "boss", "boss_ram") > 0
				for c: Car in cars:
					if c.pos.distance_to(head.pos) < 70.0:
						c.cd = maxf(c.cd, 1.2)
				emit({"t": "boss_ram", "pos": head.pos, "hit": hit_any})
				boss_state = "recoil"
				boss_t = 0.0
				boss_ram_cd = rng.randf_range(10.0, 13.0)
		"recoil":
			boss_speed = pace * 0.7
			if boss_t > 1.2:
				boss_state = "chase"
	boss_odo += maxf(0.0, boss_speed) * dt
	_layout_boss()
	for bp: BossPart in boss_parts:
		bp.flash = maxf(0.0, bp.flash - dt)
	if boss_state == "enter":
		return
	# part attacks
	for bp: BossPart in boss_parts:
		if not bp.alive:
			continue
		bp.cd -= dt * rate
		if bp.cd > 0.0:
			continue
		match bp.kind:
			"gun":
				bp.cd = 4.2
				for k in 3:
					var pr := Proj.new()
					pr.kind = "boss_shell"
					pr.car = rng.randi_range(maxi(0, cars.size() - 3), cars.size() - 1)
					pr.from = bp.pos
					pr.to = cars[pr.car].pos
					pr.dur = 0.55 + 0.12 * k
					pr.dmg = float(Defs.BOSS.shell_dmg) * boss_dmg_mult()
					pr.friendly = false
					projs.append(pr)
				emit({"t": "boss_salvo", "pos": bp.pos})
			"brood":
				bp.cd = 10.0
				for k in 2:
					var e := _spawn("runner" if k < 2 else "dog", bp.pos + Vector2(rng.randf_range(-10, 10), rng.randf_range(-10, 10)), -1)
					e.state = ENGAGE
					e.boss_minion = true
				emit({"t": "boss_brood", "pos": bp.pos})
			"mortar":
				bp.cd = 7.0
				for k in 3:
					var pr := Proj.new()
					pr.kind = "boss_mortar"
					var lead := speed * 1.4 + rng.randf_range(-20.0, 40.0)
					pr.to = map.pos_at(odo - rng.randf_range(0.0, train_length()) + lead)
					pr.from = bp.pos
					pr.dur = 1.4
					pr.radius = 16.0
					pr.dmg = float(Defs.BOSS.mortar_dmg) * boss_dmg_mult()
					pr.friendly = false
					projs.append(pr)
					emit({"t": "boss_mortar_mark", "pos": pr.to, "dur": pr.dur})
			"head":
				bp.cd = 5.0


# ================================================================== summaries
func bank_preview() -> Dictionary:
	var keep := 1.0
	return {"scrap": int(scrap * keep), "survivors": _survivor_score(), "blueprints": blueprints.duplicate()}


func death_keep_ratio() -> float:
	var k := 0.25 + float(mods.get("keep", 0.0))
	for c: Car in cars:
		if c.type == "cargo":
			k += float(Defs.CARS.cargo.keep)
	return minf(0.6, k)


## scrap multiplier applied when the player returns: deeper runs are worth more per loop
func haul_mult() -> float:
	return clampf(0.5 + 0.1 * loop, 0.6, 1.5)


func _survivor_score() -> int:
	return int(survivors * (1.5 if has_relic("ledger") else 1.0))


func final_result() -> Dictionary:
	var res := {"state": state, "loops": loop, "time": time, "kills": 0}
	for k in stats.kills.values():
		res.kills += int(k)
	match state:
		"returned":
			res.scrap = int(round(scrap * haul_mult()))
			res.survivors = _survivor_score()
			res.blueprints = blueprints.duplicate()
		"victory":
			res.scrap = int(round(scrap * 1.5))
			res.survivors = _survivor_score() + 10
			res.blueprints = blueprints.duplicate()
		_:
			res.scrap = int(scrap * death_keep_ratio())
			res.survivors = 0
			res.blueprints = []
	return res


# ================================================================== UI previews
## Readable consequences of placing card `id` on `lot_id`: Array of [text, tone]
## tone: "good" / "bad" / "info". Lets players learn the rules while dragging.
func place_hints(id: String, lot_id: int) -> Array:
	var out: Array = []
	if id == "purge":
		if facs.has(lot_id):
			out.append(["%s 소각, 군세 -4" % Defs.FACILITIES[facs[lot_id].type].name, "good"])
		return out
	if not Defs.FACILITIES.has(id):
		return out
	var nb_types: Array = []
	for f: Fac in neighbors_of(lot_id):
		nb_types.append(f.type)
	var protected := false
	for t in nb_types:
		if (Defs.FACILITIES[t].tags as Array).has("military"):
			protected = true
	var has := func(list: Array) -> int:
		var k := 0
		for t in nb_types:
			if list.has(t):
				k += 1
		return k
	var infected: int = has.call(["infection", "hive", "ward", "sporefarm"])
	var raiders: int = has.call(["raiders", "fortress"])
	var civil := 0
	for t in nb_types:
		if (Defs.FACILITIES[t].tags as Array).has("civil"):
			civil += 1
	match id:
		"station":
			if has.call(["market", "blackmarket"]) > 0:
				out.append(["시장 인접: 환승역으로 진화", "good"])
			if has.call(["hospital", "medhub"]) > 0:
				out.append(["병원 인접: 정차 수리 +5%", "good"])
			if has.call(["hospital"]) > 0:
				out.append(["병원을 의료 거점으로 만든다", "good"])
			if has.call(["ruin"]) > 0:
				out.append(["폐역이 망령역이 되지 않는다", "good"])
			if infected > 0 and not protected:
				out.append(["감염 인접: 폐역으로 몰락 위험", "bad"])
		"market":
			var inc: int = 6 + 3 * has.call(["factory", "assembly"]) + 2 * has.call(["station", "transfer", "ruin"])
			if has.call(["station"]) > 0:
				out.append(["역을 환승역으로 만든다", "good"])
			out.append(["통과 수입 약 고철 %d" % inc, "info"])
			if raiders > 0:
				out.append(["약탈자 인접: 암시장으로 진화", "good"])
				if not protected:
					out.append(["약탈당해 수입 절반", "bad"])
			else:
				out.append(["약탈자를 끌어들일 수 있다", "bad"])
		"hospital":
			if has.call(["station", "transfer"]) > 0:
				out.append(["역 인접: 의료 거점으로 진화", "good"])
			if infected > 0 and not protected:
				out.append(["감염 인접: 감염병동이 될 수 있다!", "bad"])
		"factory":
			if has.call(["power"]) > 0:
				out.append(["발전소 인접: 조립공장으로 진화", "good"])
			if has.call(["market", "blackmarket"]) > 0:
				out.append(["시장 수입 +3", "good"])
			if has.call(["greenhouse"]) > 0:
				out.append(["온실 인접: 소음 -2", "good"])
			if has.call(["infection", "hive"]) > 0:
				out.append(["오염: 인접 감염구역 가속", "bad"])
		"checkpoint":
			if raiders > 0:
				out.append(["약탈자 인접: 용병 초소로 진화", "good"])
			if has.call(["armory"]) > 0:
				out.append(["무기고 인접: 포대로 진화", "good"])
			if civil > 0:
				out.append(["인접 민간 시설 %d곳 보호" % civil, "good"])
			out.append(["유지비: 바퀴마다 보급품 1", "info"])
		"infection":
			out.append(["처치 시 카드가 잘 나온다", "good"])
			var victims := 0
			for f: Fac in neighbors_of(lot_id):
				if ["hospital", "medhub", "shelter", "commune", "greenhouse", "station"].has(f.type) and not is_protected(f.lot):
					victims += 1
			if victims > 0:
				out.append(["인접 민간 시설 %d곳 감염 위험" % victims, "bad"])
			if has.call(["factory", "assembly"]) > 0:
				out.append(["공장 인접: 둥지로 빨리 진화", "bad"])
		"raiders":
			out.append(["처치 시 고철이 많다", "good"])
			if has.call(["market", "blackmarket"]) >= 2:
				out.append(["시장 2곳: 즉시 요새화!", "bad"])
			elif has.call(["market"]) > 0:
				out.append(["시장을 암시장으로 만든다", "good"])
			if has.call(["shelter", "commune"]) > 0:
				out.append(["피난처 생존자를 약탈", "bad"])
			if has.call(["armory"]) > 0:
				out.append(["무기고 인접: 약탈자 무장", "bad"])
			if has.call(["checkpoint"]) > 0:
				out.append(["검문소를 용병 초소로", "good"])
		"shelter":
			if has.call(["greenhouse"]) > 0:
				out.append(["온실 인접: 공동체로 진화", "good"])
			if infected > 0 and not protected:
				out.append(["감염 인접: 감염구역이 될 수 있다", "bad"])
			if raiders > 0 and not protected:
				out.append(["약탈자가 생존자를 빼앗는다", "bad"])
			if has.call(["ruin"]) > 0:
				out.append(["인접 폐역을 역으로 복구", "good"])
		"ruin":
			if has.call(["shelter", "commune"]) > 0:
				out.append(["피난처 인접: 역으로 복구", "good"])
			elif has.call(["station", "transfer"]) == 0:
				out.append(["4바퀴 뒤 망령역 (터널 괴물)", "bad"])
		"greenhouse":
			if has.call(["shelter"]) > 0:
				out.append(["피난처를 공동체로 만든다", "good"])
			if has.call(["factory", "assembly"]) > 0:
				out.append(["인접 공장 소음 -2", "good"])
			if infected > 0 and not protected:
				out.append(["감염되면 포자농장", "bad"])
		"armory":
			if has.call(["checkpoint"]) > 0:
				out.append(["검문소를 포대로 만든다", "good"])
			if raiders > 0:
				out.append(["인접 약탈자가 무장한다", "bad"])
		"power":
			if has.call(["factory"]) > 0:
				out.append(["공장을 조립공장으로 만든다", "good"])
			out.append(["주변 선로에 전류 + 가속", "good"])
		"radio":
			out.append(["매 바퀴 무전 사건", "info"])
	var nz := float(Defs.FACILITIES[id].noise)
	if nz > 0.0:
		out.append(["군세 +%s/바퀴" % _fmt(nz), "bad" if nz >= 2.0 else "info"])
	return out


func _fmt(v: float) -> String:
	return str(int(v)) if absf(v - round(v)) < 0.01 else "%.1f" % v


## live status lines for a placed facility (tooltip)
func fac_status(lot_id: int) -> Array:
	var out: Array = []
	if not facs.has(lot_id):
		return out
	var f: Fac = facs[lot_id]
	match f.type:
		"station", "transfer":
			var pct := 0.12 + 0.05 * adj_count(lot_id, ["hospital", "medhub"])
			out.append(["정차 수리 %d%%" % int(round(pct * 100)), "info"])
		"market", "blackmarket":
			var inc := (6 if f.type == "market" else 8) + 3 * adj_count(lot_id, ["factory", "assembly"]) + 2 * adj_tag(lot_id, "transit")
			if adj_count(lot_id, ["raiders", "fortress"]) > 0 and not is_protected(lot_id):
				inc = int(inc * 0.5)
				out.append(["약탈당하는 중 (수입 절반)", "bad"])
			out.append(["통과 수입 약 고철 %d" % inc, "good"])
		"shelter", "commune", "hospital", "medhub":
			if f.waiting > 0:
				out.append(["대기 생존자 %d명" % f.waiting, "good"])
	if f.disabled:
		out.append(["유지비 부족: 작동 정지", "bad"])
	var evo := evo_target(lot_id, 1)
	if evo != "":
		var hostile: bool = Defs.FACILITIES[evo].cat == "hostile"
		out.append(["다음 정차 시 %s(으)로 변화" % Defs.FACILITIES[evo].name, "bad" if hostile else "good"])
	else:
		var cd := evo_countdown(lot_id)
		if cd > 0:
			var to: String = {"ruin": "망령역", "infection": "둥지", "raiders": "약탈자 요새"}.get(f.type, "?")
			out.append(["%d바퀴 뒤 %s" % [cd, to], "bad"])
	var nz := float(Defs.FACILITIES[f.type].noise)
	if f.type in ["factory", "assembly"]:
		nz = maxf(0.0, nz - 2.0 * adj_count(lot_id, ["greenhouse"]))
	if nz > 0.0:
		out.append(["군세 +%s/바퀴" % _fmt(nz), "info"])
	return out


## projected horde gain at the next depot stop (for the HUD gauge preview)
func noise_per_loop() -> float:
	var noise := Defs.HORDE_BASE_PER_LOOP
	for lot_id in facs.keys():
		var f: Fac = facs[lot_id]
		var nz := float(Defs.FACILITIES[f.type].noise)
		if f.type == "factory" or f.type == "assembly":
			nz = maxf(0.0, nz - 2.0 * adj_count(lot_id, ["greenhouse"]))
		noise += nz
	if has_relic("jammer"):
		noise *= 0.75
	return noise


func loop_progress() -> float:
	var start := map.depot_s + (loop - 1) * map.length
	return clampf((odo - start) / map.length, 0.0, 1.0)


## short threat forecast for the next loop (depot panel)
func forecast() -> Array:
	var out: Array = []
	var elites := {}
	for lot_id in facs.keys():
		var f: Fac = facs[lot_id]
		var d: Dictionary = Defs.FACILITIES[f.type]
		if d.has("elite") and f.elite_timer + 1 >= int(d.elite_every):
			var nm: String = Defs.ENEMIES[d.elite].name
			elites[nm] = int(elites.get(nm, 0)) + 1
	for nm in elites.keys():
		out.append("[color=#ff9a6a]%s%s[/color]" % [nm, (" x%d" % elites[nm]) if elites[nm] > 1 else ""])
	var raid := fac_count("raiders") + fac_count("fortress")
	if raid > 0:
		out.append("바리케이드 %d곳 가능" % raid)
	out.append("적 체력 +%d%%" % int(round((Defs.ENEMY_HP_GROWTH - 1.0) * 100)))
	if not boss_active and horde < 100.0 and horde + noise_per_loop() >= 100.0:
		out.append("[color=#ff4a4a]다음 정차 때 군세 100[/color]")
	return out
