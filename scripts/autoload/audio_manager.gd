extends Node
## Autoload "AudioManager": sound effects (pooled, positional in the world),
## UI sounds and music with cross-fade. Buses Music / SFX / UI are created at
## start-up under Master; volumes come from SaveManager.
## Sounds are referenced by id (AssetPaths.SFX / AssetPaths.MUSIC); a missing
## file is skipped silently, so placeholder files can be removed or replaced.

const BUSES: Array[StringName] = [&"Music", &"SFX", &"UI"]
const WORLD_VOICES := 16
const UI_VOICES := 4
const MUSIC_FADE := 1.2

var _world: Array[AudioStreamPlayer2D] = []
var _ui: Array[AudioStreamPlayer] = []
var _music: Array[AudioStreamPlayer] = []
var _music_index := 0
var _music_id: StringName = &""
var _cache: Dictionary = {}  # path -> AudioStream
var _last_played: Dictionary = {}  # id -> msec (avoid stacking the same sound)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus_name in BUSES:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, &"Master")
	for i in WORLD_VOICES:
		var p := AudioStreamPlayer2D.new()
		p.bus = &"SFX"
		p.max_distance = 700.0
		p.attenuation = 1.5
		add_child(p)
		_world.append(p)
	for i in UI_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = &"UI"
		add_child(p)
		_ui.append(p)
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = &"Music"
		p.volume_db = -80.0
		p.finished.connect(func() -> void:
			if p == _music[_music_index]:
				p.play())  # loop
		add_child(p)
		_music.append(p)
	apply_volumes()


func apply_volumes() -> void:
	_set_bus(&"Master", SaveManager.master_volume)
	_set_bus(&"Music", SaveManager.music_volume)
	_set_bus(&"SFX", SaveManager.sfx_volume)
	_set_bus(&"UI", SaveManager.ui_volume)


func _set_bus(bus_name: StringName, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))


func _stream(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	var s: AudioStream = load(path) if ResourceLoader.exists(path) else null
	_cache[path] = s
	return s


func _throttled(id: StringName, min_ms: int) -> bool:
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(id, -100000)) < min_ms:
		return true
	_last_played[id] = now
	return false


## World sound. `pos` = Vector2.INF plays it at the listener (non-positional).
func play_sfx(id: StringName, pos: Vector2 = Vector2.INF, volume_db := 0.0, pitch_variation := 0.08) -> void:
	if id == &"" or not AssetPaths.SFX.has(id) or _throttled(id, 30):
		return
	var stream := _stream(AssetPaths.SFX[id])
	if stream == null:
		return
	var player: AudioStreamPlayer2D = null
	for p in _world:
		if not p.playing:
			player = p
			break
	if player == null:
		player = _world[0]
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	var cam := get_viewport().get_camera_2d()
	player.global_position = pos if pos != Vector2.INF else (cam.get_screen_center_position() if cam else Vector2.ZERO)
	player.play()


func play_ui(id: StringName, volume_db := 0.0) -> void:
	if id == &"" or not AssetPaths.SFX.has(id) or _throttled(id, 25):
		return
	var stream := _stream(AssetPaths.SFX[id])
	if stream == null:
		return
	for p in _ui:
		if not p.playing:
			p.stream = stream
			p.volume_db = volume_db
			p.play()
			return


## Cross-fades to another music track (same id = keep playing).
func play_music(id: StringName) -> void:
	if id == _music_id:
		return
	_music_id = id
	var old := _music[_music_index]
	_music_index = 1 - _music_index
	var new := _music[_music_index]
	if old.playing:
		var tw := create_tween()
		tw.tween_property(old, "volume_db", -80.0, MUSIC_FADE)
		tw.tween_callback(old.stop)
	var stream: AudioStream = _stream(AssetPaths.MUSIC.get(id, ""))
	if stream == null:
		return
	new.stream = stream
	new.volume_db = -40.0
	new.play()
	create_tween().tween_property(new, "volume_db", 0.0, MUSIC_FADE)


func stop_music() -> void:
	_music_id = &""
	for p in _music:
		p.stop()
