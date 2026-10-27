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
## LAN co-op: world replication coordinator and the shared player container.
var net_sync: NetSync
var net_players: Node2D
var _players_spawned := false
var _shake := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	get_tree().paused = false
	Input.set_custom_mouse_cursor(AssetPaths.tex(AssetPaths.CROSSHAIR), Input.CURSOR_ARROW, Vector2(10, 10))
	tree_exiting.connect(func() -> void: Input.set_custom_mouse_cursor(null))
	if GameState.hero == null and not Net.active:
		# Started directly from the editor: use the first race and class.
		GameState.hero = Hero.new(ItemDatabase.races[0], ItemDatabase.classes[0], ItemDatabase.equipment_layout)
		GameState.hero.give_starting_kit()
		GameState.hero.skills.add_points(1)
		GameState.run_seed = randi()
		GameState.floor_number = 1
		GameState.run_active = true
		GameState.reset_run_stats()
	if Net.active:
		# A network client builds its own hero from what it registered with.
		if GameState.hero == null:
			var info: Dictionary = Net.players.get(Net.multiplayer.get_unique_id(), Net.my_info)
			GameState.hero = _make_hero_from(info)
		_net_bootstrap()
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
	EventBus.damage_dealt_others.connect(_on_damage_dealt_others)
	EventBus.screen_shake.connect(func(s: float) -> void: _shake = maxf(_shake, s))
	EventBus.floor_changed.connect(func(_f: int) -> void: _load_floor.call_deferred())
	EventBus.player_died.connect(_on_player_died)
	SaveManager.settings_changed.connect(_apply_brightness)
	EventBus.shop_requested.connect(_open_shop)
	EventBus.pet_changed.connect(func(_p: PetData) -> void: _sync_pet())
	EventBus.smith_requested.connect(func(_s: Node, _p: Node) -> void:
		if not get_tree().paused:
			var forge := SmithBook.new()
			add_child(forge)
			forge.open(GameState.hero))
	EventBus.quest_requested.connect(func(_g: Node, _p: Node) -> void:
		if not get_tree().paused:
			var book := QuestBook.new()
			add_child(book)
			book.open())
	EventBus.boss_spawned.connect(func(b: Node) -> void: AudioManager.play_music((b as Boss).boss.music))
	# Boss defeated: a victory sting, then back to the floor's music.
	EventBus.boss_defeated.connect(func(b: BossData, _p: Vector2) -> void:
		var biome := GameState.current_biome()
		AudioManager.play_sting(&"victory", biome.music if biome else &"")
		if b.final:
			_on_eclipse_defeated())
	_load_floor()


func _load_floor() -> void:
	# A dead hero's spectator overlay belongs to the previous floor; clear it
	# before rebuilding and always resume the tree when the party transitions.
	get_tree().paused = false
	overlay.visible = false
	if net_sync:
		net_sync.clear_floor()  # before the new level spawns and registers
	if level:
		world.remove_child(level)
		level.queue_free()
	var floor_number := GameState.floor_number
	var seed_value := GameState.floor_seed()
	var gen := LevelGenerator.new()
	var layout: LevelLayout
	if GameState.is_town():
		layout = TownBuilder.build()
	elif GameState.is_boss_floor():
		layout = gen.generate_arena(floor_number, seed_value)
	else:
		layout = gen.generate(floor_number, seed_value)
	var biome := GameState.current_biome()
	level = LEVEL_SCENE.instantiate()
	world.add_child(level)
	world.move_child(level, 0)
	level.build(layout, floor_number, seed_value, biome)
	player.global_position = level.start_position()
	player.set_level(level)
	_apply_biome(biome)
	_sync_pet()
	for b in get_tree().get_nodes_in_group("bosses"):
		AudioManager.play_music((b as Boss).boss.music)
	if GameState.is_town():
		EventBus.message.emit("%s. Вход в подземелье — в конце улицы." % biome.display_name)
	elif GameState.is_boss_floor():
		EventBus.message.emit("Этаж %d — логово стража!" % floor_number)
	else:
		EventBus.message.emit("Этаж %d — %s" % [floor_number, biome.display_name] if biome else "Этаж %d" % floor_number)
	_net_on_floor_loaded()

	# Between-floors save: the snapshot must be taken with the floor freshly
	# built (it regenerates from the seed on continue, loot included).
	if GameState.run_active and not player.dead \
			and not (GameState.floor_number == GameState.TOWN_FLOOR and GameState.town_return_floor > 0) \
			and not Net.active:
		# A mid-run visit to town keeps the snapshot of the floor the hero
		# left, so "continue" resumes the descent, not the street.
		# (In co-op the host's save is the only one; taken outside this branch.)
		if Net.is_host:
			SaveManager.save_run()


