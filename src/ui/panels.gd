class_name Panels
extends RefCounted
## Modal panels for the run: depot stop, rewards, radio events, black market, pause, results.

const PORTRAIT := {"sos": "refugee", "drop": "dispatcher", "toll": "warlord", "signal": "unknown",
	"crew": "mechanic", "sighting": "dispatcher", "merchant": "merchant", "outbreak": "refugee"}


static func _dim(hud: Hud) -> Control:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.root.add_child(dim)
	return dim


static func _pop_in(c: Control) -> void:
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2(0.9, 0.9)
	c.modulate.a = 0.0
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(c, "modulate:a", 1.0, 0.12)


static func close(hud: Hud) -> void:
	if hud.modal and is_instance_valid(hud.modal):
		hud.modal.queue_free()
	hud.modal = null
	hud.modal_kind = ""
	hud.hide_tooltip()


static func _center(p: Control, sz: Vector2) -> void:
	# width is fixed, height follows the content (re-centred once layout settles)
	p.custom_minimum_size = Vector2(sz.x, 0)
	p.size = Vector2(sz.x, 0)
	p.position = ((Vector2(640, 360) - sz) * 0.5).floor()
	p.resized.connect(func(): p.position = ((Vector2(640, 360) - p.size) * 0.5).floor())
	(func():
		if is_instance_valid(p):
			p.reset_size()
			p.position = ((Vector2(640, 360) - p.size) * 0.5).floor()).call_deferred()


## a pickable reward tile (depot supply choice / transfer station bonus)
static func reward_tile(hud: Hud, id: String, on_pick: Callable, w := 92.0) -> Button:
	var info := UI.reward_info(id)
	var b := Button.new()
	b.custom_minimum_size = Vector2(w, 98)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", UI.style("res://assets/sprites/ui/button.png", 3, 4))
	b.add_theme_stylebox_override("hover", UI.style("res://assets/sprites/ui/button_hover.png", 3, 4))
	b.add_theme_stylebox_override("pressed", UI.style("res://assets/sprites/ui/button_hot.png", 3, 4))
	b.add_theme_stylebox_override("disabled", UI.style("res://assets/sprites/ui/button_off.png", 3, 4))
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 4
	vb.offset_right = -4
	vb.offset_top = 3
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 1)
	b.add_child(vb)
	var tag := UI.label(info.tag, 7, UI.COL.dim)
	vb.add_child(tag)
	var ic := TextureRect.new()
	ic.texture = info.icon
	ic.custom_minimum_size = Vector2(w - 8, 30)
	ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(ic)
	var tl := UI.label(info.title, 9, UI.COL.yellow)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(tl)
	var dl := UI.label(info.desc, 7, UI.COL.text)
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.custom_minimum_size = Vector2(w - 8, 0)
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(dl)
	b.pressed.connect(on_pick)
	b.mouse_entered.connect(func(): Audio.sfx("hover", -14.0))
	return b


