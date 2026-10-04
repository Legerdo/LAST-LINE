extends Node2D
## One run on the line: owns the Sim, steps it at a fixed 60 Hz, routes input, events,
## modal panels and the end-of-run sequences.

var sim: Sim
var view: WorldView
var hud: Hud
var juice: Juice
var speed := 1
var paused := false
var menu_open := false
var acc := 0.0
var stop_time := 0.0
var drag_id := ""
var ending := ""
var end_t := 0.0
var end_done := false
var result := {}
var combat_level := 0.0
var tutorial: Tutorial
# --autoplay[=persona]: a scripted player drives the run (visual QA / attract mode)
var auto: AIPlayer = null
var auto_wait := 0.0


func _ready() -> void:
	var mods := Game.sim_mods()
	var seed_value := Game.new_seed()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_value = int(a.substr(7))
		elif a.begins_with("--autoplay"):
			var persona := a.substr(11) if a.length() > 11 else "economy"
			auto = AIPlayer.new(persona, 7)
		elif a.begins_with("--speed="):
			speed = int(a.substr(8))
		elif a.begins_with("--meta="):
			var preset := a.substr(7)
			if preset == "full":
				mods = {"hull": 60, "cars": ["flame", "mortar", "armor", "repair", "tesla"],
					"cards": ["greenhouse", "armory", "power", "radio"], "survivors": 4, "supplies": 10,
					"keep": 0.30, "max_cars": 2, "depot_options": 1, "extra_gun": true, "hand": 2, "locked": []}
		elif a.begins_with("--horde="):
			pass
	sim = Sim.new(seed_value, mods)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--horde="):
			sim.horde = float(a.substr(8))
	view = WorldView.new()
	add_child(view)
	view.setup(sim, self)
	hud = Hud.new()
	add_child(hud)
	hud.setup(self, sim)
	juice = Juice.new(self, view, hud, sim)
	tutorial = Tutorial.new()
	add_child(tutorial)
	var soak := OS.get_cmdline_user_args().has("--probe=soak")
	if auto and not soak:
		tutorial.enabled = false
	else:
		if soak:
			# QA: the AI plays while every contextual tip fires for real (opening skipped)
			Game.mark_seen("tutorial_done")
		tutorial.setup(self, sim, view, hud)
	Audio.music("run")
	Audio.sfx("horn", -2.0)
	Audio.voice("depart", -2.0)
	if not tutorial.scripted:
		var lines := ["마지막 노선, 다시 운행 개시. 무리하지 말고 돌아와.", "기지 불은 켜 둘게. 욕심은 적당히.",
			"오늘도 선로가 우리를 기다린다. 출발.", "검은 열차 목격담이 늘었어. 조심해."]
		hud.radio(lines[randi() % lines.size()], "dispatcher", 4.0)


func first_time(key: String, text: String) -> void:
	if Game.seen("tip_" + key):
		return
	Game.mark_seen("tip_" + key)
	hud.radio(text, "dispatcher", 5.0)


# ================================================================ time
func set_speed(s: int) -> void:
	speed = clampi(s, 1, 3)
	paused = false


func toggle_pause() -> void:
	paused = not paused


func hitstop(t: float) -> void:
	stop_time = maxf(stop_time, t)


func _process(delta: float) -> void:
	juice.tick(delta)
	_probe(delta)
	var mp := view.get_local_mouse_position()
	_update_hover(mp)
	if ending != "":
		_update_ending(delta)
	if auto and ending == "":
		_autoplay(delta)
	var can_step := ending == "" and not paused and not menu_open and sim.pending.is_empty() and sim.state == "running" and not tutorial.hold
	if stop_time > 0.0:
		stop_time -= delta
		can_step = false
	if can_step:
		acc += minf(delta, 0.1) * speed
		var steps := 0
		while acc >= Sim.DT and steps < 8:
			view.snapshot()
			sim.step(Sim.DT)
			acc -= Sim.DT
			steps += 1
			_drain_events()
			if not sim.pending.is_empty() or sim.state != "running":
				acc = 0.0
				break
	else:
		_drain_events()
	view.sync_all(acc / Sim.DT if can_step else 1.0)
	_check_pending()
	_music_mix(delta)


