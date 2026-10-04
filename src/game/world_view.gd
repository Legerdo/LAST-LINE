class_name WorldView
extends Node2D
## Renders a Sim: ground, facilities, enemies, train, boss, lights and every piece of juice.
## Reads sim state each frame and reacts to sim.events (consumed by run.gd -> handle_event).

const Z_GROUND := 0
const Z_ENT := 1
const Z_FX := 2
const Z_ROOF := 3
const Z_OVERLAY := 50
const Z_GLOW := 60
const Z_FXGLOW := 61
const Z_UI := 70
const W := 640
const H := 272

const FAC_LIGHT := {
	"station": [Color(0.45, 0.85, 1.0), 46.0, 0.0], "transfer": [Color(0.55, 0.9, 1.0), 58.0, 0.0],
	"ruin": [Color(0.3, 0.45, 0.6), 24.0, 0.2], "ghost": [Color(0.3, 1.0, 0.95), 50.0, 0.35],
	"market": [Color(1.0, 0.62, 0.3), 46.0, 0.1], "blackmarket": [Color(1.0, 0.35, 0.75), 50.0, 0.1],
	"hospital": [Color(1.0, 0.55, 0.55), 40.0, 0.0], "medhub": [Color(1.0, 0.85, 0.85), 54.0, 0.0],
	"ward": [Color(0.75, 0.3, 1.0), 48.0, 0.3], "factory": [Color(1.0, 0.55, 0.2), 48.0, 0.25],
	"assembly": [Color(1.0, 0.6, 0.25), 58.0, 0.25], "checkpoint": [Color(1.0, 0.92, 0.7), 40.0, 0.0],
	"mercpost": [Color(0.8, 1.0, 0.6), 46.0, 0.05], "bastion": [Color(1.0, 0.85, 0.6), 46.0, 0.0],
	"infection": [Color(0.7, 1.0, 0.35), 38.0, 0.3], "hive": [Color(0.8, 0.4, 1.0), 56.0, 0.35],
	"raiders": [Color(1.0, 0.5, 0.2), 44.0, 0.45], "fortress": [Color(1.0, 0.45, 0.15), 58.0, 0.45],
	"shelter": [Color(1.0, 0.7, 0.35), 40.0, 0.35], "commune": [Color(1.0, 0.8, 0.45), 52.0, 0.2],
	"power": [Color(0.45, 0.65, 1.0), 58.0, 0.2], "radio": [Color(1.0, 0.3, 0.3), 30.0, 0.0],
	"greenhouse": [Color(0.85, 1.0, 0.55), 44.0, 0.0], "sporefarm": [Color(0.8, 0.45, 1.0), 48.0, 0.25],
	"armory": [Color(1.0, 0.8, 0.5), 38.0, 0.0],
}
const FACTION_BLOOD := {
	"infected": [Color8(150, 220, 90), Color8(70, 30, 60)], "raider": [Color8(220, 50, 50), Color8(80, 20, 20)],
	"dark": [Color8(120, 80, 200), Color8(20, 12, 30)], "neutral": [Color8(200, 200, 200), Color8(60, 60, 60)],
}
const MECH := ["barricade", "warrig"]

var sim: Sim
var run: Node
var ents: Node2D
var fx: FX
var fxg: FX
var proj_view: Node2D
var world_ui: Node2D
var overlay: ColorRect
var overlay_mat: ShaderMaterial
var light_vp: SubViewport
var light_root: Node2D
var lot_markers := {}
var fac_nodes := {}
var enemy_nodes := {}
var car_nodes: Array = []
var boss_nodes: Array = []
var prop_lights: Array = []
var head_light: Sprite2D
var depot_spr: Sprite2D
var flash_pool: Array = []
var prev_odo := 0.0
var prev_boss := 0.0
var prev_epos := {}
var alpha := 1.0
var base_pos := Vector2(0, 24)
var trauma := 0.0
var flash_amt := 0.0
var flash_col := Color.WHITE
var t := 0.0
var ambient_now := Color(0.68, 0.68, 0.84)
var drag_card := ""
var hover_lot := -1
var hover_car := -1
var hover_enemy := -1
var hover_fac := -1
var valid_lots: Array = []
var shadow_tex: Texture2D
var barrel_tex: Texture2D
var light_tex: Texture2D
var cone_tex: Texture2D
var brake_prev := 0.0


func setup(s: Sim, controller: Node) -> void:
	sim = s
	run = controller
	position = base_pos
	light_tex = UI.tex("res://assets/sprites/fx/light.png")
	cone_tex = UI.tex("res://assets/sprites/fx/cone.png")
	shadow_tex = _make_shadow()
	barrel_tex = _make_barrel()
	_build_ground()
	_build_light_map()
	ents = Node2D.new()
	ents.y_sort_enabled = true
	ents.z_index = Z_ENT
	add_child(ents)
	fx = FX.new()
	fx.z_index = Z_FX
	add_child(fx)
	var roof := Sprite2D.new()
	roof.texture = UI.tex("res://assets/sprites/world/tunnel_roof.png")
	roof.centered = false
	# the train draws above the light overlay, so the roof has to as well (pre-darkened to match)
	roof.z_index = Z_GLOW - 1
	roof.modulate = Color(0.62, 0.62, 0.74)
	add_child(roof)
	overlay = ColorRect.new()
	overlay.size = Vector2(W, H)
	overlay.z_index = Z_OVERLAY
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_mat = ShaderMaterial.new()
	overlay_mat.shader = load("res://src/game/light_overlay.gdshader")
	overlay_mat.set_shader_parameter("light_tex", light_vp.get_texture())
	overlay.material = overlay_mat
	add_child(overlay)
	fxg = FX.new()
	fxg.z_index = Z_FXGLOW
	add_child(fxg)
	proj_view = Node2D.new()
	proj_view.z_index = Z_FXGLOW
	proj_view.draw.connect(_draw_projectiles)
	add_child(proj_view)
	world_ui = Node2D.new()
	world_ui.z_index = Z_UI
	world_ui.draw.connect(_draw_world_ui)
	add_child(world_ui)
	_build_props()
	_build_lots()
	_build_depot()
	head_light = _light(Vector2.ZERO, 1.0, Color(1.0, 0.95, 0.75), cone_tex)
	head_light.offset = Vector2(48, 0)
	prev_odo = sim.odo
	sync_all(1.0)


