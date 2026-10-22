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
var skill_tree: SkillTreeBook
var hints: HintManager

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
	skill_tree = SkillTreeBook.new()
	add_child(skill_tree)
	skill_tree.setup(hero)
	# F3: monster AI overlay. Own layer that follows the camera, so the world
	# light tint does not affect it.
	var debug_layer := CanvasLayer.new()
	debug_layer.layer = 5
	debug_layer.follow_viewport_enabled = true
	add_child(debug_layer)
	debug_layer.add_child(AIDebugDraw.new())
	hints = HintManager.new()
	add_child(hints)
	hints.setup(player)

	EventBus.spawn_items.connect(_on_spawn_items)
	EventBus.floating_text.connect(_on_floating_text)
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.screen_shake.connect(func(s: float) -> void: _shake = maxf(_shake, s))
	EventBus.floor_changed.connect(func(_f: int) -> void: _load_floor.call_deferred())
	EventBus.player_died.connect(_on_player_died)
	SaveManager.settings_changed.connect(_apply_brightness)
	EventBus.shop_requested.connect(_open_shop)
	EventBus.smith_requested.connect(func(_s: Node, _p: Node) -> void:
		if not get_tree().paused:
			var forge := SmithBook.new()
			add_child(forge)
			forge.open(GameState.hero))
	EventBus.boss_spawned.connect(func(b: Node) -> void: AudioManager.play_music((b as Boss).boss.music))
	# Boss defeated: a victory sting, then back to the floor's music.
	EventBus.boss_defeated.connect(func(_b: BossData, _p: Vector2) -> void:
		var biome := GameState.current_biome()
		AudioManager.play_sting(&"victory", biome.music if biome else &""))
	_load_floor()


func _load_floor() -> void:
	if level:
		world.remove_child(level)
		level.queue_free()
	var floor_number := GameState.floor_number
	var seed_value := GameState.floor_seed()
	if GameState.is_daily():
		seed(seed_value)  # loot and monster rolls repeat for every player of the day
	var gen := LevelGenerator.new()
	var layout := gen.generate_arena(floor_number, seed_value) if GameState.is_boss_floor() else gen.generate(floor_number, seed_value)
	var biome := GameState.current_biome()
	level = LEVEL_SCENE.instantiate()
	world.add_child(level)
	world.move_child(level, 0)
	level.build(layout, floor_number, seed_value, biome)
	player.global_position = level.start_position()
	player.set_level(level)
	_apply_biome(biome)
	for b in get_tree().get_nodes_in_group("bosses"):
		AudioManager.play_music((b as Boss).boss.music)
	if GameState.is_boss_floor():
		EventBus.message.emit("Этаж %d — логово стража!" % floor_number)
	else:
		EventBus.message.emit("Этаж %d — %s" % [floor_number, biome.display_name] if biome else "Этаж %d" % floor_number)


## Palette, ambient light, parallax and post effects of the biome.
func _apply_biome(biome: BiomeData) -> void:
	if biome == null:
		return
	($Ambient as CanvasModulate).color = biome.ambient
	AudioManager.play_music(biome.music)
	player.apply_biome(biome)
	var textures := [biome.parallax_far, biome.parallax_mid, biome.parallax_near]
	var layers := $Parallax.get_children()
	for i in layers.size():
		var sprite: Sprite2D = layers[i].get_child(0)
		sprite.texture = textures[i]
		# Only a light shading of the far layers, for depth.
		sprite.modulate = biome.ambient.darkened(0.22 - 0.07 * i)
		layers[i].visible = textures[i] != null
	var m := ($PostFX/Rect as ColorRect).material as ShaderMaterial
	m.set_shader_parameter("tint", biome.grade_tint)
	m.set_shader_parameter("saturation", biome.saturation)
	m.set_shader_parameter("contrast", biome.contrast)
	_apply_brightness()
	m.set_shader_parameter("fog_color", biome.fog_color)
	m.set_shader_parameter("fog_amount", biome.fog_amount)


## Settings → «Яркость»: multiplies the picture of the world (not the HUD).
func _apply_brightness() -> void:
	var m := ($PostFX/Rect as ColorRect).material as ShaderMaterial
	m.set_shader_parameter("brightness", SaveManager.brightness)


func _process(delta: float) -> void:
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 20.0)
		player.camera.offset = Vector2(_rng.randf_range(-_shake, _shake), _rng.randf_range(-_shake, _shake))
	elif player and player.camera.offset != Vector2.ZERO:
		player.camera.offset = Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not book.is_open and not skill_tree.is_open and not player.dead:
		_toggle_pause()
		get_viewport().set_input_as_handled()


