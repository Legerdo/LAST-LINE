class_name Juice
extends RefCounted
## Turns sim events into feedback: particles, lights, shake, hitstop, sound, text, banners.

var run: Node
var view: WorldView
var hud: Hud
var sim: Sim
var station_voice_cd := 0.0
var last_hit_voice := 0.0


func _init(r: Node, v: WorldView, h: Hud, s: Sim) -> void:
	run = r
	view = v
	hud = h
	sim = s


func tick(delta: float) -> void:
	station_voice_cd = maxf(0.0, station_voice_cd - delta)


func handle(ev: Dictionary) -> void:
	var fx := view.fx
	var fxg := view.fxg
	match String(ev.t):
		"place":
			view.fac_drop(int(ev.lot))
			var d: Dictionary = Defs.FACILITIES[ev.fac]
			if d.cat == "hostile":
				Audio.sfx("hostile_place", -4.0)
		"purge":
			view.fac_remove_fx(int(ev.lot))
			Audio.sfx("boom", -2.0)
			hud.toast("%s 소각 · 군세 -4" % Defs.FACILITIES[ev.from].name, UI.COL.orange)
		"evolve":
			var to: String = ev.to
			var good: bool = Defs.FACILITIES[to].cat != "hostile"
			view.fac_morph(int(ev.lot), to, good)
			Audio.sfx("evolve" if good else "corrupt", -1.0)
			hud.show_banner("%s → %s" % [Defs.FACILITIES[ev.from].name, Defs.FACILITIES[to].name], "진화" if good else "위험한 변이", UI.COL.cyan if good else UI.COL.red, 1.3)
		"corrupt":
			view.fac_morph(int(ev.lot), String(ev.to), false)
			Audio.sfx("corrupt", -1.0)
			hud.show_banner("%s 감염" % Defs.FACILITIES[ev.from].name, "%s(으)로 변했다" % Defs.FACILITIES[ev.to].name, UI.COL.purple, 1.3)
		"spawn":
			var p: Vector2 = ev.pos
			if bool(ev.elite):
				fx.burst(p, 30, Color8(90, 80, 90), Color8(30, 26, 36, 0), 70.0, 0.9, 2.0, 30.0, 2.0, PI, -PI * 0.5, 1.0)
				fxg.ring(p, 4.0, 40.0, Color8(255, 80, 80), 0.5, 2.0)
				view.shake(0.45)
				view.flash_light(p, 90.0, Color(1.0, 0.3, 0.3), 0.6)
				Audio.sfx("elite", 0.0)
				var nm: String = Defs.ENEMIES[ev.type].name
				hud.show_banner("엘리트 출현", nm, UI.COL.orange, 1.2)
			else:
				fx.burst(p, 5, Color8(80, 74, 86), Color8(30, 28, 40, 0), 20.0, 0.4, 1.0, 0.0, 3.0)
		"hit":
			var p: Vector2 = ev.pos
			var dmg: float = ev.dmg
			var crit: bool = ev.crit
			var n := view.enemy_node(int(ev.id))
			if not n.is_empty():
				n.sq = 1.0
			fxg.burst(p + Vector2(0, -5), 3 if not crit else 8, Color8(255, 240, 200), Color8(255, 140, 60, 0), 60.0, 0.18, 1.0, 0.0, 6.0)
			if crit:
				fxg.text(p + Vector2(0, -14), str(int(round(dmg))) + "!", Color8(255, 214, 90), true)
				Audio.sfx("crit", -6.0)
			elif dmg >= 3.0:
				fxg.text(p + Vector2(0, -12), str(int(round(dmg))), Color8(240, 236, 250), false, 0.6)
			Audio.sfx("hit", -10.0)
		"kill":
			_kill(ev)
		"shot":
			var i: int = ev.car
			var from := view.car_pos(i)
			var to: Vector2 = ev.to
			var dir := (to - from).normalized()
			fxg.tracer(from + dir * 4.0, to + Vector2(0, -4), Color8(255, 240, 170), 0.06)
			fxg.burst(from + dir * 6.0, 3, Color8(255, 250, 200), Color8(255, 160, 60, 0), 50.0, 0.08, 1.0, 0.0, 6.0, 0.8, dir.angle())
			fx.burst(from, 1, Color8(220, 180, 80), Color8(120, 90, 40), 30.0, 0.5, 1.0, 120.0, 1.0, 1.0, dir.angle() + PI * 0.5, 1.0, from.y + 3.0)
			view.flash_light(from + dir * 6.0, 18.0, Color(1.0, 0.85, 0.5), 0.06)
			Audio.sfx("gun", -9.0)
		"flame":
			var from := view.car_pos(int(ev.car))
			var to: Vector2 = ev.to
			var dir := (to - from).normalized()
			fxg.burst(from + dir * 5.0, 6, Color8(255, 240, 160), Color8(220, 50, 20, 0), 110.0, 0.35, 2.0, -20.0, 3.0, 0.5, dir.angle(), 1.0)
			view.flash_light(from + dir * 16.0, 34.0, Color(1.0, 0.55, 0.2), 0.12)
			Audio.sfx("flame", -8.0)
		"mortar":
			var from := view.car_pos(int(ev.car))
			fxg.burst(from, 6, Color8(255, 250, 210), Color8(255, 120, 40, 0), 40.0, 0.15, 1.0, 0.0, 5.0)
			fx.burst(from, 4, Color8(90, 86, 96), Color8(30, 28, 40, 0), 20.0, 0.8, 2.0, -10.0, 1.0, TAU, 0.0, 4.0)
			view.flash_light(from, 30.0, Color(1.0, 0.8, 0.5), 0.1)
			Audio.sfx("mortar", -4.0)
		"tmortar":
			var from: Vector2 = ev.from
			fxg.burst(from, 6, Color8(255, 250, 210), Color8(255, 120, 40, 0), 40.0, 0.15, 1.0, 0.0, 5.0)
			Audio.sfx("mortar", -6.0)
		"boom":
			var p: Vector2 = ev.pos
			var r: float = ev.r
			var enemy := bool(ev.get("enemy", false))
			fxg.burst(p, 18, Color8(255, 250, 200), Color8(230, 70, 20, 0), 60.0 + r * 2.0, 0.35, 2.0, -20.0, 3.0, TAU, 0.0, 1.0)
			fx.burst(p, 10, Color8(70, 64, 76), Color8(24, 22, 30, 0), 30.0, 1.1, 3.0, -14.0, 1.2, TAU, 0.0, 6.0)
			fx.burst(p, 8, Color8(110, 96, 90), Color8(60, 50, 50), 70.0, 0.7, 1.0, 180.0, 1.0, PI, -PI * 0.5, 1.0, p.y + 3.0)
			fxg.ring(p, 2.0, r + 6.0, Color8(255, 220, 150), 0.25, 1.0)
			view.flash_light(p, r * 3.5, Color(1.0, 0.6, 0.3), 0.3)
			view.shake(0.18 if not enemy else 0.28)
			Audio.sfx("boom_small" if r < 18.0 else "boom", -5.0)
		"zap":
			var pts: Array = ev.pts
			if ev.has("car"):
				pts[0] = view.car_pos(int(ev.car))
			fxg.bolt(pts, Color8(120, 200, 255), 0.14)
			for q in pts:
				fxg.burst(q, 4, Color8(220, 245, 255), Color8(80, 140, 255, 0), 40.0, 0.2, 1.0, 0.0, 5.0)
			view.flash_light(pts[pts.size() - 1], 36.0, Color(0.5, 0.75, 1.0), 0.12)
			Audio.sfx("zap", -6.0)
		"tshot":
			var from: Vector2 = ev.from
			var to: Vector2 = ev.to
			fxg.tracer(from, to + Vector2(0, -4), Color8(200, 255, 170), 0.06)
			fxg.burst(from, 2, Color8(255, 255, 200), Color8(200, 255, 120, 0), 30.0, 0.08, 1.0)
			Audio.sfx("gun", -14.0, 0.8)
		"eshot":
			if String(ev.kind) == "bullet":
				Audio.sfx("shot_enemy", -12.0)
			else:
				Audio.sfx("throw", -8.0)
		"fireburst":
			var p: Vector2 = ev.pos
			fxg.burst(p, 16, Color8(255, 220, 120), Color8(220, 50, 20, 0), 50.0, 0.5, 2.0, -40.0, 2.0)
			view.flash_light(p, 50.0, Color(1.0, 0.5, 0.2), 0.3)
			Audio.sfx("molotov", -4.0)
		"train_hit":
			var p: Vector2 = ev.pos
			var dmg: float = ev.dmg
			fxg.burst(p, 4 + int(dmg), Color8(255, 230, 170), Color8(255, 90, 40, 0), 70.0, 0.25, 1.0, 60.0, 3.0)
			if dmg >= 1.5:
				fxg.text(p + Vector2(0, -8), "-" + str(int(round(dmg))), Color8(255, 90, 90), dmg >= 8.0, 0.7)
			view.shake(clampf(dmg * 0.03, 0.04, 0.5))
			if dmg >= 10.0:
				run.hitstop(0.06)
				view.screen_flash(Color(1, 0.2, 0.2), 0.35)
			Audio.sfx("train_hit", -6.0 + minf(6.0, dmg * 0.4))
		"bite":
			var p: Vector2 = ev.pos
			fx.burst(p, 3, Color8(200, 50, 50), Color8(80, 20, 20), 30.0, 0.3, 1.0, 60.0, 2.0)
			if bool(ev.get("heavy", false)):
				view.shake(0.3)
				Audio.sfx("heavy_bite", -2.0)
		"ram":
			var p: Vector2 = ev.pos
			fx.burst(p, 8, Color8(200, 60, 60), Color8(70, 20, 30), 60.0, 0.4, 1.0, 100.0, 2.0)
			fxg.burst(p, 5, Color8(255, 240, 200), Color8(255, 150, 60, 0), 60.0, 0.15, 1.0)
			view.shake(0.12)
			Audio.sfx("ram", -4.0)
		"thud":
			view.shake(0.35)
			Audio.sfx("thud", -2.0)
		"push":
			var p: Vector2 = ev.pos
			fxg.burst(p, 6, Color8(255, 240, 180), Color8(255, 120, 40, 0), 60.0, 0.25, 1.0, 80.0, 3.0)
			view.shake(0.1)
			Audio.sfx("metal_hit", -8.0, 0.7)
		"blast":
			var p: Vector2 = ev.pos
			var r: float = ev.r
			fxg.burst(p, 26, Color8(210, 255, 120), Color8(140, 50, 200, 0), 90.0, 0.6, 2.0, 40.0, 2.5)
			fx.burst(p, 16, Color8(120, 70, 140), Color8(50, 30, 60, 0), 60.0, 1.2, 2.0, 0.0, 2.0, TAU, 0.0, 5.0)
			fxg.ring(p, 3.0, r + 4.0, Color8(200, 255, 120), 0.35, 1.0)
			view.flash_light(p, r * 3.0, Color(0.7, 1.0, 0.4), 0.35)
			view.shake(0.35)
			Audio.sfx("splat", -2.0)
		"scrap":
			var n: int = ev.n
			var p: Vector2 = ev.pos
			if n >= 6:
				fxg.text(p + Vector2(0, -20), "+%d 고철" % n, Color8(255, 214, 90), true, 1.0)
				Audio.sfx("scrap_big", -6.0)
			elif n > 0:
				fxg.text(p + Vector2(0, -10), "+%d" % n, Color8(255, 214, 90), false, 0.7)
				Audio.sfx("scrap", -12.0)
		"card":
			var p: Vector2 = ev.pos
			if p.x >= 0.0:
				fxg.burst(p + Vector2(0, -8), 10, Color8(255, 255, 220), Color8(255, 200, 80, 0), 50.0, 0.4, 1.0, -30.0, 3.0)
				fxg.text(p + Vector2(0, -22), "카드!", Color8(180, 240, 255), true, 0.8)
			hud.card_arrived(String(ev.card))
			Audio.sfx("card_get", -4.0)
		"discard":
			if not bool(ev.get("manual", false)):
				hud.toast("손패가 가득: %s 버림 (+고철 2)" % UI.card_title(String(ev.card)), UI.COL.dim)
		"survivors":
			var n: int = ev.n
			var p: Vector2 = ev.get("pos", view.car_pos(0))
			if n > 0:
				fxg.text(p + Vector2(0, -24), "+%d 생존자" % n, Color8(120, 230, 255), true, 1.0)
				_board(p, n)
				hud.punch_survivors()
				Audio.sfx("board", -4.0)
		"full":
			var lp: Vector2 = view._fac_anchor(int(ev.lot))
			fxg.text(lp + Vector2(0, -30), "탑승 한도!", Color8(255, 150, 120), false, 1.0)
			run.first_time("full", "객차가 가득 찼어. 객차를 달면 더 태울 수 있어.")
		"station":
			var lp: Vector2 = view._fac_anchor(int(ev.lot))
			view.flash_light(lp + Vector2(0, -10), 70.0, Color(0.6, 0.9, 1.0), 0.6)
			Audio.sfx("station", -3.0)
			if station_voice_cd <= 0.0:
				station_voice_cd = 50.0
				var vname: String = ["station_1", "station_2", "station_3"][randi() % 3]
				Audio.voice(vname, -2.0)
		"repair":
			var n: float = ev.n
			if n >= 1.0:
				var p := view.car_pos(0)
				fxg.text(p + Vector2(0, -16), "+%d 수리" % int(round(n)), Color8(140, 240, 120), n >= 10.0, 0.9)
				for i in sim.cars.size():
					fxg.burst(view.car_pos(i), 3, Color8(180, 255, 160), Color8(60, 200, 90, 0), 20.0, 0.6, 1.0, -30.0, 1.0)
				Audio.sfx("repair", -6.0)
		"armory":
			var lp: Vector2 = view._fac_anchor(int(ev.lot))
			fxg.text(lp + Vector2(0, -34), "무기 강화!", Color8(255, 200, 120), true, 1.0)
			Audio.sfx("upgrade", -6.0)
		"spores":
			var lp: Vector2 = view._fac_anchor(int(ev.lot))
			fxg.burst(lp + Vector2(0, -12), 30, Color8(210, 140, 255, 200), Color8(120, 60, 180, 0), 50.0, 1.2, 3.0, -8.0, 1.0)
			Audio.sfx("spore", -4.0)
		"unpaid":
			var lp: Vector2 = view._fac_anchor(int(ev.lot))
			fxg.text(lp + Vector2(0, -34), "유지비 부족", Color8(255, 110, 110), false, 1.4)
			run.first_time("unpaid", "보급품이 모자라 검문소가 멈췄어. 온실이나 공장이 보급을 채워 줘.")
		"starve":
			hud.toast("보급 부족: 생존자 %d명이 떠났다" % int(ev.n), UI.COL.red)
			Audio.sfx("bad", -4.0)
		"theft":
			var lp: Vector2 = view._fac_anchor(int(ev.lot))
			fxg.text(lp + Vector2(0, -34), "약탈당함", Color8(255, 150, 90), false, 1.2)
		"raiders_arrive":
			hud.toast("시장 소문을 듣고 약탈자가 자리 잡았다", UI.COL.orange)
			var lp: Vector2 = view._fac_anchor(int(ev.lot))
			view.fac_drop(int(ev.lot))
			fxg.ring(lp + Vector2(0, -10), 4.0, 30.0, Color8(255, 120, 60), 0.4)
		"bell":
			var p: Vector2 = ev.pos
			fxg.ring(p, 6.0, 70.0, Color8(255, 230, 150), 0.5, 2.0)
			Audio.sfx("bell", -2.0)
		"relic":
			var r: Dictionary = Defs.RELICS[ev.relic]
			hud.show_banner("유물 획득 — " + String(r.name), String(r.desc), UI.COL.yellow, 2.0)
			view.screen_flash(Color(1.0, 0.9, 0.6), 0.4)
			Audio.sfx("relic", 0.0)
			run.hitstop(0.08)
		"blueprint":
			var names := {"card:power": "발전소", "card:radio": "무선탑", "car:tesla": "테슬라차"}
			hud.show_banner("설계도 발견 — " + String(names.get(ev.id, ev.id)), "귀환하면 기지에서 해금할 수 있다", UI.COL.cyan, 2.0)
			Audio.sfx("relic", 0.0)
		"module":
			hud.toast("개조 완료: " + String(Defs.MODULES[ev.mod].name), UI.COL.yellow)
			for i in sim.cars.size():
				fxg.burst(view.car_pos(i), 4, Color8(255, 240, 160), Color8(255, 150, 60, 0), 40.0, 0.4, 1.0, 20.0, 2.0)
			Audio.sfx("upgrade", -3.0)
		"car_added", "car_replaced":
			view.call_deferred("car_pop", int(ev.index))
			Audio.sfx("couple", -2.0)
			hud.toast("%s 연결" % Defs.CARS[ev.car].name, UI.COL.yellow)
		"supplies":
			hud.toast("보급품 +%d" % int(ev.n), UI.COL.orange)
		"depot":
			Audio.sfx("depot", -3.0)
			Audio.voice("depot", -2.0)
		"depart":
			Audio.sfx("horn", -3.0)
		"loop_end":
			pass
		"loop_pass":
			hud.show_banner("차량기지 봉쇄", "검은 열차를 쓰러뜨려야 한다", UI.COL.red, 1.4)
		"event":
			pass
		"boss_spawn":
			view.screen_flash(Color(0.9, 0.1, 0.1), 0.8)
			view.shake(0.8)
			Audio.sfx("alarm", 0.0)
			Audio.voice("boss_warning", 0.0)
			Audio.music("boss")
			hud.show_banner("검은 열차", "죽은 노선 위로 무언가 달려온다", UI.COL.red, 2.6)
			run.hitstop(0.25)
		"boss_alongside":
			Audio.sfx("boss_horn", 0.0)
			view.shake(0.5)
			if Game.seen("tip_boss"):
				hud.radio("붙었어! 호위 차량부터 부숴. 그래야 기관차에 제대로 박힌다.", "dispatcher", 4.0)
		"boss_telegraph":
			Audio.sfx("boss_charge", -2.0)
		"boss_ram":
			var p: Vector2 = ev.pos
			fxg.ring(p, 8.0, 76.0, Color8(255, 60, 60), 0.5, 3.0)
			fxg.ring(p, 4.0, 50.0, Color8(255, 200, 150), 0.35, 1.0)
			view.shake(0.8)
			view.screen_flash(Color(1, 0.3, 0.2), 0.5)
			run.hitstop(0.12)
			Audio.sfx("boss_horn", 2.0)
		"boss_salvo":
			var p: Vector2 = ev.pos
			fxg.burst(p, 12, Color8(255, 240, 200), Color8(255, 60, 40, 0), 60.0, 0.2, 2.0)
			view.flash_light(p, 50.0, Color(1.0, 0.4, 0.3), 0.15)
			Audio.sfx("cannon", -3.0)
		"boss_brood":
			var p: Vector2 = ev.pos
			fxg.burst(p, 20, Color8(210, 255, 120), Color8(160, 60, 200, 0), 50.0, 0.6, 2.0)
			Audio.sfx("splat", -4.0)
		"boss_mortar_mark":
			fxg.mark(ev.pos, float(ev.dur), Color8(255, 70, 60), "x", 14.0)
		"bhit":
			var p: Vector2 = ev.pos
			var dmg: float = ev.dmg
			fxg.burst(p + Vector2(randf_range(-8, 8), randf_range(-3, 3)), 3, Color8(255, 220, 160), Color8(255, 90, 40, 0), 50.0, 0.2, 1.0)
			if dmg >= 4.0 or bool(ev.crit):
				fxg.text(p + Vector2(randf_range(-10, 10), -10), str(int(round(dmg))), Color8(255, 170, 120) if not bool(ev.crit) else Color8(255, 220, 90), bool(ev.crit), 0.6)
			Audio.sfx("metal_hit", -10.0)
		"bpart_dead":
			var p: Vector2 = ev.pos
			for k in 4:
				fxg.burst(p + Vector2(randf_range(-12, 12), randf_range(-4, 4)), 20, Color8(255, 250, 200), Color8(230, 60, 20, 0), 90.0, 0.5, 2.0, -20.0, 2.0)
			fx.burst(p, 20, Color8(60, 54, 64), Color8(20, 18, 26, 0), 40.0, 1.6, 3.0, -16.0, 1.0, TAU, 0.0, 6.0)
			fxg.ring(p, 4.0, 60.0, Color8(255, 200, 120), 0.5, 2.0)
			view.flash_light(p, 120.0, Color(1.0, 0.6, 0.3), 0.7)
			view.shake(0.7)
			run.hitstop(0.14)
			Audio.sfx("big_boom", 0.0)
			if String(ev.part) != "head":
				hud.toast("검은 열차 %s 격파" % {"gun": "포탑차", "brood": "번식차", "mortar": "박격포차"}.get(ev.part, "차량"), UI.COL.yellow)
		"boss_enrage":
			view.screen_flash(Color(1, 0.1, 0.1), 0.5)
			hud.show_banner("검은 열차가 격노했다", "", UI.COL.red, 1.2)
			Audio.sfx("roar", 0.0)
		"boss_dead":
			run.boss_death_sequence()
		"dead":
			run.death_sequence()
		"returned":
			pass


