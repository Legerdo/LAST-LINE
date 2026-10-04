class_name Hud
extends CanvasLayer
## In-run UI: top status bar, hand of cards, relics, tooltips, banners, radio subtitles,
## boss bar, and the modal panels (depot stop, radio events, rewards, pause, results).

const TOP_H := 24
const BOT_Y := 296

var run: Node
var sim: Sim
var root: Control
var top: Control
var bottom: Control
var hand_box: Control
var cards: Array = []
var tooltip: PanelContainer
var tip_text: RichTextLabel
var banner: Label
var banner_sub: Label
var toast_box: VBoxContainer
var subtitle: PanelContainer
var sub_label: RichTextLabel
var sub_portrait: TextureRect
var sub_t := 0.0
var sub_full := ""
var sub_shown := 0.0
var modal: Control = null
var modal_kind := ""
var boss_bar: Control
var drag_ghost: CardView = null
var drag_index := -1
var hover_card: CardView = null
var relic_box: Control
# displayed (animated) values
var d_hull := 0.0
var d_chip := 0.0
var d_scrap := 0.0
var d_sup := 0.0
var d_horde := 0.0
var punch_scrap := 0.0
var punch_sup := 0.0
var punch_surv := 0.0
var punch_hull := 0.0
var punch_horde := 0.0
var t := 0.0
var speed_rects: Array = []
var help_rect := Rect2(541, 5, 16, 14)
var hand_sig := ""
# named controls the tutorial spotlight can point at (registered by panels)
var targets := {}


func setup(controller: Node, s: Sim) -> void:
	run = controller
	sim = s
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_top()
	_build_bottom()
	boss_bar = Control.new()
	boss_bar.position = Vector2(170, TOP_H + 3)
	boss_bar.size = Vector2(300, 16)
	boss_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_bar.draw.connect(_draw_boss_bar)
	boss_bar.visible = false
	root.add_child(boss_bar)
	toast_box = VBoxContainer.new()
	toast_box.position = Vector2(6, TOP_H + 4)
	toast_box.size = Vector2(200, 120)
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_box.add_theme_constant_override("separation", 1)
	root.add_child(toast_box)
	banner = UI.label("", 12, UI.COL.white)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.size = Vector2(640, 16)
	banner.position = Vector2(0, 86)
	banner.pivot_offset = Vector2(320, 8)
	banner.visible = false
	root.add_child(banner)
	banner_sub = UI.label("", 11, UI.COL.text)
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_sub.size = Vector2(640, 14)
	banner_sub.position = Vector2(0, 104)
	banner_sub.visible = false
	root.add_child(banner_sub)
	_build_subtitle()
	_build_tooltip()
	d_hull = sim.hull
	d_chip = sim.hull
	d_scrap = sim.scrap
	d_sup = sim.supplies
	d_horde = sim.horde
	rebuild_hand()


# ================================================================ top bar
func _build_top() -> void:
	top = Control.new()
	top.size = Vector2(640, TOP_H)
	top.mouse_filter = Control.MOUSE_FILTER_PASS
	top.draw.connect(_draw_top)
	top.gui_input.connect(_top_input)
	root.add_child(top)
	speed_rects = [Rect2(560, 5, 17, 14), Rect2(579, 5, 17, 14), Rect2(598, 5, 17, 14), Rect2(617, 5, 18, 14)]
	top.mouse_exited.connect(func(): hide_tooltip())


