class_name BossHazard
extends Node2D
## A dangerous area of a boss fight: a wall of fire sweeping the arena, the
## bell's toll wave, smouldering ash, lava or deep water. The area is a
## rectangle standing on `position` (bottom centre), it may move and expire.
## Heroes whose feet are inside get `damage` every TICK (and `slow` for water).
## Co-op: only the host's copy (`real`) hurts; guests get a visual copy
## through NetSync.boss_fx, the hits reach them through their puppets.

enum Style { FIRE, WAVE, ASH, LAVA, WATER, BONE, VOID }

const TICK := 0.45
const COLORS := {
	Style.FIRE: Color(1.0, 0.45, 0.12),
	Style.WAVE: Color(0.55, 1.0, 0.85),
	Style.ASH: Color(1.0, 0.35, 0.1),
	Style.LAVA: Color(1.0, 0.4, 0.08),
	Style.WATER: Color(0.3, 0.6, 1.0),
	Style.BONE: Color(0.92, 0.88, 0.75),
	Style.VOID: Color(0.6, 0.25, 1.0),
}

var style: Style = Style.FIRE
var size := Vector2(16, 30)
var velocity := Vector2.ZERO
var lifetime := 3.0  # < 0: forever (arena hazards)
var damage := 10
var damage_type := 1
var real := true
## Water: slows instead of (or besides) hurting; WAVE: a short stun.
var slow := 0.0
var stun := 0.0
var _t := 0.0
var _hit_cd := {}  # hero -> seconds before the next hit
var _particles: CPUParticles2D
var _light: PointLight2D


static func spawn(parent: Node, p_style: Style, pos: Vector2, p_size: Vector2, p_lifetime: float,
		p_velocity := Vector2.ZERO, p_damage := 10, p_damage_type := 1, p_real := true) -> BossHazard:
	var h := BossHazard.new()
	h.style = p_style
	h.size = p_size
	h.lifetime = p_lifetime
	h.velocity = p_velocity
	h.damage = p_damage
	h.damage_type = p_damage_type
	h.real = p_real and (not Net.active or Net.is_host)
	match p_style:
		Style.WATER:
			h.slow = 0.45
		Style.WAVE:
			h.stun = 0.5
	parent.add_child(h)
	h.global_position = pos
	return h


func _ready() -> void:
	z_index = 11
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = m
	var col: Color = COLORS[style]
	_particles = CPUParticles2D.new()
	_particles.amount = clampi(int(size.x * size.y / 60.0), 6, 40)
	_particles.lifetime = 0.8
	_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_particles.emission_rect_extents = Vector2(size.x * 0.5, 2.0)
	_particles.position = Vector2(0, -2)
	_particles.direction = Vector2.UP
	_particles.spread = 15.0
	_particles.gravity = Vector2(0, -20 if style != Style.WATER else 40)
	_particles.initial_velocity_min = size.y * 0.6
	_particles.initial_velocity_max = size.y * 1.2
	_particles.scale_amount_min = 1.0
	_particles.scale_amount_max = 2.0
	_particles.color = col
	_particles.material = m
	add_child(_particles)
	if style != Style.BONE:
		_light = PointLight2D.new()
		_light.texture = AssetPaths.tex(AssetPaths.LIGHT)
		_light.color = col
		_light.energy = 0.9
		_light.texture_scale = clampf(maxf(size.x, size.y) / 90.0, 0.25, 1.6)
		_light.position = Vector2(0, -size.y * 0.5)
		add_child(_light)


func _process(delta: float) -> void:
	_t += delta
	position += velocity * delta
	if lifetime >= 0.0 and _t >= lifetime:
		_fade()
		return
	queue_redraw()