# ================================================================ construction
func _make_shadow() -> Texture2D:
	var img := Image.create(12, 5, false, Image.FORMAT_RGBA8)
	for y in 5:
		for x in 12:
			var dx := (x - 5.5) / 6.0
			var dy := (y - 2.0) / 2.5
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, Color(0.02, 0.02, 0.06, 0.45))
	return ImageTexture.create_from_image(img)


func _make_barrel() -> Texture2D:
	var img := Image.create(8, 3, false, Image.FORMAT_RGBA8)
	for x in 8:
		img.set_pixel(x, 0, Color8(12, 10, 20))
		img.set_pixel(x, 1, Color8(150, 146, 170) if x < 7 else Color8(255, 220, 140))
		img.set_pixel(x, 2, Color8(12, 10, 20))
	return ImageTexture.create_from_image(img)


func _build_ground() -> void:
	var g := Sprite2D.new()
	g.texture = UI.tex("res://assets/sprites/world/ground.png")
	g.centered = false
	g.z_index = Z_GROUND
	add_child(g)


func _build_light_map() -> void:
	light_vp = SubViewport.new()
	light_vp.size = Vector2i(W / 2, H / 2)
	light_vp.transparent_bg = false
	light_vp.disable_3d = true
	light_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	light_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(light_vp)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.size = Vector2(W, H)
	light_vp.add_child(bg)
	light_root = Node2D.new()
	light_root.scale = Vector2(0.5, 0.5)
	light_vp.add_child(light_root)


func _light(pos: Vector2, radius: float, col: Color, tex_override: Texture2D = null) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex_override if tex_override else light_tex
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	s.material = mat
	s.position = pos
	s.scale = Vector2.ONE * (radius / 32.0)
	s.modulate = col
	light_root.add_child(s)
	return s


