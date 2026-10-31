class_name RescueCage
extends Area2D
## The prisoner of a rescue node: a cage watched by its guards (an elite
## jailer among them). The lock holds while any guard lives; then E opens
## it, the prisoner speaks (DialogBook) and follows the hero to the exit.
## They move into the town only if the hero comes home alive (RunState).

const REFUGEE := &"refugee"

var level: DungeonLevel
## NpcData id, or REFUGEE for a nameless townsman.
var npc_id: StringName = REFUGEE
var freed := false
var _guards: Array[Enemy] = []
var _cage: Sprite2D
var _person: Sprite2D


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("rescue_cages")
	collision_layer = 16
	collision_mask = 0
	monitoring = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(28, 34)
	shape.shape = rect
	shape.position = Vector2(0, -17)
	add_child(shape)
	_person = Sprite2D.new()
	_person.texture = _npc().sprite if _npc() else AssetPaths.tex(AssetPaths.SPRITES_DIR + "npc/townsfolk_a.png")
	_person.centered = false
	_person.offset = Vector2(-10, -31)
	add_child(_person)
	_cage = Sprite2D.new()
	_cage.texture = AssetPaths.tex(AssetPaths.SPRITES_DIR + "world/cage.png")
	_cage.centered = false
	_cage.offset = Vector2(-14, -36)
	add_child(_cage)


func _npc() -> NpcData:
	return ItemDatabase.npcs.get(npc_id)


func display_name() -> String:
	var n := _npc()
	return "%s (%s)" % [n.display_name, n.profession] if n else tr("Пленный горожанин")


## The guards spawned around the cage.
func guard(guards: Array[Enemy]) -> void:
	_guards = guards


func guards_left() -> int:
	var n := 0
	for g in _guards:
		if is_instance_valid(g) and not g.is_dead():
			n += 1
	return n


func can_interact() -> bool:
	return not freed


func get_prompt() -> String:
	var left := guards_left()
	if left > 0:
		return tr("Клетка заперта: охрана ещё жива (%d)") % left
	return tr("Освободить: %s") % display_name()


func interact(player: Node) -> void:
	if freed:
		return
	if guards_left() > 0:
		EventBus.message.emit(tr("Ключ у тюремщика: сначала разберитесь с охраной."))
		AudioManager.play_sfx(&"chest_locked", global_position)
		return
	freed = true
	remove_from_group("interactable")
	AudioManager.play_sfx(&"chest_open", global_position)
	_cage.visible = false
	Fx.sparks(get_parent(), global_position + Vector2(0, -16), Color(1.0, 0.9, 0.5), 22, 80.0)
	GameFlow.rescue(npc_id)
	var n := _npc()
	if n:
		var book := DialogBook.new()
		get_tree().current_scene.add_child(book)
		book.open_text(n, n.rescue_text, tr("Идём, город ждёт."))
	else:
		var hero: Hero = (player as Player).hero if player is Player else GameState.hero
		var gold := 20 + 6 * (level.floor_number if level else 1)
		hero.add_gold(gold)
		EventBus.message.emit(tr("Горожанин благодарит, отдаёт %d золота и обещает прийти в город.") % gold)
	_follow(player as Node2D)


## The freed one walks behind the hero to the exit.
func _follow(player: Node2D) -> void:
	if player == null:
		return
	var f := Follower.new()
	f.target = player
	f.texture = _person.texture
	get_parent().add_child(f)
	f.global_position = global_position
	_person.visible = false


class Follower extends Sprite2D:
	var target: Node2D
	var _t := 0.0

	func _ready() -> void:
		centered = false
		offset = Vector2(-10, -31)
		z_index = 1

	func _process(delta: float) -> void:
		if not is_instance_valid(target):
			return
		_t += delta
		var behind := target.global_position + Vector2(-18.0 * (1.0 if target.get("facing") == null or float(target.get("facing")) >= 0.0 else -1.0), 0)
		global_position = global_position.lerp(behind, minf(1.0, delta * 4.0))
		flip_h = behind.x < global_position.x
		offset.y = -31 + absf(sin(_t * 9.0)) * -1.5
