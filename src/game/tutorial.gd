class_name Tutorial
extends Node
## Guided onboarding.
## 1. First run: a scripted opening that pauses the line and walks through the train, hull,
##    hostile sites, the hand, placing a station, adjacency (market -> transfer evolution),
##    noise / the horde gauge and the controls. Drops are restricted to the highlighted lots.
## 2. First depot stop: supply pick, shop, the return-vs-continue rule.
## 3. One-time contextual spotlights when a system first matters (train cards, elites,
##    evolutions, infection spread, raiders, rations, low hull, horde 70, the Black Train...).
## Everything is skippable; seen flags live in the profile.

const TIP_KEYS := ["card_drop", "train_card", "hand_full", "evolve", "grow", "countdown", "corrupt",
	"raiders", "elite", "relic", "starve", "unpaid", "lowhull", "horde70", "boss"]

var run: Node
var sim: Sim
var view: WorldView
var hud: Hud
var layer: CanvasLayer
var overlay: FocusOverlay
var hold := false              # run.gd does not step the sim while true
var enabled := true
var scripted := false
var steps: Array = []
var idx := -1
var allow := {}                # {"card": id, "lots": [...]} during placement steps ([] = any empty lot)
var station_lot := -1
var market_lots: Array = []
var seed_infection := -1
var queue: Array = []          # contextual tips waiting for a quiet moment
var current := {}              # the tip / step being shown
var depot_step := -1
var watch_pick := false


func setup(controller: Node, s: Sim, v: WorldView, h: Hud) -> void:
	run = controller
	sim = s
	view = v
	hud = h
	layer = CanvasLayer.new()
	layer.layer = 15
	add_child(layer)
	overlay = FocusOverlay.new()
	layer.add_child(overlay)
	overlay.next_pressed.connect(_on_next)
	overlay.skip_pressed.connect(skip_all)
	enabled = not Game.seen("tips_off")
	if enabled and not Game.seen("tutorial_done"):
		_start_scripted()


# ================================================================ targets (screen space)
func _lot_rect(lot_id: int, tall := false) -> Rect2:
	if lot_id < 0 or lot_id >= sim.map.lots.size():
		return Rect2()
	var l: Dictionary = sim.map.lots[lot_id]
	var r: Rect2i = l.rect
	var p := Vector2(r.position * 16) + view.position
	if tall:
		return Rect2(p + Vector2(-6, -14), Vector2(44, 48))
	return Rect2(p, Vector2(32, 32))


func _card_rect(id: String) -> Rect2:
	for c in hud.cards:
		var cv: CardView = c
		if is_instance_valid(cv) and cv.card_id == id:
			return cv.get_global_rect()
	return Rect2()


func _first_train_card() -> String:
	for id in sim.hand:
		if String(id).begins_with("car:") or String(id).begins_with("mod:"):
			return id
	return ""


func target(key: String) -> Rect2:
	match key:
		"train":
			var p := view.car_pos(0) + view.position
			return Rect2(p - Vector2(15, 15), Vector2(30, 30))
		"train_all":
			var r := Rect2(view.car_pos(0) + view.position, Vector2.ZERO)
			for i in sim.cars.size():
				r = r.expand(view.car_pos(i) + view.position)
			return r.grow(12)
		"hull":
			return Rect2(54, 2, 136, 20)
		"scrap":
			return Rect2(192, 2, 54, 20)
		"supplies":
			return Rect2(246, 2, 52, 20)
		"survivors":
			return Rect2(296, 2, 62, 20)
		"horde":
			return Rect2(358, 2, 182, 20)
		"speed":
			return Rect2(538, 2, 100, 20)
		"hand":
			var r2 := Rect2()
			for c in hud.cards:
				var g: Rect2 = (c as CardView).get_global_rect()
				r2 = g if r2.size == Vector2.ZERO else r2.merge(g)
			return r2 if r2.size != Vector2.ZERO else Rect2(126, 296, 390, 64)
		"relics":
			return Rect2(2, 298, 120, 60)
		"boss_bar":
			if hud.boss_bar and hud.boss_bar.is_visible_in_tree():
				return hud.boss_bar.get_global_rect().grow(2)
			return Rect2()
		"boss_head":
			if sim.boss_parts.is_empty():
				return Rect2()
			var hp: Vector2 = (sim.boss_parts[0] as Sim.BossPart).pos + view.position
			return Rect2(hp - Vector2(22, 14), Vector2(44, 28))
		"station_lot":
			return _lot_rect(station_lot)
		"station_fac":
			return _lot_rect(station_lot, true)
		"market_lots":
			var r3 := Rect2()
			for lot_id in market_lots:
				r3 = _lot_rect(lot_id) if r3.size == Vector2.ZERO else r3.merge(_lot_rect(lot_id))
			return r3
		"seed_infection":
			return _lot_rect(seed_infection, true)
	if key.begins_with("card:"):
		return _card_rect(key.substr(5))
	if key.begins_with("fac:"):
		return _lot_rect(int(key.substr(4)), true)
	if key.begins_with("enemy:"):
		var id := int(key.substr(6))
		for e: Sim.Enemy in sim.enemies:
			if e.id == id and not e.dead:
				var p2 := e.pos + view.position
				return Rect2(p2 - Vector2(16, 28), Vector2(32, 34))
		return Rect2()
	if key.begins_with("ui:"):
		var c2: Control = hud.targets.get(key.substr(3), null)
		if c2 and is_instance_valid(c2) and c2.is_visible_in_tree():
			return c2.get_global_rect().grow(2)
		return Rect2()
	return Rect2()


