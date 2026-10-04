extends Control
## The depot base between runs: spend banked scrap and survivors on permanent upgrades.
## The depot art stays visible; upgrades sit in a panel along the bottom.

const GROUPS := [
	["열차", ["hull", "flame", "mortar", "armor", "repair", "tesla"]],
	["노선 기술", ["greenhouse", "armory", "power", "radio", "gunworks", "signal"]],
	["기지", ["barracks", "store", "coupler", "window"]],
]
const ICONS := {
	"hull": "icon/plate", "flame": "train/flame", "mortar": "train/mortar", "armor": "train/armor",
	"repair": "train/repair", "tesla": "train/tesla", "greenhouse": "fac/greenhouse", "armory": "fac/armory",
	"power": "fac/power", "radio": "fac/radio", "gunworks": "train/gun", "signal": "icon/mic",
	"barracks": "enemy/survivor", "store": "icon/crate", "coupler": "icon/coupler", "window": "icon/cardback",
}
const UPGRADE_TIP_WIDTH := 286.0

var res_label: RichTextLabel
var tip: PanelContainer
var tip_text: RichTextLabel
var cols: Array = []
var fx: FX
var t := 0.0
var spark_t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := TextureRect.new()
	var tex := UI.tex("res://assets/sprites/ui/hub_bg.png")
	bg.texture = tex if tex else UI.tex("res://assets/sprites/ui/keyart.png")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	fx = FX.new()
	add_child(fx)
	var head := UI.panel(true)
	head.position = Vector2(6, 6)
	head.custom_minimum_size = Vector2(628, 0)
	add_child(head)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	head.add_child(hb)
	hb.add_child(UI.label("차량기지", 12, UI.COL.yellow))
	res_label = UI.rich(11)
	res_label.custom_minimum_size = Vector2(300, 14)
	hb.add_child(res_label)
	var rec := UI.rich(9)
	rec.custom_minimum_size = Vector2(250, 12)
	var heat := mini(int(Game.profile.wins), 5)
	rec.text = "[color=#8a86a0]운행 %d · 격파 %d · 최고 %d바퀴[/color]%s" % [int(Game.profile.runs), int(Game.profile.wins), int(Game.profile.best_loop),
		("   [color=#ff6a6a]위협 등급 %d[/color]" % heat) if heat > 0 else ""]
	hb.add_child(rec)
	# last run card (left, over the art)
	var lr: Dictionary = Game.last_result
	if not lr.is_empty():
		var lp := UI.panel(true)
		lp.position = Vector2(8, 36)
		var l := UI.rich(9)
		l.custom_minimum_size = Vector2(150, 0)
		var st: String = {"dead": "[color=#ff6a6a]열차 파괴[/color]", "returned": "[color=#60d4ec]무사 귀환[/color]", "victory": "[color=#ffcc66]검은 열차 격파[/color]"}.get(lr.state, "")
		l.text = "지난 운행: %s\n%d바퀴 · 처치 %d\n[color=#ffcc66]+고철 %d[/color]  [color=#60d4ec]+생존자 %d[/color]" % [st, int(lr.loops), int(lr.kills), int(lr.scrap), int(lr.survivors)]
		lp.add_child(l)
		add_child(lp)
	# bottom panel
	var body := UI.panel()
	body.position = Vector2(6, 190)
	body.custom_minimum_size = Vector2(486, 164)
	body.self_modulate = Color(1, 1, 1, 0.94)
	add_child(body)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	body.add_child(row)
	for g in GROUPS:
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 1)
		vb.add_child(UI.label(g[0], 9, UI.COL.dim))
		row.add_child(vb)
		cols.append([vb, g[1]])
	# launch side
	var side := UI.panel()
	side.position = Vector2(498, 190)
	side.custom_minimum_size = Vector2(136, 164)
	add_child(side)
	var svb := VBoxContainer.new()
	svb.add_theme_constant_override("separation", 5)
	side.add_child(svb)
	var go := UI.button("출발  ▶", 12, true)
	go.custom_minimum_size = Vector2(124, 30)
	go.pressed.connect(func(): Game.goto("run"))
	svb.add_child(go)
	var info := UI.rich(9)
	info.custom_minimum_size = Vector2(124, 0)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var m := Game.sim_mods()
	var cars := ["기관총", "객차", "화물"]
	for c in m.cars:
		cars.append(String(Defs.CARS[c].name).replace("차", ""))
	var hull := int(Defs.BASE_HULL) + int(m.hull) + int(Defs.CARS.gun.hull) + int(Defs.CARS.cargo.hull) + (int(Defs.CARS.gun.hull) if m.extra_gun else 0)
	info.text = "[color=#8a86a0]출발 준비[/color]\n선체 %d · 생존자 %d\n보급품 %d · 카드 %d장\n[color=#8a86a0]보급 차량[/color]\n%s" % [
		hull, int(m.survivors), 10 + int(m.supplies), 4 + int(m.hand), ", ".join(cars)]
	svb.add_child(info)
	var back := UI.button("타이틀", 9)
	back.pressed.connect(func(): Game.goto("title"))
	svb.add_child(back)
	tip = UI.panel()
	tip.visible = false
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.z_index = 5
	tip.custom_minimum_size = Vector2(UPGRADE_TIP_WIDTH, 0)
	tip_text = UI.rich(11)
	tip_text.custom_minimum_size = Vector2(UPGRADE_TIP_WIDTH - 12.0, 0)
	tip_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tip.add_child(tip_text)
	add_child(tip)
	_refresh()
	Audio.music("hub")
	body_panel = body
	head_panel = head
	go_button = go
	var probe := OS.get_cmdline_user_args().has("--probe=hubwalk")
	if (int(Game.profile.runs) >= 1 or probe) and not Game.seen("hub_walk") and not Game.seen("tips_off"):
		_start_walk()
		if probe:
			_probe_walk()


