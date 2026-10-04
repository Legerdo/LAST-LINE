class_name AIPlayer
extends RefCounted
## Scripted virtual players used by the balance harness. Each persona places cards,
## answers depot / event prompts and decides when to go home.

var persona := "safe"
var rng := RandomNumberGenerator.new()
var think_cd := 0.0
var fight_boss := true

const FRIENDLY := ["station", "hospital", "shelter", "market", "factory", "checkpoint", "greenhouse", "armory", "power", "radio"]
const HOSTILE := ["infection", "raiders", "ruin"]


func _init(p: String, seed_value: int) -> void:
	persona = p
	rng.seed = seed_value * 7919 + 13


func act(sim: Sim, dt: float) -> void:
	if not sim.pending.is_empty():
		_resolve(sim)
		return
	think_cd -= dt
	if think_cd > 0.0:
		return
	think_cd = 0.6 if persona != "random" else 1.0
	# train cards first
	for i in range(sim.hand.size() - 1, -1, -1):
		if sim.can_use_train_card(i):
			sim.use_train_card(i)
	_place_best(sim)


# ---------------------------------------------------------------- placement
func _card_value(id: String) -> float:
	var pp := "economy" if persona == "sprint" else persona
	match pp:
		"safe":
			return {"station": 6.0, "hospital": 7.0, "shelter": 4.0, "checkpoint": 6.0, "greenhouse": 5.0,
				"market": 3.0, "factory": 1.5, "armory": 2.0, "power": 1.0, "radio": -5.0,
				"infection": -2.0, "raiders": -3.0, "ruin": 0.5}.get(id, 0.0)
		"aggressive":
			return {"infection": 6.0, "raiders": 5.0, "ruin": 5.0, "armory": 5.0, "checkpoint": 4.0,
				"station": 3.0, "hospital": 3.0, "market": 2.0, "factory": 3.0, "power": 3.0,
				"shelter": 2.0, "greenhouse": 1.0, "radio": 1.0}.get(id, 0.0)
		"economy":
			return {"market": 7.0, "factory": 6.0, "station": 5.0, "shelter": 4.0, "greenhouse": 5.0,
				"hospital": 4.0, "checkpoint": 3.0, "power": 4.0, "armory": 1.0, "radio": -2.0,
				"infection": 1.0, "raiders": 1.0, "ruin": 2.0}.get(id, 0.0)
		"greedy":
			return {"infection": 5.0, "raiders": 5.0, "ruin": 5.0, "market": 5.0, "factory": 5.0,
				"station": 4.0, "hospital": 4.0, "shelter": 4.0, "checkpoint": 3.0, "power": 4.0,
				"radio": 4.0, "armory": 4.0, "greenhouse": 3.0}.get(id, 0.0)
		"turtle":
			return {"checkpoint": 9.0, "station": 6.0, "hospital": 6.0, "armory": 5.0, "greenhouse": 3.0,
				"infection": 2.0, "raiders": 3.0, "ruin": 1.0, "market": 1.0, "shelter": 1.0}.get(id, -1.0)
		"farmer":
			# exploit attempt: hostile spawners wrapped in checkpoints for free kills
			return {"infection": 7.0, "checkpoint": 7.0, "raiders": 5.0, "armory": 5.0, "ruin": 4.0,
				"station": 3.0, "hospital": 3.0}.get(id, 0.0)
		"stall":
			# exploit attempt: keep noise minimal and farm many cheap loops
			return {"greenhouse": 8.0, "hospital": 5.0, "shelter": 4.0, "station": 4.0, "checkpoint": 3.0,
				"infection": 2.0, "ruin": 2.0}.get(id, -3.0)
	return 1.0