## "a|b" keys spotlight several things at once (e.g. the card to drag AND where it goes)
func rects(key: String) -> Array:
	var out: Array = []
	if key == "":
		return out
	for part in key.split("|"):
		if part == "market_lots":
			for lot_id in market_lots:
				out.append(_lot_rect(lot_id))
		else:
			var r := target(part)
			if r.size != Vector2.ZERO:
				out.append(r)
	return out


func _tf(key: String) -> Callable:
	return func() -> Array: return rects(key)


func _center_of(key: String) -> Callable:
	return func() -> Vector2:
		var rs := rects(key)
		return (rs[0] as Rect2).get_center() if not rs.is_empty() else Vector2.ZERO


# ================================================================ scripted opening
func _start_scripted() -> void:
	scripted = true
	# a readable starting hand for the lesson (two lesson cards + two to experiment with)
	sim.hand = ["station", "market", "shelter", "infection"]
	for lot_id in sim.facs.keys():
		if sim.facs[lot_id].type == "infection":
			seed_infection = lot_id
	_pick_lesson_lots()
	steps = [
		{"text": "여기는 관제실. 이게 우리 [color=#ffcc66]마지막 열차[/color]야.\n열차는 노선을 스스로 돌면서 알아서 싸워.\n넌 [color=#60d4ec]카드[/color]로 선로 주변을 꾸며서 열차를 도와 줘.", "focus": "train"},
		{"text": "[color=#8cd660]선체[/color]가 0이 되면 운행이 끝나.\n역이나 병원을 지나가면 수리돼.", "focus": "hull"},
		{"text": "보라색 건물은 [color=#ff6a6a]감염구역[/color]이야. 좀비가 쏟아져 나와.\n대신 쓰러뜨리면 [color=#ffcc66]고철[/color]과 [color=#60d4ec]카드[/color]를 줘.", "focus": "seed_infection"},
		{"text": "아래가 [color=#60d4ec]손패[/color]야. 카드 한 장이 시설 하나.\n선로 옆 [color=#ffcc66]빈 부지[/color]에 놓으면 거기에 세워져.\n카드는 적을 쓰러뜨리면 계속 들어와.", "focus": "hand"},
		{"text": "[color=#60d4ec]역[/color] 카드를 빛나는 부지로 끌어다 놓아 봐.\n역은 지날 때마다 열차를 세우고 수리해 줘.", "focus": "card:station|station_lot",
			"wait": "place", "card": "station", "lots_key": "station", "hand": ["card:station", "station_lot"],
			"prompt": "카드를 누른 채로 빛나는 부지까지 끌어서 놓기"},
		{"text": "좋아! 이번엔 [color=#ffcc66]시장[/color]을 역 [color=#ffcc66]바로 옆[/color]에 놓아 봐.\n카드를 끌고 있으면 [color=#8cd660]인접 효과[/color] 미리보기가 떠.", "focus": "card:market|market_lots",
			"wait": "place", "card": "market", "lots_key": "market", "hand": ["card:market", "market_lots"],
			"prompt": "빛나는 부지 중 한 곳에 놓기"},
		{"text": "역 위에 [color=#b8f0ff]위쪽 화살표[/color]가 떴지? 조합이 맞았다는 뜻이야.\n다음 [color=#ffcc66]차량기지[/color] 정차 때 역이 [color=#b8f0ff]환승역[/color]으로 진화해.\n좋은 이웃 조합을 찾는 게 이 게임의 핵심이야.", "focus": "station_fac", "need": "transfer"},
		{"text": "카드 오른쪽 아래 숫자는 [color=#ff78aa]소음[/color]이야.\n매 바퀴 소음만큼 [color=#ff78aa]군세[/color]가 차오르고, 100이 되면\n[color=#e63e46]검은 열차[/color]가 깨어나. 많이 지을수록 위험해져.", "focus": "horde|hand"},
		{"text": "[color=#ffcc66]Space[/color] 일시정지 · [color=#ffcc66]1 2 3[/color] 속도 · [color=#60d4ec]?[/color] 도움말.\n궁금한 건 무엇이든 [color=#60d4ec]마우스를 올려[/color] 봐.\n멈춘 채로도 카드를 놓을 수 있어. 남은 카드는 자유롭게!", "focus": "speed", "next": "출발!"},
	]
	idx = -1
	_advance()


