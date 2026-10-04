extends SceneTree
## Dumps the line geometry to art_src/map.json for the ground baker (tools/gen_ground.py).


func _init() -> void:
	var m := LineMap.build_default(1)
	var lots: Array = []
	for l: Dictionary in m.lots:
		var r: Rect2i = l.rect
		lots.append({"id": l.id, "x": r.position.x, "y": r.position.y, "w": r.size.x, "h": r.size.y,
			"side": l.side, "neighbors": l.neighbors})
	var cells: Array = []
	for i in m.cells.size():
		var d := m.cell_dirs(i)
		cells.append([m.cells[i].x, m.cells[i].y, d[0].x, d[0].y, d[1].x, d[1].y])
	var gcells: Array = []
	for i in m.gcells.size():
		var d := LineMap.dirs_of(m.gcells, i)
		gcells.append([m.gcells[i].x, m.gcells[i].y, d[0].x, d[0].y, d[1].x, d[1].y])
	var tun: Array = []
	for c: Vector2i in m.tunnel.keys():
		tun.append([c.x, c.y])
	var out := {"cols": LineMap.COLS, "rows": LineMap.ROWS, "tile": LineMap.TILE, "cells": cells,
		"gcells": gcells, "tunnel": tun, "lots": lots, "length": m.length, "glength": m.glength,
		"depot": [m.depot_rect.position.x, m.depot_rect.position.y, m.depot_rect.size.x, m.depot_rect.size.y]}
	var f := FileAccess.open("res://art_src/map.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("lots=%d cells=%d gcells=%d length=%.0f glength=%.0f" % [lots.size(), cells.size(), gcells.size(), m.length, m.glength])
	quit()
