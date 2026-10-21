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
		GameState.reset_run_stats()
	var hero := GameState.hero

	player = PLAYER_SCENE.instantiate()
	world.add_child(player)
	player.setup(hero, null)
	hud.setup(hero, player)
	book.setup(hero)

	EventBus.spawn_items.connect(_on_spawn_items)
	EventBus.floating_text.connect(_on_floating_text)
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.screen_shake.connect(func(s: float) -> void: _shake = maxf(_shake, s))
	EventBus.floor_changed.connect(func(_f: int) -> void: _load_floor.call_deferred())
	EventBus.player_died.connect(_on_player_died)
	EventBus.shop_requested.connect(_open_shop)
	_load_floor()


func _load_floor() -> void:
	if level:
		world.remove_child(level)
		level.queue_free()
	var floor_number := GameState.floor_number
	var seed_value := GameState.floor_seed()
	var layout := LevelGenerator.new().generate(floor_number, seed_value)
	var biome := GameState.current_biome()
	level = LEVEL_SCENE.instantiate()
	world.add_child(level)
	world.move_child(level, 0)
	level.build(layout, floor_number, seed_value, biome)
	player.global_position = level.start_position()
	player.set_level(level)
	_apply_biome(biome)
	EventBus.message.emit("Этаж %d — %s" % [floor_number, biome.display_name] if biome else "Этаж %d" % floor_number)


## Palette, light, parallax and post effects of the biome.
func _apply_biome(biome: BiomeData) -> void:
	if biome == null:
		return
	($Darkness as CanvasModulate).color = biome.darkness
	AudioManager.play_music(biome.music)
	player.apply_biome(biome)
	var textures := [biome.parallax_far, biome.parallax_mid, biome.parallax_near]
	var layers := $Parallax.get_children()
	for i in layers.size():
		var sprite: Sprite2D = layers[i].get_child(0)
		sprite.texture = textures[i]
		# The parallax is its own canvas layer: darken it like the world.
		sprite.modulate = biome.darkness.lightened(0.25 + 0.1 * i)
		layers[i].visible = textures[i] != null
	var m := ($PostFX/Rect as ColorRect).material as ShaderMaterial
	m.set_shader_parameter("tint", biome.grade_tint)
	m.set_shader_parameter("saturation", biome.saturation)
	m.set_shader_parameter("contrast", biome.contrast)
	m.set_shader_parameter("vignette", biome.vignette)
	m.set_shader_parameter("fog_color", biome.fog_color)
	m.set_shader_parameter("fog_amount", biome.fog_amount)


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


func _open_shop(merchant: Node, _player: Node) -> void:
	if get_tree().paused:
		return
	var shop := ShopBook.new()
	add_child(shop)
	shop.open(merchant, GameState.hero)


## Damage numbers + game feel: hit-stop, camera shake, red flash on the hero.
func _on_damage_dealt(pos: Vector2, amount: int, crit: bool, on_player: bool) -> void:
	var n: DamageNumber = DAMAGE_NUMBER_SCENE.instantiate()
	world.add_child(n)
	if on_player:
		n.show_text(str(amount), Color(1.0, 0.3, 0.3), pos, 1.2)
		_shake = maxf(_shake, 4.0)
		_flash_screen(Color(0.8, 0.05, 0.05, 0.35))
		hit_stop(0.06)
	elif crit:
		n.show_text("%d!" % amount, Color(1.0, 0.85, 0.2), pos, 1.6)
		_shake = maxf(_shake, 3.0)
		hit_stop(0.07)
	else:
		n.show_text(str(amount), Color.WHITE, pos)
		_shake = maxf(_shake, 1.2)
		hit_stop(0.03)


## Freezes the action for a few real-time milliseconds.
func hit_stop(duration: float) -> void:
	if get_tree().paused or Engine.time_scale < 1.0:
		return
	Engine.time_scale = 0.05
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0


func _flash_screen(color: Color) -> void:
	var rect: ColorRect = $ScreenFlash/Rect
	rect.color = color
	var tw := create_tween()
	tw.tween_property(rect, "color:a", 0.0, 0.3)


func _exit_tree() -> void:
	Engine.time_scale = 1.0


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
