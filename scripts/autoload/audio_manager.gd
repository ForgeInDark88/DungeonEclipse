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

const BUSES: Array[StringName] = [&"Music", &"SFX", &"UI", &"Ambient"]
const WORLD_VOICES := 16
const UI_VOICES := 4
const MUSIC_FADE := 1.5

## Voice priority by sound id prefix (higher wins a voice when all are busy;
## a sound never steals from a more important one). Unlisted: 1.
const PRIORITY := {&"step_": 0, &"land": 0, &"dust": 0, &"dig": 0, &"bubbles": 0, &"swim": 0,
	&"coin": 1, &"pickup_": 1, &"attack_": 2, &"hit_": 2, &"enemy_": 2, &"cast_": 2,
	&"player_": 3, &"boss_": 3, &"level_up": 3, &"explosion": 3, &"meteor_": 3, &"portal": 2}
## Acoustics of a place (BiomeData.acoustics): reverb on the SFX bus.
## room_size, damping, wet, pre-delay ms; "open" = no reverb.
const SPACES := {
	&"open": [0.0, 0.0, 0.0, 0.0],
	&"room": [0.35, 0.6, 0.12, 10.0],
	&"hall": [0.7, 0.45, 0.2, 25.0],
	&"cave": [0.8, 0.3, 0.24, 35.0],
	&"crypt": [0.6, 0.55, 0.22, 18.0],
	&"water": [0.75, 0.75, 0.26, 30.0],
}
## How long the combat layer stays after the last monster in a fight.
const COMBAT_HOLD := 4.0
const COMBAT_RANGE := 360.0

## A one-shot track (victory, death) ended.
signal music_finished(id: StringName)

var _world: Array[AudioStreamPlayer2D] = []
var _world_prio: Array[int] = []
var _ui: Array[AudioStreamPlayer] = []
var _music: Array[AudioStreamPlayer] = []
var _music_index := 0
## The combat layer of each music player (same index), and its fade.
var _combat: Array[AudioStreamPlayer] = []
var _combat_fades: Array[Tween] = [null, null]
var _combat_on := false
var _combat_hold := 0.0
var _combat_poll := 0.0
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
	_setup_underwater()
	for i in WORLD_VOICES:
		var p := AudioStreamPlayer2D.new()
		p.bus = &"SFX"
		p.max_distance = 700.0
		p.attenuation = 1.5
		add_child(p)
		_world.append(p)
		_world_prio.append(0)
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
		# its combat layer (music_<id>_combat.ogg), started with it
		var c := AudioStreamPlayer.new()
		c.bus = &"Music"
		c.volume_db = -80.0
		add_child(c)
		_combat.append(c)
	_setup_reverb()
	apply_volumes()


func apply_volumes() -> void:
	_set_bus(&"Master", SaveManager.master_volume)
	_set_bus(&"Music", SaveManager.music_volume)
	_set_bus(&"SFX", SaveManager.sfx_volume)
	_set_bus(&"UI", SaveManager.ui_volume)
	_set_bus(&"Ambient", SaveManager.ambient_volume)


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
	var stream := _variant(id)
	if stream == null:
		return
	var prio := priority_of(id)
	var slot := -1
	for i in _world.size():
		if not _world[i].playing:
			slot = i
			break
	if slot < 0:
		# All voices busy: take the least important one, never a more
		# important sound than this one.
		var low := prio + 1
		for i in _world.size():
			if _world_prio[i] < low:
				low = _world_prio[i]
				slot = i
		if slot < 0:
			return
	var player := _world[slot]
	_world_prio[slot] = prio
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	var cam := get_viewport().get_camera_2d()
	player.global_position = pos if pos != Vector2.INF else (cam.get_screen_center_position() if cam else Vector2.ZERO)
	player.play()


func play_ui(id: StringName, volume_db := 0.0) -> void:
	if id == &"" or not AssetPaths.SFX.has(id) or _throttled(id, 25):
		return
	var stream := _variant(id)
	if stream == null:
		return
	for p in _ui:
		if not p.playing:
			p.stream = stream
			p.volume_db = volume_db
			p.play()
			return