# ------------------------------------------------------------------ depot
static func depot(hud: Hud) -> void:
	close(hud)
	var sim := hud.sim
	var p: Dictionary = sim.pending
	var dim := _dim(hud)
	hud.modal = dim
	hud.modal_kind = "depot"
	var panel := UI.panel()
	dim.add_child(panel)
	_center(panel, Vector2(470, 262))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	head.add_child(UI.label("차량기지", 12, UI.COL.yellow))
	head.add_child(UI.label("  %d바퀴 완주" % sim.loop, 11, UI.COL.dim))
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	vb.add_child(body)
	# supply choice
	var left := VBoxContainer.new()
	body.add_child(left)
	var picked: int = p.picked
	left.add_child(UI.label("보급 — 하나를 고른다" if picked < 0 else "보급 수령 완료", 9, UI.COL.text if picked < 0 else UI.COL.dim))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	left.add_child(row)
	hud.targets["depot_supply"] = row
	var opts: Array = p.options
	var tw := 92.0 if opts.size() <= 3 else 72.0
	for i in opts.size():
		var idx := i
		var b := reward_tile(hud, String(opts[i]), func():
			if sim.depot_pick(idx):
				Audio.sfx("pick", -2.0)
				hud.run.after_reward(String(opts[idx]))
				depot(hud), tw)
		b.disabled = picked >= 0
		if picked == i:
			b.modulate = Color(1.2, 1.1, 0.8)
		row.add_child(b)
	# shop
	var right := VBoxContainer.new()
	body.add_child(right)
	right.add_child(UI.label("상점 — 고철 %d" % sim.scrap, 9, UI.COL.text))
	var srow := VBoxContainer.new()
	srow.add_theme_constant_override("separation", 3)
	right.add_child(srow)
	hud.targets["depot_shop"] = right
	var shop: Array = p.shop
	for i in shop.size():
		var item: Dictionary = shop[i]
		var idx := i
		var info := UI.reward_info(String(item.id))
		var b := UI.button("%s  %d고철" % [info.title, int(item.cost)] if not item.sold else "%s  (구매함)" % info.title, 9)
		b.custom_minimum_size = Vector2(150, 22)
		b.icon = info.icon
		b.expand_icon = false
		b.disabled = item.sold or sim.scrap < int(item.cost)
		b.mouse_entered.connect(func(): hud.show_tooltip("[color=#ffcc66]%s[/color]\n%s" % [info.title, info.desc], hud.get_viewport().get_mouse_position()))
		b.mouse_exited.connect(func(): hud.hide_tooltip())
		b.pressed.connect(func():
			if sim.depot_buy(idx):
				Audio.sfx("buy", -2.0)
				hud.run.after_reward(String(item.id))
				depot(hud))
		srow.add_child(b)
	# status + decision
	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator", UI.flat(UI.COL.line, Color(0, 0, 0, 0), 0, 0))
	vb.add_child(sep)
	var st := UI.rich(9)
	st.custom_minimum_size = Vector2(456, 0)
	var hp := int(ceil(sim.hull))
	var next_h := sim.horde
	var status := "[color=#8cd660]선체 %d/%d[/color]   [color=#ffcc66]고철 %d[/color]   [color=#60d4ec]생존자 %d[/color]   [color=#e8923c]보급 %d[/color]   [color=#ff78aa]군세 %d/100[/color]" % [hp, int(sim.max_hull), sim.scrap, sim.survivors, sim.supplies, int(next_h)]
	var warn := ""
	if bool(p.boss_next):
		warn = "\n[color=#ff4a4a]검은 열차가 깨어났다. 계속 운행하면 결전이 벌어진다. 차량기지는 봉쇄된다.[/color]"
	elif sim.horde >= 70.0:
		warn = "\n[color=#ff9a6a]군세가 높다. 곧 검은 열차가 온다.[/color]"
	var fc := sim.forecast()
	if not fc.is_empty():
		warn += "\n[color=#8a86a0]다음 바퀴 예보[/color]  " + "  ·  ".join(fc)
	var keep := int(sim.scrap * sim.death_keep_ratio())
	var haul := sim.haul_mult()
	var bank := "\n귀환하면 [color=#ffcc66]고철 %d[/color] [color=#8a86a0](운행 보너스 x%.1f)[/color] · [color=#60d4ec]생존자 %d[/color]%s 를 기지로.\n파괴되면 [color=#ff7070]고철 %d만 남고 생존자는 잃는다[/color]. 오래 달릴수록 귀환 보너스가 커진다." % [int(round(sim.scrap * haul)), haul, sim._survivor_score(), (" · [color=#b8f0ff]설계도 %d[/color]" % sim.blueprints.size()) if sim.blueprints.size() > 0 else "", keep]
	st.text = status + warn + bank
	vb.add_child(st)
	hud.targets["depot_status"] = st
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 12)
	vb.add_child(btns)
	hud.targets["depot_buttons"] = btns
	var ret := UI.button("귀환한다  [R]", 11)
	ret.custom_minimum_size = Vector2(150, 22)
	ret.pressed.connect(func(): hud.run.depot_return())
	btns.add_child(ret)
	var go := UI.button(("결전에 나선다" if bool(p.boss_next) else "계속 운행 · %d바퀴" % (sim.loop + 1)) + "  [Enter]", 11, true)
	go.custom_minimum_size = Vector2(190, 22)
	go.pressed.connect(func(): hud.run.depot_continue())
	btns.add_child(go)
	_pop_in(panel)


