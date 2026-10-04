extends Node
## Autoload "Game": persistent profile, depot (meta) upgrades, settings and screen flow.

signal profile_changed

const SAVE_PATH := "user://profile.json"
const BLUEPRINTS := ["card:power", "card:radio", "car:tesla"]

const UPGRADES := [
	{"id": "hull", "name": "정비고", "desc": "최대 선체 +20.", "max": 3, "cost": [[60, 0], [120, 0], [200, 2]]},
	{"id": "flame", "name": "화염방사차 설계", "desc": "화염방사차가 보급에 등장한다.\n근거리 광역 화상.", "max": 1, "cost": [[80, 0]]},
	{"id": "mortar", "name": "박격포차 설계", "desc": "박격포차가 보급에 등장한다.\n먼 무리에 포격.", "max": 1, "cost": [[100, 0]]},
	{"id": "armor", "name": "장갑차 설계", "desc": "장갑차가 보급에 등장한다.\n모든 피해 -1, 들이받기 강화.", "max": 1, "cost": [[90, 0]]},
	{"id": "repair", "name": "정비차 설계", "desc": "정비차가 보급에 등장한다.\n전투 밖 자동 수리.", "max": 1, "cost": [[110, 2]]},
	{"id": "greenhouse", "name": "온실 기술", "desc": "온실 카드가 나온다.\n보급품 생산, 피난처를 공동체로.", "max": 1, "cost": [[70, 2]]},
	{"id": "armory", "name": "무기고 기술", "desc": "무기고 카드가 나온다.\n통과 시 무기 강화, 검문소를 포대로.", "max": 1, "cost": [[90, 0]]},
	{"id": "tesla", "name": "테슬라차 설계", "desc": "테슬라차가 보급에 등장한다.\n연쇄 전격.", "max": 1, "cost": [[150, 3]], "blueprint": "car:tesla"},
	{"id": "power", "name": "발전소 기술", "desc": "발전소 카드가 나온다.\n전기 선로, 공장을 조립공장으로.", "max": 1, "cost": [[120, 3]], "blueprint": "card:power"},
	{"id": "radio", "name": "무선탑 기술", "desc": "무선탑 카드가 나온다.\n매 바퀴 무전 사건, 큰 소음.", "max": 1, "cost": [[100, 3]], "blueprint": "card:radio"},
	{"id": "barracks", "name": "숙소 증축", "desc": "시작 생존자 +2.\n생존자는 연사 속도를 올린다.", "max": 2, "cost": [[40, 5], [80, 10]]},
	{"id": "store", "name": "창고", "desc": "시작 보급품 +5.\n열차 파괴 시 고철 보존 +10%.", "max": 2, "cost": [[70, 0], [140, 4]]},
	{"id": "gunworks", "name": "무기 공방", "desc": "기관총차 1량을 더 달고 출발.", "max": 1, "cost": [[130, 4]]},
	{"id": "signal", "name": "비상 무전", "desc": "시작 카드 +2.", "max": 1, "cost": [[90, 3]]},
	{"id": "coupler", "name": "연결소", "desc": "연결 가능한 차량 +1.", "max": 1, "cost": [[150, 8]]},
	{"id": "window", "name": "보급 창구", "desc": "차량기지 보급 선택지 +1.", "max": 1, "cost": [[160, 6]]},
]

var profile := {}
var main: Node = null
var last_result := {}
var run_seed := 0


func _ready() -> void:
	load_profile()
	_apply_settings()


func _exit_tree() -> void:
	# static texture/font caches would otherwise be reported as leaks at exit
	UI._tex.clear()
	UI._fonts.clear()


func default_profile() -> Dictionary:
	return {"scrap": 0, "survivors": 0, "upgrades": {}, "blueprints": [], "runs": 0, "wins": 0,
		"deaths": 0, "returns": 0, "best_loop": 0, "total_kills": 0, "seen": {},
		"settings": {"sfx": 0.8, "music": 0.6, "voice": 0.9, "shake": 1.0, "fullscreen": false}}


func load_profile() -> void:
	profile = default_profile()
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		var data = JSON.parse_string(f.get_as_text())
		if data is Dictionary:
			for k in data.keys():
				profile[k] = data[k]
			var s: Dictionary = default_profile().settings
			for k in s.keys():
				if not profile.settings.has(k):
					profile.settings[k] = s[k]


func save_profile() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(profile, "  "))
	f.close()
	profile_changed.emit()


