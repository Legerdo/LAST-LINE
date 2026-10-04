class_name FX
extends Node2D
## Immediate-mode pixel FX layer: square particles, tracers, rings, bolts, floating text,
## ground markers. Two instances exist: one lit by the light map, one "glow" drawn above it.

class P:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var life := 1.0
	var t := 0.0
	var size := 1.0
	var size_end := 1.0
	var c0 := Color.WHITE
	var c1 := Color.WHITE
	var grav := 0.0
	var drag := 0.0
	var floor_y := INF      # particles bounce/settle on this y (debris)


class Line:
	var a := Vector2.ZERO
	var b := Vector2.ZERO
	var t := 0.0
	var life := 0.08
	var c := Color.WHITE
	var w := 1.0


class Ring:
	var pos := Vector2.ZERO
	var r0 := 2.0
	var r1 := 20.0
	var t := 0.0
	var life := 0.3
	var c := Color.WHITE
	var w := 1.0


class Bolt:
	var pts: PackedVector2Array
	var t := 0.0
	var life := 0.12
	var c := Color.WHITE


class Txt:
	var pos := Vector2.ZERO
	var text := ""
	var t := 0.0
	var life := 0.8
	var c := Color.WHITE
	var size := 9
	var big := false
	var vy := -26.0


class Mark:
	var pos := Vector2.ZERO
	var t := 0.0
	var life := 1.0
	var c := Color.RED
	var kind := "x"
	var r := 12.0


var parts: Array = []
var lines: Array = []
var rings: Array = []
var bolts: Array = []
var texts: Array = []
var marks: Array = []
var font: Font
var small_font: Font
const MAX_PARTS := 1400


func _ready() -> void:
	font = UI.font(9)
	small_font = UI.font(7)


func burst(pos: Vector2, n: int, c0: Color, c1: Color, speed := 40.0, life := 0.5, size := 1.0,
		grav := 0.0, drag := 2.0, spread := TAU, dir := 0.0, size_end := -1.0, floor_y := INF) -> void:
	for i in n:
		if parts.size() >= MAX_PARTS:
			parts.pop_front()
		var p := P.new()
		p.pos = pos
		var a := dir + randf_range(-spread * 0.5, spread * 0.5)
		p.vel = Vector2.from_angle(a) * speed * randf_range(0.35, 1.0)
		p.life = life * randf_range(0.6, 1.2)
		p.size = size
		p.size_end = size if size_end < 0.0 else size_end
		p.c0 = c0
		p.c1 = c1
		p.grav = grav
		p.drag = drag
		p.floor_y = floor_y
		parts.append(p)


func tracer(a: Vector2, b: Vector2, c: Color, life := 0.07, w := 1.0) -> void:
	var l := Line.new()
	l.a = a
	l.b = b
	l.c = c
	l.life = life
	l.w = w
	lines.append(l)


func ring(pos: Vector2, r0: float, r1: float, c: Color, life := 0.3, w := 1.0) -> void:
	var r := Ring.new()
	r.pos = pos
	r.r0 = r0
	r.r1 = r1
	r.c = c
	r.life = life
	r.w = w
	rings.append(r)


func bolt(pts: Array, c: Color, life := 0.12) -> void:
	var b := Bolt.new()
	var out := PackedVector2Array()
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var z: Vector2 = pts[i + 1]
		var seg := int(maxf(2.0, a.distance_to(z) / 6.0))
		for k in seg:
			var p := a.lerp(z, float(k) / seg)
			if k > 0:
				p += Vector2(randf_range(-3, 3), randf_range(-3, 3))
			out.append(p)
	out.append(pts[pts.size() - 1])
	b.pts = out
	b.c = c
	b.life = life
	bolts.append(b)


func text(pos: Vector2, s: String, c: Color, big := false, life := 0.8) -> void:
	var t := Txt.new()
	t.pos = pos + Vector2(randf_range(-3, 3), 0)
	t.text = s
	t.c = c
	t.big = big
	t.life = life
	t.vy = -34.0 if big else -24.0
	texts.append(t)
	if texts.size() > 60:
		texts.pop_front()


