class_name LineMap
extends RefCounted
## Geometry of the loop line: ordered track cells, a dense arc-length path,
## building lots beside the track, their adjacency graph, and the derelict
## "dead line" that runs parallel on the inside (the Black Train's track).

const TILE := 16
const COLS := 40
const ROWS := 17
const STEP := 2.0  # arc-length resolution of the sampled path (px)

var cells: Array[Vector2i] = []          # track cells in travel order
var cell_index := {}                     # Vector2i -> index in cells
var tunnel := {}                         # Vector2i -> true for tunnel cells (both lines)
var pts := PackedVector2Array()          # uniformly resampled path points
var length := 0.0
var lots: Array = []                     # Array[Dictionary]
var depot_rect := Rect2i()               # cells occupied by the depot building
var depot_s := 0.0
var blocked := {}                        # Vector2i -> true (track, depot, lots)
# dead line
var gcells: Array[Vector2i] = []
var gcell_index := {}
var gpts := PackedVector2Array()
var glength := 0.0
var m2g := PackedFloat32Array()          # main pts index -> ghost s


static func build_default(rng_seed: int) -> LineMap:
	var m := LineMap.new()
	# Clockwise loop (screen space, y down). Start at the depot heading west.
	var turns: Array[Vector2i] = [
		Vector2i(9, 13), Vector2i(4, 13), Vector2i(4, 3), Vector2i(15, 3),
		Vector2i(15, 7), Vector2i(24, 7), Vector2i(24, 3), Vector2i(35, 3),
		Vector2i(35, 13), Vector2i(9, 13)]
	m.cells = _cells_from_turns(turns)
	for i in m.cells.size():
		m.cell_index[m.cells[i]] = i
		m.blocked[m.cells[i]] = true
	m.gcells = _cells_from_turns(_inset(turns))
	for i in m.gcells.size():
		m.gcell_index[m.gcells[i]] = i
		m.blocked[m.gcells[i]] = true
	for y in range(5, 12):
		m.tunnel[Vector2i(35, y)] = true
		m.tunnel[Vector2i(34, y)] = true
	for x in range(17, 23):
		m.tunnel[Vector2i(x, 7)] = true
		m.tunnel[Vector2i(x, 8)] = true
	m.depot_rect = Rect2i(7, 14, 4, 3)
	var main := _sample(m.cells)
	m.pts = main[0]
	m.length = main[1]
	var ghost := _sample(m.gcells)
	m.gpts = ghost[0]
	m.glength = ghost[1]
	m.depot_s = 8.0
	m.m2g.resize(m.pts.size())
	for k in m.pts.size():
		m.m2g[k] = m._nearest_on(m.gpts, m.pts[k])
	m._build_lots(rng_seed)
	return m


## inset a clockwise rectilinear loop by one cell toward its interior
static func _inset(turns: Array[Vector2i]) -> Array[Vector2i]:
	var n := turns.size() - 1  # last == first
	var out: Array[Vector2i] = []
	for i in n:
		var prev: Vector2i = turns[(i - 1 + n) % n]
		var cur: Vector2i = turns[i]
		var nxt: Vector2i = turns[(i + 1) % n]
		var da := Vector2i(signi(cur.x - prev.x), signi(cur.y - prev.y))
		var db := Vector2i(signi(nxt.x - cur.x), signi(nxt.y - cur.y))
		var na := Vector2i(-da.y, da.x)
		var nb := Vector2i(-db.y, db.x)
		out.append(cur + na if da == db else cur + na + nb)
	out.append(out[0])
	return out