# ------------------------------------------------------------ first-visit walkthrough
var body_panel: Control
var head_panel: Control
var go_button: Control
var walk: FocusOverlay
var walk_step := -1


func _start_walk() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 15
	add_child(layer)
	walk = FocusOverlay.new()
	layer.add_child(walk)
	walk.next_pressed.connect(_walk_next)
	walk.skip_pressed.connect(func():
		Game.mark_seen("hub_walk")
		walk.hide_step())
	_walk_next()


func _walk_next() -> void:
	walk_step += 1
	match walk_step:
		0:
			walk.show_step("여기는 우리 [color=#ffcc66]기지[/color]. 운행에서 가져온 자원이 쌓이는 곳이야.\n[color=#ffcc66]고철[/color]과 [color=#60d4ec]생존자[/color]는 귀환해야만 가져올 수 있어.",
				func() -> Rect2: return head_panel.get_global_rect().grow(1), {"skip": true, "count": "1/3"})
		1:
			walk.show_step("자원을 써서 기지를 키워. 새 [color=#ffcc66]차량[/color], [color=#60d4ec]시설 카드[/color],\n시작 자원이 해금돼. 어두운 칸은 엘리트의\n[color=#b8f0ff]설계도[/color]를 가지고 귀환해야 열려.",
				func() -> Rect2: return body_panel.get_global_rect().grow(1), {"skip": true, "count": "2/3"})
		2:
			walk.show_step("준비되면 [color=#ffcc66]출발[/color]. 운행할수록 기지가 커지고 열차가 강해져.\n막히면 운행 중에 [color=#60d4ec]?[/color] 버튼으로 도움말을 봐.",
				func() -> Rect2: return go_button.get_global_rect().grow(2), {"next": "알겠어", "count": "3/3"})
		_:
			Game.mark_seen("hub_walk")
			walk.hide_step()


## QA: --screen=hub --probe=hubwalk photographs each walkthrough step, then quits
func _probe_walk() -> void:
	var dir := ProjectSettings.globalize_path("res://art_src/shots/hub")
	DirAccess.make_dir_recursive_absolute(dir)
	for i in 3:
		await get_tree().create_timer(0.6).timeout
		get_viewport().get_texture().get_image().save_png(dir + "/walk_%d.png" % i)
		print("PROBE hub walk ", i, " active=", walk.active)
		_walk_next()
	await get_tree().create_timer(0.3).timeout
	print("PROBE hub walk done: active=", walk.active, " seen=", Game.seen("hub_walk"))
	get_tree().quit()


