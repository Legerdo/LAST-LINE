class_name FocusOverlay
extends Control
## Tutorial spotlight: dims the screen except one or more target rects, frames and points at
## them, optionally animates a ghost hand dragging from A to B, and shows the dispatcher's
## instruction box (Next / Skip, or a prompt while waiting for the player's action).
## Text lines never auto-wrap (Korean would split mid-word): the box sizes itself to the
## explicit lines and is placed where it covers neither the targets nor (drag steps) the hand.

signal next_pressed
signal skip_pressed

const HAND_AREA := Rect2(120, 294, 400, 66)
const HUD_BOTTOM := 294.0

var target := Callable()        # -> Rect2 or Array[Rect2] in screen space
var arrow_target := Callable()  # optional -> Rect2 / Array: what the bouncing arrow points at
var hand_from := Callable()     # -> Vector2
var hand_to := Callable()       # -> Vector2
var blocking := true
var keep_hand_clear := false
var dock := ""                  # "", "top" or "bottom"
var active := false
var t := 0.0
var auto_close := 0.0
var shake_t := 0.0
var dim_rect: ColorRect
var dim_mat: ShaderMaterial
var box: PanelContainer
var text_label: RichTextLabel
var tag_label: Label
var prompt_icon: TextureRect
var prompt_label: Label
var next_btn: Button
var skip_btn: Button
var hand_tex: Texture2D
var arrow_tex: Texture2D
var card_tex: Texture2D
var _placed_for := -1.0
var _box_pos := Vector2.ZERO
var _fade: Tween
var _bb := RegEx.create_from_string("\\[/?[a-zA-Z_]+(=[^\\]]*)?\\]")


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hand_tex = UI.tex("res://assets/sprites/icon/i_hand.png")
	arrow_tex = UI.tex("res://assets/sprites/icon/i_arrow.png")
	dim_rect = ColorRect.new()
	dim_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim_mat = ShaderMaterial.new()
	dim_mat.shader = load("res://src/ui/focus_dim.gdshader")
	dim_rect.material = dim_mat
	add_child(dim_rect)
	box = UI.panel(false)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.custom_minimum_size = Vector2(240, 0)
	add_child(box)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	box.add_child(hb)
	var por := TextureRect.new()
	por.texture = UI.tex("res://assets/sprites/portrait/dispatcher.png")
	por.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	por.custom_minimum_size = Vector2(54, 50)
	por.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	hb.add_child(por)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vb)
	text_label = UI.rich(11)
	text_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	vb.add_child(text_label)
	# bottom row: [hand icon + what to do | speaker tag] ...... [skip] [next]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	vb.add_child(row)
	prompt_icon = TextureRect.new()
	prompt_icon.texture = hand_tex
	prompt_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	prompt_icon.custom_minimum_size = Vector2(12, 14)
	prompt_icon.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(prompt_icon)
	prompt_label = UI.label("", 9, UI.COL.yellow)
	prompt_label.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(prompt_label)
	tag_label = UI.label("관제실", 7, UI.COL.green)
	tag_label.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(tag_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	skip_btn = UI.button("튜토리얼 건너뛰기", 7)
	skip_btn.size_flags_vertical = Control.SIZE_SHRINK_END
	skip_btn.pressed.connect(func(): skip_pressed.emit())
	row.add_child(skip_btn)
	next_btn = UI.button("다음", 11, true)
	next_btn.custom_minimum_size = Vector2(64, 18)
	next_btn.size_flags_vertical = Control.SIZE_SHRINK_END
	next_btn.pressed.connect(func(): next_pressed.emit())
	row.add_child(next_btn)
	visible = false


## opts: next (String, "" = wait for action), prompt, block (bool), hand ([Callable, Callable]),
##       skip (bool), auto (seconds; non-blocking tips close themselves), card (card id for the
##       ghost), arrow (Callable -> Rect2/Array), dock ("top"/"bottom"), count ("3/9")
func show_step(bb: String, target_fn: Callable, opts: Dictionary = {}) -> void:
	active = true
	visible = true
	t = 0.0
	shake_t = 0.0
	_placed_for = -1.0
	target = target_fn
	arrow_target = opts.get("arrow", Callable())
	dock = String(opts.get("dock", ""))
	blocking = bool(opts.get("block", true))
	mouse_filter = Control.MOUSE_FILTER_STOP if blocking else Control.MOUSE_FILTER_IGNORE
	dim_mat.set_shader_parameter("dim", 0.62 if blocking else 0.4)
	auto_close = float(opts.get("auto", 0.0))
	var hand: Array = opts.get("hand", [])
	hand_from = hand[0] if hand.size() == 2 else Callable()
	hand_to = hand[1] if hand.size() == 2 else Callable()
	keep_hand_clear = hand.size() == 2
	card_tex = null
	if opts.has("card"):
		card_tex = UI.tex("res://assets/sprites/ui/card_%s.png" % UI.card_cat(String(opts.card)))
	text_label.text = bb
	text_label.custom_minimum_size = text_size(bb)
	var nx: String = opts.get("next", "다음")
	next_btn.visible = nx != ""
	next_btn.text = nx
	var tag := "관제실"
	if opts.has("count"):
		tag += "  " + String(opts.count)
	tag_label.text = tag
	_set_prompt(String(opts.get("prompt", "")))
	skip_btn.visible = bool(opts.get("skip", false))
	# fade in a moment later so the first layout pass has settled (no visible jump)
	if _fade and _fade.is_valid():
		_fade.kill()
	box.modulate.a = 0.0
	_fade = box.create_tween()
	_fade.tween_interval(0.05)
	_fade.tween_property(box, "modulate:a", 1.0, 0.15)
	Audio.sfx("radio_blip", -8.0)
	_place_box()


func hide_step() -> void:
	active = false
	visible = false
	target = Callable()
	arrow_target = Callable()
	hand_from = Callable()
	hand_to = Callable()
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## little shake + message when the player tries something the step does not allow
func nudge(msg: String) -> void:
	_set_prompt(msg)
	_place_box()
	shake_t = 0.35
	Audio.sfx("bad", -10.0)


func _set_prompt(p: String) -> void:
	prompt_label.text = p
	prompt_label.visible = p != ""
	prompt_icon.visible = p != ""
	tag_label.visible = p == ""


## pixel size of explicit BBCode lines in the box font (the label never wraps)
func text_size(bb: String) -> Vector2:
	var f := UI.font(11)
	var px := UI.px(11)
	var lines := bb.split("\n")
	var w := 0.0
	for ln in lines:
		w = maxf(w, f.get_string_size(_bb.sub(ln, "", true), HORIZONTAL_ALIGNMENT_LEFT, -1, px).x)
	return Vector2(ceilf(w) + 2.0, f.get_height(px) * lines.size())


func holes() -> Array:
	return _rects_of(target)


func _rects_of(fn: Callable) -> Array:
	if not fn.is_valid():
		return []
	var r = fn.call()
	var out: Array = []
	if r is Rect2:
		if (r as Rect2).size != Vector2.ZERO:
			out.append(r)
	elif r is Array:
		for x in r:
			if x is Rect2 and (x as Rect2).size != Vector2.ZERO:
				out.append(x)
	return out


func _bounds(hs: Array) -> Rect2:
	var b := Rect2()
	for h: Rect2 in hs:
		b = h if b.size == Vector2.ZERO else b.merge(h)
	return b


func _place_box() -> void:
	box.reset_size()
	var sz := box.get_combined_minimum_size()
	box.size = sz
	var hs := holes()
	var b := _bounds(hs)
	var cx := clampf(320.0 - sz.x * 0.5, 4.0, 636.0 - sz.x)
	var pick := Vector2(cx, 120.0)
	if dock != "":
		var ax := b.get_center().x if b.size != Vector2.ZERO else 320.0
		pick = Vector2(clampf(ax - sz.x * 0.5, 4.0, 636.0 - sz.x), 3.0 if dock == "top" else 357.0 - sz.y)
	elif b.size != Vector2.ZERO:
		var avoid: Array = []
		var in_top := false
		var in_bottom := false
		for h: Rect2 in hs:
			avoid.append(h.grow(6))
			in_top = in_top or h.get_center().y < 24.0
			in_bottom = in_bottom or h.get_center().y > HUD_BOTTOM
		if keep_hand_clear:
			avoid.append(HAND_AREA)
		# keep the HUD strips readable unless the lesson is about them
		if not in_top:
			avoid.append(Rect2(0, 0, 640, 23))
		if not in_bottom:
			avoid.append(Rect2(0, HUD_BOTTOM, 640, 66))
		var bx := clampf(b.get_center().x - sz.x * 0.5, 4.0, 636.0 - sz.x)
		var sy := clampf(b.get_center().y - sz.y * 0.5, 26.0, 292.0 - sz.y)
		# prefer staying near the target: above, below, the sides, then free screen areas
		var cands: Array = [
			Vector2(bx, b.position.y - sz.y - 18.0), Vector2(bx, b.end.y + 18.0),
			Vector2(b.end.x + 16.0, sy), Vector2(b.position.x - sz.x - 16.0, sy),
			Vector2(cx, 26.0), Vector2(cx, 292.0 - sz.y), Vector2(4.0, 26.0), Vector2(636.0 - sz.x, 26.0),
			Vector2(4.0, 292.0 - sz.y), Vector2(636.0 - sz.x, 292.0 - sz.y)]
		pick = cands[4]
		for c: Vector2 in cands:
			var r := Rect2(c, sz)
			if r.position.x < 2.0 or r.position.y < 2.0 or r.end.x > 638.0 or r.end.y > 358.0:
				continue
			var ok := true
			for a: Rect2 in avoid:
				if r.intersects(a):
					ok = false
					break
			if ok:
				pick = c
				break
	_box_pos = pick.floor()
	box.position = _box_pos


func _process(delta: float) -> void:
	if not active or not visible:
		return
	t += delta
	shake_t = maxf(0.0, shake_t - delta)
	# settle during the first frames, then follow moving targets (the train) a few times a second
	if t < 0.12 or t - _placed_for > 0.25:
		_placed_for = t
		_place_box()
	box.position = _box_pos + Vector2(roundf(sin(t * 60.0) * 2.0) if shake_t > 0.0 else 0.0, 0.0)
	if auto_close > 0.0 and t >= auto_close:
		auto_close = 0.0
		next_pressed.emit()
		return
	var hs := holes()
	var packed: Array = []
	for i in mini(hs.size(), 6):
		var g: Rect2 = (hs[i] as Rect2).grow(2)
		packed.append(Vector4(g.position.x, g.position.y, g.size.x, g.size.y))
	while packed.size() < 6:
		packed.append(Vector4.ZERO)
	dim_mat.set_shader_parameter("holes", packed)
	dim_mat.set_shader_parameter("hole_count", mini(hs.size(), 6))
	queue_redraw()


func _draw() -> void:
	if not active:
		return
	var hs := holes()
	var pulse := 0.55 + 0.45 * sin(t * 6.0)
	for h: Rect2 in hs:
		var g := h.grow(2)
		draw_rect(g.grow(-0.5), Color(1.0, 0.85, 0.35, 0.5 + 0.5 * pulse), false, 1.0)
		var e := g.grow(roundf(1.0 + 1.5 * pulse))
		var L := 6.0
		for c in [[e.position, Vector2(1, 0), Vector2(0, 1)], [Vector2(e.end.x, e.position.y), Vector2(-1, 0), Vector2(0, 1)],
				[Vector2(e.position.x, e.end.y), Vector2(1, 0), Vector2(0, -1)], [e.end, Vector2(-1, 0), Vector2(0, -1)]]:
			draw_line(c[0], c[0] + c[1] * L, Color(1, 0.95, 0.7), 1.0)
			draw_line(c[0], c[0] + c[2] * L, Color(1, 0.95, 0.7), 1.0)
	var aim := _arrow_rect(hs)
	if aim.size != Vector2.ZERO:
		_draw_arrow(aim.grow(2))
	_draw_hand()


## the arrow points at the destination: with a card + lot spotlight, at the lot, not the hand
func _arrow_rect(hs: Array) -> Rect2:
	if arrow_target.is_valid():
		return _bounds(_rects_of(arrow_target))
	var world: Array = []
	for h: Rect2 in hs:
		if h.get_center().y < HUD_BOTTOM:
			world.append(h)
	return _bounds(world if not world.is_empty() else hs)


func _draw_arrow(g: Rect2) -> void:
	if arrow_tex == null:
		return
	var bob := roundf(sin(t * 7.0) * 2.0)
	var sz := arrow_tex.get_size()
	var cx := g.get_center().x
	var box_r := Rect2(_box_pos, box.size)
	var up_pos := Vector2(cx - sz.x * 0.5, g.position.y - sz.y - 4.0 + bob).floor()
	# point down from above unless that spot is off-screen or under the instruction box
	if g.position.y > sz.y + 8.0 and not Rect2(up_pos, sz).intersects(box_r):
		draw_texture(arrow_tex, up_pos)
	else:
		draw_set_transform(Vector2(cx + sz.x * 0.5, g.end.y + sz.y + 4.0 - bob).floor(), PI, Vector2.ONE)
		draw_texture(arrow_tex, Vector2.ZERO)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_hand() -> void:
	if hand_tex == null or not hand_from.is_valid() or not hand_to.is_valid():
		return
	var a: Vector2 = hand_from.call()
	var b: Vector2 = hand_to.call()
	if a == Vector2.ZERO or b == Vector2.ZERO:
		return
	var cycle := fmod(t, 2.2)
	var p := a
	var pressed := false
	var alpha := 1.0
	if cycle < 0.35:
		p = a
		pressed = cycle > 0.2
	elif cycle < 1.45:
		var k := (cycle - 0.35) / 1.1
		k = k * k * (3.0 - 2.0 * k)
		p = a.lerp(b, k) + Vector2(0, -sin(k * PI) * 14.0)
		pressed = true
	elif cycle < 1.75:
		p = b
		pressed = cycle < 1.55
	else:
		p = b
		alpha = 1.0 - (cycle - 1.75) / 0.45
	if pressed and card_tex:
		# a small translucent card travels with the finger
		var cs := card_tex.get_size() * 0.5
		draw_texture_rect(card_tex, Rect2((p - cs * 0.5 + Vector2(-6, -10)).floor(), cs), false, Color(1, 1, 1, 0.55 * alpha))
	var off := Vector2(-2, -1) if not pressed else Vector2(-2, 1)
	draw_texture(hand_tex, (p + off).floor(), Color(1, 1, 1, alpha))
	if pressed:
		draw_arc(p.floor(), 4.0 + fmod(t * 8.0, 3.0), 0, TAU, 12, Color(1, 0.9, 0.5, 0.6 * alpha), 1.0)