# ------------------------------------------------------------------ transfer reward
static func reward(hud: Hud) -> void:
	close(hud)
	var sim := hud.sim
	var dim := _dim(hud)
	hud.modal = dim
	hud.modal_kind = "reward"
	var panel := UI.panel()
	dim.add_child(panel)
	_center(panel, Vector2(320, 130))
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	vb.add_child(UI.label("환승역 보급", 12, UI.COL.cyan))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	vb.add_child(row)
	var opts: Array = sim.pending.options
	for i in opts.size():
		var idx := i
		row.add_child(reward_tile(hud, String(opts[i]), func():
			sim.reward_pick(idx)
			Audio.sfx("pick", -2.0)
			hud.run.after_reward(String(opts[idx]))
			close(hud)))
	_pop_in(panel)


# ------------------------------------------------------------------ black market
static func blackmarket(hud: Hud) -> void:
	close(hud)
	var sim := hud.sim
	var p: Dictionary = sim.pending
	var dim := _dim(hud)
	hud.modal = dim
	hud.modal_kind = "blackmarket"
	var panel := UI.panel()
	dim.add_child(panel)
	_center(panel, Vector2(300, 120))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	panel.add_child(hb)
	var por := TextureRect.new()
	por.texture = UI.tex("res://assets/sprites/portrait/merchant.png")
	por.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	por.custom_minimum_size = Vector2(48, 48)
	hb.add_child(por)
	var vb := VBoxContainer.new()
	hb.add_child(vb)
	var r: Dictionary = Defs.RELICS[p.relic]
	vb.add_child(UI.label("암시장", 12, UI.COL.pink))
	var t := UI.rich(9)
	t.custom_minimum_size = Vector2(220, 0)
	t.text = "\"이거 어디서 났는지는 묻지 마.\"\n[color=#ffcc66]%s[/color] — %s" % [r.name, r.desc]
	vb.add_child(t)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 6)
	vb.add_child(btns)
	var buy := UI.button("산다 (고철 %d)" % int(p.cost), 9, true)
	buy.disabled = sim.scrap < int(p.cost)
	buy.pressed.connect(func():
		sim.bm_choose(true)
		Audio.sfx("buy", -2.0)
		close(hud))
	btns.add_child(buy)
	var no := UI.button("됐다", 9)
	no.pressed.connect(func():
		sim.bm_choose(false)
		close(hud))
	btns.add_child(no)
	_pop_in(panel)


# ------------------------------------------------------------------ radio event
static func event(hud: Hud) -> void:
	close(hud)
	var sim := hud.sim
	var id: String = sim.pending.id
	var ev: Dictionary = Defs.EVENTS[id]
	var dim := _dim(hud)
	dim.color = Color(0.02, 0.04, 0.05, 0.45)
	hud.modal = dim
	hud.modal_kind = "event"
	var panel := UI.panel()
	dim.add_child(panel)
	_center(panel, Vector2(380, 140))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	panel.add_child(hb)
	var por := TextureRect.new()
	por.texture = UI.tex("res://assets/sprites/portrait/%s.png" % PORTRAIT.get(id, "dispatcher"))
	por.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	por.custom_minimum_size = Vector2(52, 60)
	hb.add_child(por)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	hb.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	head.add_child(UI.label("무전", 7, UI.COL.green))
	head.add_child(UI.label("  " + String(ev.title), 12, UI.COL.white))
	var txt := UI.rich(11)
	txt.custom_minimum_size = Vector2(300, 44)
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.text = String(ev.text)
	txt.visible_ratio = 0.0
	vb.add_child(txt)
	var tw := txt.create_tween()
	tw.tween_property(txt, "visible_ratio", 1.0, 0.9)
	var choices: Array = ev.choices
	for i in choices.size():
		var idx := i
		var b := UI.button("%d. %s" % [i + 1, choices[i]], 9, i == 0)
		b.disabled = not sim.event_can(i)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func(): hud.run.event_choose(idx))
		vb.add_child(b)
	Audio.sfx("radio", -3.0)
	_pop_in(panel)