func _hint(text: String) -> void:
	var p := UI.panel(true)
	p.position = Vector2(170, 150)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	p.add_child(hb)
	var por := TextureRect.new()
	por.texture = UI.tex("res://assets/sprites/portrait/dispatcher_s.png")
	por.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	hb.add_child(por)
	var l := UI.rich(9)
	l.custom_minimum_size = Vector2(280, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.text = text
	hb.add_child(l)
	add_child(p)
	var tw := p.create_tween()
	tw.tween_interval(8.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)


func _refresh() -> void:
	res_label.text = "[color=#ffcc66]고철 %d[/color]   [color=#60d4ec]생존자 %d[/color]   [color=#b8f0ff]설계도 %d/3[/color]" % [int(Game.profile.scrap), int(Game.profile.survivors), (Game.profile.blueprints as Array).size()]
	for c in cols:
		var vb: VBoxContainer = c[0]
		for i in range(vb.get_child_count() - 1, 0, -1):
			vb.get_child(i).queue_free()
		for id in c[1]:
			vb.add_child(_tile(Game.upgrade_def(id)))


func _tile(u: Dictionary) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(158, 21)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", UI.style("res://assets/sprites/ui/button.png", 3, 3))
	b.add_theme_stylebox_override("hover", UI.style("res://assets/sprites/ui/button_hover.png", 3, 3))
	b.add_theme_stylebox_override("pressed", UI.style("res://assets/sprites/ui/button_hot.png", 3, 3))
	b.add_theme_stylebox_override("disabled", UI.style("res://assets/sprites/ui/button_off.png", 3, 3))
	var lv := Game.level(u.id)
	var maxed := lv >= int(u.max)
	var needs_bp := u.has("blueprint") and not (Game.profile.blueprints as Array).has(u.blueprint)
	var cost := Game.upgrade_cost(u)
	var can := Game.can_buy(u)
	var hb := HBoxContainer.new()
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 3
	hb.add_theme_constant_override("separation", 3)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(hb)
	var ic := TextureRect.new()
	ic.texture = UI.tex("res://assets/sprites/%s.png" % ICONS.get(u.id, "icon/wrench"))
	ic.custom_minimum_size = Vector2(34, 18)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	ic.clip_contents = true
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if needs_bp:
		ic.modulate = Color(0.2, 0.2, 0.3)
	hb.add_child(ic)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", -2)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(vb)
	var name_row := String(u.name)
	if int(u.max) > 1:
		var pips := ""
		for i in int(u.max):
			pips += "■" if i < lv else "□"
		name_row += " " + pips
	vb.add_child(UI.label(name_row, 9, UI.COL.green if maxed else (UI.COL.white if not needs_bp else UI.COL.dim)))
	var line := ""
	if maxed:
		line = "완료"
	elif needs_bp:
		line = "설계도 필요"
	else:
		line = "고철 %d" % int(cost[0]) + ((" · 생존자 %d" % int(cost[1])) if int(cost[1]) > 0 else "")
	vb.add_child(UI.label(line, 7, UI.COL.yellow if can else (UI.COL.green if maxed else UI.COL.dim)))
	b.disabled = not can
	b.mouse_entered.connect(func():
		var extra := ""
		if needs_bp:
			extra = "\n[color=#b8f0ff]엘리트를 쓰러뜨려 설계도를 얻고 귀환하면 해금[/color]"
		tip_text.text = "[color=#ffcc66]%s[/color]\n%s%s" % [u.name, u.desc, extra]
		tip.visible = true
		tip.reset_size()
		var p := b.get_global_rect().position - Vector2(0, tip.size.y + 2)
		var viewport_size := get_viewport_rect().size
		tip.position = Vector2(
			clampf(p.x, 2, viewport_size.x - tip.size.x - 2),
			clampf(p.y, 2, viewport_size.y - tip.size.y - 2)
		)
	)
	b.mouse_exited.connect(func(): tip.visible = false)
	b.pressed.connect(func():
		if Game.buy(u):
			Audio.sfx("build", -2.0)
			tip.visible = false
			var at := b.get_global_rect().get_center()
			fx.burst(at, 24, Color8(255, 230, 150), Color8(255, 150, 60, 0), 90.0, 0.5, 2.0, 60.0, 2.0)
			_refresh())
	return b


func _process(delta: float) -> void:
	t += delta
	spark_t -= delta
	# welding sparks at the workshop bench and the train
	if spark_t <= 0.0:
		spark_t = randf_range(0.05, 0.4)
		var p: Vector2 = [Vector2(165, 205), Vector2(172, 198), Vector2(410, 186)][randi() % 3]
		fx.burst(p, randi_range(3, 8), Color8(255, 250, 200), Color8(255, 140, 40, 0), 70.0, 0.4, 1.0, 160.0, 1.0, PI, -PI * 0.5)


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ENTER:
		Game.goto("run")