func _autoplay(delta: float) -> void:
	if not sim.pending.is_empty():
		auto_wait += delta
		if auto_wait < 1.6:
			return
		var kind: String = sim.pending.kind
		auto.act(sim, delta)
		auto_wait = 0.0
		_drain_events()
		if kind == "depot" and sim.state == "returned":
			ending = "returned"
			end_t = 0.0
		return
	auto_wait = 0.0
	var before := sim.hand.size()
	auto.act(sim, delta * speed)
	if sim.hand.size() != before:
		_drain_events()


## QA: --probe=results|depot|event opens that panel after a moment and dumps control rects
var _probe_t := -1.0


func _probe(delta: float) -> void:
	if _probe_t < 0.0:
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--probe="):
				_probe_t = 0.0
		if _probe_t < 0.0:
			_probe_t = -2.0
		return
	if _probe_t == -2.0:
		return
	_probe_t += delta
	if _probe_t > 1.0 and _probe_t - delta <= 1.0:
		for a in OS.get_cmdline_user_args():
			if a == "--probe=results":
				Panels.results(hud, {"state": "dead", "loops": 2, "time": 67.0, "kills": 68, "scrap": 115, "survivors": 0})
			elif a == "--probe=event":
				sim.pending = {"kind": "event", "id": "toll"}
			elif a == "--probe=reward":
				sim.pending = {"kind": "reward", "source": "transfer", "options": ["car:gun", "mod:scope", "relic:bell"]}
			elif a == "--probe=drag":
				_probe_drag()
			elif a == "--probe=tutorial":
				_probe_tutorial()
			elif a == "--probe=tips":
				_probe_tips()
			elif a == "--probe=soak":
				_probe_soak()
	if _probe_t > 1.6 and _probe_t - delta <= 1.6 and hud.modal:
		_dump(hud.modal, 0)


## QA: play the scripted tutorial like a new player and save a screenshot per step
func _probe_tutorial() -> void:
	var dir := ProjectSettings.globalize_path("res://art_src/shots/tutorial")
	DirAccess.make_dir_recursive_absolute(dir)
	var shot := func(name: String) -> void:
		await get_tree().process_frame
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(dir + "/%s.png" % name)
		print("PROBE shot ", name, " step=", tutorial.idx, " hold=", tutorial.hold, " facs=", sim.facs.size())
	var wait := func(sec: float) -> void:
		await get_tree().create_timer(sec).timeout
	await shot.call("s0_train")
	for i in 3:
		tutorial.overlay.next_pressed.emit()
		await wait.call(0.4)
		await shot.call("s%d" % (i + 1))
	tutorial.overlay.next_pressed.emit()
	await wait.call(0.9)
	await shot.call("s4_place_station_hint")
	# drag the station card, pause mid-drag for a screenshot, then drop on the lesson lot
	await _drag_card("station", tutorial.station_lot, func(): await shot.call("s4_dragging"))
	await wait.call(0.6)
	await shot.call("s5_market")
	# wrong drop first: market on a lot that is not next to the station
	var far := -1
	for l: Dictionary in sim.map.lots:
		if not sim.facs.has(l.id) and not tutorial.market_lots.has(l.id):
			far = l.id
			break
	await _drag_card("market", far, Callable())
	await wait.call(0.2)
	await shot.call("s5_wrong_drop")
	# a right-click discard of a lesson card must be refused
	var hand_n := sim.hand.size()
	for c in hud.cards:
		if (c as CardView).card_id == "market":
			hud._on_card_right(c)
	print("PROBE discard blocked: ", sim.hand.size() == hand_n)
	await _drag_card("market", tutorial.market_lots[0], func(): await shot.call("s5_hover_preview"))
	await wait.call(0.6)
	await shot.call("s6_evolution_arrow")
	for i in 2:
		tutorial.overlay.next_pressed.emit()
		await wait.call(0.4)
		await shot.call("s%d" % (7 + i))
	tutorial.overlay.next_pressed.emit()
	print("PROBE scripted done: scripted=", tutorial.scripted, " hold=", tutorial.hold, " hand=", sim.hand)
	speed = 3
	# run to the first depot stop, photographing each contextual tip once
	var guard := 0
	var seen_tips := {}
	while sim.pending.get("kind", "") != "depot" and guard < 900:
		await wait.call(0.1)
		guard += 1
		var key := String(tutorial.current.get("key", ""))
		if key != "" and tutorial.overlay.active and not seen_tips.has(key):
			seen_tips[key] = true
			await wait.call(0.3)
			await shot.call("tip_" + key)
			if tutorial.overlay.blocking:
				tutorial.overlay.next_pressed.emit()
	print("PROBE tips on the way: ", seen_tips.keys())
	await wait.call(0.5)
	await shot.call("d0_pick")
	sim.depot_pick(0)
	Panels.depot(hud)
	await wait.call(0.5)
	await shot.call("d1_shop")
	tutorial.overlay.next_pressed.emit()
	await wait.call(0.4)
	await shot.call("d2_status")
	tutorial.overlay.next_pressed.emit()
	await wait.call(0.4)
	await shot.call("d3_buttons")
	depot_continue()
	await wait.call(0.5)
	print("PROBE depot done: depot_step=", tutorial.depot_step, " hold=", tutorial.hold, " loop=", sim.loop)
	get_tree().quit()