func _kill(ev: Dictionary) -> void:
	var fx := view.fx
	var fxg := view.fxg
	var type: String = ev.type
	var p: Vector2 = ev.pos
	var d: Dictionary = Defs.ENEMIES[type]
	var faction: String = d.faction
	var elite: bool = ev.elite
	if MECH_TYPES.has(type):
		fxg.burst(p + Vector2(0, -6), 20, Color8(255, 240, 180), Color8(255, 100, 30, 0), 90.0, 0.4, 2.0, 60.0, 2.0)
		fx.burst(p + Vector2(0, -4), 14, Color8(90, 80, 80), Color8(50, 44, 44), 80.0, 0.9, 2.0, 200.0, 1.0, PI, -PI * 0.5, 1.0, p.y + 2.0)
		fx.burst(p, 10, Color8(60, 56, 66), Color8(24, 22, 30, 0), 20.0, 1.4, 3.0, -16.0, 1.0, TAU, 0.0, 6.0)
		view.flash_light(p, 60.0, Color(1.0, 0.6, 0.3), 0.3)
		view.shake(0.3)
		Audio.sfx("boom", -3.0)
	else:
		var cols: Array = Juice.BLOOD.get(faction, Juice.BLOOD["neutral"])
		fx.burst(p + Vector2(0, -5), 10 if not elite else 40, cols[0], cols[1], 60.0, 0.5, 1.0, 140.0, 2.0, PI * 1.2, -PI * 0.5, 1.0, p.y + 2.0)
		fxg.burst(p + Vector2(0, -6), 6, Color(cols[0], 0.9), Color(cols[0], 0.0), 40.0, 0.25, 1.0, 0.0, 4.0)
		Audio.sfx("enemy_die", -8.0)
	if elite:
		view.shake(0.6)
		view.screen_flash(Color(1, 0.95, 0.8), 0.45)
		fxg.ring(p, 4.0, 50.0, Color8(255, 230, 160), 0.5, 2.0)
		view.flash_light(p, 110.0, Color(1.0, 0.8, 0.5), 0.6)
		run.hitstop(0.16)
		Audio.sfx("elite_die", 0.0)
		hud.show_banner("%s 처치" % d.name, "", UI.COL.yellow, 1.0)


func _board(from: Vector2, n: int) -> void:
	# little survivors run from the building to the train (pure visual)
	for k in mini(n, 5):
		var s := Sprite2D.new()
		s.texture = UI.tex("res://assets/sprites/enemy/%s.png" % ("child" if randf() < 0.3 else "survivor"))
		s.position = from + Vector2(randf_range(-10, 10), randf_range(-4, 4))
		s.offset = Vector2(0, -6)
		view.ents.add_child(s)
		var target := view.car_pos(randi_range(0, maxi(0, sim.cars.size() - 1)))
		var tw := s.create_tween()
		tw.tween_interval(k * 0.08)
		tw.tween_property(s, "position", target, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(s, "scale", Vector2(0.6, 0.6), 0.5)
		tw.tween_callback(s.queue_free)


const MECH_TYPES := ["barricade", "warrig"]
const BLOOD := {
	"infected": [Color8(170, 230, 90), Color8(70, 40, 70)], "raider": [Color8(220, 50, 50), Color8(90, 24, 24)],
	"dark": [Color8(130, 90, 220), Color8(24, 16, 36)], "neutral": [Color8(200, 200, 200), Color8(60, 60, 60)],
}