var _variants: Dictionary = {}  # id -> Array[String] of files


## A sound and its variants: <file>.wav, <file>_2.wav ... <file>_6.wav
## (tools/gen_audio.py); one is picked at random each time.
func _variant(id: StringName) -> AudioStream:
	if not _variants.has(id):
		var base: String = AssetPaths.SFX[id]
		var files: Array[String] = [base]
		for k in range(2, 7):
			var v := base.get_basename() + "_%d.%s" % [k, base.get_extension()]
			if ResourceLoader.exists(v):
				files.append(v)
		_variants[id] = files
	var list: Array = _variants[id]
	return _stream(list[randi() % list.size()])


## How many files sound `id` has (the base and its variants).
func variant_count(id: StringName) -> int:
	if not AssetPaths.SFX.has(id):
		return 0
	_variant(id)
	return (_variants[id] as Array).size()


static func priority_of(id: StringName) -> int:
	var s := String(id)
	for k in PRIORITY:
		if s.begins_with(String(k)):
			return PRIORITY[k]
	return 1


## Quitting: every player lets go of its stream first, so the audio thread
## holds no playback while the engine frees resources (no leaks at exit).
func _exit_tree() -> void:
	for p in find_children("*", "AudioStreamPlayer", true, false):
		(p as AudioStreamPlayer).stop()
		(p as AudioStreamPlayer).stream = null
	for p in find_children("*", "AudioStreamPlayer2D", true, false):
		(p as AudioStreamPlayer2D).stop()
		(p as AudioStreamPlayer2D).stream = null


# --------------------------------------------------------------- ambience
var _amb: Array[AudioStreamPlayer] = []
var _amb_id: Array[StringName] = [&"", &""]


## A loop of the world's air under the music (wind, birds, rain...) in one
## of two channels (0: the land, 1: the weather); &"" fades it out.
func play_ambience(id: StringName, channel := 0, volume_db := -10.0) -> void:
	if _amb.is_empty():
		for i in 2:
			var p := AudioStreamPlayer.new()
			p.bus = &"Ambient"
			p.volume_db = -80.0
			add_child(p)
			_amb.append(p)
	if _amb_id[channel] == id:
		return
	_amb_id[channel] = id
	var p := _amb[channel]
	var tw := create_tween()
	tw.tween_property(p, "volume_db", -80.0, 0.8)
	if id == &"" or not AssetPaths.AMBIENCE.has(id):
		tw.tween_callback(p.stop)
		return
	var stream := _stream(AssetPaths.AMBIENCE[id])
	if stream == null:
		return
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	tw.tween_callback(func() -> void:
		p.stream = stream
		p.play())
	tw.tween_property(p, "volume_db", volume_db, 1.2)


# ------------------------------------------------------------ under water
## A low-pass on the Master bus while the hero's head is under water: the
## world sounds dull and far away (Player._swim). Off by default.
var _underwater := false
var _uw_effect: AudioEffectLowPassFilter
var _uw_tween: Tween


func _setup_underwater() -> void:
	var master := AudioServer.get_bus_index(&"Master")
	_uw_effect = AudioEffectLowPassFilter.new()
	_uw_effect.cutoff_hz = 20000.0
	_uw_effect.resonance = 0.4
	AudioServer.add_bus_effect(master, _uw_effect)
	AudioServer.set_bus_effect_enabled(master, AudioServer.get_bus_effect_count(master) - 1, false)


func set_underwater(on: bool) -> void:
	if on == _underwater or _uw_effect == null:
		return
	_underwater = on
	var master := AudioServer.get_bus_index(&"Master")
	var idx := -1
	for i in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, i) == _uw_effect:
			idx = i
	if idx < 0:
		return
	if _uw_tween:
		_uw_tween.kill()
	if on:
		AudioServer.set_bus_effect_enabled(master, idx, true)
	_uw_tween = create_tween()
	_uw_tween.tween_property(_uw_effect, "cutoff_hz", 700.0 if on else 20000.0, 0.25)
	if not on:
		_uw_tween.tween_callback(func() -> void: AudioServer.set_bus_effect_enabled(master, idx, false))