func _toggle_pause() -> void:
	if overlay.visible:
		overlay.visible = false
		get_tree().paused = false
		return
	get_tree().paused = true
	overlay.clear()
	overlay.set_panel_size(Vector2(220, 200))
	overlay.add_text("Пауза", 12)
	overlay.add_button("Продолжить", _toggle_pause).grab_focus()
	overlay.add_button("Настройки", open_settings)
	overlay.add_button("Дерево навыков", func() -> void:
		_toggle_pause()
		skill_tree.open())
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
	# Numbers can be turned off in the settings; the game feel stays.
	var n: DamageNumber = null
	if SaveManager.show_damage_numbers:
		n = DAMAGE_NUMBER_SCENE.instantiate()
		world.add_child(n)
	if on_player:
		if n:
			n.show_text(str(amount), Color(1.0, 0.3, 0.3), pos, 1.2)
		_shake = maxf(_shake, 4.0)
		_flash_screen(Color(0.8, 0.05, 0.05, 0.35))
		hit_stop(0.06)
	elif crit:
		if n:
			n.show_text("%d!" % amount, Color(1.0, 0.85, 0.2), pos, 1.6)
		_shake = maxf(_shake, 3.0)
		hit_stop(0.07)
	else:
		if n:
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


## Settings book over the pause menu; the pause menu comes back when it closes.
func open_settings() -> SettingsBook:
	overlay.visible = false
	var sb := SettingsBook.new()
	add_child(sb)
	sb.closed.connect(func() -> void: overlay.visible = true)
	return sb


func _flash_screen(color: Color) -> void:
	var rect: ColorRect = $ScreenFlash/Rect
	rect.color = color
	var tw := create_tween()
	tw.tween_property(rect, "color:a", 0.0, 0.3)


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func _on_player_died() -> void:
	AudioManager.play_sting(&"death")
	book.close()
	skill_tree.close()
	await get_tree().create_timer(1.2).timeout
	var hero := GameState.hero
	get_tree().paused = true
	var stats := GameState.run_stats.duplicate()
	var seconds := (Time.get_ticks_msec() - int(stats.get("start_ms", 0))) / 1000
	var reward := GameState.end_run()
	overlay.clear()
	overlay.set_panel_size(Vector2(340, 236))
	overlay.add_text("Герой погиб", 14)
	overlay.add_text("%s %s · уровень %d" % [hero.race.display_name, hero.class_data.display_name, hero.level], 8)
	var found: Array = stats.get("found", [0, 0, 0])
	overlay.add_control(_stats_grid([
		["Этаж", str(GameState.floor_number)], ["Время", "%d:%02d" % [seconds / 60, seconds % 60]],
		["Убито врагов", str(GameState.kills)], ["Элиты / стражи", "%d / %d" % [int(stats.get("elites", 0)), int(stats.get("bosses", 0))]],
		["Золото собрано", str(int(stats.get("gold", 0)))], ["Находки", _found_text(found)],
	]))
	if reward.has("daily"):
		var d: Dictionary = reward["daily"]
		overlay.add_text("Ежедневный забег: %d очков%s" % [d["score"], (", место %d за сегодня" % d["place"]) if d["place"] > 0 else ""], 9)
	if not reward.is_empty() and (reward["shards"] > 0 or reward["gold"] > 0):
		var text := "Святилище Затмения: +%d осколков, +%d золота" % [reward["shards"], reward["gold"]]
		if not reward["parts"].is_empty():
			text += "\n(" + ", ".join(reward["parts"]) + ")"
		overlay.add_text(text, 7)
	overlay.add_button("В главное меню", func() -> void: GameState.go_to_menu()).grab_focus()
	overlay.visible = true


## Found items by rarity, each number in its rarity color.
func _found_text(found: Array) -> String:
	var parts: Array[String] = []
	for r in found.size():
		var col: Color = ItemData.RARITY_COLORS[r]
		parts.append("[color=#%s]%d[/color]" % [(UIStyle.INK if r == 0 else col.darkened(0.25)).to_html(false), int(found[r])])
	return " · ".join(parts)


## Two-column table of run statistics: [[label, value (bbcode)], ...].
func _stats_grid(rows: Array) -> Control:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 1)
	for r in rows:
		var l := UIStyle.label(r[0] + ":", 7, UIStyle.INK_SOFT)
		grid.add_child(l)
		var v := RichTextLabel.new()
		v.bbcode_enabled = true
		v.fit_content = true
		v.scroll_active = false
		v.autowrap_mode = TextServer.AUTOWRAP_OFF
		v.custom_minimum_size = Vector2(56, 0)
		v.add_theme_color_override("default_color", UIStyle.INK)
		v.add_theme_font_size_override("normal_font_size", 8)
		v.text = "[b]%s[/b]" % r[1]
		v.add_theme_font_size_override("bold_font_size", 8)
		grid.add_child(v)
	var center := CenterContainer.new()
	center.add_child(grid)
	return center