func mark(pos: Vector2, life: float, c: Color, kind := "x", r := 12.0) -> void:
	var m := Mark.new()
	m.pos = pos
	m.life = life
	m.c = c
	m.kind = kind
	m.r = r
	marks.append(m)


func _process(delta: float) -> void:
	var dt := delta
	var i := 0
	while i < parts.size():
		var p: P = parts[i]
		p.t += dt
		if p.t >= p.life:
			parts.remove_at(i)
			continue
		p.vel.y += p.grav * dt
		p.vel *= maxf(0.0, 1.0 - p.drag * dt)
		p.pos += p.vel * dt
		if p.pos.y > p.floor_y:
			p.pos.y = p.floor_y
			p.vel.y *= -0.3
			p.vel.x *= 0.5
		i += 1
	for arr in [lines, rings, bolts, texts, marks]:
		var j := 0
		while j < arr.size():
			var o = arr[j]
			o.t += dt
			if o.t >= o.life:
				arr.remove_at(j)
				continue
			if o is Txt:
				o.pos.y += o.vy * dt
				o.vy *= maxf(0.0, 1.0 - 4.0 * dt)
			j += 1
	queue_redraw()


func _draw() -> void:
	for p: P in parts:
		var k := p.t / p.life
		var c := p.c0.lerp(p.c1, k)
		var s := maxf(1.0, round(lerpf(p.size, p.size_end, k)))
		draw_rect(Rect2(p.pos.floor() - Vector2(s, s) * 0.5, Vector2(s, s)), c)
	for l: Line in lines:
		var k := l.t / l.life
		var c := l.c
		c.a *= 1.0 - k
		draw_line(l.a.floor(), l.b.floor(), c, l.w)
	for r: Ring in rings:
		var k := r.t / r.life
		var e := 1.0 - pow(1.0 - k, 3.0)
		var c := r.c
		c.a *= 1.0 - k
		var rad := lerpf(r.r0, r.r1, e)
		var n := int(clampf(rad * 1.2, 10, 48))
		draw_arc(r.pos.floor(), rad, 0, TAU, n, c, r.w)
	for b: Bolt in bolts:
		var c := b.c
		c.a *= 1.0 - b.t / b.life
		draw_polyline(b.pts, Color(1, 1, 1, c.a), 1.0)
		var off := PackedVector2Array()
		for p in b.pts:
			off.append(p + Vector2(0, 1))
		draw_polyline(off, c, 1.0)
	for m: Mark in marks:
		var k := m.t / m.life
		var blink := int(m.t * (6.0 + 10.0 * k)) % 2 == 0
		var c := m.c
		c.a = 0.9 if blink else 0.45
		var r := m.r * (1.0 - 0.25 * k)
		if m.kind == "x":
			draw_line(m.pos + Vector2(-r, -r) * 0.5, m.pos + Vector2(r, r) * 0.5, c, 1.0)
			draw_line(m.pos + Vector2(-r, r) * 0.5, m.pos + Vector2(r, -r) * 0.5, c, 1.0)
			draw_arc(m.pos, r * 0.75, 0, TAU, 16, c, 1.0)
		else:
			draw_arc(m.pos, m.r * k, 0, TAU, 32, c, 1.0)
	for t: Txt in texts:
		var k := t.t / t.life
		var c := t.c
		c.a = 1.0 if k < 0.7 else 1.0 - (k - 0.7) / 0.3
		var f := font if t.big else small_font
		var fs := 10 if t.big else 8
		var pop := 1.0
		var w := f.get_string_size(t.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var p := (t.pos - Vector2(w * 0.5, 0)).floor()
		draw_string(f, p + Vector2(1, 1), t.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, c.a * 0.9))
		draw_string(f, p, t.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
		if pop:
			pass