func _physics_process(delta: float) -> void:
	if not real or (lifetime >= 0.0 and _t >= lifetime):
		return
	for k in _hit_cd.keys():
		_hit_cd[k] -= delta
	var rect := Rect2(global_position - Vector2(size.x * 0.5, size.y), size)
	for n in get_tree().get_nodes_in_group("player"):
		var p := n as Player
		if p == null or p.dead or float(_hit_cd.get(p, 0.0)) > 0.0:
			continue
		if not rect.has_point(p.global_position + Vector2(0, -3)):
			continue
		_hit_cd[p] = TICK
		if damage > 0:
			p.take_damage(damage, global_position + Vector2(0, -size.y * 0.5), damage_type)
		if slow > 0.0:
			p.status.apply(&"slow", 0.6, slow)
		if stun > 0.0:
			p.status.apply(&"stun", stun, 1.0)
	# Servants burn, drown and get rung out too.
	if damage > 0:
		for n in get_tree().get_nodes_in_group("minions"):
			var m := n as Minion
			if m and not m.is_queued_for_deletion() and float(_hit_cd.get(m, 0.0)) <= 0.0 \
					and rect.has_point(m.global_position + Vector2(0, -3)):
				_hit_cd[m] = TICK
				m.take_damage(damage)


func _fade() -> void:
	set_process(false)
	set_physics_process(false)
	_particles.emitting = false
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.35)
	tw.tween_callback(queue_free)


func _draw() -> void:
	var col: Color = COLORS[style]
	var w := size.x
	var h := size.y
	var flick := 0.75 + 0.25 * sin(_t * 17.0 + position.x * 0.1)
	match style:
		Style.FIRE, Style.ASH:
			# Tongues of flame: columns of varying height, hot core.
			var cols := maxi(3, int(w / 4.0))
			for i in cols:
				var x := -w * 0.5 + (i + 0.5) * w / cols
				var hh := h * (0.55 + 0.45 * absf(sin(_t * 9.0 + i * 1.7))) * (0.6 if style == Style.ASH else 1.0)
				draw_rect(Rect2(x - w / cols * 0.5, -hh, w / cols, hh), Color(col.r, col.g, col.b, 0.55 * flick))
				draw_rect(Rect2(x - w / cols * 0.25, -hh * 0.6, w / cols * 0.5, hh * 0.6), Color(1.0, 0.85, 0.4, 0.7 * flick))
			draw_rect(Rect2(-w * 0.5, -2, w, 2), Color(1.0, 0.95, 0.7, 0.9))
		Style.WAVE:
			# A curling ring of sound / water.
			draw_rect(Rect2(-w * 0.5, -h, w, h), Color(col.r, col.g, col.b, 0.28 * flick))
			draw_arc(Vector2(0, 0), h, PI, TAU, 16, Color(col.r, col.g, col.b, 0.85), 2.0)
			draw_arc(Vector2(0, 0), h * 0.6, PI, TAU, 12, Color(1, 1, 1, 0.6), 1.0)
		Style.LAVA:
			draw_rect(Rect2(-w * 0.5, -h, w, h), Color(0.6, 0.12, 0.02, 0.9))
			for i in int(w / 6.0):
				var x := -w * 0.5 + i * 6.0 + fmod(_t * 6.0, 6.0)
				draw_rect(Rect2(x, -h, 3, 2), Color(1.0, 0.75, 0.3, 0.9 * flick))
			draw_rect(Rect2(-w * 0.5, -h, w, 1), Color(1.0, 0.85, 0.4, 0.95))
		Style.WATER:
			draw_rect(Rect2(-w * 0.5, -h, w, h), Color(0.15, 0.35, 0.7, 0.45))
			for i in int(w / 8.0):
				var x := -w * 0.5 + i * 8.0
				var y := -h + sin(_t * 3.0 + i) * 1.5
				draw_line(Vector2(x, y), Vector2(x + 5, y), Color(0.7, 0.9, 1.0, 0.8), 1.0)
		Style.BONE:
			draw_rect(Rect2(-w * 0.5, -h, w, h), Color(0.35, 0.3, 0.25, 0.4))
			for i in int(w / 5.0):
				var x := -w * 0.5 + i * 5.0 + 2.0
				draw_line(Vector2(x, 0), Vector2(x + 1, -h * (0.5 + 0.5 * absf(sin(i * 2.3)))), col, 1.0)
		Style.VOID:
			draw_rect(Rect2(-w * 0.5, -h, w, h), Color(0.08, 0.02, 0.15, 0.7))
			draw_rect(Rect2(-w * 0.5, -h, w, h), Color(col.r, col.g, col.b, 0.25 * flick), false, 1.0)