# ------------------------------------------------------------------ pause
static func pause(hud: Hud) -> void:
	close(hud)
	var dim := _dim(hud)
	hud.modal = dim
	hud.modal_kind = "pause"
	var panel := UI.panel()
	dim.add_child(panel)
	_center(panel, Vector2(220, 184))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	panel.add_child(vb)
	var t := UI.label("일시정지", 12, UI.COL.yellow)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	for pair in [["효과음", "sfx"], ["음악", "music"], ["음성", "voice"], ["화면 흔들림", "shake"]]:
		var row := HBoxContainer.new()
		var l := UI.label(pair[0], 9)
		l.custom_minimum_size = Vector2(70, 0)
		row.add_child(l)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.value = float(Game.setting(pair[1], 1.0))
		sl.custom_minimum_size = Vector2(120, 12)
		var key: String = pair[1]
		sl.value_changed.connect(func(v): Game.set_setting(key, v))
		row.add_child(sl)
		vb.add_child(row)
	var fs := CheckButton.new()
	fs.text = "전체 화면"
	fs.add_theme_font_override("font", UI.font(9))
	fs.add_theme_font_size_override("font_size", 10)
	fs.button_pressed = bool(Game.setting("fullscreen", false))
	fs.focus_mode = Control.FOCUS_NONE
	fs.toggled.connect(func(on): Game.set_setting("fullscreen", on))
	vb.add_child(fs)
	var resume := UI.button("계속  [Esc]", 11, true)
	resume.pressed.connect(func(): hud.run.toggle_menu())
	vb.add_child(resume)
	var hp := UI.button("도움말  [H]", 9)
	hp.pressed.connect(func(): hud.run.open_help())
	vb.add_child(hp)
	var quit := UI.button("운행 포기 (열차 파괴 처리)", 9)
	quit.pressed.connect(func(): hud.run.abandon())
	vb.add_child(quit)
	_pop_in(panel)


# ------------------------------------------------------------------ results
static func results(hud: Hud, res: Dictionary) -> void:
	close(hud)
	var dim := _dim(hud)
	dim.color = Color(0.02, 0.02, 0.05, 0.72)
	hud.modal = dim
	hud.modal_kind = "results"
	var panel := UI.panel()
	dim.add_child(panel)
	_center(panel, Vector2(330, 220))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	var state: String = res.state
	var title: String = {"dead": "운행 종료 — 열차 파괴", "returned": "무사 귀환", "victory": "검은 열차 격파"}.get(state, "운행 종료")
	var col: Color = {"dead": UI.COL.red, "returned": UI.COL.cyan, "victory": UI.COL.yellow}.get(state, UI.COL.white)
	var tl := UI.label(title, 12, col)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(tl)
	var flavor: String = {"dead": "\"...교신 두절. 마지막 노선이 또 하나 끊겼다.\"",
		"returned": "\"잘 돌아왔어. 기지 불은 켜 둘게.\"",
		"victory": "\"검은 열차가 멈췄다. 이 노선은... 우리 거야.\""}.get(state, "")
	var fl := UI.label(flavor, 9, UI.COL.dim)
	fl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(fl)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	vb.add_child(grid)
	var lines := [["운행", "%d바퀴 · %d분 %d초" % [int(res.loops), int(res.time) / 60, int(res.time) % 60]],
		["처치", str(res.kills)], ["기지로 가져간 고철", str(res.scrap)],
		["데려간 생존자", str(res.survivors)]]
	if state == "dead":
		lines.append(["잃은 것", "생존자 전원, 고철 대부분"])
	if state == "victory":
		lines.append(["위협 등급", "상승 — 적이 강해지고 고철이 늘어난다"])
	elif state == "returned":
		lines[2][1] = "%s  (운행 보너스 포함)" % str(res.scrap)
	var nbp: Array = res.get("new_blueprints", [])
	if nbp.size() > 0:
		var names: Array = []
		for b in nbp:
			names.append({"card:power": "발전소", "card:radio": "무선탑", "car:tesla": "테슬라차"}.get(b, b))
		lines.append(["새 설계도", ", ".join(names)])
	var delay := 0.0
	for pair in lines:
		var a := UI.label(pair[0], 9, UI.COL.dim)
		var b := UI.label(pair[1], 11, UI.COL.white)
		a.modulate.a = 0.0
		b.modulate.a = 0.0
		grid.add_child(a)
		grid.add_child(b)
		var tw := a.create_tween()
		tw.tween_interval(delay)
		tw.tween_property(a, "modulate:a", 1.0, 0.2)
		tw.parallel().tween_property(b, "modulate:a", 1.0, 0.2)
		tw.tween_callback(func(): Audio.sfx("tick", -6.0))
		delay += 0.22
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	vb.add_child(spacer)
	var btn := UI.button("차량기지로", 11, true)
	btn.pressed.connect(func(): Game.goto("hub"))
	vb.add_child(btn)
	_pop_in(panel)