## QA: --autoplay --probe=soak lets the AI play with the tutorial on; blocking tips are
## dismissed after a beat and every tip that fired is listed
func _probe_soak() -> void:
	var shown := {}
	var t0 := Time.get_ticks_msec()
	speed = 3
	while ending == "" and sim.state == "running" and Time.get_ticks_msec() - t0 < 150000:
		await get_tree().create_timer(0.3).timeout
		var key := String(tutorial.current.get("key", ""))
		if key != "":
			shown[key] = true
		if tutorial.depot_step >= 0:
			shown["depot_walk_%d" % tutorial.depot_step] = true
		if tutorial.overlay.active and tutorial.overlay.visible and tutorial.overlay.blocking and tutorial.overlay.t > 0.5:
			tutorial.overlay.next_pressed.emit()
	print("PROBE soak: loop=", sim.loop, " state=", sim.state, " horde=", int(sim.horde), " queue=", tutorial.queue.size(),
		" hold=", tutorial.hold, " tips=", shown.keys())
	get_tree().quit()


## QA: show every contextual tip and every help page once, one screenshot each
func _probe_tips() -> void:
	var dir := ProjectSettings.globalize_path("res://art_src/shots/tips")
	DirAccess.make_dir_recursive_absolute(dir)
	var shot := func(name: String) -> void:
		await get_tree().process_frame
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(dir + "/%s.png" % name)
		print("PROBE shot ", name)
	var wait := func(sec: float) -> void:
		await get_tree().create_timer(sec).timeout
	if tutorial.scripted:
		tutorial._end_scripted()
	# drive the tips by hand: stop the automatic triggers
	tutorial.enabled = false
	tutorial.queue.clear()
	sim.hand = ["station", "car:gun", "checkpoint", "market", "infection"]
	hud.rebuild_hand()
	speed = 2
	await wait.call(2.5)
	paused = true
	var any_lot := -1
	var hostile_lot := -1
	for lot_id in sim.facs.keys():
		any_lot = lot_id
		if Defs.FACILITIES[sim.facs[lot_id].type].cat == "hostile":
			hostile_lot = lot_id
	var enemy_id := -1
	for e: Sim.Enemy in sim.enemies:
		if not e.dead:
			enemy_id = e.id
	for key in Tutorial.TIP_KEYS:
		var a := {"lot": any_lot}
		match key:
			"evolve":
				a = {"lot": any_lot, "from": "station", "to": "transfer"}
			"grow", "countdown":
				a = {"lot": hostile_lot, "to": "hive"}
			"elite":
				a = {"id": enemy_id}
			"train_card":
				a = {"card": "car:gun"}
			"boss":
				paused = false
				sim._spawn_boss()
				_drain_events()
				await wait.call(1.5)
				paused = true
		var d := tutorial.tip_def(key, a)
		if tutorial.rects(String(d.focus)).is_empty():
			print("PROBE tip ", key, ": no target on screen")
		d["key"] = key
		tutorial._show_tip(d)
		await wait.call(0.4)
		await shot.call("tip_" + key)
		var part := 1
		while not (tutorial.current.get("then", []) as Array).is_empty():
			tutorial.overlay.next_pressed.emit()
			await wait.call(0.4)
			await shot.call("tip_%s_%d" % [key, part])
			part += 1
		tutorial.overlay.next_pressed.emit()
		await wait.call(0.2)
	print("PROBE tips done: overlay active=", tutorial.overlay.active, " hold=", tutorial.hold)
	for p in Panels.HELP.size():
		open_help(p)
		await wait.call(0.3)
		await shot.call("help_%d" % p)
	close_help()
	await wait.call(0.2)
	get_tree().quit()