func is_underwater() -> bool:
	return _underwater


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
		tw.parallel().tween_property(_combat[old_i], "volume_db", -80.0, MUSIC_FADE)
		tw.tween_callback(old.stop)
		tw.tween_callback(_combat[old_i].stop)
		_fades[old_i] = tw
	new.stop()
	var stream := _music_stream(id)
	if stream == null:
		return
	new.stream = stream
	new.volume_db = -40.0
	var layer := _combat_stream(id)
	var c := _combat[_music_index]
	c.stop()
	c.stream = layer
	c.volume_db = 0.0 if _combat_on and layer else -80.0
	new.play()
	if layer:
		c.play()
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
		_combat[i].stop()


# ----------------------------------------------------------- combat layer
## The combat layer of a track: music_<id>_combat.ogg next to it, as long as
## the track (it loops in step). None: the track has no layer.
func _combat_stream(id: StringName) -> AudioStream:
	if id in AssetPaths.MUSIC_ONE_SHOT or not AssetPaths.MUSIC.has(id):
		return null
	var path := String(AssetPaths.MUSIC[id]).get_basename() + "_combat.ogg"
	var s := _stream(path)
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	return s


## Fades the combat layer in or out (also driven by _process from the
## monsters near the camera).
func set_combat(on: bool) -> void:
	if on == _combat_on:
		return
	_combat_on = on
	var c := _combat[_music_index]
	if _combat_fades[_music_index] and _combat_fades[_music_index].is_valid():
		_combat_fades[_music_index].kill()
	if c.stream == null:
		return
	var tw := create_tween()
	tw.tween_property(c, "volume_db", 0.0 if on else -80.0, 0.6 if on else 2.5) \
		.set_trans(Tween.TRANS_SINE)
	_combat_fades[_music_index] = tw


func in_combat() -> bool:
	return _combat_on


## Is a monster near the camera fighting (chasing, attacking)? Polled 4 times
## a second; the layer stays COMBAT_HOLD s after the last one.
func _process(delta: float) -> void:
	_combat_poll -= delta
	if _combat_poll > 0.0:
		return
	_combat_poll = 0.25
	var cam := get_viewport().get_camera_2d() if get_viewport() else null
	var fighting := false
	if cam:
		var c := cam.get_screen_center_position()
		for e in get_tree().get_nodes_in_group("enemies"):
			if e.has_method("is_fighting") and e.is_fighting() and (e as Node2D).global_position.distance_to(c) < COMBAT_RANGE:
				fighting = true
				break
	if fighting:
		_combat_hold = COMBAT_HOLD
	else:
		_combat_hold -= 0.25
	set_combat(_combat_hold > 0.0)


# ----------------------------------------------------------------- reverb
var _reverb: AudioEffectReverb
var _space: StringName = &"open"


func _setup_reverb() -> void:
	var bus := AudioServer.get_bus_index(&"SFX")
	_reverb = AudioEffectReverb.new()
	_reverb.wet = 0.0
	_reverb.dry = 1.0
	AudioServer.add_bus_effect(bus, _reverb)
	AudioServer.set_bus_effect_enabled(bus, AudioServer.get_bus_effect_count(bus) - 1, false)


## The acoustics of the place (BiomeData.acoustics, AudioManager.SPACES).
func set_space(space: StringName) -> void:
	if not SPACES.has(space):
		space = &"open"
	if space == _space or _reverb == null:
		return
	_space = space
	var v: Array = SPACES[space]
	var bus := AudioServer.get_bus_index(&"SFX")
	var idx := -1
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i) == _reverb:
			idx = i
	if idx < 0:
		return
	_reverb.room_size = v[0]
	_reverb.damping = v[1]
	_reverb.wet = v[2]
	_reverb.predelay_msec = v[3]
	_reverb.hipass = 0.15
	AudioServer.set_bus_effect_enabled(bus, idx, space != &"open")


func current_space() -> StringName:
	return _space