## The pet of the run follows the hero (one at a time, re-placed every floor).
func _sync_pet() -> void:
	var cur := get_tree().get_first_node_in_group("pets") as Pet
	if cur and cur.data != GameState.pet:
		cur.queue_free()
		cur.remove_from_group("pets")
		cur = null
	if GameState.pet == null:
		return
	if cur == null:
		cur = (load(AssetPaths.PET_SCENE) as PackedScene).instantiate()
		cur.setup(GameState.pet, player)
		world.add_child(cur)
	else:
		cur.global_position = cur.home_position()


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
	# A fallen hero spectates the party until the next floor revives them.
	if Net.active and player != null and player.dead and net_players:
		for p: Player in net_players.get_children():
			if p != player and not p.dead:
				player.camera.global_position = p.global_position + Vector2(0, -10)
				break
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
	overlay.add_text("(забег продолжится с начала этажа)", 7)
	# Esc resumes: handled by the overlay (ALWAYS), the game tree itself pauses.
	overlay.on_pause_key = _toggle_pause
	overlay.visible = true


func _on_spawn_items(pos: Vector2, stacks: Array) -> void:
	if level == null:
		return
	for entry: Dictionary in stacks:
		var p: ItemPickup = PICKUP_SCENE.instantiate()
		p.setup(entry["item"], entry["count"], Vector2(randf_range(-70.0, 70.0), randf_range(-170.0, -110.0)))
		level.add_entity(p, pos)
		if Net.active and Net.is_host and net_sync:
			net_sync.broadcast_item(p)


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
	# Co-op: combat game feel (shake, hit-stop) is shared - whoever fights,
	# everyone feels it. Remote events already arrived through net RPCs.
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


## Co-op: a teammate's hit - show the number, keep the game feel personal.
func _on_damage_dealt_others(pos: Vector2, amount: int, crit: bool) -> void:
	if not SaveManager.show_damage_numbers:
		return
	var n: DamageNumber = DAMAGE_NUMBER_SCENE.instantiate()
	world.add_child(n)
	if crit:
		n.show_text("%d!" % amount, Color(1.0, 0.85, 0.2), pos, 1.6)
	else:
		n.show_text(str(amount), Color(0.9, 0.9, 0.9), pos)


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
	if Net.active:
		await _on_player_died_coop()
		return
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
	overlay.add_text("Героиня погибла" if hero.female else "Герой погиб", 14)
	overlay.add_text("%s %s · уровень %d" % [hero.race.display_name, hero.class_data.display_name, hero.level], 8)
	var found: Array = stats.get("found", [0, 0, 0])
	overlay.add_control(_stats_grid([
		["Этаж", str(GameState.floor_number)], ["Время", "%d:%02d" % [seconds / 60, seconds % 60]],
		["Убито врагов", str(GameState.kills)], ["Элиты / стражи", "%d / %d" % [int(stats.get("elites", 0)), int(stats.get("bosses", 0))]],
		["Золото собрано", str(int(stats.get("gold", 0)))], ["Находки", _found_text(found)],
		["Лучшее комбо", "×%d" % int(stats.get("best_combo", 0))],
	]))
	if not reward.is_empty() and (reward["shards"] > 0 or reward["gold"] > 0):
		var text := "Святилище Затмения: +%d осколков, +%d золота" % [reward["shards"], reward["gold"]]
		if not reward["parts"].is_empty():
			text += "\n(" + ", ".join(reward["parts"]) + ")"
		overlay.add_text(text, 7)
	overlay.add_button("В главное меню", func() -> void: GameState.go_to_menu()).grab_focus()
	overlay.visible = true


## The Eclipse fell: the ending of the run. The hero may end the run with
## the victory bonus or keep descending (endless floors, the bonus is kept:
## run_stats.victory is already set and paid whenever the run ends).
func _on_eclipse_defeated() -> void:
	await get_tree().create_timer(2.5).timeout
	if not is_inside_tree() or player == null or player.dead:
		return
	book.close()
	skill_tree.close()
	_flash_screen(Color(1.0, 0.9, 0.6, 0.8))
	var hero := GameState.hero
	var stats := GameState.run_stats.duplicate()
	var seconds := (Time.get_ticks_msec() - int(stats.get("start_ms", 0))) / 1000
	get_tree().paused = true
	overlay.clear()
	overlay.set_panel_size(Vector2(360, 262))
	overlay.add_text("Затмение рассеяно", 14)
	overlay.add_text("Чёрное солнце угасло, и свет вернулся в подземелья.\n%s %s · уровень %d — %s." % [
		hero.race.display_name, hero.class_data.display_name, hero.level,
		"героиня, разбившая Затмение" if hero.female else "герой, разбивший Затмение"], 7)
	overlay.add_control(_stats_grid([
		["Этаж", str(GameState.floor_number)], ["Время", "%d:%02d" % [seconds / 60, seconds % 60]],
		["Убито врагов", str(GameState.kills)], ["Элиты / стражи", "%d / %d" % [int(stats.get("elites", 0)), int(stats.get("bosses", 0))]],
		["Золото собрано", str(int(stats.get("gold", 0)))], ["Находки", _found_text(stats.get("found", [0, 0, 0]))],
		["Лучшее комбо", "×%d" % int(stats.get("best_combo", 0))],
	]))
	overlay.add_text("Награда за победу: +%d осколков Затмения." % MetaProgress.SHARDS_VICTORY, 7)
	overlay.add_button("Завершить забег", _finish_victory).grab_focus()
	overlay.add_button("Спуститься глубже (бесконечный режим)", func() -> void:
		get_tree().paused = false
		overlay.visible = false
		EventBus.message.emit("Глубины зовут дальше. Награда за победу сохранится."))
	overlay.visible = true