func _drag_card(card: String, lot_id: int, mid: Callable) -> void:
	var cv: CardView = null
	for c in hud.cards:
		if (c as CardView).card_id == card:
			cv = c
			break
	if cv == null or lot_id < 0:
		print("PROBE drag: missing card/lot ", card, " ", lot_id)
		return
	var start := cv.get_global_rect().get_center()
	var r: Rect2i = sim.map.lots[lot_id].rect
	var end := Vector2(r.position.x * 16 + 16, r.position.y * 16 + 16) + view.base_pos
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = start
	get_viewport().push_input(press, true)
	await get_tree().process_frame
	for k in 6:
		var mv := InputEventMouseMotion.new()
		mv.position = start.lerp(end, (k + 1) / 6.0)
		get_viewport().push_input(mv, true)
		get_viewport().warp_mouse(mv.position)
		await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	if mid.is_valid():
		# hover right over the lot so the placement preview shows in the shot
		for k in 3:
			var hv := InputEventMouseMotion.new()
			hv.position = end
			get_viewport().push_input(hv, true)
			await get_tree().process_frame
		await mid.call()
	# the real OS cursor may have moved meanwhile: re-assert the probe position right before release
	var last := InputEventMouseMotion.new()
	last.position = end
	get_viewport().push_input(last, true)
	get_viewport().warp_mouse(end)
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	rel.position = end
	get_viewport().push_input(rel, true)
	await get_tree().process_frame


## simulated player input: press a hand card, drag it over an empty lot, release
func _probe_drag() -> void:
	var before := sim.facs.size()
	var hand_before := sim.hand.size()
	var cv: CardView = null
	for c in hud.cards:
		if sim.card_kind((c as CardView).card_id) == "facility":
			cv = c
			break
	if cv == null:
		print("PROBE drag: no facility card")
		return
	var start := cv.get_global_rect().get_center()
	var target_lot := -1
	for l: Dictionary in sim.map.lots:
		if not sim.facs.has(l.id):
			target_lot = l.id
			break
	var r: Rect2i = sim.map.lots[target_lot].rect
	var end := Vector2(r.position.x * 16 + 16, r.position.y * 16 + 16) + view.base_pos
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = start
	press.global_position = start
	get_viewport().push_input(press, true)
	await get_tree().process_frame
	var mv := InputEventMouseMotion.new()
	mv.position = end
	mv.global_position = end
	get_viewport().push_input(mv, true)
	get_viewport().warp_mouse(end)
	await get_tree().process_frame
	await get_tree().process_frame
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	rel.position = end
	rel.global_position = end
	get_viewport().push_input(rel, true)
	await get_tree().process_frame
	print("PROBE drag: card=%s lot=%d facs %d -> %d, hand %d -> %d, drag_id='%s'" % [cv.card_id if is_instance_valid(cv) else "?", target_lot, before, sim.facs.size(), hand_before, sim.hand.size(), drag_id])