func _pick_lesson_lots() -> void:
	# the soonest empty lot ahead of the train that has an empty, infection-free neighbour
	var best := -1
	var best_d := INF
	for l: Dictionary in sim.map.lots:
		if sim.facs.has(l.id):
			continue
		var d := sim.map.ahead(sim.map.wrap_s(sim.odo), float(l.s))
		if d < 40.0:
			continue
		var free := 0
		var tainted := false
		for nb in l.neighbors:
			if sim.facs.has(nb):
				tainted = true
			else:
				free += 1
		if free == 0 or tainted:
			continue
		if d < best_d:
			best_d = d
			best = l.id
	station_lot = best
	_market_lots_from(best)


func _market_lots_from(lot_id: int) -> void:
	market_lots.clear()
	if lot_id >= 0:
		for nb in (sim.map.lots[lot_id] as Dictionary).neighbors:
			if not sim.facs.has(nb):
				market_lots.append(nb)


func _lesson_lots(key: String) -> Array:
	match key:
		"station":
			return [station_lot] if station_lot >= 0 else []
		"market":
			return market_lots.duplicate()
	return []


## lots that light up while dragging the lesson card (every empty lot if the map gave no lesson lot)
func lesson_lots() -> Array:
	var lots: Array = allow.get("lots", [])
	if not lots.is_empty():
		return lots
	var out: Array = []
	for l: Dictionary in sim.map.lots:
		if not sim.facs.has(l.id):
			out.append(l.id)
	return out


func _advance() -> void:
	idx += 1
	if idx >= steps.size():
		_end_scripted()
		return
	var s: Dictionary = steps[idx]
	if String(s.get("need", "")) == "transfer" and sim.evo_target(station_lot) != "transfer":
		_advance()
		return
	current = s
	var wait: String = s.get("wait", "next")
	hold = true
	allow = {}
	var opts := {"skip": true, "next": String(s.get("next", "다음")), "count": "%d/%d" % [idx + 1, steps.size()]}
	if wait == "place":
		allow = {"card": s.card, "lots": _lesson_lots(String(s.lots_key))}
		opts.next = ""
		opts.block = false
		opts.prompt = String(s.get("prompt", ""))
		opts.card = s.card
		var hk: Array = s.hand
		opts.hand = [_center_of(hk[0]), _center_of(hk[1])]
	overlay.show_step(String(s.text), _tf(String(s.focus)), opts)


func _end_scripted() -> void:
	scripted = false
	hold = false
	allow = {}
	current = {}
	overlay.hide_step()
	Game.mark_seen("tutorial_done")
	run.paused = false
	Audio.sfx("horn", -4.0)
	hud.show_banner("운행 개시", "위험해지면 차량기지에서 귀환할 수 있다", UI.COL.white, 1.6)


func skip_all() -> void:
	enabled = false
	scripted = false
	hold = false
	allow = {}
	current = {}
	queue.clear()
	depot_step = -1
	overlay.hide_step()
	Game.mark_seen("tutorial_done")
	Game.mark_seen("tips_off")
	run.paused = false
	hud.toast("튜토리얼을 건너뛰었다 · ? 버튼으로 도움말", UI.COL.dim)


func _on_next() -> void:
	if scripted:
		# placement steps only advance when the card actually lands
		if not current.is_empty() and String(current.get("wait", "next")) == "next":
			Audio.sfx("click", -6.0)
			_advance()
		return
	if depot_step >= 0:
		_depot_next()
		return
	# contextual tip closed (multi-part tips continue)
	var multi: Array = current.get("then", [])
	if not multi.is_empty():
		var nxt: Dictionary = multi.pop_front()
		nxt["then"] = multi
		_show_tip(nxt)
		return
	current = {}
	hold = false
	overlay.hide_step()


