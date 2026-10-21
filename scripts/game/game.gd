extends Node2D
## Run scene: builds floors, owns the player, HUD, inventory book and the
## pause / death overlays. Listens to EventBus for world-level requests
## (spawning drops, floating text, screen shake, floor change, death).

const LEVEL_SCENE := preload("res://scenes/levels/dungeon_level.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const PICKUP_SCENE := preload("res://scenes/world/item_pickup.tscn")
const DAMAGE_NUMBER_SCENE := preload("res://scenes/world/damage_number.tscn")

@onready var world: Node2D = $World
@onready var hud: HUD = $HUD
@onready var book: InventoryBook = $InventoryBook
@onready var overlay: OverlayPanel = $Overlay

var level: DungeonLevel
var player: Player
var _shake := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	get_tree().paused = false
	if GameState.hero == null:
		# Started directly from the editor: use the first race and class.
		GameState.hero = Hero.new(ItemDatabase.races[0], ItemDatabase.classes[0], ItemDatabase.equipment_layout)
		GameState.hero.give_starting_kit()
		GameState.run_seed = randi()
		GameState.floor_number = 1
		GameState.run_active = true
	var hero := GameState.hero

	player = PLAYER_SCENE.instantiate()
	world.add_child(player)
	player.setup(hero, null)
	hud.setup(hero, player)
	book.setup(hero)

	EventBus.spawn_items.connect(_on_spawn_items)
	EventBus.floating_text.connect(_on_floating_text)
	EventBus.screen_shake.connect(func(s: float) -> void: _shake = maxf(_shake, s))
	EventBus.floor_changed.connect(func(_f: int) -> void: _load_floor.call_deferred())
	EventBus.player_died.connect(_on_player_died)
	_load_floor()


func _load_floor() -> void:
	if level:
		world.remove_child(level)
		level.queue_free()
	var floor_number := GameState.floor_number
	var seed_value := GameState.floor_seed()
	var layout := LevelGenerator.new().generate(floor_number, seed_value)
	level = LEVEL_SCENE.instantiate()
	world.add_child(level)
	world.move_child(level, 0)
	level.build(layout, floor_number, seed_value)
	player.global_position = level.start_position()
	player.set_level(level)
	EventBus.message.emit("Этаж %d" % floor_number)


func _process(delta: float) -> void:
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 20.0)
		player.camera.offset = Vector2(_rng.randf_range(-_shake, _shake), _rng.randf_range(-_shake, _shake))
	elif player and player.camera.offset != Vector2.ZERO:
		player.camera.offset = Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not book.is_open and not player.dead:
		_toggle_pause()
		get_viewport().set_input_as_handled()


func _toggle_pause() -> void:
	if overlay.visible:
		overlay.visible = false
		get_tree().paused = false
		return
	get_tree().paused = true
	overlay.clear()
	overlay.add_text("Пауза", 12)
	overlay.add_button("Продолжить", _toggle_pause).grab_focus()
	overlay.add_button("В главное меню", func() -> void: GameState.go_to_menu())
	overlay.add_text("(забег будет потерян)", 7)
	overlay.visible = true


func _on_spawn_items(pos: Vector2, stacks: Array) -> void:
	if level == null:
		return
	for entry: Dictionary in stacks:
		var p: ItemPickup = PICKUP_SCENE.instantiate()
		p.setup(entry["item"], entry["count"], Vector2(randf_range(-70.0, 70.0), randf_range(-170.0, -110.0)))
		level.add_entity(p, pos)


func _on_floating_text(pos: Vector2, text: String, color: Color) -> void:
	var n: DamageNumber = DAMAGE_NUMBER_SCENE.instantiate()
	world.add_child(n)
	n.show_text(text, color, pos)


func _on_player_died() -> void:
	book.close()
	await get_tree().create_timer(1.2).timeout
	var hero := GameState.hero
	get_tree().paused = true
	overlay.clear()
	overlay.add_text("Герой погиб", 14)
	overlay.add_text("%s %s, уровень %d\nДостигнут этаж: %d\nУбито врагов: %d" % [
		hero.race.display_name, hero.class_data.display_name, hero.level, GameState.floor_number, GameState.kills])
	overlay.add_button("В главное меню", func() -> void: GameState.go_to_menu()).grab_focus()
	overlay.visible = true