func _dump(n: Node, depth: int) -> void:
	if n is Control:
		var c: Control = n
		print("%s%s %s %s" % ["  ".repeat(depth), c.get_class(), c.name, str(c.get_global_rect())])
	for ch in n.get_children():
		_dump(ch, depth + 1)


func _drain_events() -> void:
	if sim.events.is_empty():
		return
	var evs := sim.events.duplicate()
	sim.events.clear()
	for ev in evs:
		juice.handle(ev)
		if tutorial and tutorial.enabled:
			tutorial.on_event(ev)


func _music_mix(delta: float) -> void:
	var near := 0
	for e: Sim.Enemy in sim.enemies:
		if not e.dead and e.state == Sim.ENGAGE:
			near += 1
	var target := clampf(near / 6.0, 0.0, 1.0)
	combat_level = move_toward(combat_level, target, delta * (0.8 if target > combat_level else 0.25))
	var tension := clampf(sim.horde / 100.0, 0.0, 1.0)
	Audio.music_mix(0.2 + tension * 0.8, combat_level)


# ================================================================ help reference
func open_help(page := 0) -> void:
	if hud.modal != null and hud.modal_kind not in ["pause", "help"]:
		return
	if drag_id != "":
		cancel_drag()
	menu_open = true
	Panels.help(hud, page)


func close_help() -> void:
	menu_open = false
	Panels.close(hud)


# ================================================================ pending panels
func _check_pending() -> void:
	if ending != "":
		return
	var kind: String = sim.pending.get("kind", "")
	if kind == "" and hud.modal_kind in ["depot", "event", "reward", "blackmarket"]:
		Panels.close(hud)
		return
	if kind != "" and hud.modal_kind != kind:
		if drag_id != "":
			cancel_drag()
		match kind:
			"depot":
				Panels.depot(hud)
			"event":
				Panels.event(hud)
			"reward":
				Panels.reward(hud)
			"blackmarket":
				Panels.blackmarket(hud)


func after_reward(_id: String) -> void:
	_drain_events()


func depot_continue() -> void:
	if sim.pending.get("kind", "") != "depot":
		return
	var boss_next: bool = sim.pending.boss_next
	Panels.close(hud)
	tutorial.on_depot_decided()
	sim.depot_continue()
	_drain_events()
	if not boss_next:
		hud.show_banner("%d바퀴" % sim.loop, "군세 %d / 100" % int(sim.horde), UI.COL.white, 1.0)


func depot_return() -> void:
	if sim.pending.get("kind", "") != "depot":
		return
	Panels.close(hud)
	tutorial.on_depot_decided()
	sim.depot_return()
	_drain_events()
	ending = "returned"
	end_t = 0.0
	Audio.sfx("return", -2.0)
	Audio.voice("returned", -2.0)


func event_choose(i: int) -> void:
	sim.event_choose(i)
	Panels.close(hud)
	_drain_events()