## run.gd asks before accepting a drop
func can_drop(card_id: String, lot_id: int) -> bool:
	if overlay == null or not enabled:
		return true
	if allow.is_empty():
		return not (hold and overlay.blocking)
	if card_id != String(allow.card):
		return false
	var lots: Array = allow.lots
	return lots.is_empty() or lots.has(lot_id)


func drop_rejected() -> void:
	if not allow.is_empty():
		overlay.nudge("%s 카드를 빛나는 부지에 놓아 줘" % UI.card_title(String(allow.card)))


## hud.gd asks before a right-click discard: the lesson must not lose its cards
func can_discard() -> bool:
	if overlay == null or not enabled or not scripted:
		return true
	overlay.nudge("튜토리얼 중에는 카드를 버릴 수 없어")
	return false


# ================================================================ first depot stop
func _depot_start() -> void:
	depot_step = 0
	hold = true
	watch_pick = true
	overlay.show_step("[color=#ffcc66]차량기지[/color]에 도착했어. 한 바퀴를 돌 때마다 여기 들러.\n먼저 [color=#ffcc66]보급[/color]을 하나 골라. 이번 운행에 바로 도움이 돼.", _tf("ui:depot_supply"),
		{"next": "", "block": false, "prompt": "보급 카드 하나를 클릭", "dock": "top", "count": "1/4"})


func _depot_next() -> void:
	depot_step += 1
	match depot_step:
		1:
			overlay.show_step("고철이 있으면 [color=#ffcc66]상점[/color]에서 개조 부품이나 수리를 살 수 있어.\n지금은 둘러보기만 해도 괜찮아.", _tf("ui:depot_shop"),
				{"dock": "top", "count": "2/4"})
		2:
			overlay.show_step("제일 중요한 규칙! [color=#60d4ec]귀환[/color]하면 모은 자원을 기지로 가져가.\n늦게 돌아갈수록 [color=#ffcc66]보너스[/color]가 커지지만, [color=#ff6a6a]파괴[/color]되면 대부분 잃어.", _tf("ui:depot_status"),
				{"dock": "top", "count": "3/4"})
		3:
			overlay.show_step("이번엔 한 바퀴 더 달려 보자.\n위험해지면 다음 정차 때 [color=#60d4ec]귀환[/color]하면 돼.", _tf("ui:depot_buttons"),
				{"next": "", "block": false, "prompt": "계속 운행 또는 귀환 선택", "dock": "bottom", "count": "4/4"})
		_:
			depot_step = -1
			hold = false
			overlay.hide_step()


func on_depot_decided() -> void:
	if depot_step >= 0:
		depot_step = -1
		hold = false
		overlay.hide_step()