func _finish_victory() -> void:
	var reward := GameState.end_run()
	overlay.clear()
	overlay.set_panel_size(Vector2(340, 150))
	overlay.add_text("Забег завершён победой", 13)
	if not reward.is_empty():
		var text := "Святилище Затмения: +%d осколков, +%d золота" % [reward["shards"], reward["gold"]]
		if not reward["parts"].is_empty():
			text += "\n(" + ", ".join(reward["parts"]) + ")"
		overlay.add_text(text, 7)
	overlay.add_button("В главное меню", func() -> void:
		if Net.active:
			Net.leave()
		GameState.go_to_menu()).grab_focus()


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


# ================================================================ LAN co-op
## One machine hosts the truth: enemies, loot and floor changes replicate
## from it; every player owns their hero and sends hits/pickups to the host.
func _net_bootstrap() -> void:
	# Multiplayer: pause menus and books still set get_tree().paused (the UI
	# treats it as "a menu is open"), but the shared run ignores it - the
	# whole game scene keeps processing while anyone browses a menu.
	process_mode = Node.PROCESS_MODE_ALWAYS
	net_sync = NetSync.new()
	# A fixed node name: RPC targets are resolved by path, and an auto name
	# (@Node@N) differs between machines and breaks every NetSync RPC.
	net_sync.name = "NetSync"
	world.add_child(net_sync)
	net_sync.local_player = null
	net_players = Node2D.new()
	net_players.name = "NetPlayers"
	net_players.add_to_group("net_players")
	world.add_child(net_players)
	Net.player_joined.connect(_on_net_peer_joined)
	Net.player_left.connect(_on_net_peer_left)
	Net.host_closed.connect(func() -> void:
		if is_inside_tree():
			get_tree().paused = false
			get_tree().change_scene_to_file(GameState.MAIN_MENU))
	# The host is the clock: every floor move of the party goes through it.
	# town_return rides along so the guests' city gate knows the resume floor.
	EventBus.floor_changed.connect(func(f: int) -> void:
		if Net.is_host:
			Net.rpc_set_floor(f, GameState.town_return_floor))
	# Late roster updates must not leave puppets missing on clients.
	Net.players_changed.connect(func() -> void:
		if _players_spawned and not Net.is_host and net_players:
			for peer_id in Net.players:
				_spawn_net_puppet(peer_id))
	# The client's own hero is built from the race/class it registered with.
	if not Net.is_host and GameState.hero == null:
		var info: Dictionary = Net.players.get(Net.multiplayer.get_unique_id(), Net.my_info)
		GameState.hero = _make_hero_from(info)


## A Hero from a registered peer description (host mirrors and client selves).
func _make_hero_from(info: Dictionary) -> Hero:
	var race := ItemDatabase.races[0]
	var cls := ItemDatabase.classes[0]
	for r in ItemDatabase.races:
		if r.id == StringName(info.get("race", "")):
			race = r
	for c in ItemDatabase.classes:
		if c.id == StringName(info.get("cls", "")):
			cls = c
	var h := Hero.new(race, cls, ItemDatabase.equipment_layout)
	h.female = bool(info.get("female", false))
	h.give_starting_kit()
	h.skills.add_points(1)
	return h


func _net_player_name(peer_id: int) -> String:
	return String(Net.players.get(peer_id, {}).get("name", "Игрок"))


