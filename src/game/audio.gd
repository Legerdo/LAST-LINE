extends Node
## Autoload "Audio": pooled SFX with rate limiting and variants, layered adaptive music,
## and PA-style voice announcements that duck the music.

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const VOICE_DIR := "res://assets/audio/voice/"
const POOL := 28
# minimum seconds between two plays of the same sound
const MIN_GAP := {"gun": 0.045, "hit": 0.03, "flame": 0.12, "zap": 0.05, "scrap": 0.05, "step": 0.1,
	"hover": 0.05, "enemy_die": 0.04, "train_hit": 0.08, "shot_enemy": 0.06, "boom_small": 0.05}

var _players: Array[AudioStreamPlayer] = []
var _cache := {}
var _last := {}
var _layers := {}          # name -> AudioStreamPlayer
var _layer_target := {}    # name -> linear volume target
var _voice: AudioStreamPlayer
var _duck := 1.0
var _music_set := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for b in ["Music", "SFX", "Voice"]:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
	_voice = AudioStreamPlayer.new()
	_voice.bus = "Voice"
	add_child(_voice)
	apply_volumes()


func apply_volumes() -> void:
	var s: Dictionary = Game.profile.get("settings", {})
	_set_bus("SFX", float(s.get("sfx", 0.8)))
	_set_bus("Music", float(s.get("music", 0.6)))
	_set_bus("Voice", float(s.get("voice", 0.9)))


func _set_bus(bus: String, v: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(0.0001, v)))
		AudioServer.set_bus_mute(i, v <= 0.001)


func _load(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
	_cache[path] = s
	return s


func _variants(name: String) -> Array:
	var key := "v:" + name
	if _cache.has(key):
		return _cache[key]
	var out: Array = []
	var base := _load(SFX_DIR + name + ".wav")
	if base:
		out.append(base)
	for i in range(1, 6):
		var v := _load(SFX_DIR + "%s_%d.wav" % [name, i])
		if v:
			out.append(v)
	_cache[key] = out
	return out


## play a sound effect; returns false if it was rate-limited or missing
func sfx(name: String, vol_db := 0.0, pitch := 1.0, pitch_var := 0.06) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	var gap: float = MIN_GAP.get(name, 0.02)
	if now - float(_last.get(name, -10.0)) < gap:
		return false
	var vs := _variants(name)
	if vs.is_empty():
		return false
	_last[name] = now
	var p := _free_player()
	p.stream = vs[randi() % vs.size()]
	p.volume_db = vol_db
	p.pitch_scale = maxf(0.05, pitch * (1.0 + randf_range(-pitch_var, pitch_var)))
	p.play()
	return true


func _free_player() -> AudioStreamPlayer:
	for p in _players:
		if not p.playing:
			return p
	# steal the oldest
	var p: AudioStreamPlayer = _players.pop_front()
	_players.append(p)
	return p


# ------------------------------------------------------------ music
## set: "title", "hub", "run", "boss", "end", ""
func music(set_name: String) -> void:
	if set_name == _music_set:
		return
	_music_set = set_name
	var layers := {}
	match set_name:
		"title":
			layers = {"title": 1.0}
		"hub":
			layers = {"hub": 1.0}
		"run":
			layers = {"run_base": 1.0, "run_tension": 0.0, "run_combat": 0.0}
		"boss":
			layers = {"boss": 1.0}
		"end":
			layers = {"end": 1.0}
	# fade out layers not in the new set
	for k in _layers.keys():
		if not layers.has(k):
			_layer_target[k] = 0.0
	var start_pos := -1.0
	for k in layers.keys():
		if not _layers.has(k):
			var st := _load(MUSIC_DIR + k + ".ogg")
			if st == null:
				st = _load(MUSIC_DIR + k + ".wav")
			if st == null:
				continue
			if st is AudioStreamOggVorbis:
				(st as AudioStreamOggVorbis).loop = k != "end"
			elif st is AudioStreamWAV:
				(st as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD if k != "end" else AudioStreamWAV.LOOP_DISABLED
			var p := AudioStreamPlayer.new()
			p.bus = "Music"
			p.stream = st
			p.volume_db = -60.0
			add_child(p)
			_layers[k] = p
			# layers of one set start together so they stay in sync
			if start_pos < 0.0:
				start_pos = 0.0
			p.play(start_pos)
		_layer_target[k] = float(layers[k])


## intensity layers inside the run set (0..1 each)
func music_mix(tension: float, combat: float) -> void:
	if _music_set != "run":
		return
	_layer_target["run_tension"] = clampf(tension, 0.0, 1.0)
	_layer_target["run_combat"] = clampf(combat, 0.0, 1.0)


func _process(delta: float) -> void:
	var target_duck := 0.45 if _voice.playing else 1.0
	_duck = move_toward(_duck, target_duck, delta * 2.5)
	for k in _layers.keys():
		var p: AudioStreamPlayer = _layers[k]
		var target: float = _layer_target.get(k, 0.0) * _duck
		var cur := db_to_linear(p.volume_db)
		var speed := 0.6 if target > cur else 0.9
		cur = move_toward(cur, target, delta * speed)
		p.volume_db = linear_to_db(maxf(cur, 0.0001))
		if target <= 0.0 and cur <= 0.001 and not (_layer_target.get(k, 0.0) > 0.0):
			p.queue_free()
			_layers.erase(k)
			_layer_target.erase(k)


# ------------------------------------------------------------ voice
func voice(name: String, vol_db := 0.0) -> bool:
	var st := _load(VOICE_DIR + name + ".ogg")
	if st == null:
		st = _load(VOICE_DIR + name + ".wav")
	if st == null:
		return false
	if _voice.playing:
		return false
	_voice.stream = st
	_voice.volume_db = vol_db
	_voice.play()
	return true


func voice_playing() -> bool:
	return _voice.playing