# ================================================================ contextual tips
## text / spotlight / options of each one-time tip; `a` carries the triggering event fields
func tip_def(key: String, a := {}) -> Dictionary:
	var lot := "fac:%d" % int(a.get("lot", -1))
	match key:
		"card_drop":
			return {"text": "적이 [color=#60d4ec]카드[/color]를 떨어뜨렸어! 손패는 8장까지 모여.\n안 쓰는 카드는 [color=#ffcc66]우클릭[/color]으로 버리면 고철 +2.", "focus": "hand",
				"opts": {"block": false, "auto": 7.0}}
		"train_card":
			var tc := String(a.get("card", _first_train_card()))
			return {"text": "[color=#ffcc66]차량·개조 카드[/color]는 부지가 아니라 [color=#ffcc66]열차[/color]에 놓아.\n차량이 늘면 선체와 화력이 함께 늘어나.", "focus": "card:%s|train_all" % tc,
				"opts": {"block": false, "hand_keys": ["card:" + tc, "train_all"], "card": tc, "auto": 9.0}}
		"hand_full":
			return {"text": "손패가 가득 찼어! 이제 새 카드가 오면\n[color=#ff6a6a]가장 오래된 카드[/color]부터 버려져.", "focus": "hand",
				"opts": {"block": false, "auto": 6.0}}
		"evolve":
			var from: String = Defs.FACILITIES[String(a.get("from", "station"))].name
			var to: String = Defs.FACILITIES[String(a.get("to", "transfer"))].name
			return {"text": "[color=#b8f0ff]진화![/color] %s → [color=#b8f0ff]%s[/color]. 조합이 맞으면 더 강해져.\n시설에 마우스를 올리면 다음 변화가 미리 보여." % [from, to], "focus": lot,
				"opts": {"block": false, "auto": 8.0}}
		"grow":
			return {"text": "위험 시설이 [color=#ff6a6a]%s[/color](으)로 커졌어.\n이제 [color=#ff9a6a]엘리트[/color]가 나와. [color=#ff78aa]소각 작전[/color] 카드로 없앨 수도 있어." % Defs.FACILITIES[String(a.get("to", "hive"))].name,
				"focus": lot, "opts": {"block": false, "auto": 8.0}}
		"countdown":
			return {"text": "빨간 숫자는 위험 시설이 커지기까지 [color=#ff6a6a]남은 바퀴[/color]야.\n커지면 엘리트가 나오고 보상도 커져.", "focus": lot,
				"opts": {"block": false, "auto": 7.0}}
		"corrupt":
			return {"text": "감염이 옆 시설로 [color=#aa64e6]번졌어[/color]! 감염구역 옆은 위험해.\n[color=#8cd660]검문소[/color]를 이웃에 두면 감염과 약탈을 막아 줘.", "focus": lot,
				"opts": {"block": true}}
		"raiders":
			return {"text": "[color=#ffcc66]시장[/color]이 [color=#ff6a6a]약탈자[/color]를 끌어들였어. 시장 수입을 빼앗아 가.\n옆에 [color=#8cd660]검문소[/color]를 두면 막을 수 있어.", "focus": lot,
				"opts": {"block": true}}
		"elite":
			return {"text": "[color=#ff9a6a]엘리트[/color] 출현! 강하지만 쓰러뜨리면\n[color=#ffcc66]유물[/color]이나 기지 해금용 [color=#b8f0ff]설계도[/color]를 떨어뜨려.", "focus": "enemy:%d" % int(a.get("id", -1)),
				"opts": {"block": false, "auto": 6.0}}
		"relic":
			return {"text": "[color=#ffcc66]유물[/color]은 이번 운행 내내 효과가 있어.\n왼쪽 아래 아이콘에 마우스를 올려 확인해.", "focus": "relics",
				"opts": {"block": false, "auto": 6.0}}
		"starve":
			return {"text": "[color=#e8923c]보급품[/color]이 모자라 생존자가 떠났어.\n생존자 3명당 매 바퀴 보급품 1이 필요해.\n공장·온실·역이 보급품을 채워 줘.", "focus": "supplies|survivors",
				"opts": {"block": true}}
		"unpaid":
			return {"text": "보급품이 모자라 [color=#8cd660]군사 시설[/color]이 멈췄어.\n검문소 같은 군사 시설은 매 바퀴 [color=#e8923c]보급품[/color]을 먹어.", "focus": lot,
				"opts": {"block": false, "auto": 7.0}}
		"lowhull":
			return {"text": "[color=#ff6a6a]선체 위험![/color] 역·병원을 지나면 수리돼.\n차량기지 상점에서 긴급 수리도 살 수 있어.\n무리하지 말고 [color=#60d4ec]귀환[/color]하는 것도 방법이야.", "focus": "hull",
				"opts": {"block": true}}
		"horde70":
			return {"text": "[color=#ff78aa]군세 70[/color]. 곧 [color=#e63e46]검은 열차[/color]가 온다.\n100이 되면 차량기지에서 [color=#e63e46]결전[/color]과 [color=#60d4ec]귀환[/color] 중에 골라.", "focus": "horde",
				"opts": {"block": true}}
		"boss":
			return {"text": "[color=#e63e46]검은 열차[/color]가 옆 폐선로로 따라붙는다!\n체력 막대의 [color=#ffcc66]호위 차량[/color]부터 부숴야\n기관차에 제대로 피해가 들어가.", "focus": "boss_bar",
				"opts": {"block": true},
				"then": [{"text": "[color=#ff6a6a]붉은 원[/color]이 차오르면 경적 충격파야.\n원 안에 있는 차량이 피해를 입어.\n무장 차량이 알아서 싸워. 행운을 빌어.", "focus": "boss_head",
					"opts": {"block": true, "next": "싸운다!"}}]}
	return {}


