class_name SurfaceLife
extends Node2D
## Small life of the open surface (LocationManager adds it to the surface
## layer; only the view around the camera is alive, nothing touches play):
## - butterflies by day, fireflies at night (SurfaceSky.is_night);
## - birds perched in the crowns of trees take off when a hero comes near
##   and fly off; a while later others settle there again;
## - now and then a fish leaps out of a pond with a splash.
## Personal on every machine (pure decoration, no network).

const BUTTERFLIES := 5
const FIREFLIES := 14
const BIRD_SCARE := 90.0
const BIRD_RETURN := 50.0
const CRITTERS := "res://assets/sprites/critters/"

var level: DungeonLevel
var band := 0
var sky: SurfaceSky
var active := true
var _rng := RandomNumberGenerator.new()
var _flyers: Array = []     # {node, kind, home, t, vel}
var _perches: Array = []    # {pos, birds: [Sprite2D], gone_t}
var _fish_t := 4.0
var _ground: Dictionary = {}  # column -> global y of the ground top
var _rect := Rect2()


func setup(p_level: DungeonLevel, p_band: int, p_sky: SurfaceSky, seed_value: int) -> void:
	level = p_level
	band = p_band
	sky = p_sky
	_rng.seed = seed_value
	z_index = 1
	top_level = true  # everything here in world coordinates
	global_position = Vector2.ZERO
	var b := level.layout_band(band)
	if b.is_empty():
		return
	_rect = level.band_rect_px(level.cell_bottom(Vector2i(b["origin"]) + Vector2i(2, 2)))
	var sub: LevelLayout = b["layout"]
	var origin: Vector2i = b["origin"]
	for x in sub.width:
		for y in range(1, sub.height):
			if LevelLayout.is_solid(sub.get_tile(x, y)):
				_ground[x + origin.x] = level.cell_bottom(Vector2i(x, y - 1) + origin).y
				break
	for p in sub.surface_props:
		var tex := String(p["tex"])
		if tex.begins_with("tree") and _rng.randf() < 0.4:
			var base := level.cell_bottom(Vector2i(p["cell"]) + origin)
			_perches.append({"pos": base + Vector2(_rng.randf_range(-8, 8), -76 if tex != "tree_dead" else -66), "birds": [], "gone_t": 0.0})
	for perch in _perches:
		_settle(perch)


func _tex(name: String) -> Texture2D:
	return AssetPaths.tex(CRITTERS + name + ".png")


func _sprite(tex_name: String, frames: int) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = _tex(tex_name)
	s.hframes = frames
	add_child(s)
	return s


func _heroes() -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group("player"):
		var p := n as Node2D
		if p and is_instance_valid(p) and not ("dead" in p and p.dead):
			out.append(p)
	return out


func _view() -> Rect2:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return Rect2()
	var size := get_viewport_rect().size / cam.zoom
	return Rect2(cam.get_screen_center_position() - size / 2.0, size).grow(40)


func _ground_y(x: float) -> float:
	var col := int(floor(x / DungeonLevel.TILE))
	return float(_ground.get(col, _rect.end.y))


func _process(delta: float) -> void:
	visible = active
	if not active or level == null:
		return
	var view := _view()
	if view.size == Vector2.ZERO or not view.intersects(_rect):
		return
	var night := sky != null and sky.is_night()
	_keep(view, &"butterfly" if not night else &"firefly", BUTTERFLIES if not night else FIREFLIES)
	_step_flyers(delta, view, night)
	_step_birds(delta)
	_step_fish(delta, view)


# ------------------------------------------------------ butterflies, fireflies
func _keep(view: Rect2, kind: StringName, count: int) -> void:
	var have := 0
	for f in _flyers:
		if f["kind"] == kind:
			have += 1
	while have < count:
		var x := _rng.randf_range(view.position.x, view.end.x)
		var gy := _ground_y(x)
		if gy > view.end.y or gy < view.position.y:
			return
		var s: Sprite2D
		if kind == &"butterfly":
			s = _sprite("butterfly_%d" % _rng.randi_range(0, 3), 2)
		else:
			s = _sprite("firefly", 1)
			var m := CanvasItemMaterial.new()
			m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			s.material = m
			s.modulate = Color(1.6, 1.8, 0.9, 0.0)
		var home := Vector2(x, gy - _rng.randf_range(6, 40 if kind == &"firefly" else 22))
		s.position = home
		_flyers.append({"node": s, "kind": kind, "home": home, "t": _rng.randf() * 10.0, "life": _rng.randf_range(14, 30)})
		have += 1


