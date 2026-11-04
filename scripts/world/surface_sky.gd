class_name SurfaceSky
extends Node
## The sky over the surface of a location (LocationManager keeps one):
## - time of day within the session: dawn, day, evening, night, a full
##   turn in DAY_LENGTH seconds from a phase the location's seed picks;
##   the night is a soft blue darkening (never below NIGHT_LIGHT), the
##   brightness slider still works on top (post FX);
## - the weather of the biome (SurfaceBiomeData.weather): rain, fog, wind,
##   ash or snow particles around the camera, re-rolled now and then;
## - the ambience loops: day / night of the biome, the rain.
## Active only while the local hero is on the surface.

const DAY_LENGTH := 600.0
const NIGHT_LIGHT := 0.58
const WEATHER_EVERY := 180.0
## Tints of the phases (multiplying the biome's ambient light).
const TINTS := {
	&"dawn": Color(0.98, 0.9, 0.9), &"day": Color(1, 1, 1),
	&"evening": Color(1.0, 0.86, 0.72), &"night": Color(NIGHT_LIGHT, 0.64, 0.9),
}

var biome: SurfaceBiomeData
var active := false
## 0..1 along the day (0 dawn, 0.12 day, 0.55 evening, 0.68 night, 0.95 dawn).
var phase := 0.15
var weather: StringName = &"none"
var _ambient: CanvasModulate
var _base := Color.WHITE
var _particles: CPUParticles2D
var _camera: Camera2D
var _weather_left := WEATHER_EVERY
var _rng := RandomNumberGenerator.new()


func setup(p_biome: SurfaceBiomeData, seed_value: int, ambient: CanvasModulate, camera: Camera2D) -> void:
	biome = p_biome
	_ambient = ambient
	_camera = camera
	_rng.seed = seed_value
	phase = _rng.randf_range(0.05, 0.8)
	_roll_weather()


## The hero came up (true) or went down (false).
func set_active(on: bool) -> void:
	active = on
	if on:
		_base = _ambient.color if _ambient else Color.WHITE
		_apply_weather()
		_ambience()
	else:
		if _particles:
			_particles.emitting = false
		AudioManager.play_ambience(&"", 0)
		AudioManager.play_ambience(&"", 1)
		_light_backgrounds(true)


static func phase_name(p: float) -> StringName:
	if p < 0.1 or p >= 0.95:
		return &"dawn"
	if p < 0.55:
		return &"day"
	if p < 0.68:
		return &"evening"
	return &"night"


func is_night() -> bool:
	return phase_name(phase) == &"night"


func _process(delta: float) -> void:
	if not active or biome == null:
		return
	var was := phase_name(phase)
	phase = fmod(phase + delta / DAY_LENGTH, 1.0)
	if _ambient:
		_ambient.color = _base * _tint()
	if phase_name(phase) != was:
		_ambience()
		if phase_name(phase) == &"night":
			EventBus.message.emit(tr("Наступает ночь."))
		elif phase_name(phase) == &"dawn":
			EventBus.message.emit(tr("Светает."))
	_weather_left -= delta
	if _weather_left <= 0.0:
		_weather_left = WEATHER_EVERY
		_roll_weather()
		_apply_weather()
		_ambience()
	if _particles and _camera:
		_particles.global_position = _camera.get_screen_center_position() + Vector2(0, -200)
	_light_backgrounds()


## How dark the sky is (0 day .. 1 deep night), smooth over dusk and dawn.
func night_amount() -> float:
	if phase < 0.06:
		return lerpf(0.35, 0.0, phase / 0.06)
	if phase < 0.64:
		return 0.0
	if phase < 0.72:
		return (phase - 0.64) / 0.08
	if phase < 0.93:
		return 1.0
	return lerpf(1.0, 0.35, (phase - 0.93) / 0.07)


## The colour of the hour on the backgrounds: rosy dawn, a golden evening;
## a grey overcast while it rains.
func sky_tint() -> Color:
	var c := _hour_tint()
	if weather == &"rain":
		c = c.lerp(Color(0.62, 0.68, 0.78), 0.62)
	return c


func _hour_tint() -> Color:
	if phase < 0.1:
		return Color(1.0, 0.84, 0.86).lerp(Color.WHITE, phase / 0.1)
	if phase > 0.5 and phase < 0.74:
		var t := 1.0 - absf(phase - 0.63) / 0.11
		return Color.WHITE.lerp(Color(1.0, 0.68, 0.46), clampf(t * 1.3, 0.0, 1.0))
	return Color.WHITE