func _tip(key: String, a := {}) -> void:
	if not enabled or Game.seen("tip_" + key):
		return
	for q in queue:
		if q.key == key:
			return
	if current.get("key", "") == key:
		return
	var d := tip_def(key, a)
	if d.is_empty():
		return
	d["key"] = key
	d["tries"] = 0
	queue.append(d)


func _show_tip(tip: Dictionary) -> void:
	current = tip
	var o: Dictionary = (tip.get("opts", {}) as Dictionary).duplicate()
	var blocking: bool = o.get("block", true)
	hold = blocking
	if not o.has("next"):
		o.next = "계속" if blocking else "확인"
	if tip.has("key"):
		Game.mark_seen("tip_" + String(tip.key))
	if o.has("hand_keys"):
		var hk: Array = o.hand_keys
		o.hand = [_center_of(hk[0]), _center_of(hk[1])]
	overlay.show_step(String(tip.text), _tf(String(tip.focus)), o)


func on_event(ev: Dictionary) -> void:
	if not enabled:
		return
	match String(ev.t):
		"place":
			if scripted and String(current.get("wait", "")) == "place" and String(ev.fac) == String(current.card):
				if String(ev.fac) == "station":
					# teach adjacency around wherever the station actually went
					station_lot = int(ev.lot)
					_market_lots_from(station_lot)
				Audio.sfx("pick", -2.0)
				_advance()
		"card":
			var p: Vector2 = ev.get("pos", Vector2(-1, -1))
			if p.x >= 0.0:
				_tip("card_drop")
		"evolve":
			if Defs.FACILITIES[String(ev.to)].cat != "hostile":
				_tip("evolve", ev)
			else:
				_tip("grow", ev)
		"corrupt":
			_tip("corrupt", ev)
		"raiders_arrive":
			_tip("raiders", ev)
		"spawn":
			if bool(ev.get("elite", false)):
				_tip("elite", ev)
		"relic":
			_tip("relic")
		"starve":
			_tip("starve")
		"unpaid":
			_tip("unpaid", ev)
		"depot":
			if not Game.seen("tip_depot_walk"):
				Game.mark_seen("tip_depot_walk")
				# queued tips (e.g. the evolution that just happened) wait until the depot closes
				current = {}
				overlay.hide_step()
				_depot_start()
		"boss_spawn":
			_tip("boss")


func _process(_delta: float) -> void:
	if not enabled or overlay == null:
		return
	# panels open under the spotlight layer: step aside while help / pause are up, and a
	# contextual tip waits behind any panel (depot, event, reward...) until it closes
	if overlay.active:
		var covered: bool = hud.modal_kind in ["help", "pause"]
		if not scripted and depot_step < 0 and hud.modal != null:
			covered = true
		overlay.visible = not covered
	# the depot walk-through: advance once a supply was picked, end when the stop is over
	if depot_step >= 0:
		var p: Dictionary = sim.pending
		if p.get("kind", "") != "depot":
			on_depot_decided()
		elif depot_step == 0 and watch_pick and int(p.get("picked", -1)) >= 0:
			watch_pick = false
			_depot_next()
	if scripted or depot_step >= 0:
		return
	# polled conditions
	var kind: String = sim.pending.get("kind", "")
	if sim.state == "running":
		if _first_train_card() != "":
			_tip("train_card")
		if sim.hand.size() >= Defs.HAND_MAX:
			_tip("hand_full")
		if sim.hull < sim.max_hull * 0.3:
			_tip("lowhull")
		if sim.horde >= 70.0 and not sim.boss_active:
			_tip("horde70")
		for lot_id in sim.facs.keys():
			var cd := sim.evo_countdown(lot_id)
			if cd > 0 and cd <= 2:
				_tip("countdown", {"lot": lot_id})
				break
	# show the next queued tip when nothing else is on screen
	if current.is_empty() and not queue.is_empty() and kind == "" and hud.modal == null and not run.menu_open and run.ending == "" and run.drag_id == "":
		var tip: Dictionary = queue.pop_front()
		if rects(String(tip.focus)).is_empty() and String(tip.focus) != "":
			# target not on screen yet (card still flying in...): retry for a few seconds
			tip.tries = int(tip.tries) + 1
			if int(tip.tries) < 180:
				queue.append(tip)
			return
		_show_tip(tip)
	# a non-blocking tip whose target vanished (the elite died) closes itself
	if not current.is_empty() and not scripted and depot_step < 0 and current.has("focus") and overlay.active and not overlay.blocking:
		if rects(String(current.focus)).is_empty() and overlay.t > 1.0:
			current = {}
			hold = false
			overlay.hide_step()
