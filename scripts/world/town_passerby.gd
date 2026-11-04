class_name TownPasserby
extends Node2D
## A passer-by of the town (tools/art/gen_townsfolk.py draws them): walks the
## street between two points, stops for a while, turns. Pure life: not
## interactable, no physics, local to every machine (like decorations).
## DungeonLevel spawns more of them as the town's prosperity grows.

const SPEED := 14.0
## Roles with sprites folk_<role>_idle.png / folk_<role>_walk.png.
const ROLES: Array[StringName] = [&"farmer", &"guard", &"boy", &"girl", &"noble", &"monk", &"beggar",
	&"baker", &"fisher", &"miner", &"maid", &"elder", &"merchant", &"hunter", &"scholar", &"lamplighter",
	&"washer", &"shepherd", &"priest", &"apprentice", &"traveller", &"veteran", &"herbalist", &"sweeper",
	&"bard", &"courier"]
## Who is out after dark.
const NIGHT_ROLES: Array[StringName] = [&"guard", &"lamplighter", &"traveller", &"bard"]

var role: StringName = &"farmer"
## Street bounds (px) and the ground row per column (TownBuilder.ground_at).
var x_min := 0.0
var x_max := 0.0
var ground: Callable
var _sprite: AnimatedSprite2D
var _target := 0.0
var _wait := 0.0
var _rng := RandomNumberGenerator.new()


func setup(p_role: StringName, p_min: float, p_max: float, p_ground: Callable, seed_value: int) -> void:
	role = p_role
	x_min = p_min
	x_max = p_max
	ground = p_ground
	_rng.seed = seed_value


func _ready() -> void:
	add_to_group("passersby")
	_sprite = AnimatedSprite2D.new()
	_sprite.centered = true
	_sprite.offset = Vector2(0, -15)
	_sprite.z_index = -1
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	for anim in [[&"idle", 2, 2.0], [&"walk", 4, 6.0]]:
		var tex := AssetPaths.tex_or_null(AssetPaths.SPRITES_DIR + "npc/folk_%s_%s.png" % [role, anim[0]])
		frames.add_animation(anim[0])
		frames.set_animation_speed(anim[0], anim[2])
		if tex == null:
			continue
		for i in anim[1]:
			var a := AtlasTexture.new()
			a.atlas = tex
			a.region = Rect2(i * 20, 0, 20, 30)
			frames.add_frame(anim[0], a)
	_sprite.sprite_frames = frames
	add_child(_sprite)
	_wait = _rng.randf_range(0.0, 3.0)
	_target = position.x
	_sprite.play(&"idle")
	_sprite.frame = _rng.randi_range(0, 1)


func _process(delta: float) -> void:
	if _wait > 0.0:
		_wait -= delta
		if _wait <= 0.0:
			_target = _rng.randf_range(x_min, x_max)
		return
	var dx := _target - position.x
	if absf(dx) < 1.0:
		_wait = _rng.randf_range(2.0, 7.0)
		_sprite.play(&"idle")
		return
	var step := signf(dx) * minf(absf(dx), SPEED * delta)
	position.x += step
	_sprite.flip_h = dx < 0.0
	if _sprite.animation != &"walk":
		_sprite.play(&"walk")
	if ground.is_valid():
		position.y = ground.call(position.x)


## How many passers-by a town of this prosperity has (night: a few).
static func count_for(prosperity: int, night: bool) -> int:
	var n := clampi(2 + prosperity / 3, 2, 10)
	return mini(n, 3) if night else n