func _synergy(sim: Sim, id: String, lot_id: int) -> float:
	var v := 0.0
	var nb := sim.neighbors_of(lot_id)
	var types: Array = []
	for f in nb:
		types.append(f.type)
	var infected := 0
	var raider := 0
	var military := 0
	var civil := 0
	for t in types:
		var tags: Array = Defs.FACILITIES[t].tags
		if tags.has("infected"):
			infected += 1
		if tags.has("raider"):
			raider += 1
		if tags.has("military"):
			military += 1
		if tags.has("civil"):
			civil += 1
	var careful := persona in ["safe", "economy", "turtle", "stall"]
	match id:
		"station":
			v += 3.0 * (types.count("market")) + 2.0 * types.count("hospital")
			if infected > 0 and military == 0:
				v -= 3.0 if careful else 1.0
		"market":
			v += 3.0 * (types.count("station") + types.count("factory"))
			if raider > 0:
				v += 1.0 if not careful else -2.0
		"hospital":
			v += 3.0 * types.count("station")
			if infected > 0 and military == 0:
				v -= 5.0 if careful else 1.0
		"factory":
			v += 2.0 * types.count("market") + 3.0 * types.count("power")
			if persona == "safe":
				v -= 1.0 * types.count("infection")
		"shelter":
			v += 4.0 * types.count("greenhouse")
			if infected > 0 and military == 0:
				v -= 5.0 if careful else 1.5
			if raider > 0 and military == 0:
				v -= 2.0
		"greenhouse":
			v += 3.0 * types.count("shelter") + 2.0 * types.count("factory")
			if infected > 0 and military == 0:
				v -= 3.0
		"checkpoint":
			v += 1.5 * civil + 2.0 * infected + (2.0 * raider if persona != "safe" else 1.0 * raider)
			v += 2.0 * types.count("armory")
		"armory":
			v += 2.0 * types.count("checkpoint")
			if raider > 0:
				v -= 2.0
		"power":
			v += 3.0 * types.count("factory")
		"infection":
			if careful:
				v -= 2.0 * civil
			else:
				v += 2.0 * military + 1.0 * types.count("factory")
		"raiders":
			if careful:
				v -= 2.0 * civil
			else:
				v += 2.0 * types.count("market") + 2.0 * military
		"ruin":
			v += 2.0 * types.count("shelter") if careful else 0.5
		"radio":
			v += 0.0
	# spread things around the loop so every stretch has something going on
	v += rng.randf_range(-0.8, 0.8)
	return v


func _place_best(sim: Sim) -> void:
	if sim.state != "running":
		return
	var best_v := -INF
	var best_i := -1
	var best_l := -1
	for i in sim.hand.size():
		var id: String = sim.hand[i]
		var kind := sim.card_kind(id)
		if kind == "action":
			var tgt := _purge_target(sim)
			if tgt >= 0 and best_v < 6.0:
				best_v = 6.0
				best_i = i
				best_l = tgt
			continue
		if kind != "facility":
			continue
		var base := _card_value(id)
		if persona == "random":
			base = rng.randf_range(-1.0, 3.0)
		for l in sim.map.lots:
			if sim.facs.has(l.id):
				continue
			var v := base + (_synergy(sim, id, l.id) if persona != "random" else 0.0)
			if v > best_v:
				best_v = v
				best_i = i
				best_l = l.id
	var threshold: float = {"safe": 3.0, "aggressive": 1.0, "economy": 2.0, "greedy": -1.0, "random": 0.0,
		"turtle": 2.0, "farmer": 2.0, "stall": 3.5}.get(persona, 1.0)
	# hold a couple of cards back so the hand does not overflow uselessly
	if best_i >= 0 and (best_v >= threshold or (sim.hand.size() >= Defs.HAND_MAX - 1 and best_v >= threshold - 2.5)):
		sim.place_card(best_i, best_l)


func _purge_target(sim: Sim) -> int:
	var best := -1
	var best_v := 0.0
	for lot_id in sim.facs.keys():
		var t: String = sim.facs[lot_id].type
		var v: float = {"hive": 6.0, "fortress": 5.0, "ward": 5.0, "ghost": 3.0, "sporefarm": 1.0}.get(t, 0.0)
		if persona in ["aggressive", "greedy", "farmer"]:
			v -= 3.0
		if v > best_v:
			best_v = v
			best = lot_id
	return best