func _top_input(ev: InputEvent) -> void:
	var mp: Vector2 = top.get_local_mouse_position()
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		if help_rect.has_point(mp):
			Audio.sfx("click", -6.0)
			run.open_help()
			return
		for i in speed_rects.size():
			if (speed_rects[i] as Rect2).has_point(mp):
				Audio.sfx("click", -6.0)
				if i == 0:
					run.toggle_pause()
				else:
					run.set_speed(i)
	if ev is InputEventMouseMotion:
		if Rect2(56, 3, 132, 18).has_point(mp):
			show_tooltip("[color=#8cd660]선체[/color] %d / %d\n0이 되면 열차가 파괴된다.\n역·병원을 지나며 수리한다." % [int(sim.hull), int(sim.max_hull)], get_viewport().get_mouse_position())
		elif Rect2(194, 3, 52, 18).has_point(mp):
			show_tooltip("[color=#ffcc66]고철[/color] %d\n차량기지 상점과 귀환 후 기지 건설에 쓴다.\n파괴되면 일부만 남는다." % sim.scrap, get_viewport().get_mouse_position())
		elif Rect2(248, 3, 48, 18).has_point(mp):
			show_tooltip("[color=#e8923c]보급품[/color] %d\n바퀴마다 생존자 3명당 1 소비.\n검문소 유지비로도 쓴다." % sim.supplies, get_viewport().get_mouse_position())
		elif Rect2(298, 3, 58, 18).has_point(mp):
			show_tooltip("[color=#60d4ec]생존자[/color] %d / %d\n1명당 무기 연사 +%d%%.\n귀환해야 기지로 데려갈 수 있다." % [sim.survivors, sim.crew_cap(), int(round((Defs.CREW_RATE_BONUS + 0.01 * sim.mod_count("drill")) * 100))], get_viewport().get_mouse_position())
		elif help_rect.has_point(mp):
			show_tooltip("도움말 [H]\n조작, 시설, 진화, 군세, 귀환 규칙 정리", get_viewport().get_mouse_position())
		elif Rect2(362, 3, 176, 18).has_point(mp):
			show_tooltip("[color=#ff56aa]군세[/color] %d / 100\n노선에 시설이 늘수록 매 바퀴 차오른다. (다음 정차 +%d)\n100에 도달하면 [color=#e63e46]검은 열차[/color]가 깨어난다." % [int(sim.horde), int(round(sim.noise_per_loop()))], get_viewport().get_mouse_position())
		elif Rect2(4, 3, 48, 18).has_point(mp):
			show_tooltip("%d바퀴째 운행 중.\n바퀴마다 적이 강해진다. (체력 +%d%%)" % [sim.loop, int(round((Defs.ENEMY_HP_GROWTH - 1.0) * 100))], get_viewport().get_mouse_position())
		elif Rect2(558, 3, 80, 18).has_point(mp):
			show_tooltip("일시정지 [Space]\n속도 [1] [2] [3]", get_viewport().get_mouse_position())
		else:
			hide_tooltip()