func _build_props() -> void:
	var f := FileAccess.open("res://assets/data/props.json", FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if not data is Array:
		return
	for p in data:
		var tex := UI.tex("res://assets/sprites/prop/%s.png" % p.name)
		if tex == null:
			continue
		var s := Sprite2D.new()
		s.texture = tex
		s.position = Vector2(p.x, p.y)
		s.offset = Vector2(0, -tex.get_height() * 0.5)
		ents.add_child(s)
		var glow := UI.tex("res://assets/sprites/prop/%s_glow.png" % p.name)
		if glow:
			_glow_child(s, glow)
		match String(p.name):
			"lamp":
				var col := Color(1.0, 0.8, 0.45) if randf() < 0.7 else Color(0.5, 0.9, 1.0)
				prop_lights.append([_light(s.position + Vector2(3, -tex.get_height() + 2), 34.0, col), col, randf() * 10.0, 0.15])
			"vending":
				prop_lights.append([_light(s.position + Vector2(0, -6), 22.0, Color(0.4, 1.0, 0.9)), Color(0.4, 1.0, 0.9), randf() * 10.0, 0.3])
			"campfire":
				prop_lights.append([_light(s.position + Vector2(0, -4), 30.0, Color(1.0, 0.6, 0.25)), Color(1.0, 0.6, 0.25), randf() * 10.0, 0.4])


func _glow_child(parent: Sprite2D, tex: Texture2D) -> Sprite2D:
	var g := Sprite2D.new()
	g.texture = tex
	g.offset = parent.offset
	g.centered = parent.centered
	g.z_as_relative = false
	g.z_index = Z_GLOW
	parent.add_child(g)
	return g


func _build_lots() -> void:
	var tex := UI.fac_tex("lot_empty")
	for l: Dictionary in sim.map.lots:
		var s := Sprite2D.new()
		s.texture = tex
		var r: Rect2i = l.rect
		s.position = Vector2(r.position.x * 16 + 16, r.position.y * 16 + 30)
		s.offset = Vector2(0, -tex.get_height() * 0.5)
		s.modulate = Color(0.62, 0.62, 0.74, 0.5)
		s.z_index = -1
		ents.add_child(s)
		lot_markers[l.id] = s


func _build_depot() -> void:
	var r: Rect2i = sim.map.depot_rect
	var tex := UI.fac_tex("depot")
	depot_spr = Sprite2D.new()
	depot_spr.texture = tex
	depot_spr.position = Vector2(r.position.x * 16 + r.size.x * 8, (r.position.y + r.size.y) * 16 - 1)
	depot_spr.offset = Vector2(0, -tex.get_height() * 0.5)
	ents.add_child(depot_spr)
	var glow := UI.fac_tex("depot_glow")
	if glow:
		_glow_child(depot_spr, glow)
	_light(depot_spr.position + Vector2(0, -18), 60.0, Color(1.0, 0.78, 0.45))


# ================================================================ per-frame sync
func snapshot() -> void:
	prev_odo = sim.odo
	prev_boss = sim.boss_odo
	for e: Sim.Enemy in sim.enemies:
		prev_epos[e.id] = e.pos


func sync_all(a: float) -> void:
	alpha = clampf(a, 0.0, 1.0)
	_sync_facilities()
	_sync_train()
	_sync_enemies()
	_sync_boss()


func _process(delta: float) -> void:
	t += delta
	# shake: trauma^2 with pixel steps
	trauma = maxf(0.0, trauma - delta * 1.6)
	var amp := trauma * trauma * 7.0 * float(Game.setting("shake", 1.0))
	position = base_pos + Vector2(randf_range(-amp, amp), randf_range(-amp, amp)).round()
	flash_amt = maxf(0.0, flash_amt - delta * 4.0)
	overlay_mat.set_shader_parameter("flash", flash_amt * 0.6)
	overlay_mat.set_shader_parameter("flash_color", flash_col)
	_update_ambient(delta)
	_update_lights(delta)
	_ambient_particles(delta)
	proj_view.queue_redraw()
	world_ui.queue_redraw()


func _update_ambient(delta: float) -> void:
	var stage := sim.danger_stage()
	var target: Color = [Color(0.68, 0.68, 0.84), Color(0.66, 0.62, 0.78), Color(0.7, 0.56, 0.68), Color(0.72, 0.48, 0.56)][stage]
	if sim.state == "dead":
		target = Color(0.35, 0.25, 0.3)
	ambient_now = ambient_now.lerp(target, clampf(delta * 0.8, 0.0, 1.0))
	var pulse := 0.0
	if stage == 3:
		pulse = 0.05 * (0.5 + 0.5 * sin(t * 3.0))
	overlay_mat.set_shader_parameter("ambient", ambient_now * (1.0 - pulse))
	var hp := sim.hull / maxf(1.0, sim.max_hull)
	var vig := 0.35 + 0.1 * stage
	if hp < 0.3:
		vig += 0.35 * (0.6 + 0.4 * sin(t * 6.0))
	overlay_mat.set_shader_parameter("vignette", vig)
	var tint := Color(1, 1, 1)
	if hp < 0.3:
		tint = Color(1.15, 0.85, 0.85)
	overlay_mat.set_shader_parameter("danger_tint", tint)


func _update_lights(delta: float) -> void:
	for pl in prop_lights:
		var s: Sprite2D = pl[0]
		var col: Color = pl[1]
		var fl: float = pl[3]
		var k := 1.0 - fl * (0.5 + 0.5 * sin(t * 9.0 + pl[2])) * randf_range(0.6, 1.0)
		s.modulate = col * k
	for fl in flash_pool:
		var s: Sprite2D = fl.s
		if fl.t <= 0.0:
			s.visible = false
			continue
		fl.t -= delta
		var k: float = clampf(fl.t / fl.life, 0.0, 1.0)
		s.visible = true
		s.modulate = (fl.c as Color) * k


func flash_light(pos: Vector2, radius: float, col: Color, life := 0.25) -> void:
	var slot = null
	for fl in flash_pool:
		if fl.t <= 0.0:
			slot = fl
			break
	if slot == null:
		if flash_pool.size() >= 40:
			slot = flash_pool[0]
		else:
			slot = {"s": _light(pos, radius, col), "t": 0.0, "life": life, "c": col}
			flash_pool.append(slot)
	slot.s.position = pos
	slot.s.scale = Vector2.ONE * (radius / 32.0)
	slot.t = life
	slot.life = life
	slot.c = col


func shake(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


func screen_flash(c: Color, amount := 1.0) -> void:
	flash_col = c
	flash_amt = maxf(flash_amt, amount)


# ---------------------------------------------------------------- facilities
func _sync_facilities() -> void:
	for lot_id in lot_markers.keys():
		var has: bool = sim.facs.has(lot_id)
		lot_markers[lot_id].visible = not has
	for lot_id in sim.facs.keys():
		var f: Sim.Fac = sim.facs[lot_id]
		var node: Dictionary = fac_nodes.get(lot_id, {})
		if node.is_empty():
			node = _make_fac(lot_id, f.type)
			fac_nodes[lot_id] = node
		elif node.type != f.type and not node.get("morphing", false):
			_set_fac_type(node, f.type)
		var spr: Sprite2D = node.spr
		spr.modulate = Color(0.55, 0.55, 0.6) if f.disabled else Color.WHITE
		var li: Array = FAC_LIGHT.get(f.type, [Color(1, 0.9, 0.7), 36.0, 0.0])
		var fl: float = li[2]
		var k := 1.0 - fl * (0.5 + 0.5 * sin(t * 7.0 + lot_id)) * randf_range(0.7, 1.0)
		if f.type == "radio":
			k = 0.3 + 0.7 * float(int(t * 1.5) % 2)
		if f.flash > 0.0:
			k += f.flash * 1.5
		(node.light as Sprite2D).modulate = (li[0] as Color) * k * (0.5 if f.disabled else 1.0)
	for lot_id in fac_nodes.keys():
		if not sim.facs.has(lot_id):
			var node: Dictionary = fac_nodes[lot_id]
			(node.light as Sprite2D).queue_free()
			(node.spr as Sprite2D).queue_free()
			fac_nodes.erase(lot_id)


func _fac_anchor(lot_id: int) -> Vector2:
	var l: Dictionary = sim.map.lots[lot_id]
	var r: Rect2i = l.rect
	return Vector2(r.position.x * 16 + 16, r.position.y * 16 + 31)


func _make_fac(lot_id: int, type: String) -> Dictionary:
	var s := Sprite2D.new()
	s.position = _fac_anchor(lot_id)
	ents.add_child(s)
	var li: Array = FAC_LIGHT.get(type, [Color(1, 0.9, 0.7), 36.0, 0.0])
	var light := _light(s.position + Vector2(0, -12), li[1], li[0])
	var node := {"spr": s, "glow": null, "type": "", "light": light, "lot": lot_id}
	_set_fac_type(node, type)
	return node


func _set_fac_type(node: Dictionary, type: String) -> void:
	var s: Sprite2D = node.spr
	var tex := UI.fac_tex(type)
	s.texture = tex
	s.offset = Vector2(0, -tex.get_height() * 0.5) if tex else Vector2.ZERO
	if node.glow:
		(node.glow as Sprite2D).queue_free()
		node.glow = null
	var gt := UI.fac_tex(type + "_glow")
	if gt:
		node.glow = _glow_child(s, gt)
	node.type = type
	var li: Array = FAC_LIGHT.get(type, [Color(1, 0.9, 0.7), 36.0, 0.0])
	(node.light as Sprite2D).scale = Vector2.ONE * (float(li[1]) / 32.0)


func fac_drop(lot_id: int) -> void:
	var node: Dictionary = fac_nodes.get(lot_id, {})
	if node.is_empty():
		_sync_facilities()
		node = fac_nodes.get(lot_id, {})
		if node.is_empty():
			return
	var s: Sprite2D = node.spr
	var base := _fac_anchor(lot_id)
	s.position = base + Vector2(0, -34)
	s.scale = Vector2(0.8, 1.25)
	var tw := s.create_tween()
	tw.tween_property(s, "position", base, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		s.scale = Vector2(1.3, 0.72)
		fx.burst(base + Vector2(0, -2), 16, Color8(120, 110, 120), Color8(40, 36, 50, 0), 60.0, 0.5, 2.0, 0.0, 5.0, PI, PI, 1.0)
		fx.burst(base + Vector2(0, -2), 16, Color8(120, 110, 120), Color8(40, 36, 50, 0), 60.0, 0.5, 2.0, 0.0, 5.0, PI, 0.0, 1.0)
		fxg.ring(base + Vector2(0, -6), 4.0, 26.0, Color(1, 1, 1, 0.8), 0.3)
		flash_light(base + Vector2(0, -10), 60.0, Color(1, 0.9, 0.7), 0.35)
		shake(0.28)
		Audio.sfx("place", -2.0)
	)
	tw.tween_property(s, "scale", Vector2(0.92, 1.1), 0.08)
	tw.tween_property(s, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func fac_morph(lot_id: int, to: String, good: bool) -> void:
	var node: Dictionary = fac_nodes.get(lot_id, {})
	if node.is_empty():
		return
	node.morphing = true
	var s: Sprite2D = node.spr
	var base := _fac_anchor(lot_id)
	var col := Color8(120, 240, 255) if good else Color8(200, 90, 255)
	var tw := s.create_tween()
	tw.tween_property(s, "scale", Vector2(1.12, 0.86), 0.12)
	tw.parallel().tween_property(s, "self_modulate", Color(3, 3, 3), 0.12)
	tw.tween_callback(func():
		node.morphing = false
		_set_fac_type(node, to)
		s.scale = Vector2(0.8, 1.35)
		fxg.burst(base + Vector2(0, -14), 30, col, Color(col, 0), 80.0, 0.7, 2.0, -40.0, 3.0)
		fxg.ring(base + Vector2(0, -12), 6.0, 40.0, col, 0.45, 1.0)
		flash_light(base + Vector2(0, -14), 90.0, col, 0.6)
		shake(0.25)
	)
	tw.tween_property(s, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(s, "self_modulate", Color.WHITE, 0.35)


func fac_remove_fx(lot_id: int) -> void:
	var base := _fac_anchor(lot_id)
	fxg.burst(base + Vector2(0, -12), 40, Color8(255, 200, 90), Color8(200, 40, 20, 0), 90.0, 0.6, 2.0, -30.0, 3.0)
	fx.burst(base + Vector2(0, -8), 24, Color8(60, 56, 70), Color8(20, 18, 26, 0), 40.0, 1.4, 3.0, -12.0, 1.0, TAU, 0.0, 5.0)
	flash_light(base, 100.0, Color(1, 0.6, 0.3), 0.5)
	shake(0.35)


# ---------------------------------------------------------------- train
func _render_odo() -> float:
	return lerpf(prev_odo, sim.odo, alpha)


func _sync_train() -> void:
	while car_nodes.size() < sim.cars.size():
		car_nodes.append({})
	while car_nodes.size() > sim.cars.size():
		var n: Dictionary = car_nodes.pop_back()
		if n.has("spr"):
			(n.spr as Sprite2D).queue_free()
			(n.light as Sprite2D).queue_free()
	var odo_r := _render_odo()
	for i in sim.cars.size():
		var c: Sim.Car = sim.cars[i]
		var n: Dictionary = car_nodes[i]
		if n.is_empty() or n.type != c.type:
			if n.has("spr"):
				(n.spr as Sprite2D).queue_free()
				(n.light as Sprite2D).queue_free()
			n = _make_car(c.type)
			car_nodes[i] = n
		var s := odo_r - c.off
		var p := sim.map.pos_at(s)
		var d := sim.map.pos_at(s + c.length * 0.4) - sim.map.pos_at(s - c.length * 0.4)
		var ang := d.angle()
		var spr: Sprite2D = n.spr
		var jitter := Vector2.ZERO
		if c.flash > 0.0:
			jitter = Vector2(randf_range(-1, 1), randf_range(-1, 1)).round()
		spr.position = p + jitter
		spr.rotation = ang
		spr.self_modulate = Color(3.0, 1.2, 1.1) if c.flash > 0.08 else Color.WHITE
		(n.light as Sprite2D).position = p
		if n.has("barrel"):
			var b: Sprite2D = n.barrel
			b.rotation = c.aim - ang
			b.position = Vector2.from_angle(c.aim - ang) * (1.0 - c.recoil * 2.0)
		if i == 0:
			head_light.position = p + Vector2.from_angle(ang) * 14.0
			head_light.rotation = ang
			head_light.scale = Vector2(1.1, 0.9)
			var on := not sim.map.is_tunnel_s(odo_r)
			head_light.modulate = Color(1.0, 0.95, 0.75) * (0.9 if on else 0.35)


func _make_car(type: String) -> Dictionary:
	var s := Sprite2D.new()
	s.texture = UI.tex("res://assets/sprites/train/%s.png" % type)
	# the train is the hero: drawn above the light overlay so it always reads at full brightness
	s.z_as_relative = false
	s.z_index = Z_GLOW - 1
	ents.add_child(s)
	var g := UI.tex("res://assets/sprites/train/%s_glow.png" % type)
	if g:
		_glow_child(s, g)
	var n := {"spr": s, "type": type, "light": _light(Vector2.ZERO, 40.0, Color(1.0, 0.86, 0.62) * 0.8)}
	if type == "gun":
		var b := Sprite2D.new()
		b.texture = barrel_tex
		b.offset = Vector2(4, 0)
		s.add_child(b)
		n.barrel = b
	return n


func car_pop(index: int) -> void:
	if index < 0 or index >= car_nodes.size() or car_nodes[index].is_empty():
		return
	var s: Sprite2D = car_nodes[index].spr
	s.scale = Vector2(1.4, 0.6)
	var tw := s.create_tween()
	tw.tween_property(s, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	fxg.burst(s.position, 20, Color8(255, 230, 150), Color8(255, 120, 40, 0), 70.0, 0.4, 1.0, 60.0, 2.0)
	flash_light(s.position, 60.0, Color(1, 0.85, 0.6), 0.4)
	shake(0.2)


func car_pos(i: int) -> Vector2:
	if i < 0 or i >= sim.cars.size():
		return Vector2.ZERO
	var c: Sim.Car = sim.cars[i]
	return sim.map.pos_at(_render_odo() - c.off)


# ---------------------------------------------------------------- enemies
func _sync_enemies() -> void:
	var alive := {}
	for e: Sim.Enemy in sim.enemies:
		if e.dead:
			continue
		alive[e.id] = true
		var n: Dictionary = enemy_nodes.get(e.id, {})
		if n.is_empty():
			n = _make_enemy(e)
			enemy_nodes[e.id] = n
		var pp: Vector2 = prev_epos.get(e.id, e.pos)
		var p := pp.lerp(e.pos, alpha)
		var spr: Sprite2D = n.spr
		spr.position = p.round()
		var moving := pp.distance_squared_to(e.pos) > 0.0004
		if n.frames > 1:
			var fr := 0
			if e.state == Sim.ENGAGE and e.cd < 0.18 and e.ai != "static":
				fr = 3
			elif moving:
				fr = 1 + int(e.anim * (4.0 + e.spd * 0.12)) % 2
			spr.frame = fr
			if n.glow:
				(n.glow as Sprite2D).frame = fr
		spr.flip_h = e.face < 0
		if n.glow:
			(n.glow as Sprite2D).flip_h = spr.flip_h
		# emergence / stealth / flash
		var a := 1.0
		if e.stealth and not e.visible:
			a = 0.16 + 0.06 * sin(t * 8.0 + e.id)
		var sc := Vector2.ONE
		if e.emerge > 0.0:
			var k := clampf(1.0 - e.emerge / 0.5, 0.0, 1.0)
			sc = Vector2(1.0 + 0.3 * (1.0 - k), k)
		var hit_sq: float = n.get("sq", 0.0)
		if hit_sq > 0.0:
			sc *= Vector2(1.0 + 0.3 * hit_sq, 1.0 - 0.25 * hit_sq)
			n.sq = maxf(0.0, hit_sq - 0.12)
		spr.scale = sc
		if e.flash > 0.0:
			spr.self_modulate = Color(5, 5, 5, a)
			spr.z_as_relative = false
			spr.z_index = Z_GLOW
		else:
			spr.self_modulate = Color(1, 1, 1, a)
			spr.z_as_relative = true
			spr.z_index = 0
		if e.stun > 0.0:
			spr.rotation = sin(t * 30.0) * 0.08
		else:
			spr.rotation = 0.0
		if n.light:
			var lt: Sprite2D = n.light
			lt.position = p + Vector2(0, -6)
			lt.modulate = (n.lcol as Color) * (0.8 + 0.2 * sin(t * 4.0 + e.id))
	for id in enemy_nodes.keys():
		if not alive.has(id):
			var n: Dictionary = enemy_nodes[id]
			_retire_enemy(n)
			enemy_nodes.erase(id)
			prev_epos.erase(id)


func _make_enemy(e: Sim.Enemy) -> Dictionary:
	var s := Sprite2D.new()
	var anim := UI.tex("res://assets/sprites/enemy/%s_anim.png" % e.type)
	var frames := 1
	var tex: Texture2D
	if anim:
		tex = anim
		frames = 4
		s.hframes = 4
	else:
		tex = UI.tex("res://assets/sprites/enemy/%s.png" % e.type)
	s.texture = tex
	var fh := tex.get_height() if tex else 16
	s.offset = Vector2(0, -fh * 0.5 + 1)
	s.position = e.pos
	var sh := Sprite2D.new()
	sh.texture = shadow_tex
	sh.z_index = -1
	sh.scale = Vector2.ONE * (e.r / 5.0)
	s.add_child(sh)
	ents.add_child(s)
	var n := {"spr": s, "type": e.type, "frames": frames, "glow": null, "light": null, "sq": 0.0, "elite": e.elite}
	var gt := UI.tex("res://assets/sprites/enemy/%s_anim_glow.png" % e.type) if anim else UI.tex("res://assets/sprites/enemy/%s_glow.png" % e.type)
	if gt:
		var g := _glow_child(s, gt)
		if frames > 1:
			g.hframes = 4
		n.glow = g
	if e.elite or e.type == "bloater":
		var col := Color(0.8, 0.4, 1.0) if e.faction == "infected" else (Color(1.0, 0.5, 0.2) if e.faction == "raider" else Color(0.5, 0.9, 1.0))
		n.light = _light(e.pos, 40.0 if e.elite else 22.0, col * 0.7)
		n.lcol = col * (0.7 if e.elite else 0.45)
	return n


func _retire_enemy(n: Dictionary) -> void:
	var s: Sprite2D = n.spr
	if n.light:
		(n.light as Sprite2D).queue_free()
	# corpse: tip over and fade in the lit layer
	s.self_modulate = Color(0.6, 0.55, 0.6, 1)
	s.z_as_relative = true
	s.z_index = -1
	var tw := s.create_tween()
	var dir := -1.0 if s.flip_h else 1.0
	tw.tween_property(s, "rotation", dir * PI * 0.5, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(s, "scale", Vector2(1.1, 0.8), 0.18)
	tw.tween_interval(0.6)
	tw.tween_property(s, "modulate:a", 0.0, 0.5)
	tw.tween_callback(s.queue_free)


func enemy_node(id: int) -> Dictionary:
	return enemy_nodes.get(id, {})


# ---------------------------------------------------------------- boss
func _sync_boss() -> void:
	if sim.boss_parts.is_empty():
		return
	while boss_nodes.size() < sim.boss_parts.size():
		var i := boss_nodes.size()
		var bp: Sim.BossPart = sim.boss_parts[i]
		var s := Sprite2D.new()
		s.texture = UI.tex("res://assets/sprites/boss/%s.png" % bp.kind)
		s.z_as_relative = false
		s.z_index = Z_GLOW - 1
		s.self_modulate = Color(0.9, 0.85, 0.9)
		ents.add_child(s)
		var gt := UI.tex("res://assets/sprites/boss/%s_glow.png" % bp.kind)
		if gt:
			_glow_child(s, gt)
		var li := _light(bp.pos, 44.0 if bp.kind == "head" else 28.0, Color(1.0, 0.2, 0.2) * 0.6)
		boss_nodes.append({"spr": s, "light": li, "dead": false})
	var bodo := lerpf(prev_boss, sim.boss_odo, alpha)
	for i in sim.boss_parts.size():
		var bp: Sim.BossPart = sim.boss_parts[i]
		var n: Dictionary = boss_nodes[i]
		var s: Sprite2D = n.spr
		var sp := bodo - bp.off
		var p := sim.map.gpos_at(sp)
		var d := sim.map.gpos_at(sp + bp.length * 0.4) - sim.map.gpos_at(sp - bp.length * 0.4)
		s.position = p
		s.rotation = d.angle()
		s.visible = sim.boss_active or sim.state == "victory"
		(n.light as Sprite2D).position = p
		if not bp.alive:
			s.self_modulate = Color(0.35, 0.3, 0.32)
			(n.light as Sprite2D).modulate = Color(1.0, 0.45, 0.15) * (0.4 + 0.2 * randf())
			if randf() < 0.3:
				fx.burst(p + Vector2(randf_range(-10, 10), -2), 1, Color8(50, 44, 56), Color8(20, 18, 26, 0), 12.0, 1.4, 2.0, -18.0, 0.5, 0.6, -PI * 0.5, 4.0)
			if randf() < 0.25:
				fxg.burst(p + Vector2(randf_range(-8, 8), 0), 1, Color8(255, 200, 90), Color8(220, 60, 20, 0), 16.0, 0.5, 1.0, -30.0, 0.5, 0.8, -PI * 0.5)
		else:
			s.self_modulate = Color(4, 2, 2) if bp.flash > 0.05 else Color.WHITE
			var tele := sim.boss_state == "telegraph" and bp.kind == "head"
			var k := 0.6 + (0.6 * float(int(t * 10.0) % 2) if tele else 0.1 * sin(t * 3.0))
			(n.light as Sprite2D).modulate = Color(1.0, 0.2, 0.2) * k
			if bp.hp < bp.max_hp * 0.4 and randf() < 0.15:
				fx.burst(p, 1, Color8(60, 54, 64), Color8(20, 18, 26, 0), 10.0, 1.2, 2.0, -16.0, 0.5, 0.6, -PI * 0.5, 4.0)


func boss_part_pos(kind: String) -> Vector2:
	for bp: Sim.BossPart in sim.boss_parts:
		if bp.kind == kind:
			return bp.pos
	return Vector2.ZERO


# ---------------------------------------------------------------- ambience
var _amb_t := 0.0


func _ambient_particles(delta: float) -> void:
	_amb_t += delta
	if _amb_t < 0.08:
		return
	_amb_t = 0.0
	for lot_id in sim.facs.keys():
		var f: Sim.Fac = sim.facs[lot_id]
		var base := _fac_anchor(lot_id)
		match f.type:
			"factory", "assembly":
				if randf() < 0.5:
					fx.burst(base + Vector2(-6, -34), 1, Color8(70, 64, 80), Color8(30, 28, 40, 0), 10.0, 2.2, 2.0, -12.0, 0.3, 0.5, -PI * 0.5, 5.0)
				if randf() < 0.15:
					fxg.burst(base + Vector2(4, -10), 1, Color8(255, 200, 90), Color8(255, 90, 20, 0), 20.0, 0.4, 1.0, 40.0, 1.0, 1.0, -PI * 0.5)
			"raiders", "fortress", "shelter", "commune":
				if randf() < 0.35:
					fxg.burst(base + Vector2(randf_range(-10, 10), -8), 1, Color8(255, 190, 80), Color8(220, 60, 20, 0), 14.0, 0.5, 1.0, -30.0, 0.5, 0.6, -PI * 0.5)
			"infection", "hive", "sporefarm", "ward":
				if randf() < 0.3:
					fxg.burst(base + Vector2(randf_range(-14, 14), randf_range(-16, -2)), 1, Color8(200, 255, 110, 200), Color8(160, 80, 220, 0), 6.0, 1.6, 1.0, -6.0, 0.2)
			"ghost":
				if randf() < 0.3:
					fxg.burst(base + Vector2(randf_range(-14, 14), randf_range(-14, 0)), 1, Color8(140, 255, 240, 160), Color8(60, 140, 200, 0), 5.0, 1.8, 2.0, -5.0, 0.2)
			"power":
				if randf() < 0.12:
					var a := base + Vector2(randf_range(-10, 10), -24)
					fxg.bolt([a, a + Vector2(randf_range(-10, 10), randf_range(8, 18))], Color8(120, 180, 255), 0.08)
	# electrified track segments
	for ps in sim.power_s:
		if randf() < 0.5:
			var s: float = float(ps) + randf_range(-44.0, 44.0)
			var a := sim.map.pos_at(s)
			fxg.bolt([a, a + Vector2(randf_range(-6, 6), randf_range(-6, 6))], Color8(140, 200, 255), 0.06)
	# wheel sparks when braking hard or cornering
	if sim.cars.size() > 0 and sim.state == "running":
		var braking := sim.speed < brake_prev - 0.4
		brake_prev = sim.speed
		for i in sim.cars.size():
			var c: Sim.Car = sim.cars[i]
			var turning := absf(wrapf(sim.map.dir_at(sim.odo - c.off).angle() - sim.map.dir_at(sim.odo - c.off - 8.0).angle(), -PI, PI)) > 0.2
			if (braking and randf() < 0.5) or (turning and sim.speed > 25.0 and randf() < 0.35):
				fxg.burst(car_pos(i), 2, Color8(255, 240, 180), Color8(255, 120, 40, 0), 50.0, 0.25, 1.0, 80.0, 3.0)
	# low hull smoke
	if sim.hull < sim.max_hull * 0.35 and sim.cars.size() > 0 and randf() < 0.6:
		var i := randi() % sim.cars.size()
		fx.burst(car_pos(i) + Vector2(randf_range(-6, 6), -2), 1, Color8(50, 46, 56), Color8(20, 18, 24, 0), 12.0, 1.6, 2.0, -20.0, 0.5, 0.6, -PI * 0.5, 5.0)


# ================================================================ projectiles & world UI
func _draw_projectiles() -> void:
	for pr: Sim.Proj in sim.projs:
		var k := clampf(pr.t / maxf(0.001, pr.dur), 0.0, 1.0)
		match pr.kind:
			"shell", "turret_shell", "boss_mortar", "bomb":
				var h := 26.0 if pr.kind != "bomb" else 14.0
				var p := pr.from.lerp(pr.to, k) + Vector2(0, -h * 4.0 * k * (1.0 - k))
				var k2 := maxf(0.0, k - 0.06)
				var p2 := pr.from.lerp(pr.to, k2) + Vector2(0, -h * 4.0 * k2 * (1.0 - k2))
				var col := Color8(255, 230, 150) if pr.friendly else Color8(255, 80, 60)
				if pr.kind == "bomb":
					col = Color8(255, 150, 40)
				proj_view.draw_line(p2.floor(), p.floor(), Color(col, 0.5), 1.0)
				proj_view.draw_rect(Rect2(p.floor() - Vector2(1, 1), Vector2(2, 2)), col)
			"bullet", "boss_shell":
				var p := pr.from.lerp(pr.to, k)
				var q := pr.from.lerp(pr.to, maxf(0.0, k - 0.25))
				var col := Color8(255, 110, 90) if pr.kind == "bullet" else Color8(255, 60, 60)
				proj_view.draw_line(q.floor(), p.floor(), col, 1.0 if pr.kind == "bullet" else 2.0)


func _corner_brackets(r: Rect2, c: Color, len := 5.0) -> void:
	var a := r.position
	var b := r.end
	world_ui.draw_line(a, a + Vector2(len, 0), c)
	world_ui.draw_line(a, a + Vector2(0, len), c)
	world_ui.draw_line(Vector2(b.x, a.y), Vector2(b.x - len, a.y), c)
	world_ui.draw_line(Vector2(b.x, a.y), Vector2(b.x, a.y + len), c)
	world_ui.draw_line(Vector2(a.x, b.y), Vector2(a.x + len, b.y), c)
	world_ui.draw_line(Vector2(a.x, b.y), Vector2(a.x, b.y - len), c)
	world_ui.draw_line(b, b - Vector2(len, 0), c)
	world_ui.draw_line(b, b - Vector2(0, len), c)


func _lot_rect(lot_id: int) -> Rect2:
	var l: Dictionary = sim.map.lots[lot_id]
	var r: Rect2i = l.rect
	return Rect2(r.position.x * 16, r.position.y * 16, 32, 32)


func _draw_world_ui() -> void:
	var pulse := 0.55 + 0.45 * sin(t * 6.0)
	if drag_card != "":
		var kind := sim.card_kind(drag_card)
		if kind == "facility" or kind == "action":
			var col := UI.CAT_COL.get(UI.card_cat(drag_card), Color.WHITE) as Color
			for lot_id in valid_lots:
				var r := _lot_rect(lot_id).grow(-1)
				_corner_brackets(r, Color(col, 0.35 + 0.35 * pulse))
			if hover_lot >= 0 and valid_lots.has(hover_lot):
				var r2 := _lot_rect(hover_lot).grow(1)
				world_ui.draw_rect(r2, Color(col, 0.18), true)
				_corner_brackets(r2, Color(1, 1, 1, 0.95), 7.0)
				# adjacency links
				var l: Dictionary = sim.map.lots[hover_lot]
				for nb in l.neighbors:
					var rc := _lot_rect(nb)
					var cc := Color(1, 1, 1, 0.22) if not sim.facs.has(nb) else Color(col, 0.7)
					world_ui.draw_line(_lot_rect(hover_lot).get_center(), rc.get_center(), cc, 1.0)
		elif kind == "car" or kind == "mod":
			for i in sim.cars.size():
				var p := car_pos(i)
				world_ui.draw_arc(p, 12.0, 0, TAU, 20, Color(1, 0.85, 0.4, 0.3 + 0.4 * pulse), 1.0)
			if hover_car >= 0:
				world_ui.draw_arc(car_pos(hover_car), 15.0, 0, TAU, 24, Color(1, 1, 1, 0.9), 1.0)
	elif hover_car >= 0 and hover_car < sim.cars.size():
		var c: Sim.Car = sim.cars[hover_car]
		var p := car_pos(hover_car)
		world_ui.draw_arc(p, 13.0, 0, TAU, 20, Color(1, 1, 1, 0.7), 1.0)
		if not c.w.is_empty():
			var rr := float(c.w.range) * sim.range_mult()
			world_ui.draw_arc(p, rr, 0, TAU, 48, Color(1, 0.85, 0.4, 0.35), 1.0)
			if c.w.has("min"):
				world_ui.draw_arc(p, float(c.w.min), 0, TAU, 32, Color(1, 0.4, 0.3, 0.3), 1.0)
	elif hover_fac >= 0 and sim.facs.has(hover_fac):
		var r3 := _lot_rect(hover_fac).grow(1)
		_corner_brackets(r3, Color(1, 1, 1, 0.8), 6.0)
		var f: Sim.Fac = sim.facs[hover_fac]
		var d: Dictionary = Defs.FACILITIES[f.type]
		if d.has("turret"):
			world_ui.draw_arc(r3.get_center(), float(d.turret.range), 0, TAU, 48, Color(0.6, 1.0, 0.5, 0.35), 1.0)
		var l: Dictionary = sim.map.lots[hover_fac]
		for nb in l.neighbors:
			if sim.facs.has(nb):
				world_ui.draw_line(r3.get_center(), _lot_rect(nb).get_center(), Color(1, 1, 1, 0.3), 1.0)
	# per-facility badges: pending evolution arrow, countdown, waiting survivors, unpaid
	for lot_id in sim.facs.keys():
		var f: Sim.Fac = sim.facs[lot_id]
		var base := _fac_anchor(lot_id)
		var top := base + Vector2(0, -40)
		var evo := sim.evo_target(lot_id, 1)
		if evo != "":
			var hostile: bool = Defs.FACILITIES[evo].cat == "hostile"
			var col := Color8(255, 90, 110) if hostile else Color8(120, 240, 255)
			var bob := roundf(sin(t * 5.0 + lot_id) * 1.5)
			var p := top + Vector2(12, bob)
			world_ui.draw_rect(Rect2(p + Vector2(-3, -1), Vector2(7, 7)), Color8(12, 10, 20))
			world_ui.draw_line(p + Vector2(0.5, 4), p + Vector2(0.5, 0), col)
			world_ui.draw_line(p + Vector2(-1.5, 2), p + Vector2(0.5, 0), col)
			world_ui.draw_line(p + Vector2(2.5, 2), p + Vector2(0.5, 0), col)
		else:
			var cd := sim.evo_countdown(lot_id)
			if cd > 0 and cd <= 3:
				var p2 := top + Vector2(12, 0)
				world_ui.draw_rect(Rect2(p2 + Vector2(-4, -2), Vector2(9, 9)), Color8(12, 10, 20))
				world_ui.draw_rect(Rect2(p2 + Vector2(-4, -2), Vector2(9, 9)), Color8(230, 62, 70), false)
				world_ui.draw_string(fx.small_font, p2 + Vector2(-2, 6), str(cd), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color8(255, 200, 200))
		if f.waiting > 0:
			for k in mini(f.waiting, 6):
				var sp := base + Vector2(-14 + k * 3, -2)
				world_ui.draw_rect(Rect2(sp, Vector2(2, 2)), Color8(255, 236, 170))
				world_ui.draw_rect(Rect2(sp + Vector2(0, 2), Vector2(2, 2)), Color8(96, 212, 236))
		if f.disabled:
			var bp := top + Vector2(-12, 0)
			world_ui.draw_rect(Rect2(bp + Vector2(-3, -2), Vector2(7, 9)), Color8(230, 62, 70))
			world_ui.draw_string(fx.small_font, bp + Vector2(-1, 6), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)
	# enemy health bars
	for e: Sim.Enemy in sim.enemies:
		if e.dead or not e.visible or e.emerge > 0.0:
			continue
		if e.hp < e.max_hp or e.elite:
			var n: Dictionary = enemy_nodes.get(e.id, {})
			if n.is_empty():
				continue
			var p: Vector2 = (n.spr as Sprite2D).position
			var tex: Texture2D = (n.spr as Sprite2D).texture
			var hgt := float(tex.get_height()) if tex else 16.0
			var wbar := 12.0 if not e.elite else 24.0
			var bp2 := (p + Vector2(-wbar * 0.5, -hgt - 2)).floor()
			world_ui.draw_rect(Rect2(bp2 - Vector2(1, 1), Vector2(wbar + 2, 3)), Color8(12, 10, 20))
			var col2 := Color8(230, 62, 70) if not e.elite else Color8(255, 140, 40)
			world_ui.draw_rect(Rect2(bp2, Vector2(round(wbar * clampf(e.hp / e.max_hp, 0.0, 1.0)), 1)), col2)
	# boss telegraph: horn radius
	if sim.boss_active and sim.boss_state == "telegraph":
		var hp: Vector2 = sim.boss_parts[0].pos
		var k := clampf(sim.boss_t / 1.6, 0.0, 1.0)
		world_ui.draw_arc(hp, 70.0, 0, TAU, 56, Color(1, 0.2, 0.2, 0.3 + 0.5 * pulse), 1.0)
		world_ui.draw_arc(hp, 70.0 * k, 0, TAU, 56, Color(1, 0.3, 0.2, 0.8), 2.0)


# ================================================================ picking
func lot_at(p: Vector2) -> int:
	for l: Dictionary in sim.map.lots:
		var r := _lot_rect(l.id).grow(2)
		if r.has_point(p):
			return l.id
	return -1


func car_at(p: Vector2, radius := 12.0) -> int:
	var best := -1
	var bd := radius * radius
	for i in sim.cars.size():
		var d := car_pos(i).distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return best


func enemy_at(p: Vector2) -> int:
	var best := -1
	var bd := 81.0
	for e: Sim.Enemy in sim.enemies:
		if e.dead or not e.visible:
			continue
		var d := (e.pos + Vector2(0, -6)).distance_squared_to(p)
		if d < bd:
			bd = d
			best = e.id
	return best
