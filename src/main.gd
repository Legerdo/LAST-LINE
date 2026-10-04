extends Node
## Root: swaps screens (title / hub / run) with a short fade.

var current: Node = null
var fade: ColorRect
var fade_layer: CanvasLayer
var busy := false
# QA capture: --shots=2,10,30 saves screenshots at those seconds, then quits
var shots: Array = []
var shot_dir := "res://art_src/shots"
var elapsed := 0.0


func _ready() -> void:
	Game.main = self
	fade_layer = CanvasLayer.new()
	fade_layer.layer = 100
	add_child(fade_layer)
	fade = ColorRect.new()
	fade.color = Color(0.02, 0.02, 0.04, 1.0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.add_child(fade)
	var start := "title"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--screen="):
			start = a.substr(9)
		elif a.begins_with("--shots="):
			for s in a.substr(8).split(","):
				shots.append(float(s))
		elif a.begins_with("--shotdir="):
			shot_dir = a.substr(10)
	if not shots.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shot_dir))
	_swap(start)
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 0.0, 0.6)


func _process(delta: float) -> void:
	if shots.is_empty():
		return
	elapsed += delta
	if elapsed >= float(shots[0]):
		var t: float = shots.pop_front()
		var img := get_viewport().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path(shot_dir) + "/shot_%06.2f.png" % t)
		if shots.is_empty():
			get_tree().quit()


func show_screen(name: String) -> void:
	if busy:
		return
	busy = true
	fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.35)
	tw.tween_callback(func(): _swap(name))
	tw.tween_property(fade, "color:a", 0.0, 0.45)
	tw.tween_callback(func():
		busy = false
		fade.mouse_filter = Control.MOUSE_FILTER_IGNORE)


func _swap(name: String) -> void:
	if current:
		current.queue_free()
		current = null
	var scr: Node
	match name:
		"run":
			scr = load("res://src/game/run.gd").new()
		"hub":
			scr = load("res://src/ui/hub.gd").new()
		_:
			scr = load("res://src/ui/title.gd").new()
	current = scr
	add_child(scr)
	move_child(scr, 0)
