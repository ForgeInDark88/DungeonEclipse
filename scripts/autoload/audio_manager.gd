extends Node
## Autoload "AudioManager": sound effects (pooled, positional in the world),
## UI sounds and music with cross-fade. Buses Music / SFX / UI are created at
## start-up under Master; volumes come from SaveManager.
## Sounds are referenced by id (AssetPaths.SFX / AssetPaths.MUSIC); a missing
## file is skipped silently (music first tries AssetPaths.MUSIC_FALLBACK), so
## placeholder files can be removed or replaced at any time.
##
## Music by situation (who calls what): menus → "menu"; a floor → the biome
## track (BiomeData.music); boss arena → BossData.music; boss defeated →
## sting "victory", then back to the biome; hero died → sting "death".
## Every change is a cross-fade of MUSIC_FADE seconds.

const BUSES: Array[StringName] = [&"Music", &"SFX", &"UI"]
const WORLD_VOICES := 16
const UI_VOICES := 4
const MUSIC_FADE := 1.5

## A one-shot track (victory, death) ended.
signal music_finished(id: StringName)

var _world: Array[AudioStreamPlayer2D] = []
var _ui: Array[AudioStreamPlayer] = []
var _music: Array[AudioStreamPlayer] = []
var _music_index := 0
## Running fade tween of each music player. A new fade kills the old one:
## otherwise a quick double switch (biome track, then the boss track in the
## same frame) left a fade-out running that stopped the new track.
var _fades: Array[Tween] = [null, null]
var _music_id: StringName = &""
## Track to return to when the current sting ends (&"" = stay silent).
var _after_sting: StringName = &""
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
				_on_music_finished(p))
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
	_after_sting = &""
	_switch_music(id)


## Plays a one-shot track, then cross-fades to `then_id` (&"" = silence).
func play_sting(id: StringName, then_id: StringName = &"") -> void:
	_switch_music(id)
	_after_sting = then_id
	if _music_stream(id) == null:  # no file: go on right away
		_after_sting = &""
		if then_id != &"":
			_switch_music(then_id)


func current_music() -> StringName:
	return _music_id


## The stream for `id`, following AssetPaths.MUSIC_FALLBACK when a file is missing.
## OGG tracks loop seamlessly in the stream itself; stings never loop.
func _music_stream(id: StringName) -> AudioStream:
	var tried := {}
	var one_shot := id in AssetPaths.MUSIC_ONE_SHOT
	while id != &"" and not tried.has(id):
		tried[id] = true
		var stream := _stream(AssetPaths.MUSIC.get(id, ""))
		if stream:
			# WAV files loop through _on_music_finished instead.
			if stream is AudioStreamOggVorbis:
				(stream as AudioStreamOggVorbis).loop = not one_shot
			return stream
		id = AssetPaths.MUSIC_FALLBACK.get(id, &"")
	return null


func _switch_music(id: StringName) -> void:
	if id == _music_id:
		return
	_music_id = id
	var old_i := _music_index
	var old := _music[old_i]
	_music_index = 1 - _music_index
	var new := _music[_music_index]
	_kill_fade(old_i)
	_kill_fade(_music_index)
	if old.playing:
		var tw := create_tween()
		tw.tween_property(old, "volume_db", -80.0, MUSIC_FADE)
		tw.tween_callback(old.stop)
		_fades[old_i] = tw
	new.stop()
	var stream := _music_stream(id)
	if stream == null:
		return
	new.stream = stream
	new.volume_db = -40.0
	new.play()
	var fade_in := create_tween()
	fade_in.tween_property(new, "volume_db", 0.0, MUSIC_FADE)
	_fades[_music_index] = fade_in


func _kill_fade(i: int) -> void:
	if _fades[i] and _fades[i].is_valid():
		_fades[i].kill()
	_fades[i] = null


func _on_music_finished(p: AudioStreamPlayer) -> void:
	if _music_id not in AssetPaths.MUSIC_ONE_SHOT:
		p.play()  # loop
		return
	var done := _music_id
	music_finished.emit(done)
	var next := _after_sting
	_after_sting = &""
	_music_id = &""
	if next != &"":
		_switch_music(next)


func stop_music() -> void:
	_music_id = &""
	for i in _music.size():
		_kill_fade(i)
		_music[i].stop()