# ================================================================ input
func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var kind: String = sim.pending.get("kind", "")
		if hud.modal_kind == "help":
			match ev.keycode:
				KEY_ESCAPE, KEY_H, KEY_F1:
					close_help()
				KEY_LEFT:
					Panels.help(hud, int(hud.targets.get("help_page", 0)) - 1)
				KEY_RIGHT:
					Panels.help(hud, int(hud.targets.get("help_page", 0)) + 1)
			return
		if tutorial.hold and tutorial.overlay and tutorial.overlay.blocking:
			# a blocking tutorial step owns the keyboard: Enter/Space = next
			if ev.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] and tutorial.overlay.next_btn.visible:
				tutorial.overlay.next_pressed.emit()
			return
		match ev.keycode:
			KEY_H, KEY_F1:
				if kind == "" and ending == "":
					open_help()
			KEY_SPACE:
				if kind == "" and ending == "":
					toggle_pause()
			KEY_1, KEY_2, KEY_3:
				var n: int = ev.keycode - KEY_1
				if kind == "event":
					if sim.event_can(n):
						event_choose(n)
				elif kind == "depot":
					if sim.depot_pick(n):
						Audio.sfx("pick", -2.0)
						Panels.depot(hud)
				elif kind == "":
					set_speed(n + 1)
			KEY_ENTER, KEY_KP_ENTER:
				if kind == "depot":
					depot_continue()
			KEY_R:
				if kind == "depot":
					depot_return()
			KEY_ESCAPE:
				if drag_id != "":
					cancel_drag()
				elif ending == "":
					toggle_menu()
	if ev is InputEventMouseButton and not ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and drag_id != "":
		_drop((view.make_input_local(ev) as InputEventMouseButton).position)
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT and drag_id != "":
		cancel_drag()


func _input(ev: InputEvent) -> void:
	# releases over HUD controls never reach _unhandled_input; catch them here
	if drag_id != "" and ev is InputEventMouseButton and not ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		# drop where the button was released (not wherever the cursor is a frame later)
		_drop((view.make_input_local(ev) as InputEventMouseButton).position)
		get_viewport().set_input_as_handled()


func toggle_menu() -> void:
	if hud.modal_kind in ["depot", "event", "reward", "blackmarket", "results"]:
		return
	if hud.modal_kind == "help":
		close_help()
		return
	menu_open = not menu_open
	if menu_open:
		Panels.pause(hud)
	else:
		Panels.close(hud)


func abandon() -> void:
	menu_open = false
	Panels.close(hud)
	sim.hull = 0.0
	sim.state = "dead"
	sim.stats.death_cause = "abandon"
	death_sequence()


func begin_drag(id: String) -> void:
	drag_id = id
	view.drag_card = id
	var kind := sim.card_kind(id)
	view.valid_lots.clear()
	if not tutorial.allow.is_empty():
		# during a lesson only the taught lots light up
		if id == String(tutorial.allow.card):
			for lot_id in tutorial.lesson_lots():
				view.valid_lots.append(lot_id)
		return
	if kind == "facility":
		for l: Dictionary in sim.map.lots:
			if not sim.facs.has(l.id):
				view.valid_lots.append(l.id)
	elif kind == "action":
		for lot_id in sim.facs.keys():
			view.valid_lots.append(lot_id)


func cancel_drag() -> void:
	drag_id = ""
	view.drag_card = ""
	view.hover_lot = -1
	hud.end_drag(false)


func _drop(mp: Vector2) -> void:
	var idx := hud.drag_index
	var id := drag_id
	var placed := false
	var kind := sim.card_kind(id)
	if idx >= 0 and idx < sim.hand.size() and sim.hand[idx] == id:
		if kind == "facility" or kind == "action":
			var lot_id := view.lot_at(mp)
			if lot_id >= 0 and not tutorial.can_drop(id, lot_id):
				tutorial.drop_rejected()
			elif lot_id >= 0 and sim.can_place(idx, lot_id):
				placed = sim.place_card(idx, lot_id)
		else:
			var ci := view.car_at(mp, 16.0)
			if ci >= 0 and not tutorial.can_drop(id, -1):
				tutorial.drop_rejected()
				ci = -1
			if ci >= 0:
				if kind == "car" and sim.cars_behind() >= sim.max_cars_total():
					if ci >= 1:
						placed = sim.replace_car(idx, ci)
					else:
						hud.toast("기관차는 교체할 수 없다", UI.COL.red)
				else:
					placed = sim.use_train_card(idx)
	drag_id = ""
	view.drag_card = ""
	view.hover_lot = -1
	view.hover_car = -1
	hud.end_drag(placed)
	_drain_events()


