class_name AnimatedPortrait
extends Control
## The hero portrait of the in-game HUD, alive: breathes, blinks, glances
## aside; grimaces and shakes when hit; shows a wounded face and a red pulse
## on low HP; takes a tint while poisoned / burning / frozen / cursed; flashes
## on healing and level up; closes its eyes on death.
## Face variants sit next to the race portrait: <name>_blink, _glance, _hurt,
## _wounded (.png, tools/gen_portraits.py); a missing one falls back to the
## plain face. Menus keep the static UIStyle.portrait.

const LOW_HP := 0.3
const EXPRESSIONS: Array[String] = ["blink", "glance", "hurt", "wounded"]
const STATUS_TINTS := {
	&"poison": Color(0.55, 1.0, 0.45),
	&"burn": Color(1.0, 0.65, 0.35),
	&"slow": Color(0.6, 0.8, 1.0),
	&"curse": Color(0.8, 0.55, 1.0),
	&"stun": Color(1.0, 1.0, 0.6),
}

var hero: Hero
var player: Player
var _body: Control
var _face: TextureRect
var _overlay: TextureRect
var _flash: ColorRect
var _faces := {}  # expression -> Texture2D ("" = neutral)
var _last_hp := -1
var _dead := false
var _time := 0.0
var _blink_left := 0.0
var _next_blink := 2.0
var _double_blink := false
var _glance_left := 0.0
var _next_glance := 7.0
var _hurt_left := 0.0
var _shake_left := 0.0
var _flash_color := Color.TRANSPARENT
var _flash_left := 0.0
const FLASH_TIME := 0.45


func setup(p_hero: Hero, p_player: Player) -> void:
	hero = p_hero
	player = p_player
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body = Control.new()
	_body.set_anchors_preset(Control.PRESET_FULL_RECT)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_body)
	_face = _layer(hero.race.portrait if hero.race else null)
	_overlay = _layer(hero.class_data.portrait_overlay if hero.class_data else null)
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color.TRANSPARENT
	add_child(_flash)
	_faces[""] = _face.texture
	if _face.texture:
		var base := _face.texture.resource_path.get_basename()
		for e in EXPRESSIONS:
			var path := "%s_%s.png" % [base, e]
			_faces[e] = load(path) if ResourceLoader.exists(path) else _face.texture
	_last_hp = hero.stats.hp
	hero.stats.hp_changed.connect(_on_hp)
	hero.leveled_up.connect(func(_l: int) -> void: _start_flash(Color(1.0, 0.85, 0.3, 0.5)))
	EventBus.player_died.connect(func() -> void: _dead = true)
	_next_blink = randf_range(1.5, 4.0)


func _layer(tex: Texture2D) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(t)
	return t


func _on_hp(hp: int, max_hp: int) -> void:
	if _last_hp >= 0 and hp < _last_hp:
		_hurt_left = 0.4
		_shake_left = 0.3
		_start_flash(Color(1.0, 0.15, 0.1, 0.45))
	elif _last_hp >= 0 and hp > _last_hp + max_hp * 0.05:
		_start_flash(Color(0.4, 1.0, 0.5, 0.4))
	_last_hp = hp


func _start_flash(c: Color) -> void:
	_flash_color = c
	_flash_left = FLASH_TIME


func _low_hp() -> bool:
	return hero.stats.hp <= hero.stats.max_hp() * LOW_HP


func _process(delta: float) -> void:
	if hero == null:
		return
	_time += delta
	_update_timers(delta)
	_face.texture = _faces.get(_expression(), _faces[""])
	# Breathing: the bust rises by a pixel; faster and deeper when wounded.
	var low := _low_hp()
	var breath := sin(_time * (3.6 if low else 1.9))
	var y := roundf(breath * (1.0 if low else 0.6)) if not _dead else 1.0
	var x := 0.0
	if _shake_left > 0.0:
		x = roundf(randf_range(-1.5, 1.5))
		y += roundf(randf_range(-1.0, 1.0))
	_body.position = Vector2(x, y)
	_body.modulate = _tint()
	_flash.color = _flash_now(low)


func _update_timers(delta: float) -> void:
	_hurt_left = maxf(0.0, _hurt_left - delta)
	_shake_left = maxf(0.0, _shake_left - delta)
	_flash_left = maxf(0.0, _flash_left - delta)
	if _blink_left > 0.0:
		_blink_left -= delta
		if _blink_left <= 0.0 and _double_blink:
			_double_blink = false
			_next_blink = 0.12
	else:
		_next_blink -= delta
		if _next_blink <= 0.0:
			_blink_left = 0.12
			_double_blink = randf() < 0.2
			_next_blink = randf_range(2.5, 5.5)
	if _glance_left > 0.0:
		_glance_left -= delta
	else:
		_next_glance -= delta
		if _next_glance <= 0.0:
			_glance_left = randf_range(0.6, 1.2)
			_next_glance = randf_range(6.0, 11.0)


func _expression() -> String:
	if _dead:
		return "blink"
	if _hurt_left > 0.0:
		return "hurt"
	if _blink_left > 0.0:
		return "blink"
	if _low_hp():
		return "wounded"
	if _glance_left > 0.0:
		return "glance"
	return ""


## Status colour, pulsing; grey when dead.
func _tint() -> Color:
	if _dead:
		return Color(0.55, 0.52, 0.55)
	if player == null or not is_instance_valid(player):
		return Color.WHITE
	for id: StringName in STATUS_TINTS:
		if player.status.has(id):
			var k := 0.35 + 0.25 * sin(_time * 6.0)
			return Color.WHITE.lerp(STATUS_TINTS[id], k)
	return Color.WHITE


func _flash_now(low: bool) -> Color:
	if _flash_left > 0.0:
		var c := _flash_color
		c.a *= _flash_left / FLASH_TIME
		return c
	if low and not _dead:
		return Color(0.9, 0.05, 0.05, 0.1 + 0.1 * sin(_time * 4.0))
	return Color.TRANSPARENT
