extends SceneTree
## Headless balance harness.
## godot --headless --path . --script res://sim/runner.gd -- --persona=safe,greedy --runs=30 --meta=none --out=sim/out/x.jsonl

const META := {
	"none": {},
	"mid": {"hull": 40, "cars": ["flame", "mortar", "armor"], "cards": ["greenhouse", "armory"],
		"survivors": 2, "supplies": 5, "keep": 0.15, "max_cars": 1},
	"full": {"hull": 60, "cars": ["flame", "mortar", "armor", "repair", "tesla"],
		"cards": ["greenhouse", "armory", "power", "radio"], "survivors": 4, "supplies": 10,
		"keep": 0.30, "max_cars": 2, "depot_options": 1, "extra_gun": true, "hand": 2},
}


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if args.has("test"):
		_tests()
		quit()
		return
	var personas := String(args.get("persona", "safe,aggressive,economy,greedy,random")).split(",")
	var runs := int(args.get("runs", "10"))
	var meta_name := String(args.get("meta", "none"))
	var out_path := String(args.get("out", ""))
	var seed0 := int(args.get("seed", "1000"))
	var max_time := float(args.get("maxtime", "1800"))
	var fight := String(args.get("fight", "1")) == "1"
	var mods: Dictionary = META.get(meta_name, {}).duplicate(true)
	mods["locked"] = ["card:power", "card:radio", "car:tesla"]
	var f: FileAccess = null
	if out_path != "":
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		f = FileAccess.open(out_path, FileAccess.WRITE)
	var t0 := Time.get_ticks_msec()
	for p in personas:
		for r in runs:
			var seed_value := seed0 + r
			var res := run_one(p, seed_value, mods, max_time, fight)
			res["persona"] = p
			res["seed"] = seed_value
			res["meta"] = meta_name
			var line := JSON.stringify(res)
			if f:
				f.store_line(line)
			else:
				print(line)
	if f:
		f.close()
	print("done in %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit()


func run_one(persona: String, seed_value: int, mods: Dictionary, max_time: float, fight: bool) -> Dictionary:
	var sim := Sim.new(seed_value, mods)
	var ai := AIPlayer.new(persona, seed_value)
	ai.fight_boss = fight
	var guard := 0
	var trace := OS.get_cmdline_user_args().has("--trace=1")
	var last_loop := 0
	var tick_t := 0.0
	var dmg_dealt := {}
	while sim.state == "running" and sim.time < max_time:
		ai.act(sim, Sim.DT)
		sim.step(Sim.DT)
		if trace:
			for ev in sim.events:
				if ev.t == "hit" or ev.t == "bhit":
					var k: String = ev.t + ":" + String(ev.get("src", "boss"))
					dmg_dealt[k] = float(dmg_dealt.get(k, 0.0)) + float(ev.dmg)
			if sim.loop != last_loop:
				last_loop = sim.loop
				print("L%d t=%.0f hull=%.0f/%.0f facs=%d enemies=%d horde=%.0f cars=%s surv=%d scrap=%d hand=%d" % [
					sim.loop, sim.time, sim.hull, sim.max_hull, sim.facs.size(), sim.enemies.size(), sim.horde,
					str(sim.cars.map(func(c): return c.type)), sim.survivors, sim.scrap, sim.hand.size()])
			if sim.boss_active:
				tick_t += Sim.DT
				if tick_t >= 5.0:
					tick_t = 0.0
					print("   boss t=%.0f state=%s hull=%.0f boss=%.2f parts=%s enemies=%d dealt=%s" % [
						sim.time, sim.boss_state, sim.hull, sim.boss_hp_ratio(),
						str(sim.boss_parts.map(func(b): return int(b.hp))), sim.enemies.size(), str(dmg_dealt)])
					dmg_dealt.clear()
		sim.events.clear()
		guard += 1
		if guard > 200000:
			break
	if trace:
		print("END state=%s loop=%d t=%.0f cause=%s" % [sim.state, sim.loop, sim.time, sim.stats.death_cause])
	var res := sim.final_result()
	var st: Dictionary = sim.stats
	var kills_total := 0
	for k in st.kills.values():
		kills_total += int(k)
	res["timeout"] = sim.state == "running"
	res["hull_end"] = snappedf(sim.hull / sim.max_hull, 0.01)
	res["max_hull"] = sim.max_hull
	res["cars"] = sim.cars.map(func(c): return c.type)
	res["relics"] = sim.relics
	res["mods"] = sim.modc
	res["survivors_end"] = sim.survivors
	res["supplies_end"] = sim.supplies
	res["horde"] = snappedf(sim.horde, 0.1)
	res["facs"] = sim.facs.size()
	res["fac_types"] = _count_types(sim)
	res["placed"] = st.placed
	res["evolved"] = st.evolved
	res["corrupted"] = st.corrupted
	res["dmg_by_loop"] = (st.dmg_by_loop as Array).map(func(x): return snappedf(x, 0.1))
	res["time_by_loop"] = (st.time_by_loop as Array).map(func(x): return snappedf(x, 0.1))
	res["scrap_earned"] = st.scrap_earned
	res["kills_by"] = st.kills
	res["boss_loop"] = st.boss_loop
	res["boss_result"] = st.boss_result
	res["boss_hp"] = snappedf(sim.boss_hp_ratio(), 0.01) if sim.boss_parts.size() > 0 else -1.0
	res["boss_time"] = snappedf(float(st.get("boss_time", 0.0)), 0.1)
	res["death_cause"] = st.death_cause
	res["starved"] = st.starved
	res["cards_drawn"] = st.cards_drawn
	res["discarded"] = st.discarded
	res["depot_picks"] = st.depot_picks
	res["hull_min"] = snappedf(st.hull_min, 0.01)
	res["events"] = st.events
	return res


## regression checks for progression blockers
func _tests() -> void:
	var ok := true
	# 1. an unarmed train facing a barricade and a tunnel horror must still get through
	for kind in ["barricade", "horror"]:
		var sim := Sim.new(99, {})
		sim.facs.clear()
		for c in sim.cars:
			c.w = {}
		var s := sim.map.wrap_s(sim.odo + 80.0)
		var e := sim._spawn(kind, sim.map.pos_at(s), -1)
		e.s_track = s
		e.emerge = 0.0
		var start := sim.odo
		var t := 0.0
		while t < 120.0 and sim.state == "running" and sim.pending.is_empty() and sim.odo < start + 200.0:
			sim.step(Sim.DT)
			sim.events.clear()
			t += Sim.DT
		var passed := sim.odo >= start + 200.0 or not sim.pending.is_empty()
		print("TEST unarmed vs %s: %s (t=%.1fs, hull %.0f/%.0f, state %s)" % [kind, "PASS" if passed else "FAIL", t, sim.hull, sim.max_hull, sim.state])
		ok = ok and (passed or sim.state == "dead")
	# 2. every loop ends at the depot with a decision (no endless running without choices)
	var sim2 := Sim.new(5, {})
	var ai := AIPlayer.new("safe", 5)
	var stops := 0
	var t2 := 0.0
	while t2 < 400.0 and sim2.state == "running":
		if sim2.pending.get("kind", "") == "depot":
			stops += 1
		ai.act(sim2, Sim.DT)
		sim2.step(Sim.DT)
		sim2.events.clear()
		t2 += Sim.DT
	print("TEST depot stops reached: %d (state %s, loop %d)" % [stops, sim2.state, sim2.loop])
	ok = ok and stops >= 1
	print("TESTS ", "PASS" if ok else "FAIL")


func _count_types(sim: Sim) -> Dictionary:
	var d := {}
	for f in sim.facs.values():
		d[f.type] = int(d.get(f.type, 0)) + 1
	return d
