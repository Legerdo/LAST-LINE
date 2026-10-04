extends Control
## Title screen: key art with rain, pulsing headlights and the logo.

var fx: FX
var t := 0.0
var lights: Array = []
var logo: Label
var menu: VBoxContainer
var settings_panel: Control = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := TextureRect.new()
	bg.texture = UI.tex("res://assets/sprites/ui/keyart.png")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	# headlight glow
	for p in [Vector2(210, 174), Vector2(235, 174)]:
		var s := Sprite2D.new()
		s.texture = UI.tex("res://assets/sprites/fx/light.png")
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		s.material = m
		s.position = p
		s.scale = Vector2(0.5, 0.5)
		s.modulate = Color(1.0, 0.9, 0.6, 0.5)
		add_child(s)
		lights.append(s)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.06, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	fx = FX.new()
	add_child(fx)
	logo = UI.label("LAST LINE", 12, Color8(255, 236, 200))
	logo.scale = Vector2(4, 4)
	logo.position = Vector2(320 - 34 * 4, 34)
	add_child(logo)
	var sub := UI.label("마 지 막   노 선", 11, Color8(255, 120, 150))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.size = Vector2(640, 14)
	sub.position = Vector2(0, 92)
	add_child(sub)
	menu = VBoxContainer.new()
	menu.position = Vector2(250, 250)
	menu.size = Vector2(140, 80)
	menu.add_theme_constant_override("separation", 4)
	add_child(menu)
	var first := int(Game.profile.runs) == 0
	var start := UI.button("첫 운행 시작" if first else "차량기지로", 11, true)
	start.custom_minimum_size = Vector2(140, 22)
	start.pressed.connect(func(): Game.goto("run" if first else "hub"))
	menu.add_child(start)
	var opt := UI.button("설정", 11)
	opt.pressed.connect(_toggle_settings)
	menu.add_child(opt)
	var quit := UI.button("종료", 11)
	quit.pressed.connect(func(): get_tree().quit())
	menu.add_child(quit)
	var foot := UI.label("카드를 끌어 선로 옆에 놓으세요 · Space 일시정지 · 1/2/3 속도", 7, Color8(150, 146, 170))
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.size = Vector2(640, 10)
	foot.position = Vector2(0, 346)
	add_child(foot)
	if int(Game.profile.runs) > 0:
		var rec := UI.label("운행 %d회 · 최고 %d바퀴 · 격파 %d회" % [int(Game.profile.runs), int(Game.profile.best_loop), int(Game.profile.wins)], 7, Color8(180, 176, 200))
		rec.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rec.size = Vector2(640, 10)
		rec.position = Vector2(0, 332)
		add_child(rec)
	Audio.music("title")


func _toggle_settings() -> void:
	if settings_panel:
		settings_panel.queue_free()
		settings_panel = null
		return
	var p := UI.panel()
	p.position = Vector2(400, 230)
	var vb := VBoxContainer.new()
	p.add_child(vb)
	for pair in [["효과음", "sfx"], ["음악", "music"], ["음성", "voice"], ["화면 흔들림", "shake"]]:
		var row := HBoxContainer.new()
		var l := UI.label(pair[0], 9)
		l.custom_minimum_size = Vector2(64, 0)
		row.add_child(l)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.value = float(Game.setting(pair[1], 1.0))
		sl.custom_minimum_size = Vector2(100, 12)
		var key: String = pair[1]
		sl.value_changed.connect(func(v): Game.set_setting(key, v))
		row.add_child(sl)
		vb.add_child(row)
	var fs := CheckButton.new()
	fs.text = "전체 화면"
	fs.add_theme_font_override("font", UI.font(9))
	fs.add_theme_font_size_override("font_size", 10)
	fs.focus_mode = Control.FOCUS_NONE
	fs.button_pressed = bool(Game.setting("fullscreen", false))
	fs.toggled.connect(func(on): Game.set_setting("fullscreen", on))
	vb.add_child(fs)
	var tut := UI.button("튜토리얼 다시 보기", 9)
	tut.pressed.connect(func():
		Game.reset_tutorial()
		tut.text = "다음 운행에서 튜토리얼 시작"
		tut.disabled = true)
	vb.add_child(tut)
	var reset := UI.button("기록 초기화", 9)
	reset.pressed.connect(func():
		Game.reset_profile()
		Game.goto("title"))
	vb.add_child(reset)
	add_child(p)
	settings_panel = p


func _process(delta: float) -> void:
	t += delta
	for i in lights.size():
		var s: Sprite2D = lights[i]
		s.modulate.a = 0.45 + 0.15 * sin(t * 3.0 + i)
	# rain
	for k in 3:
		var x := randf_range(-40, 660)
		fx.burst(Vector2(x, -4), 1, Color(0.6, 0.7, 0.9, 0.5), Color(0.5, 0.6, 0.9, 0.0), 1.0, 1.2, 1.0, 0.0, 0.0, 0.0, 0.0)
		(fx.parts[fx.parts.size() - 1] as FX.P).vel = Vector2(-40, 260)
	logo.position.y = 34 + round(sin(t * 1.2) * 1.0)


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and (ev.keycode == KEY_ENTER or ev.keycode == KEY_SPACE):
		Game.goto("run" if int(Game.profile.runs) == 0 else "hub")