## Spawns the local player and a puppet per other peer (once per session).
func _net_spawn_players() -> void:
	if not Net.active or _players_spawned:
		return
	_players_spawned = true
	var my_id := Net.multiplayer.get_unique_id()
	# Local player goes into the shared container so rpc paths match.
	world.remove_child(player)
	net_players.add_child(player)
	player.name = "Player_%d" % my_id
	# The host addresses real damage at this node (net_sync.player_damage).
	net_sync.local_player = player
	for peer_id in Net.players:
		if peer_id == my_id:
			continue
		_spawn_net_puppet(peer_id)
	# Tell the host this scene is up; it spawns my puppet and shares allies.
	# (The host must not call it on itself: call_remote forbids self-RPC.)


func _spawn_net_puppet(peer_id: int) -> void:
	if net_players.has_node("Player_%d" % peer_id):
		return
	var info: Dictionary = Net.players.get(peer_id, {})
	var mirror := _make_hero_from(info)
	var p: Player = PLAYER_SCENE.instantiate()
	p.name = "Player_%d" % peer_id
	p.peer_id = peer_id
	p.puppet = true
	net_players.add_child(p)
	p.setup(mirror, null)
	p.camera.enabled = false  # only the local player owns the viewport
	p.add_to_group("player")
	p.global_position = level.start_position() + Vector2(14, 0)
	var tag := UIStyle.outlined_label(_net_player_name(peer_id), 6, UIStyle.PARCHMENT)
	tag.position = Vector2(-20, -46)
	tag.size = Vector2(40, 10)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(tag)
	hud.add_ally(_net_player_name(peer_id), mirror)
	# Everyone (except the puppet's owner) learns about it from the host.
	if Net.is_host:
		spawn_ally.rpc(peer_id, info)


## Host → clients: a new ally's puppet exists, here is who they are.
@rpc("authority", "call_remote", "reliable")
func spawn_ally(peer_id: int, info: Dictionary) -> void:
	if not Net.players.has(peer_id):
		Net.players[peer_id] = info
	if _players_spawned:
		_spawn_net_puppet(peer_id)


func _on_net_peer_joined(_info: Dictionary) -> void:
	pass  # puppets spawn through net_hello / spawn_ally, never directly


func _on_net_peer_left(peer_id: int) -> void:
	if net_players and net_players.has_node("Player_%d" % peer_id):
		net_players.get_node("Player_%d" % peer_id).queue_free()
	hud.remove_ally(peer_id)


## Every floor load: (re)spawn players once, reposition everyone, revive.
func _net_on_floor_loaded() -> void:
	if not Net.active:
		return
	_net_spawn_players()
	# Every floor: the guest asks the host for a fresh world snapshot —
	# spawn descriptors broadcast mid-transition may have been dropped.
	if not Net.is_host:
		net_sync.net_hello.rpc_id(1)
	var sp := level.start_position()
	player.global_position = sp
	for p: Player in net_players.get_children():
		if p == player:
			continue
		p.global_position = sp + Vector2(14, 0)
	# A fallen hero rises on the next floor (co-op rule).
	if player.dead:
		player.revive()
	for p: Player in net_players.get_children():
		if p != player and p.dead:
			p.revive()


## The local hero fell: wait for the next floor unless everyone is down.
func _on_player_died_coop() -> void:
	AudioManager.play_sting(&"death")
	book.close()
	skill_tree.close()
	await get_tree().create_timer(1.0).timeout
	net_sync.broadcast_player_hp(Net.multiplayer.get_unique_id(), 0,
			GameState.hero.stats.max_hp() if GameState.hero else 0, true)
	var any_alive := false
	for p: Player in net_players.get_children():
		if p != player and not p.dead:
			any_alive = true
	if any_alive:
		get_tree().paused = true
		overlay.clear()
		overlay.set_panel_size(Vector2(340, 150))
		overlay.add_text("Вы пали", 14)
		overlay.add_text("Возрождение на следующем этаже...", 9)
		overlay.add_button("Ждать (наблюдать)", func() -> void:
			get_tree().paused = false
			overlay.visible = false)
		overlay.visible = true
	else:
		# The whole party is down — the run is over for everyone.
		if Net.is_host:
			_end_run_coop()
		else:
			get_tree().paused = true


@rpc("authority", "call_remote", "reliable")
func net_run_ended() -> void:
	var hero := GameState.hero
	get_tree().paused = true
	overlay.clear()
	overlay.set_panel_size(Vector2(340, 150))
	overlay.add_text("Отряд пал", 14)
	overlay.add_button("В главное меню", func() -> void:
		Net.leave()
		GameState.go_to_menu())
	overlay.visible = true


func _end_run_coop() -> void:
	GameState.end_run()
	net_run_ended.rpc()
	var hero := GameState.hero
	get_tree().paused = true
	overlay.clear()
	overlay.set_panel_size(Vector2(340, 150))
	overlay.add_text("Отряд пал", 14)
	overlay.add_button("В главное меню", func() -> void:
		Net.leave()
		GameState.go_to_menu())
	overlay.visible = true