func _update_hover(mp: Vector2) -> void:
	view.hover_fac = -1
	view.hover_car = -1
	if drag_id != "":
		var kind := sim.card_kind(drag_id)
		if kind == "facility" or kind == "action":
			var lot_id := view.lot_at(mp)
			view.hover_lot = lot_id
			if lot_id >= 0 and view.valid_lots.has(lot_id):
				var hints := sim.place_hints(drag_id, lot_id)
				var lines: Array = []
				for h in hints:
					var c: String = {"good": "#8cd660", "bad": "#ff6a6a", "info": "#c8c4d8"}.get(h[1], "#ffffff")
					lines.append("[color=%s]%s[/color]" % [c, h[0]])
				if lines.is_empty():
					lines.append("[color=#8a86a0]인접 효과 없음[/color]")
				hud.show_tooltip("\n".join(lines), get_viewport().get_mouse_position() + Vector2(14, -30))
			else:
				hud.hide_tooltip()
		else:
			view.hover_car = view.car_at(mp, 16.0)
			if view.hover_car >= 0:
				var s := "여기에 놓기"
				if kind == "car" and sim.cars_behind() >= sim.max_cars_total():
					s = "이 차량과 교체 (+고철 10)" if view.hover_car >= 1 else "기관차는 교체 불가"
				hud.show_tooltip(s, get_viewport().get_mouse_position() + Vector2(14, -20))
			else:
				hud.hide_tooltip()
		return
	if hud.modal != null or hud.hover_card != null:
		return
	if tutorial.overlay and tutorial.overlay.active:
		# while the dispatcher is talking, world hover tips would cover her box
		hud.hide_tooltip()
		return
	var screen := get_viewport().get_mouse_position()
	if screen.y < Hud.TOP_H or screen.y > Hud.BOT_Y:
		return
	var ci := view.car_at(mp, 10.0)
	if ci >= 0:
		view.hover_car = ci
		var c: Sim.Car = sim.cars[ci]
		if c.type == "loco":
			hud.show_tooltip("[color=#ffcc66]기관차[/color]\n선로 앞을 막는 적을 들이받는다.\n들이받기 힘 %d" % sim.ram_power(), screen)
		else:
			hud.show_tooltip(hud.car_tip(c.type), screen)
		return
	var eid := view.enemy_at(mp)
	if eid >= 0:
		for e: Sim.Enemy in sim.enemies:
			if e.id == eid:
				var d: Dictionary = Defs.ENEMIES[e.type]
				var extra := ""
				match e.type:
					"bloater":
						extra = "\n가까이서 터진다. 들이받으면 즉시 폭발."
					"stalker":
						extra = "\n가까이 오기 전엔 보이지 않는다."
					"barricade":
						extra = "\n선로를 막는다. 부수기 전엔 못 지나간다."
					"horror":
						extra = "\n선로 밑에서 솟아 열차를 막아선다."
					"warrig":
						extra = "\n뒤에서 쫓아와 들이받는다."
					"brood":
						extra = "\n러너를 계속 낳는다."
				hud.show_tooltip("[color=#ff9a6a]%s[/color]  %d/%d%s" % [d.name, int(ceil(e.hp)), int(e.max_hp), extra], screen)
				return
	var lot_id := view.lot_at(mp)
	if lot_id >= 0 and sim.facs.has(lot_id):
		view.hover_fac = lot_id
		var f: Sim.Fac = sim.facs[lot_id]
		var d: Dictionary = Defs.FACILITIES[f.type]
		var col: Color = UI.CAT_COL.get(d.cat, Color.WHITE)
		var lines: Array = ["[color=#%s]%s[/color]  [color=#8a86a0]%d바퀴째[/color]" % [col.to_html(false), d.name, f.age + 1], String(d.desc)]
		for h in sim.fac_status(lot_id):
			var c: String = {"good": "#8cd660", "bad": "#ff6a6a", "info": "#c8c4d8"}.get(h[1], "#ffffff")
			lines.append("[color=%s]%s[/color]" % [c, h[0]])
		hud.show_tooltip("\n".join(lines), screen)
		return
	var r: Rect2i = sim.map.depot_rect
	if Rect2(r.position * 16, r.size * 16).has_point(mp):
		hud.show_tooltip("[color=#ffcc66]차량기지[/color]\n한 바퀴마다 정차한다.\n보급을 받고, 계속 달릴지 귀환할지 정한다.", screen)
		return
	if lot_id >= 0:
		hud.show_tooltip("[color=#8a86a0]빈 부지[/color]\n카드를 끌어다 시설을 세운다.", screen)
		return
	hud.hide_tooltip()