# ------------------------------------------------------------------ help / rules reference
const HELP := [
	["기본", [
		["train/loco", "[color=#ffcc66]열차[/color]는 노선을 스스로 돈다. 무장 차량이 가까운 적을 자동으로 쏜다."],
		["icon/i_hull", "[color=#8cd660]선체[/color]가 0이면 운행 종료. 역·병원을 지나면 수리된다."],
		["icon/cardback", "카드를 [color=#60d4ec]선로 옆 빈 부지[/color]로 끌어 시설을 세운다. 우클릭하면 버리기(고철 +2)."],
		["icon/i_scrap", "적을 쓰러뜨리면 [color=#ffcc66]고철[/color]과 [color=#60d4ec]카드[/color]. 엘리트는 유물·설계도를 준다."],
		["fac/depot", "한 바퀴마다 [color=#ffcc66]차량기지[/color]에 정차: 보급 1개를 고르고, 계속 달릴지 귀환할지 정한다."],
	]],
	["조작", [
		["icon/i_hand", "[color=#60d4ec]끌어 놓기[/color]: 시설 카드는 선로 옆 빈 부지에, 차량·개조 카드는 열차 위에 놓는다."],
		["icon/cardback", "[color=#ffcc66]우클릭[/color]: 손패 카드 버리기(고철 +2). 카드를 끄는 중에 우클릭하면 취소."],
		["icon/i_help", "[color=#60d4ec]마우스 올리기[/color]: 시설·적·차량·상단 표시 어디든 설명이 뜬다.\n카드를 끄는 동안에는 그 자리의 인접 효과를 미리 보여 준다."],
		["icon/i_arrow", "[color=#ffcc66]Space[/color] 일시정지 · [color=#ffcc66]1 2 3[/color] 속도 · [color=#ffcc66]H[/color] 도움말 · [color=#ffcc66]Esc[/color] 메뉴\n멈춘 상태에서도 카드를 놓을 수 있다."],
		["fac/transfer", "차량기지: [color=#ffcc66]1 2 3[/color] 보급 선택 · [color=#ffcc66]Enter[/color] 계속 운행 · [color=#ffcc66]R[/color] 귀환"],
	]],
	["시설", [
		["fac/station", "[color=#60d4ec]민간[/color] 역·시장·병원·피난처: 수리, 고철, 생존자. 감염과 약탈에 약하다."],
		["fac/factory", "[color=#e8923c]산업[/color] 공장·발전소·온실: 보급품, 개조 카드, 전기 선로. 소음이 크다."],
		["fac/checkpoint", "[color=#8cbe5a]군사[/color] 검문소·무기고: 민병대가 사격하고 이웃 민간 시설을 지킨다.\n유지비로 매 바퀴 보급품을 쓴다."],
		["fac/infection", "[color=#e63e46]위험[/color] 감염구역·약탈자 거점·폐역: 적을 부르지만 처치 보상이 크다.\n방치하면 더 위험한 시설로 커진다."],
		["fac/radio", "[color=#aa64e6]특수[/color] 무선탑은 매 바퀴 무전 사건. [color=#ff78aa]소각 작전[/color]은 시설 하나를 없애고 군세 -4."],
	]],
	["진화", [
		["fac/transfer", "역 + 시장 → [color=#b8f0ff]환승역[/color]: 바퀴마다 보급 선택 1회."],
		["fac/medhub", "병원 + 역 → [color=#b8f0ff]의료 거점[/color]: 큰 수리. 폐역 + 피난처 → 역 복구."],
		["fac/assembly", "공장 + 발전소 → [color=#b8f0ff]조립공장[/color]: 차량 카드 생산."],
		["fac/commune", "피난처 + 온실 → [color=#b8f0ff]공동체[/color]: 생존자 2명과 보급품."],
		["fac/mercpost", "검문소 + 약탈자 → [color=#b8f0ff]용병 초소[/color], 검문소 + 무기고 → [color=#b8f0ff]포대[/color]."],
		["fac/blackmarket", "시장 + 약탈자 → [color=#b8f0ff]암시장[/color]: 고철로 유물 거래. 진화는 차량기지 정차 때 일어난다."],
	]],
	["위험", [
		["fac/hive", "감염구역은 4바퀴 뒤 [color=#ff6a6a]둥지[/color](공장 옆이면 더 빨리). 둥지는 브루드 마더를 낳는다."],
		["fac/fortress", "약탈자 거점은 [color=#ff6a6a]요새[/color], 폐역은 [color=#ff6a6a]망령역[/color]이 된다. 시설 위 빨간 숫자 = 남은 바퀴."],
		["fac/ward", "감염은 이웃 민간 시설로 번진다: 병원→감염병동, 피난처→감염구역.\n[color=#8cd660]검문소[/color]가 이웃에 있으면 안전하다."],
		["fac/raiders", "시장은 약탈자를 끌어들이고, 약탈자는 시장 수입과 피난처 생존자를 빼앗는다."],
	]],
	["군세", [
		["icon/i_noise", "시설마다 [color=#ff78aa]소음[/color]이 있다(카드 오른쪽 아래 숫자). 매 바퀴 군세가 그만큼 오른다."],
		["icon/i_danger", "군세 35·70을 넘으면 떠도는 적이 늘고 노선이 붉게 물든다."],
		["boss/head", "군세 100: 차량기지에서 [color=#e63e46]검은 열차[/color]와의 결전을 고를 수 있다. 이기면 운행 승리."],
		["boss/gun", "호위 차량이 살아 있으면 기관차 피해 절반. [color=#ff6a6a]붉은 원[/color] = 경적 충격파 범위."],
	]],
	["귀환", [
		["icon/i_loop", "[color=#60d4ec]귀환[/color]: 고철·생존자·설계도를 기지로. 오래 달릴수록 운행 보너스(최대 x1.5)."],
		["icon/i_skull", "[color=#ff6a6a]파괴[/color]: 고철 일부만 남고 생존자와 설계도는 잃는다."],
		["enemy/survivor", "생존자 1명당 무기 연사 +2%. 대신 3명당 보급품 1을 먹는다."],
		["icon/blueprint", "기지에서 차량·카드·시작 자원을 해금한다. 일부는 엘리트의 설계도가 필요하다."],
	]],
]