func _step_flyers(delta: float, view: Rect2, night: bool) -> void:
	for f in _flyers.duplicate():
		if f["kind"] == &"bird" or f["kind"] == &"fish":
			continue
		var s: Sprite2D = f["node"]
		f["t"] += delta
		f["life"] -= delta
		var t: float = f["t"]
		var home: Vector2 = f["home"]
		var wrong: bool = (f["kind"] == &"butterfly") == night
		if f["life"] <= 0.0 or wrong or not view.grow(80).has_point(s.position):
			s.modulate.a -= delta * 1.5
			if s.modulate.a <= 0.0:
				s.queue_free()
				_flyers.erase(f)
			continue
		if f["kind"] == &"butterfly":
			# a fluttering loop around its flowers
			s.position = home + Vector2(sin(t * 0.9) * 18.0 + sin(t * 2.3) * 5.0, sin(t * 1.7) * 6.0 + sin(t * 7.0) * 1.5)
			s.frame = int(t * 9.0) % 2
			s.flip_h = cos(t * 0.9) < 0.0
			s.modulate.a = minf(1.0, s.modulate.a + delta * 2.0)
		else:
			s.position = home + Vector2(sin(t * 0.4) * 22.0 + sin(t * 1.1) * 4.0, sin(t * 0.6) * 10.0)
			var glow := 0.5 + 0.5 * sin(t * 2.2 + home.x)
			s.modulate.a = minf(glow, f["life"] / 2.0)


# -------------------------------------------------------------------- birds
func _settle(perch: Dictionary) -> void:
	for k in _rng.randi_range(2, 4):
		var b := _sprite("bird", 3)
		b.frame = 0
		b.position = perch["pos"] + Vector2(k * 6 - 8, _rng.randf_range(-1, 1))
		b.flip_h = _rng.randf() < 0.5
		perch["birds"].append(b)


func _step_birds(delta: float) -> void:
	var heroes := _heroes()
	for perch in _perches:
		var pos: Vector2 = perch["pos"]
		if perch["birds"].is_empty():
			perch["gone_t"] += delta
			var near := heroes.any(func(h): return h.global_position.distance_to(pos) < BIRD_SCARE * 2.0)
			if perch["gone_t"] > BIRD_RETURN and not near:
				perch["gone_t"] = 0.0
				_settle(perch)
			continue
		var scared: Node2D = null
		for h in heroes:
			if absf(h.global_position.x - pos.x) < BIRD_SCARE and absf(h.global_position.y - pos.y) < 130.0:
				scared = h
		if scared == null:
			continue
		var away := signf(pos.x - scared.global_position.x)
		if away == 0.0:
			away = 1.0
		for b: Sprite2D in perch["birds"]:
			var vel := Vector2(away * _rng.randf_range(50, 80), _rng.randf_range(-70, -45))
			_flyers.append({"node": b, "kind": &"bird", "home": b.position, "t": _rng.randf() * 0.3, "life": 3.5, "vel": vel})
			b.flip_h = away < 0.0
		perch["birds"] = []
		AudioManager.play_sfx(&"swim", pos, -14.0, 0.4)  # a flutter of wings
	for f in _flyers.duplicate():
		if f["kind"] != &"bird":
			continue
		var s: Sprite2D = f["node"]
		f["t"] += delta
		f["life"] -= delta
		var vel: Vector2 = f["vel"]
		vel.y = maxf(vel.y - 20.0 * delta, -90.0)
		f["vel"] = vel
		s.position += vel * delta
		s.frame = 1 + int(f["t"] * 12.0) % 2
		if f["life"] < 1.0:
			s.modulate.a = f["life"]
		if f["life"] <= 0.0:
			s.queue_free()
			_flyers.erase(f)


# --------------------------------------------------------------------- fish
func _step_fish(delta: float, view: Rect2) -> void:
	_fish_t -= delta
	for f in _flyers.duplicate():
		if f["kind"] != &"fish":
			continue
		var s: Sprite2D = f["node"]
		var vel: Vector2 = f["vel"]
		vel.y += 300.0 * delta
		f["vel"] = vel
		s.position += vel * delta
		s.rotation = vel.angle() + (PI if vel.x < 0.0 else 0.0)
		s.flip_h = vel.x < 0.0
		if vel.y > 0.0 and s.position.y >= f["home"].y:
			level.splash(s.position, false)
			s.queue_free()
			_flyers.erase(f)
	if _fish_t > 0.0:
		return
	_fish_t = _rng.randf_range(5.0, 12.0)
	var ponds := level.water_bodies.filter(func(w): return is_instance_valid(w) and view.has_point(w.global_position + w.size / 2.0))
	if ponds.is_empty():
		return
	var w: ColorRect = ponds[_rng.randi() % ponds.size()]
	var x := w.global_position.x + _rng.randf_range(8.0, w.size.x - 8.0)
	var y := w.global_position.y + 3.0
	var s := _sprite("fish_jump", 1)
	s.position = Vector2(x, y)
	s.z_index = 1
	var dir := -1.0 if _rng.randf() < 0.5 else 1.0
	_flyers.append({"node": s, "kind": &"fish", "home": Vector2(x, y), "t": 0.0, "life": 3.0, "vel": Vector2(dir * _rng.randf_range(25, 40), -_rng.randf_range(100, 130))})
	level.splash(Vector2(x, y), false)
