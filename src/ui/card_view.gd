class_name CardView
extends Control
## One card in the hand (custom drawn so every pixel lands where it should).

signal pressed(card: CardView)
signal hovered(card: CardView, on: bool)
signal right_clicked(card: CardView)

const SIZE := Vector2(48, 62)

var card_id := ""
var index := -1
var is_hover := false
var ghost := false
var usable := true
var appear := 0.0
var glow_t := 0.0


func _init(id := "", idx := -1) -> void:
	card_id = id
	index = idx
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	pivot_offset = SIZE * 0.5


func _ready() -> void:
	mouse_entered.connect(func():
		is_hover = true
		hovered.emit(self, true)
		queue_redraw())
	mouse_exited.connect(func():
		is_hover = false
		hovered.emit(self, false)
		queue_redraw())


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit(self)
			accept_event()
		elif ev.button_index == MOUSE_BUTTON_RIGHT:
			right_clicked.emit(self)
			accept_event()


func _process(delta: float) -> void:
	glow_t += delta
	if is_hover or ghost:
		queue_redraw()


func _draw() -> void:
	var cat := UI.card_cat(card_id)
	var frame := UI.tex("res://assets/sprites/ui/card_%s.png" % cat)
	if frame:
		draw_texture(frame, Vector2.ZERO, Color(1, 1, 1, 0.55) if not usable else Color.WHITE)
	# art
	var icon := UI.card_icon(card_id)
	var win := Rect2(4, 13, 40, 34)
	if icon:
		var isz := icon.get_size()
		var pos := Vector2(win.position.x + (win.size.x - isz.x) * 0.5, win.end.y - isz.y - 1)
		if card_id.begins_with("car:"):
			pos.y = win.position.y + (win.size.y - isz.y) * 0.5
			draw_line(Vector2(win.position.x + 1, pos.y + isz.y * 0.5 + 0.5), Vector2(win.end.x - 1, pos.y + isz.y * 0.5 + 0.5), Color8(66, 62, 86), 3.0)
		elif card_id.begins_with("mod:"):
			pos = Vector2(win.position.x + (win.size.x - isz.x * 2.0) * 0.5, win.position.y + (win.size.y - isz.y * 2.0) * 0.5)
			draw_texture_rect(icon, Rect2(pos.floor(), isz * 2.0), false)
			icon = null
		if icon:
			# crop to the art window
			var src := Rect2(Vector2.ZERO, isz)
			var dst := Rect2(pos.floor(), isz)
			var clip := dst.intersection(win)
			if clip.size.x > 0 and clip.size.y > 0:
				var s2 := Rect2(src.position + (clip.position - dst.position), clip.size)
				draw_texture_rect_region(icon, clip, s2)
	# name
	var title := UI.card_title(card_id)
	var f9 := UI.font(9)
	var fs := 10
	var tw := f9.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var fnt := f9
	if tw > 42:
		fnt = UI.font(7)
		fs = 8
		tw = fnt.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tp := Vector2(floor((SIZE.x - tw) * 0.5), 10 if fs == 10 else 10)
	draw_string(fnt, tp + Vector2(1, 1), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color8(12, 10, 20))
	draw_string(fnt, tp, title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color8(248, 246, 252))
	# footer
	var f7 := UI.font(7)
	var foot: String = UI.CAT_NAME.get(cat, "")
	if card_id.begins_with("car:"):
		foot = "차량"
	elif card_id.begins_with("mod:"):
		foot = "개조"
	var col: Color = UI.CAT_COL.get(cat, Color.WHITE)
	draw_string(f7, Vector2(5, 57), foot, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, col)
	if Defs.FACILITIES.has(card_id):
		var nz := float(Defs.FACILITIES[card_id].noise)
		if nz > 0.0:
			var s := "+" + (str(int(nz)) if absf(nz - round(nz)) < 0.01 else "%.1f" % nz)
			var w := f7.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
			draw_string(f7, Vector2(SIZE.x - 5 - w, 57), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color8(255, 120, 170))
			# little noise wave
			var x0 := SIZE.x - 9 - w
			draw_line(Vector2(x0, 52), Vector2(x0, 55), Color8(255, 120, 170))
			draw_line(Vector2(x0 - 2, 53), Vector2(x0 - 2, 54), Color8(255, 120, 170))
	if is_hover and not ghost:
		draw_rect(Rect2(Vector2(0.5, 0.5), SIZE - Vector2(1, 1)), Color(1, 1, 1, 0.8), false, 1.0)
	if ghost:
		var a := 0.5 + 0.5 * sin(glow_t * 8.0)
		draw_rect(Rect2(Vector2(0.5, 0.5), SIZE - Vector2(1, 1)), Color(col, a), false, 1.0)