static func help(hud: Hud, page := 0) -> void:
	close(hud)
	page = clampi(page, 0, HELP.size() - 1)
	Game.mark_seen("help_opened")
	var dim := _dim(hud)
	hud.modal = dim
	hud.modal_kind = "help"
	hud.targets["help_page"] = page
	var panel := UI.panel()
	dim.add_child(panel)
	_center(panel, Vector2(452, 250))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 2)
	vb.add_child(head)
	head.add_child(UI.label("도움말  ", 12, UI.COL.yellow))
	for i in HELP.size():
		var k := i
		var tb := UI.button(HELP[i][0], 9, i == page)
		tb.custom_minimum_size = Vector2(52, 18)
		tb.pressed.connect(func(): help(hud, k))
		head.add_child(tb)
	var rows: Array = HELP[page][1]
	for r in rows:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 6)
		var ic := TextureRect.new()
		ic.texture = UI.tex("res://assets/sprites/%s.png" % r[0])
		ic.custom_minimum_size = Vector2(46, 30)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		ic.clip_contents = true
		hb.add_child(ic)
		var tx := UI.rich(9)
		tx.custom_minimum_size = Vector2(378, 0)
		# explicit line breaks only: auto-wrap would split Korean words (tools/measure_text.py)
		tx.autowrap_mode = TextServer.AUTOWRAP_OFF
		tx.text = r[1]
		tx.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(tx)
		vb.add_child(hb)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 6)
	vb.add_child(foot)
	var prev := UI.button("◀ 이전", 9)
	prev.disabled = page == 0
	prev.pressed.connect(func(): help(hud, page - 1))
	foot.add_child(prev)
	var nxt := UI.button("다음 ▶", 9)
	nxt.disabled = page == HELP.size() - 1
	nxt.pressed.connect(func(): help(hud, page + 1))
	foot.add_child(nxt)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(sp)
	foot.add_child(UI.label("%d / %d   ←→ 페이지" % [page + 1, HELP.size()], 7, UI.COL.dim))
	var cl := UI.button("닫기 [Esc]", 9, true)
	cl.pressed.connect(func(): hud.run.close_help())
	foot.add_child(cl)