# ---------------------------------------------------------------- decisions
func _resolve(sim: Sim) -> void:
	var p := sim.pending
	match String(p.kind):
		"depot":
			_depot(sim)
		"reward":
			sim.reward_pick(_best_reward(sim, p.options))
		"event":
			var choice := 1
			var id: String = p.id
			match persona:
				"safe", "stall":
					choice = 0 if id in ["crew", "sighting", "toll", "drop"] else 1
				"aggressive", "greedy", "farmer":
					choice = 0
				"economy":
					choice = 0 if id in ["drop", "merchant", "sos", "sighting"] else 1
				"random":
					choice = rng.randi() % 2
				_:
					choice = 0 if id in ["crew", "drop"] else 1
			sim.event_choose(choice)
		"blackmarket":
			var buy := sim.scrap >= int(p.cost) + (60 if persona in ["safe", "economy"] else 0)
			if persona == "random":
				buy = rng.randf() < 0.5
			sim.bm_choose(buy)


func _reward_score(sim: Sim, id: String) -> float:
	var cat := id.split(":")[0]
	var hp := sim.hull / sim.max_hull
	var s := 0.0
	match cat:
		"car":
			s = 6.0
			var t := id.substr(4)
			if t == "passenger" and sim.survivors < sim.crew_cap() - 3:
				s -= 3.0
			if t in ["gun", "flame", "mortar", "tesla"]:
				s += 1.0
		"mod":
			s = 5.0
		"relic":
			s = 8.0
		"repair":
			s = 9.0 * (1.0 - hp) + 1.0
		"supplies":
			s = 4.0 if sim.supplies < 6 else 1.5
		"cards":
			s = 4.0
		"card":
			s = 3.0
	match persona:
		"safe", "stall":
			if cat == "repair":
				s += 2.0
		"economy":
			if cat == "cards" or cat == "card":
				s += 2.0
		"aggressive", "greedy":
			if cat == "car" or cat == "mod":
				s += 1.5
		"random":
			s = rng.randf() * 5.0
	return s


func _best_reward(sim: Sim, opts: Array) -> int:
	var best := 0
	var bv := -INF
	for i in opts.size():
		var v := _reward_score(sim, String(opts[i]))
		if v > bv:
			bv = v
			best = i
	return best


func _depot(sim: Sim) -> void:
	var p := sim.pending
	sim.depot_pick(_best_reward(sim, p.options))
	var hp := sim.hull / sim.max_hull
	# shop
	var shop: Array = p.shop
	for i in shop.size():
		var item: Dictionary = shop[i]
		if item.sold:
			continue
		var cost := int(item.cost)
		var id: String = item.id
		var want := false
		if id.begins_with("repair") and hp < 0.55:
			want = sim.scrap >= cost
		elif id.begins_with("mod"):
			match persona:
				"aggressive", "greedy", "farmer":
					want = sim.scrap >= cost
				"economy", "safe", "stall":
					want = sim.scrap >= cost * 3
				"random":
					want = rng.randf() < 0.3 and sim.scrap >= cost
				_:
					want = sim.scrap >= cost * 2
		if want:
			sim.depot_buy(i)
	hp = sim.hull / sim.max_hull
	var boss_next: bool = p.boss_next
	var go_home := false
	match persona:
		"safe":
			go_home = hp < 0.5 or sim.loop >= 7 or boss_next
		"stall":
			go_home = hp < 0.4 or (boss_next and hp < 0.9)
		"economy":
			go_home = hp < 0.4 or (boss_next and not fight_boss)
		"aggressive", "farmer", "turtle":
			go_home = hp < 0.25 or (boss_next and (hp < 0.6 or not fight_boss))
		"greedy":
			go_home = hp < 0.12
		"random":
			go_home = sim.loop >= 3 and rng.randf() < 0.25
		"sprint":
			go_home = sim.loop >= 2
	if go_home:
		sim.depot_return()
	else:
		sim.depot_continue()