static func _cells_from_turns(turns: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in range(turns.size() - 1):
		var a: Vector2i = turns[i]
		var b: Vector2i = turns[i + 1]
		var d := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
		var c := a
		while c != b:
			out.append(c)
			c += d
	return out


static func cell_center(c: Vector2i) -> Vector2:
	return Vector2(c.x * TILE + TILE * 0.5, c.y * TILE + TILE * 0.5)


static func dirs_of(list: Array[Vector2i], i: int) -> Array:
	var n := list.size()
	var prev: Vector2i = list[(i - 1 + n) % n]
	var cur: Vector2i = list[i]
	var nxt: Vector2i = list[(i + 1) % n]
	return [cur - prev, nxt - cur]


func cell_dirs(i: int) -> Array:
	return dirs_of(cells, i)


## returns [PackedVector2Array uniform points, float length]
static func _sample(list: Array[Vector2i]) -> Array:
	var raw := PackedVector2Array()
	var n := list.size()
	for i in n:
		var dirs := dirs_of(list, i)
		var din: Vector2i = dirs[0]
		var dout: Vector2i = dirs[1]
		var c := cell_center(list[i])
		var p_in := c - Vector2(din) * 8.0
		if din == dout:
			for k in 8:
				raw.append(p_in + Vector2(din) * (k * 2.0))
		else:
			var center := c - Vector2(din) * 8.0 + Vector2(dout) * 8.0
			var a0 := (p_in - center).angle()
			var p_out := c + Vector2(dout) * 8.0
			var a1 := (p_out - center).angle()
			var da := wrapf(a1 - a0, -PI, PI)
			for k in 8:
				var a := a0 + da * (k / 8.0)
				raw.append(center + Vector2(cos(a), sin(a)) * 8.0)
	var cum := PackedFloat32Array()
	cum.resize(raw.size() + 1)
	cum[0] = 0.0
	for i in raw.size():
		cum[i + 1] = cum[i] + raw[i].distance_to(raw[(i + 1) % raw.size()])
	var total := cum[raw.size()]
	var count := int(ceil(total / STEP))
	var out := PackedVector2Array()
	out.resize(count)
	var j := 0
	for k in count:
		var s := k * STEP
		while j < raw.size() - 1 and cum[j + 1] < s:
			j += 1
		var seg := cum[j + 1] - cum[j]
		var t := 0.0 if seg <= 0.0001 else (s - cum[j]) / seg
		out[k] = raw[j].lerp(raw[(j + 1) % raw.size()], t)
	return [out, total]


func _nearest_on(arr: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	var best_k := 0
	for k in arr.size():
		var d := arr[k].distance_squared_to(p)
		if d < best:
			best = d
			best_k = k
	return best_k * STEP


func wrap_s(s: float) -> float:
	return fposmod(s, length)


func pos_at(s: float) -> Vector2:
	var u := fposmod(s, length) / STEP
	var i := int(u)
	var t := u - i
	var n := pts.size()
	return pts[i % n].lerp(pts[(i + 1) % n], t)


func dir_at(s: float) -> Vector2:
	var d := pos_at(s + 3.0) - pos_at(s - 3.0)
	return d.normalized() if d.length_squared() > 0.0001 else Vector2.RIGHT


func gpos_at(s: float) -> Vector2:
	var u := fposmod(s, glength) / STEP
	var i := int(u)
	var t := u - i
	var n := gpts.size()
	return gpts[i % n].lerp(gpts[(i + 1) % n], t)


func gdir_at(s: float) -> Vector2:
	var d := gpos_at(s + 3.0) - gpos_at(s - 3.0)
	return d.normalized() if d.length_squared() > 0.0001 else Vector2.RIGHT


## ghost-line coordinate next to a main-line coordinate
func main_to_ghost(s: float) -> float:
	var u := fposmod(s, length) / STEP
	return m2g[int(u) % m2g.size()]


func nearest_s(p: Vector2) -> float:
	return _nearest_on(pts, p)


## forward distance along the loop from a to b (0..length)
func ahead(a: float, b: float) -> float:
	return fposmod(b - a, length)


func is_tunnel_s(s: float) -> bool:
	var p := pos_at(s)
	return tunnel.has(Vector2i(int(p.x / TILE), int(p.y / TILE)))


func is_tunnel_g(s: float) -> bool:
	var p := gpos_at(s)
	return tunnel.has(Vector2i(int(p.x / TILE), int(p.y / TILE)))


func _area_free(r: Rect2i) -> bool:
	if r.position.x < 0 or r.position.y < 0 or r.end.x > COLS or r.end.y > ROWS:
		return false
	for x in range(r.position.x, r.end.x):
		for y in range(r.position.y, r.end.y):
			if blocked.has(Vector2i(x, y)) or tunnel.has(Vector2i(x, y)):
				return false
	return true


func _build_lots(_rng_seed: int) -> void:
	for x in range(depot_rect.position.x, depot_rect.end.x):
		for y in range(depot_rect.position.y, depot_rect.end.y):
			blocked[Vector2i(x, y)] = true
	var reserved := Rect2i(depot_rect.position - Vector2i(1, 1), depot_rect.size + Vector2i(2, 1))
	# outside lots touch the main line; inside lots touch the dead line
	_lots_along(cells, 1, reserved)
	_lots_along(gcells, -1, reserved)
	for a in lots:
		var nb: Array = []
		for b in lots:
			if a.id == b.id:
				continue
			if (a.center as Vector2).distance_to(b.center) <= 4.3 * TILE:
				nb.append(b.id)
		a.neighbors = nb


func _lots_along(list: Array[Vector2i], side: int, reserved: Rect2i) -> void:
	var since := 99
	for i in list.size():
		var dirs := dirs_of(list, i)
		var din: Vector2i = dirs[0]
		var dout: Vector2i = dirs[1]
		var c: Vector2i = list[i]
		since += 1
		if din != dout or tunnel.has(c) or since < 4:
			continue
		# outward normal of a clockwise loop in screen space = (d.y, -d.x)
		var off := Vector2i(din.y, -din.x) * side
		var r: Rect2i
		if off.x == 0:
			var top := c.y + 1 if off.y > 0 else c.y - 2
			var left := c.x if din.x > 0 else c.x - 1
			r = Rect2i(left, top, 2, 2)
		else:
			var lft := c.x + 1 if off.x > 0 else c.x - 2
			var tp := c.y if din.y > 0 else c.y - 1
			r = Rect2i(lft, tp, 2, 2)
		if r.intersects(reserved) or not _area_free(r):
			continue
		for dx in range(r.position.x, r.end.x):
			for dy in range(r.position.y, r.end.y):
				blocked[Vector2i(dx, dy)] = true
		var center := Vector2(r.position.x * TILE + TILE, r.position.y * TILE + TILE)
		var s := nearest_s(center)
		var tp_pt := pos_at(s)
		lots.append({
			"id": lots.size(), "rect": r, "center": center, "s": s,
			"track_pt": tp_pt, "normal": (center - tp_pt).normalized(),
			"neighbors": [], "side": side})
		since = 0