func _draw_top() -> void:
	_nine(top, UI.tex("res://assets/sprites/ui/panel_dark.png"), Rect2(-2, -4, 644, TOP_H + 4), 4)
	var f7 := UI.font(7)
	var f9 := UI.font(9)
	var f11 := UI.font(11)
	# loop
	top.draw_string(f7, Vector2(6, 10), "바퀴", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UI.COL.dim)
	top.draw_string(f11, Vector2(28, 13), str(sim.loop), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.COL.white)
	var lp := sim.loop_progress()
	top.draw_rect(Rect2(6, 16, 44, 3), UI.COL.ink)
	top.draw_rect(Rect2(6, 16, round(44 * lp), 3), UI.COL.orange)
	# hull
	var hx := 56.0
	var hw := 130.0
	var ratio := clampf(d_hull / maxf(1.0, sim.max_hull), 0.0, 1.0)
	var chip := clampf(d_chip / maxf(1.0, sim.max_hull), 0.0, 1.0)
	var pk := punch_hull
	top.draw_rect(Rect2(hx - 1, 5 - pk, hw + 2, 12 + pk * 2), UI.COL.ink)
	top.draw_rect(Rect2(hx, 6 - pk, hw, 10 + pk * 2), Color8(40, 30, 40))
	top.draw_rect(Rect2(hx, 6 - pk, round(hw * chip), 10 + pk * 2), Color8(250, 240, 240))
	var hc := Color8(120, 214, 96) if ratio > 0.55 else (Color8(255, 200, 80) if ratio > 0.3 else Color8(235, 60, 70))
	if ratio <= 0.3 and int(t * 6.0) % 2 == 0:
		hc = Color8(255, 120, 120)
	top.draw_rect(Rect2(hx, 6 - pk, round(hw * ratio), 10 + pk * 2), hc)
	top.draw_rect(Rect2(hx, 6 - pk, round(hw * ratio), 2), Color(1, 1, 1, 0.25))
	var hs := "%d / %d" % [int(ceil(sim.hull)), int(sim.max_hull)]
	var hsw := f7.get_string_size(hs, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	top.draw_string(f7, Vector2(hx + (hw - hsw) * 0.5 + 1, 15), hs, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UI.COL.ink)
	top.draw_string(f7, Vector2(hx + (hw - hsw) * 0.5, 14), hs, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UI.COL.white)
	# resources
	_res(Vector2(196, 5), "res://assets/sprites/icon/i_scrap.png", str(int(round(d_scrap))), UI.COL.yellow, punch_scrap)
	_res(Vector2(250, 5), "res://assets/sprites/icon/i_supplies.png", str(int(round(d_sup))), UI.COL.orange, punch_sup)
	_res(Vector2(300, 5), "res://assets/sprites/icon/i_survivor.png", "%d/%d" % [sim.survivors, sim.crew_cap()], UI.COL.cyan, punch_surv)
	# horde gauge
	var gx := 390.0
	var gw := 136.0
	top.draw_string(f7, Vector2(362, 14), "군세", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color8(255, 120, 170))
	var hk := clampf(d_horde / 100.0, 0.0, 1.0)
	var nxt := clampf((sim.horde + sim.noise_per_loop()) / 100.0, 0.0, 1.0)
	var pkh := punch_horde
	top.draw_rect(Rect2(gx - 1, 7 - pkh, gw + 2, 9 + pkh * 2), UI.COL.ink)
	top.draw_rect(Rect2(gx, 8 - pkh, gw, 7 + pkh * 2), Color8(34, 24, 40))
	if not sim.boss_active:
		var ghost_a := 0.25 + 0.2 * sin(t * 5.0)
		top.draw_rect(Rect2(gx, 8, round(gw * nxt), 7), Color(1, 0.35, 0.6, ghost_a))
	var stage := sim.danger_stage()
	var gc: Color = [Color8(170, 100, 230), Color8(220, 90, 190), Color8(255, 80, 120), Color8(255, 50, 60)][stage]
	top.draw_rect(Rect2(gx, 8 - pkh, round(gw * hk), 7 + pkh * 2), gc)
	top.draw_rect(Rect2(gx, 8 - pkh, round(gw * hk), 1), Color(1, 1, 1, 0.3))
	for m in [35, 70]:
		var mx: float = gx + roundf(gw * float(m) / 100.0)
		top.draw_line(Vector2(mx, 6), Vector2(mx, 17), UI.COL.ink)
		top.draw_line(Vector2(mx + 1, 7), Vector2(mx + 1, 16), Color(1, 1, 1, 0.25))
	var skull := UI.tex("res://assets/sprites/icon/i_skull.png")
	if skull:
		var sc := Color(1, 1, 1) if stage < 3 else Color(1, 0.4, 0.4) * (0.7 + 0.3 * sin(t * 10.0))
		top.draw_texture(skull, Vector2(gx + gw + 3, 6), sc)
	# help button
	var hr := help_rect
	top.draw_rect(hr, UI.COL.ink)
	top.draw_rect(hr.grow(-1), Color8(40, 70, 90) if not Game.seen("help_opened") and int(t * 2.0) % 2 == 0 else Color8(40, 38, 56))
	top.draw_rect(Rect2(hr.position + Vector2(1, 1), Vector2(hr.size.x - 2, 1)), Color(1, 1, 1, 0.2))
	var hic := UI.tex("res://assets/sprites/icon/i_help.png")
	if hic:
		top.draw_texture(hic, (hr.position + (hr.size - hic.get_size()) * 0.5).floor())
	# speed buttons
	var labels := ["pause", "1", "2", "3"]
	for i in speed_rects.size():
		var r: Rect2 = speed_rects[i]
		var active: bool = (i == 0 and run.paused) or (i > 0 and not run.paused and run.speed == i)
		top.draw_rect(r, UI.COL.ink)
		top.draw_rect(r.grow(-1), Color8(96, 70, 40) if active else Color8(40, 38, 56))
		top.draw_rect(Rect2(r.position + Vector2(1, 1), Vector2(r.size.x - 2, 1)), Color(1, 1, 1, 0.2))
		var c := UI.COL.yellow if active else UI.COL.text
		var cx := r.position.x + r.size.x * 0.5
		var cy := r.position.y + r.size.y * 0.5
		if i == 0:
			top.draw_rect(Rect2(cx - 3, cy - 3, 2, 6), c)
			top.draw_rect(Rect2(cx + 1, cy - 3, 2, 6), c)
		else:
			for k in i:
				var ox := cx - i * 2.0 + k * 4.0
				for yy in range(-3, 4):
					top.draw_line(Vector2(ox - 1, cy + yy), Vector2(ox - 1 + (3 - absi(yy)) * 0.7, cy + yy), c)


func _res(p: Vector2, icon: String, text: String, col: Color, pk: float) -> void:
	var tx := UI.tex(icon)
	if tx:
		top.draw_texture(tx, p + Vector2(0, 3 - pk * 0.5))
	var f := UI.font(9)
	top.draw_string(f, p + Vector2(11, 12 - pk), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col.lerp(Color.WHITE, clampf(pk * 0.3, 0.0, 1.0)))


static func _nine(ci: CanvasItem, tx: Texture2D, r: Rect2, m: int) -> void:
	if tx == null:
		ci.draw_rect(r, UI.COL.bg)
		return
	var ts := tx.get_size()
	var xs := [0.0, m, ts.x - m, ts.x]
	var ys := [0.0, m, ts.y - m, ts.y]
	var dx := [r.position.x, r.position.x + m, r.end.x - m, r.end.x]
	var dy := [r.position.y, r.position.y + m, r.end.y - m, r.end.y]
	for j in 3:
		for i in 3:
			var src := Rect2(xs[i], ys[j], xs[i + 1] - xs[i], ys[j + 1] - ys[j])
			var dst := Rect2(dx[i], dy[j], dx[i + 1] - dx[i], dy[j + 1] - dy[j])
			if dst.size.x > 0 and dst.size.y > 0:
				ci.draw_texture_rect_region(tx, dst, src)


# ================================================================ bottom
func _build_bottom() -> void:
	bottom = Control.new()
	bottom.position = Vector2(0, BOT_Y)
	bottom.size = Vector2(640, 64)
	bottom.mouse_filter = Control.MOUSE_FILTER_PASS
	bottom.draw.connect(_draw_bottom)
	bottom.gui_input.connect(_bottom_input)
	bottom.mouse_exited.connect(func(): hide_tooltip())
	root.add_child(bottom)
	hand_box = Control.new()
	hand_box.position = Vector2(126, 0)
	hand_box.size = Vector2(390, 64)
	hand_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(hand_box)


func _draw_bottom() -> void:
	_nine(bottom, UI.tex("res://assets/sprites/ui/panel_dark.png"), Rect2(-2, 0, 644, 66), 4)
	var f7 := UI.font(7)
	bottom.draw_string(f7, Vector2(6, 11), "유물", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UI.COL.dim)
	for i in sim.relics.size():
		var tx := UI.relic_icon(sim.relics[i])
		var p := Vector2(6 + (i % 6) * 19, 15 + int(i / 6) * 21)
		bottom.draw_rect(Rect2(p - Vector2(1, 1), Vector2(19, 19)), Color8(22, 20, 33))
		if tx:
			bottom.draw_texture(tx, p)
	if sim.relics.is_empty():
		bottom.draw_string(f7, Vector2(8, 30), "엘리트를 쓰러뜨려", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color8(80, 76, 100))
		bottom.draw_string(f7, Vector2(8, 40), "유물을 얻자", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color8(80, 76, 100))
	# train summary on the right
	var rx := 524.0
	bottom.draw_string(f7, Vector2(rx, 11), "열차 %d/%d량" % [sim.cars_behind(), sim.max_cars_total()], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UI.COL.dim)
	var k := 0
	for c: Sim.Car in sim.cars:
		if c.type == "loco":
			continue
		var tx := UI.tex("res://assets/sprites/train/%s.png" % c.type)
		if tx:
			var p := Vector2(rx + (k % 3) * 38, 15 + int(k / 3) * 14)
			bottom.draw_texture(tx, p)
		k += 1
	var mk := 0
	for m in sim.modc.keys():
		var ic := UI.mod_icon(m)
		var p2 := Vector2(rx + mk * 19, 44)
		if ic and mk < 6:
			bottom.draw_texture(ic, p2)
			if int(sim.modc[m]) > 1:
				bottom.draw_string(f7, p2 + Vector2(11, 17), str(sim.modc[m]), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UI.COL.yellow)
		mk += 1
	if sim.hand.is_empty() and drag_index < 0:
		var msg := "적을 처치하면 카드를 얻는다"
		var w := f7.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		bottom.draw_string(f7, Vector2(126 + (390 - w) * 0.5, 36), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color8(90, 86, 110))


func _bottom_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var mp: Vector2 = bottom.get_local_mouse_position()
		for i in sim.relics.size():
			var p := Vector2(6 + (i % 6) * 19, 15 + int(i / 6) * 21)
			if Rect2(p, Vector2(18, 18)).has_point(mp):
				var r: Dictionary = Defs.RELICS[sim.relics[i]]
				show_tooltip("[color=#ffcc66]%s[/color]\n%s" % [r.name, r.desc], get_viewport().get_mouse_position())
				return
		var k := 0
		for c: Sim.Car in sim.cars:
			if c.type == "loco":
				continue
			var p := Vector2(524 + (k % 3) * 38, 15 + int(k / 3) * 14)
			if Rect2(p, Vector2(34, 12)).has_point(mp):
				show_tooltip(car_tip(c.type), get_viewport().get_mouse_position())
				return
			k += 1
		var mk := 0
		for m in sim.modc.keys():
			if Rect2(Vector2(524 + mk * 19, 44), Vector2(18, 18)).has_point(mp):
				show_tooltip("[color=#ffcc66]%s[/color] x%d\n%s" % [Defs.MODULES[m].name, sim.modc[m], Defs.MODULES[m].desc], get_viewport().get_mouse_position())
				return
			mk += 1
		hide_tooltip()


func car_tip(type: String) -> String:
	var d: Dictionary = Defs.CARS[type]
	var s := "[color=#ffcc66]%s[/color]  선체 +%d\n%s" % [d.name, int(d.hull), d.desc]
	if d.has("weapon"):
		var w: Dictionary = d.weapon
		s += "\n[color=#8a86a0]피해 %s · 초당 %s회 · 사거리 %d[/color]" % [str(w.dmg), str(w.rate), int(w.range)]
	return s


# ================================================================ hand
func rebuild_hand() -> void:
	for c in cards:
		(c as CardView).queue_free()
	cards.clear()
	hover_card = null
	var n := sim.hand.size()
	for i in n:
		var cv := CardView.new(sim.hand[i], i)
		cv.pressed.connect(_on_card_pressed)
		cv.hovered.connect(_on_card_hover)
		cv.right_clicked.connect(_on_card_right)
		hand_box.add_child(cv)
		cards.append(cv)
		if i == drag_index:
			cv.modulate.a = 0.25
	hand_sig = ",".join(sim.hand)
	_layout_hand(true)


func _layout_hand(instant := false) -> void:
	var n := cards.size()
	var spacing := 49.0 if n <= 7 else 390.0 / n
	var total := spacing * (n - 1) + 48.0 if n > 0 else 0.0
	var x0 := (390.0 - total) * 0.5
	for i in n:
		var cv: CardView = cards[i]
		var target := Vector2(x0 + i * spacing, 1.0 - (6.0 if cv == hover_card and drag_index < 0 else 0.0))
		if instant:
			cv.position = target
		else:
			cv.position = cv.position.lerp(target, 0.35)


func card_arrived(id: String) -> void:
	# newest card pops in
	rebuild_hand()
	if cards.size() > 0:
		var cv: CardView = cards[cards.size() - 1]
		if cv.card_id == id:
			cv.scale = Vector2(1.5, 1.5)
			cv.position.y -= 30
			var tw := cv.create_tween()
			tw.tween_property(cv, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_card_pressed(cv: CardView) -> void:
	if modal != null or sim.state != "running":
		return
	drag_index = cv.index
	cv.modulate.a = 0.25
	drag_ghost = CardView.new(cv.card_id, cv.index)
	drag_ghost.ghost = true
	drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(drag_ghost)
	drag_ghost.position = get_viewport().get_mouse_position() - CardView.SIZE * 0.5
	drag_ghost.scale = Vector2(1.1, 1.1)
	hide_tooltip()
	Audio.sfx("card_pick", -4.0)
	run.begin_drag(cv.card_id)


func _on_card_hover(cv: CardView, on: bool) -> void:
	if drag_index >= 0:
		return
	if on:
		hover_card = cv
		var p := cv.get_global_rect().position + Vector2(24, -4)
		show_tooltip(card_tip(cv.card_id), p, true)
		Audio.sfx("hover", -16.0)
	elif hover_card == cv:
		hover_card = null
		hide_tooltip()


func _on_card_right(cv: CardView) -> void:
	if drag_index >= 0 or modal != null:
		return
	if run.tutorial and not run.tutorial.can_discard():
		return
	if sim.discard_card(cv.index):
		toast("카드 버림 → 고철 +2", UI.COL.yellow)
		Audio.sfx("discard", -4.0)
		rebuild_hand()


func card_tip(id: String) -> String:
	if id.begins_with("car:"):
		var s := car_tip(id.substr(4))
		if sim.cars_behind() >= sim.max_cars_total():
			s += "\n[color=#ff7070]차량이 가득 찼다. 기존 차량 위에 놓으면 교체 (+고철 10)[/color]"
		else:
			s += "\n[color=#60d4ec]열차로 끌어다 놓아 연결[/color]"
		return s
	if id.begins_with("mod:"):
		var m: Dictionary = Defs.MODULES[id.substr(4)]
		return "[color=#ffcc66]%s[/color]  개조\n%s\n[color=#60d4ec]열차로 끌어다 놓아 장착[/color]" % [m.name, m.desc]
	var d: Dictionary = Defs.FACILITIES[id]
	var cat: String = d.cat
	var col: Color = UI.CAT_COL.get(cat, Color.WHITE)
	var s2 := "[color=#%s]%s[/color]  [color=#8a86a0]%s[/color]\n%s" % [col.to_html(false), d.name, UI.CAT_NAME.get(cat, ""), d.desc]
	if d.has("evo"):
		s2 += "\n[color=#b8f0ff]진화: %s[/color]" % d.evo
	var nz := float(d.noise)
	if nz > 0:
		s2 += "\n[color=#ff78aa]군세 +%s/바퀴[/color]" % (str(int(nz)) if absf(nz - round(nz)) < 0.01 else "%.1f" % nz)
	if id == "purge":
		s2 += "\n[color=#60d4ec]시설 위에 끌어다 놓기[/color]"
	else:
		s2 += "\n[color=#60d4ec]선로 옆 빈 부지에 끌어다 놓기[/color]"
	s2 += "\n[color=#5a5670]우클릭: 버리기 (+고철 2)[/color]"
	return s2


func end_drag(placed: bool) -> void:
	if drag_ghost:
		drag_ghost.queue_free()
		drag_ghost = null
	drag_index = -1
	rebuild_hand()
	hide_tooltip()
	if not placed:
		Audio.sfx("card_back", -8.0)


# ================================================================ tooltip / toasts / banners
func _build_tooltip() -> void:
	tooltip = UI.panel(false)
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip.visible = false
	tooltip.z_index = 20
	tip_text = UI.rich(11)
	tip_text.custom_minimum_size = Vector2(150, 0)
	tip_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	tooltip.add_child(tip_text)
	# tooltips sit above the tutorial spotlight so drag previews stay readable during lessons
	var tl := CanvasLayer.new()
	tl.layer = 16
	add_child(tl)
	tl.add_child(tooltip)


func show_tooltip(bb: String, at: Vector2, above := false) -> void:
	tip_text.text = bb
	tooltip.visible = true
	tooltip.reset_size()
	var sz := tooltip.get_combined_minimum_size()
	var p := at + Vector2(10, 10)
	if above:
		p = at - Vector2(sz.x * 0.5, sz.y + 2)
	p.x = clampf(p.x, 2, 640 - sz.x - 2)
	p.y = clampf(p.y, 2, 360 - sz.y - 2)
	tooltip.position = p.floor()


func hide_tooltip() -> void:
	tooltip.visible = false


func toast(text: String, col: Color = UI.COL.text) -> void:
	var l := UI.label(text, 9, col)
	toast_box.add_child(l)
	if toast_box.get_child_count() > 7:
		toast_box.get_child(0).queue_free()
	l.modulate.a = 0.0
	var tw := l.create_tween()
	tw.tween_property(l, "modulate:a", 1.0, 0.15)
	tw.tween_interval(3.2)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)


func show_banner(text: String, sub := "", col: Color = UI.COL.white, hold := 1.6) -> void:
	banner.text = text
	banner.add_theme_color_override("font_color", col)
	banner.visible = true
	banner.modulate.a = 1.0
	banner.scale = Vector2(1.6, 1.6)
	banner_sub.text = sub
	banner_sub.visible = sub != ""
	banner_sub.modulate.a = 0.0
	var tw := banner.create_tween()
	tw.tween_property(banner, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(banner_sub, "modulate:a", 1.0, 0.3)
	tw.tween_interval(hold)
	tw.tween_property(banner, "modulate:a", 0.0, 0.4)
	tw.parallel().tween_property(banner_sub, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func():
		banner.visible = false
		banner_sub.visible = false)


func _build_subtitle() -> void:
	subtitle = UI.panel(true)
	subtitle.position = Vector2(120, BOT_Y - 44)
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	subtitle.add_child(hb)
	sub_portrait = TextureRect.new()
	sub_portrait.custom_minimum_size = Vector2(28, 28)
	sub_portrait.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	hb.add_child(sub_portrait)
	sub_label = UI.rich(11)
	sub_label.custom_minimum_size = Vector2(330, 28)
	sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hb.add_child(sub_label)
	subtitle.visible = false
	root.add_child(subtitle)


## radio chatter: short diegetic lines instead of tutorial popups
func radio(text: String, who := "dispatcher", hold := 4.5) -> void:
	sub_portrait.texture = UI.tex("res://assets/sprites/portrait/%s_s.png" % who)
	sub_full = text
	sub_shown = 0.0
	sub_t = hold + text.length() * 0.03
	subtitle.visible = true
	subtitle.modulate.a = 1.0
	sub_label.text = ""
	Audio.sfx("radio_blip", -8.0)


# ================================================================ boss bar
func _draw_boss_bar() -> void:
	if sim.boss_parts.is_empty():
		return
	var f7 := UI.font(7)
	boss_bar.draw_rect(Rect2(0, 0, 300, 14), Color8(12, 10, 20, 230))
	boss_bar.draw_string(f7, Vector2(4, 10), "검은 열차", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color8(255, 90, 90))
	var x := 50.0
	for bp: Sim.BossPart in sim.boss_parts:
		var w := 90.0 if bp.kind == "head" else 48.0
		var k := clampf(bp.hp / bp.max_hp, 0.0, 1.0)
		boss_bar.draw_rect(Rect2(x, 4, w, 6), Color8(50, 20, 26))
		var col := Color8(230, 50, 60) if bp.kind == "head" else Color8(200, 90, 60)
		if bp.kind == "head" and sim._boss_cars_alive() > 0:
			col = Color8(150, 60, 70)
		boss_bar.draw_rect(Rect2(x, 4, round(w * k), 6), col if bp.flash <= 0.0 else Color.WHITE)
		boss_bar.draw_rect(Rect2(x, 4, w, 6), Color8(12, 10, 20), false)
		x += w + 3.0
	if sim._boss_cars_alive() > 0:
		boss_bar.draw_string(f7, Vector2(52, 22), "호위 차량이 살아있는 동안 기관차 피해 절반", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color8(200, 150, 150))


# ================================================================ per-frame
func _process(delta: float) -> void:
	t += delta
	# animated numbers
	if sim.hull < d_hull:
		d_hull = sim.hull
		punch_hull = 2.0
	else:
		d_hull = move_toward(d_hull, sim.hull, delta * sim.max_hull * 0.8)
	d_chip = move_toward(d_chip, d_hull, delta * sim.max_hull * (0.3 if d_chip - d_hull < 20 else 0.8)) if d_chip > d_hull else d_hull
	if int(round(d_scrap)) != sim.scrap:
		if sim.scrap > d_scrap:
			punch_scrap = 2.0
		d_scrap = move_toward(d_scrap, sim.scrap, maxf(1.0, absf(sim.scrap - d_scrap) * delta * 8.0))
	if int(round(d_sup)) != sim.supplies:
		punch_sup = 2.0
		d_sup = sim.supplies
	if absf(d_horde - sim.horde) > 0.05:
		if sim.horde > d_horde:
			punch_horde = 2.0
		d_horde = move_toward(d_horde, sim.horde, delta * 30.0)
	punch_scrap = maxf(0.0, punch_scrap - delta * 10.0)
	punch_sup = maxf(0.0, punch_sup - delta * 10.0)
	punch_surv = maxf(0.0, punch_surv - delta * 10.0)
	punch_hull = maxf(0.0, punch_hull - delta * 10.0)
	punch_horde = maxf(0.0, punch_horde - delta * 6.0)
	top.queue_redraw()
	bottom.queue_redraw()
	boss_bar.visible = sim.boss_active
	if boss_bar.visible:
		boss_bar.queue_redraw()
	if ",".join(sim.hand) != hand_sig and drag_index < 0:
		rebuild_hand()
	_layout_hand()
	if drag_ghost:
		var target := get_viewport().get_mouse_position() - CardView.SIZE * 0.5
		drag_ghost.position = drag_ghost.position.lerp(target, 0.6)
	# subtitle typewriter
	if subtitle.visible:
		sub_t -= delta
		if sub_shown < sub_full.length():
			sub_shown += delta * 40.0
			sub_label.text = sub_full.substr(0, int(sub_shown))
			if int(sub_shown) % 3 == 0:
				Audio.sfx("type", -22.0)
		if sub_t <= 0.0:
			subtitle.modulate.a = maxf(0.0, subtitle.modulate.a - delta * 2.0)
			if subtitle.modulate.a <= 0.0:
				subtitle.visible = false


func punch_survivors() -> void:
	punch_surv = 2.0