## The parallax of the scene follows the hour (assets/shaders/parallax_life):
## night and stars on the sky, the tint of dawn and evening, shafts of light.
func _light_backgrounds(off := false) -> void:
	var scene := get_tree().current_scene
	var par := scene.get_node_or_null("Parallax") if scene else null
	if par == null:
		return
	var n := 0.0 if off else night_amount()
	var tint := Color.WHITE if off else sky_tint()
	var day := 0.0 if off else clampf(1.0 - n, 0.0, 1.0) * (1.0 if phase > 0.1 and phase < 0.55 else 0.4)
	for layer in par.get_children():
		var spr := layer.get_child(0) as Sprite2D if layer.get_child_count() > 0 else null
		var m := spr.material as ShaderMaterial if spr else null
		if m == null:
			continue
		m.set_shader_parameter("night", n)
		m.set_shader_parameter("sky_tint", tint)
		m.set_shader_parameter("rays", day * (biome.light_rays if biome else 0.0))
	var front := scene.get_node_or_null("FrontParallax") as ParallaxBackground
	if front:
		front.get_child(0).modulate = tint.lerp(Color(0.3, 0.34, 0.5), n * 0.8) if not off else Color.WHITE


## A smooth blend between the phases' tints.
func _tint() -> Color:
	var keys := [[0.0, &"dawn"], [0.1, &"day"], [0.55, &"day"], [0.62, &"evening"], [0.7, &"night"], [0.93, &"night"], [1.0, &"dawn"]]
	for i in keys.size() - 1:
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if phase >= a[0] and phase <= b[0]:
			var t := (phase - float(a[0])) / maxf(0.0001, float(b[0]) - float(a[0]))
			return (TINTS[a[1]] as Color).lerp(TINTS[b[1]], t)
	return Color.WHITE


func _roll_weather() -> void:
	var total := 0.0
	for k in biome.weather:
		total += float(biome.weather[k])
	var r := _rng.randf() * total
	weather = &"none"
	for k in biome.weather:
		r -= float(biome.weather[k])
		if r <= 0.0:
			weather = StringName(k)
			break


func _apply_weather() -> void:
	if _particles == null:
		_particles = CPUParticles2D.new()
		_particles.local_coords = false
		_particles.z_index = 30
		_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		_particles.emission_rect_extents = Vector2(420, 10)
		add_child(_particles)
	var p := _particles
	p.emitting = weather != &"none" and active
	p.texture = null
	p.particle_flag_align_y = false
	p.scale_amount_min = 1.0
	p.scale_amount_max = 1.0
	match weather:
		&"rain":
			p.amount = 260
			p.lifetime = 1.2
			p.direction = Vector2(0.18, 1)
			p.spread = 3.0
			p.gravity = Vector2(60, 500)
			p.initial_velocity_min = 300.0
			p.initial_velocity_max = 360.0
			p.color = Color(0.8, 0.88, 1.0, 0.6)
			p.texture = AssetPaths.tex("res://assets/sprites/critters/raindrop.png")
			p.particle_flag_align_y = true  # streaks along the fall, not dots
		&"snow":
			p.amount = 140
			p.lifetime = 6.0
			p.direction = Vector2(0.1, 1)
			p.spread = 30.0
			p.gravity = Vector2(10, 20)
			p.initial_velocity_min = 20.0
			p.initial_velocity_max = 40.0
			p.color = Color(1, 1, 1, 0.8)
			p.scale_amount_max = 2.0
		&"ash":
			p.amount = 90
			p.lifetime = 7.0
			p.direction = Vector2(0.4, 1)
			p.spread = 40.0
			p.gravity = Vector2(15, 12)
			p.initial_velocity_min = 15.0
			p.initial_velocity_max = 35.0
			p.color = Color(0.55, 0.5, 0.48, 0.7)
		&"wind":
			p.amount = 40
			p.lifetime = 4.0
			p.direction = Vector2(1, 0.2)
			p.spread = 20.0
			p.gravity = Vector2(0, 15)
			p.initial_velocity_min = 120.0
			p.initial_velocity_max = 180.0
			p.color = Color(0.55, 0.7, 0.35, 0.8)
			p.emission_rect_extents = Vector2(420, 180)
		&"fog":
			p.amount = 10
			p.lifetime = 10.0
			p.texture = AssetPaths.tex(AssetPaths.LIGHT)
			p.direction = Vector2(1, 0)
			p.spread = 10.0
			p.gravity = Vector2.ZERO
			p.initial_velocity_min = 6.0
			p.initial_velocity_max = 14.0
			p.color = Color(0.92, 0.95, 0.96, 0.07)  # a veil, not a wall
			p.scale_amount_min = 2.5
			p.scale_amount_max = 4.0
			p.emission_rect_extents = Vector2(420, 200)
	if weather != &"wind" and weather != &"fog":
		p.emission_rect_extents = Vector2(420, 10)
	# raindrops ring the ponds
	var lvl = get_tree().current_scene.get("level") if get_tree().current_scene else null
	if lvl is DungeonLevel:
		(lvl as DungeonLevel).set_rain(1.0 if weather == &"rain" and active else 0.0)


func _ambience() -> void:
	if not active or biome == null:
		return
	AudioManager.play_ambience(biome.ambience_night if is_night() else biome.ambience_day, 0)
	AudioManager.play_ambience(&"amb_rain" if weather == &"rain" else (&"amb_wind" if weather == &"wind" else &""), 1, -14.0)