func reset_profile() -> void:
	var settings: Dictionary = profile.settings
	profile = default_profile()
	profile.settings = settings
	save_profile()


func _apply_settings() -> void:
	var s: Dictionary = profile.settings
	if s.get("fullscreen", false):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func set_setting(k: String, v) -> void:
	profile.settings[k] = v
	if k == "fullscreen":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if v else DisplayServer.WINDOW_MODE_WINDOWED)
	Audio.apply_volumes()
	save_profile()


func setting(k: String, default = null):
	return profile.settings.get(k, default)


func seen(key: String) -> bool:
	return bool(profile.seen.get(key, false))


func mark_seen(key: String) -> void:
	if not seen(key):
		profile.seen[key] = true
		save_profile()


## forget every tutorial / tip flag so the next run teaches again
func reset_tutorial() -> void:
	var keep := {}
	for k in profile.seen.keys():
		var key := String(k)
		if not (key == "tutorial_done" or key == "tips_off" or key == "hub_walk" or key == "help_opened" or key.begins_with("tip_")):
			keep[k] = profile.seen[k]
	profile.seen = keep
	save_profile()


# ------------------------------------------------------------ upgrades
func level(id: String) -> int:
	return int(profile.upgrades.get(id, 0))


func upgrade_def(id: String) -> Dictionary:
	for u in UPGRADES:
		if u.id == id:
			return u
	return {}


func upgrade_available(u: Dictionary) -> bool:
	if u.has("blueprint") and not (profile.blueprints as Array).has(u.blueprint):
		return false
	return level(u.id) < int(u.max)


func upgrade_cost(u: Dictionary) -> Array:
	var lv := level(u.id)
	if lv >= int(u.max):
		return [0, 0]
	return u.cost[lv]


func can_buy(u: Dictionary) -> bool:
	if not upgrade_available(u):
		return false
	var c := upgrade_cost(u)
	return int(profile.scrap) >= int(c[0]) and int(profile.survivors) >= int(c[1])


func buy(u: Dictionary) -> bool:
	if not can_buy(u):
		return false
	var c := upgrade_cost(u)
	profile.scrap = int(profile.scrap) - int(c[0])
	profile.survivors = int(profile.survivors) - int(c[1])
	profile.upgrades[u.id] = level(u.id) + 1
	save_profile()
	return true


func sim_mods() -> Dictionary:
	var m := {"heat": mini(int(profile.wins), 5), "hull": 20 * level("hull"), "cars": [], "cards": [], "survivors": 2 * level("barracks"),
		"supplies": 5 * level("store"), "keep": 0.10 * level("store"), "max_cars": level("coupler"),
		"depot_options": level("window"), "extra_gun": level("gunworks") > 0, "hand": 2 * level("signal")}
	for c in ["flame", "mortar", "armor", "repair", "tesla"]:
		if level(c) > 0:
			m.cars.append(c)
	for c in ["greenhouse", "armory", "power", "radio"]:
		if level(c) > 0:
			m.cards.append(c)
	var locked: Array = []
	for b in BLUEPRINTS:
		if not (profile.blueprints as Array).has(b):
			locked.append(b)
	m["locked"] = locked
	return m


# ------------------------------------------------------------ runs
func new_seed() -> int:
	run_seed = int(Time.get_unix_time_from_system()) % 1000000 + randi() % 1000
	return run_seed


func finish_run(res: Dictionary) -> void:
	last_result = res.duplicate(true)
	profile.runs = int(profile.runs) + 1
	profile.scrap = int(profile.scrap) + int(res.get("scrap", 0))
	profile.survivors = int(profile.survivors) + int(res.get("survivors", 0))
	profile.total_kills = int(profile.total_kills) + int(res.get("kills", 0))
	profile.best_loop = maxi(int(profile.best_loop), int(res.get("loops", 0)))
	var new_bp: Array = []
	for b in res.get("blueprints", []):
		if not (profile.blueprints as Array).has(b):
			profile.blueprints.append(b)
			new_bp.append(b)
	last_result["new_blueprints"] = new_bp
	match String(res.get("state", "")):
		"dead":
			profile.deaths = int(profile.deaths) + 1
		"returned":
			profile.returns = int(profile.returns) + 1
		"victory":
			profile.wins = int(profile.wins) + 1
	save_profile()


func goto(screen: String) -> void:
	if main:
		main.show_screen(screen)