# ================================================================ endings
func death_sequence() -> void:
	if ending != "":
		return
	ending = "dead"
	end_t = 0.0
	Panels.close(hud)
	if drag_id != "":
		cancel_drag()
	view.screen_flash(Color(1, 0.3, 0.2), 1.0)
	view.shake(1.0)
	hitstop(0.35)
	Audio.sfx("big_boom", 2.0)
	Audio.music("end")
	Audio.voice("destroyed", 0.0)
	hud.show_banner("열차 파괴", "마지막 노선이 끊겼다", UI.COL.red, 2.2)


func boss_death_sequence() -> void:
	if ending != "":
		return
	ending = "victory"
	end_t = 0.0
	Panels.close(hud)
	view.screen_flash(Color(1, 1, 1), 1.0)
	view.shake(1.0)
	hitstop(0.4)
	Audio.sfx("big_boom", 3.0)
	Audio.music("end")
	Audio.voice("victory", 0.0)
	hud.show_banner("검은 열차 격파", "노선이 조용해졌다", UI.COL.yellow, 3.0)


var _boom_t := 0.0


func _update_ending(delta: float) -> void:
	end_t += delta
	_boom_t -= delta
	match ending:
		"dead":
			if end_t < 1.6 and _boom_t <= 0.0:
				_boom_t = 0.16
				var i := randi() % maxi(1, sim.cars.size())
				var p := view.car_pos(i) + Vector2(randf_range(-8, 8), randf_range(-4, 4))
				view.fxg.burst(p, 26, Color8(255, 250, 200), Color8(230, 60, 20, 0), 100.0, 0.5, 2.0, -20.0, 2.0)
				view.fx.burst(p, 14, Color8(60, 54, 64), Color8(20, 18, 26, 0), 40.0, 1.8, 3.0, -16.0, 1.0, TAU, 0.0, 6.0)
				view.flash_light(p, 90.0, Color(1.0, 0.55, 0.25), 0.5)
				view.shake(0.4)
				Audio.sfx("boom", -1.0)
		"victory":
			if end_t < 2.2 and _boom_t <= 0.0 and sim.boss_parts.size() > 0:
				_boom_t = 0.12
				var bp: Sim.BossPart = sim.boss_parts[randi() % sim.boss_parts.size()]
				var p := bp.pos + Vector2(randf_range(-12, 12), randf_range(-5, 5))
				view.fxg.burst(p, 26, Color8(255, 250, 200), Color8(230, 60, 20, 0), 110.0, 0.5, 2.0, -20.0, 2.0)
				view.fx.burst(p, 10, Color8(60, 54, 64), Color8(20, 18, 26, 0), 40.0, 1.8, 3.0, -16.0, 1.0, TAU, 0.0, 6.0)
				view.flash_light(p, 100.0, Color(1.0, 0.6, 0.3), 0.5)
				view.shake(0.35)
				Audio.sfx("boom", 0.0)
	var wait: float = {"dead": 2.6, "victory": 3.4, "returned": 1.2}.get(ending, 2.0)
	if end_t >= wait and not end_done:
		end_done = true
		result = sim.final_result()
		Game.finish_run(result)
		Panels.results(hud, Game.last_result)
	if auto and end_done and end_t >= wait + 3.0:
		auto = null
		Game.goto("hub")
