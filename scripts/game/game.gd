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
## The layers of a location of several (null in an ordinary level).
var location: LocationManager
var _players_spawned := false
var _shake := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	get_tree().paused = false
	add_to_group("graphics_listeners")
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
	EventBus.boss_spawned.connect(func(b: Node) -> void:
		if location == null:  # a location of layers: its music changes per layer
			AudioManager.play_music((b as Boss).boss.music))
	# Boss defeated: a victory sting, then back to the floor's music.
	EventBus.boss_defeated.connect(func(b: BossData, _p: Vector2) -> void:
		var biome := GameState.current_biome()
		# The Eclipse: a long dawn chord instead of the usual fanfare.
		AudioManager.play_sting(&"ending" if b.final else &"victory", biome.music if biome else &"")
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
	if location:
		location.queue_free()
		location = null
	if GameState.location.has("instance"):
		_load_location()
		return
	var floor_number := GameState.floor_number
	var seed_value := GameState.floor_seed()
	var gen := LevelGenerator.new()
	var fb := GameState.current_biome()
	gen.flooded_pools = fb.flooded_pools if fb and not GameState.is_town() else 0
	var layout: LevelLayout
	if GameState.is_town() and GameState.expedition and GameState.town:
		layout = TownBuilder.build_hub(GameState.town)
	elif GameState.is_town():
		layout = TownBuilder.build()
	elif GameState.is_boss_floor():
		layout = gen.generate_arena(floor_number, seed_value)
	elif GameState.location_type() == &"camp":
		_load_camp()
		return
	elif GameState.location_type() == &"event":
		layout = gen.generate_event_room(floor_number, seed_value)
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
	if GameState.is_town() and GameState.expedition:
		EventBus.message.emit(tr("%s · %s. Ворота похода — в конце улицы.") % [biome.display_name, Buildings.phase_name()])
		_town_sky()
		AudioManager.play_sfx(&"town_bell", Vector2.INF, -10.0, 0.0)
		# butterflies over the street, fireflies at night, birds in the trees
		var life := SurfaceLife.new()
		level.add_child(life)
		life.setup(level, -1, town_sky, seed_value)
		_take_thumbnail()
		_town_news()
	elif GameState.expedition:
		EventBus.message.emit(_location_title())
	elif GameState.is_town():
		EventBus.message.emit(tr("%s. Вход в подземелье — в конце улицы.") % biome.display_name)
	elif GameState.is_boss_floor():
		EventBus.message.emit(tr("Этаж %d — логово стража!") % floor_number)
	else:
		EventBus.message.emit(tr("Этаж %d — %s") % [floor_number, biome.display_name] if biome else tr("Этаж %d") % floor_number)
	_net_on_floor_loaded()

	# Between-floors save: the snapshot must be taken with the floor freshly
	# built (it regenerates from the seed on continue, loot included).
	if GameState.run_active and not player.dead and not GameState.expedition \
			and not (GameState.floor_number == GameState.TOWN_FLOOR and GameState.town_return_floor > 0) \
			and not Net.active:
		# A mid-run visit to town keeps the snapshot of the floor the hero
		# left, so "continue" resumes the descent, not the street.
		# (In co-op the host's save is the only one; taken outside this branch.)
		if Net.is_host:
			SaveManager.save_run()


## A location of layers (LocationInstance): the whole of it in one level,
## LocationManager runs the portals, the save points and the layers.
func _load_location() -> void:
	var li := LocationInstance.from_dict(GameState.location["instance"])
	var layout := LocationBuilder.build(li)
	level = LEVEL_SCENE.instantiate()
	world.add_child(level)
	world.move_child(level, 0)
	level.build_location(layout, li.gen_seed)
	player.set_level(level)
	location = LocationManager.new()
	add_child(location)
	location.setup(self, level, li)
	_sync_pet()
	_net_on_floor_loaded()
	location.place_player(player)
	if not GameFlow.is_guest():
		location.save_point()  # the first save point: the start of the location


## A camp of the road as a place to walk (CampBuilder): forest, ruins or
## cave by the region and the node; the town decides what stands there.
func _load_camp() -> void:
	var seed_value := GameState.floor_seed()
	var sid := LocationInstance.surface_biome_for(int(GameState.location.get("region", 0)), seed_value)
	var kind := &"forest"
	if sid in [&"surface_ruins", &"surface_wasteland"]:
		kind = &"ruins"
	elif sid == &"surface_mountains" or (GameState.floor_number >= 10 and absi(seed_value) % 3 == 0):
		kind = &"cave"
	var biome: BiomeData = ItemDatabase.surface_biomes.get(sid) if kind != &"cave" else GameState.current_biome()
	var companions: Array = GameState.run.rescued.duplicate() if GameState.run else []
	var layout := CampBuilder.build(seed_value, kind, GameState.town, companions)
	if GameState.town:
		GameState.town.flags["camp_level"] = CampBuilder.camp_level(GameState.town)
	level = LEVEL_SCENE.instantiate()
	world.add_child(level)
	world.move_child(level, 0)
	level.build(layout, GameState.floor_number, seed_value, biome)
	player.set_level(level)
	player.global_position = level.start_position()
	apply_layer_biome(biome)
	if kind != &"cave" and biome is SurfaceBiomeData:
		# the land around the fire is alive too: grass, butterflies, birds
		var life := SurfaceLife.new()
		level.add_child(life)
		life.setup(level, -1, null, seed_value)
		var grass := GrassField.new()
		level.add_child(grass)
		grass.setup(level, -1, (biome as SurfaceBiomeData).grass_color, (biome as SurfaceBiomeData).grass_density, seed_value + 1)
	AudioManager.play_music(&"camp")
	# the fire crackles; the land around it is heard more quietly
	AudioManager.play_ambience(&"amb_fire", 0, -12.0)
	if biome is SurfaceBiomeData:
		AudioManager.play_ambience((biome as SurfaceBiomeData).ambience_day, 1, -20.0)
	else:
		AudioManager.play_ambience(&"", 1)
	_sync_pet()
	EventBus.message.emit(tr("Лагерь · %s") % (biome.display_name if biome else ""))
	_net_on_floor_loaded()


## LocationManager: the hero went to a layer with another biome.
## Under the open sky the background stands still vertically (the sky fills
## the screen, the hills sit at its bottom); underground it scrolls and
## repeats as before.
func apply_layer_biome(b: BiomeData) -> void:
	_apply_biome(b)
	_front_layer(b)


## Expedition: the exit of a location shows what it gave (gold, kills,
## finds, town resources, shards), then back to the map.
func finish_location() -> void:
	if overlay.visible or player.dead:
		return
	var s := GameFlow.location_summary()
	book.close()
	skill_tree.close()
	get_tree().paused = true
	overlay.clear()
	overlay.set_panel_size(Vector2(320, 210))
	overlay.add_text(tr("Локация пройдена"), 13)
	overlay.add_text(_location_title(), 7)
	overlay.add_control(_stats_grid([
		[tr("Золото"), "%+d" % int(s.get("gold", 0))], [tr("Убито"), str(int(s.get("kills", 0)))],
		[tr("Подобрано"), str(int(s.get("picked", 0)))], [tr("Осколки"), "%+d" % int(s.get("shards", 0))],
	]))
	var finds: Array = s.get("finds", [])
	if not finds.is_empty():
		overlay.add_text(tr("Находки: %s") % ", ".join(finds), 7)
	var res: Dictionary = s.get("resources", {})
	if not res.is_empty():
		overlay.add_text(tr("Для города: %s") % TownResources.describe(res), 7)
	var saved := StringName(s.get("rescued", &""))
	if saved != &"":
		var nd: NpcData = ItemDatabase.npcs.get(saved)
		overlay.add_text(tr("Спасён: %s — придёт в город, если вы вернётесь живым.") % (nd.display_name if nd else tr("горожанин")), 7)
	var bp := StringName(s.get("blueprint", &""))
	if bp != &"":
		var bd := ItemDatabase.building(bp)
		overlay.add_text(tr("Чертёж: %s") % (bd.display_name if bd else String(bp)), 7)
	overlay.add_text(tr("Добыча едет с вами, пока вы живы: дома она станет вашей."), 6)
	overlay.add_button(tr("На карту похода"), func() -> void:
		overlay.visible = false
		GameFlow.location_cleared()).grab_focus()
	overlay.on_pause_key = Callable()
	overlay.visible = true


## The town's hour and weather (visual only: the light, the people's
## schedule, rain or fog): the day turns on from the phase the expeditions
## left it at (Buildings.day_phase).
var town_sky: SurfaceSky


func _town_sky() -> void:
	if town_sky:
		town_sky.queue_free()
	var sb := load("res://data/town/town_sky.tres") as SurfaceBiomeData
	if sb == null:
		return
	town_sky = SurfaceSky.new()
	town_sky.add_to_group("town_sky")
	add_child(town_sky)
	town_sky.setup(sb, int(GameState.town.world_seed if GameState.town else 0) + Buildings.day_phase(),
			$Ambient as CanvasModulate, player.camera)
	town_sky.phase = [0.04, 0.3, 0.6, 0.8][Buildings.day_phase()]
	town_sky.set_active(true)


## A miniature of the world for the load screen (taken in the street).
func _take_thumbnail() -> void:
	if DisplayServer.get_name() == "headless":
		return
	await get_tree().create_timer(0.6).timeout
	if is_inside_tree() and GameState.is_town():
		SaveManager.save_thumbnail(get_viewport().get_texture().get_image())


## What changed in town while the hero was away (TownState.news): a page
## of news with the portraits of the people who moved in; the newcomers
## shine in the street.
func _town_news() -> void:
	var t := GameState.town
	if t:
		for d in TownDistricts.newly_open(t):
			t.news.append(tr("Открылся новый квартал: %s.") % tr(d.display_name))
	if t == null or (t.news.is_empty() and (t.flags.get("arrived", []) as Array).is_empty()):
		return
	var lines := t.news.duplicate()
	var arrived: Array = t.flags.get("arrived", [])
	t.news.clear()
	t.flags.erase("arrived")
	GameFlow.save_town()
	await get_tree().create_timer(0.9).timeout
	if not is_inside_tree() or overlay.visible:
		return
	get_tree().paused = true
	overlay.clear()
	overlay.set_panel_size(Vector2(340, 190 + 14 * mini(lines.size(), 6)))
	overlay.add_text(tr("Новости города"), 12)
	if not arrived.is_empty():
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 6)
		for id in arrived:
			var n: NpcData = ItemDatabase.npcs.get(StringName(id))
			if n == null:
				continue
			var pic := TextureRect.new()
			pic.texture = n.portrait
			pic.custom_minimum_size = Vector2(40, 40)
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.tooltip_text = n.display_name
			row.add_child(pic)
		overlay.add_control(row)
	for line in lines.slice(0, 6):
		overlay.add_text(line, 7)
	overlay.add_button(tr("Пройтись по городу"), func() -> void:
		overlay.visible = false
		get_tree().paused = false
		for n in get_tree().get_nodes_in_group("town_npcs"):
			if String((n as TownNpc).data.id) in arrived:
				Fx.sparks(n.get_parent(), (n as Node2D).global_position + Vector2(0, -16), Color(1.0, 0.9, 0.5), 24, 90.0)).grab_focus()
	overlay.on_pause_key = Callable()
	overlay.visible = true


## «Глубина 7 — Логово элиты · Руины» for the location banner.
func _location_title() -> String:
	var type := GameState.location_type()
	var name := ExpeditionMap.type_name(type)
	var sub := StringName(GameState.location.get("sub", &""))
	if sub != &"":
		name = tr(ExpeditionMap.SPECIAL_NAMES.get(sub, String(sub)))
	var biome := GameState.current_biome()
	return tr("Глубина %d — %s · %s") % [GameState.depth(), name, biome.display_name if biome else ""]


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
	var open_sky := biome.is_open_sky()
	# Underground a touch below the biome's ambient: torches, ore and magic
	# make warm pools of light. Under the open sky the daylight is full.
	($Ambient as CanvasModulate).color = biome.ambient if open_sky else biome.ambient * Color(0.88, 0.87, 0.86, 1.0)
	# (the town's hour: its SurfaceSky, see _town_sky)
	AudioManager.play_music(biome.music)
	AudioManager.set_space(biome.space())
	player.apply_biome(biome)
	var textures := biome.parallax_textures()
	var layers := $Parallax.get_children()
	for i in layers.size():
		var sprite: Sprite2D = layers[i].get_child(0)
		sprite.texture = textures[i]
		# Underground a light shading of the far layers, for depth; the open
		# sky has its depth painted in (aerial perspective) and stays bright.
		sprite.modulate = Color.WHITE if open_sky else biome.ambient.darkened(0.22 - 0.07 * i)
		layers[i].visible = textures[i] != null
		_parallax_life(sprite, textures[i], i, open_sky)
		# Under the open sky the background stands still vertically (the sky
		# fills the screen and does not repeat upward); underground it scrolls.
		var pl := layers[i] as ParallaxLayer
		if not pl.has_meta(&"scale"):
			pl.set_meta(&"scale", pl.motion_scale)
			pl.set_meta(&"mirror", pl.motion_mirroring)
		var sc: Vector2 = pl.get_meta(&"scale")
		var mi: Vector2 = pl.get_meta(&"mirror")
		pl.motion_scale = Vector2(sc.x, 0.0) if open_sky else sc
		pl.motion_mirroring = Vector2(mi.x, 0.0) if open_sky else mi
	var m := ($PostFX/Rect as ColorRect).material as ShaderMaterial
	m.set_shader_parameter("tint", biome.grade_tint)
	m.set_shader_parameter("saturation", biome.saturation)
	m.set_shader_parameter("contrast", biome.contrast)
	_apply_brightness()
	apply_graphics()
	m.set_shader_parameter("fog_color", biome.fog_color)
	m.set_shader_parameter("fog_amount", biome.fog_amount)


var _front: ParallaxBackground
var _front_wanted := false  # under the open sky (the setting may still hide it)


## A rare dark branch hanging over the top of the screen under the open sky
## (surface_<biome>_front.png), sliding faster than the world: depth. Under
## the world's post effects (layer 2 < PostFX 3), under the HUD.
func _front_layer(b: BiomeData) -> void:
	var path := ""
	if b is SurfaceBiomeData and b.parallax_far != "":
		path = b.parallax_far.replace("_far.png", "_front.png")
	_front_wanted = path != "" and ResourceLoader.exists(path)
	if not _front_wanted:
		if _front:
			_front.visible = false
		return
	if _front == null:
		_front = ParallaxBackground.new()
		_front.name = "FrontParallax"
		_front.layer = 2
		var pl := ParallaxLayer.new()
		pl.motion_scale = Vector2(1.35, 0.0)
		pl.motion_mirroring = Vector2(640, 0)
		var sp := Sprite2D.new()
		sp.centered = false
		sp.scale = Vector2(2, 2)
		pl.add_child(sp)
		_front.add_child(pl)
		add_child(_front)
	(_front.get_child(0).get_child(0) as Sprite2D).texture = AssetPaths.tex(path)
	_front.visible = SaveManager.scenery >= 2


## Quiet life in the backgrounds (assets/shaders/parallax_life.gdshader):
## under the sky the clouds drift and the foliage sways (its mask is
## <layer>_sway.png next to the texture), underground the light breathes.
func _parallax_life(sprite: Sprite2D, tex: Texture2D, i: int, open_sky: bool) -> void:
	if tex == null:
		sprite.material = null
		return
	var m := sprite.material as ShaderMaterial
	if m == null:
		m = ShaderMaterial.new()
		m.shader = AssetPaths.shader(AssetPaths.SHADER_PARALLAX)
		sprite.material = m
	var path := tex.resource_path
	var clouds_path := path.replace("_far.png", "_clouds.png")
	var sway_path := path.replace(".png", "_sway.png")
	var has_clouds := open_sky and i == 0 and clouds_path != path and ResourceLoader.exists(clouds_path)
	var has_sway := open_sky and i > 0 and ResourceLoader.exists(sway_path)
	m.set_shader_parameter("has_clouds", has_clouds)
	m.set_shader_parameter("clouds", load(clouds_path) if has_clouds else null)
	m.set_shader_parameter("has_sway", has_sway)
	m.set_shader_parameter("sway_mask", load(sway_path) if has_sway else null)
	m.set_shader_parameter("sway", 1.0 if SaveManager.scenery > 0 else 0.0)
	m.set_shader_parameter("cloud_speed", 0.0025 if SaveManager.scenery > 0 else 0.0)
	m.set_shader_parameter("life", SaveManager.scenery_amount())
	m.set_shader_parameter("tex_size", Vector2(tex.get_width(), tex.get_height()))
	m.set_shader_parameter("shimmer", 0.0 if open_sky else 0.035 - 0.008 * i)
	var glow_path := path.replace(".png", "_glow.png")
	var has_glow := not open_sky and ResourceLoader.exists(glow_path)
	m.set_shader_parameter("has_glow", has_glow)
	m.set_shader_parameter("glow_mask", load(glow_path) if has_glow else null)
	m.set_shader_parameter("is_sky", open_sky and i == 0)
	var stars := "res://assets/sprites/backgrounds/surface_stars.png"
	m.set_shader_parameter("has_stars", open_sky and i == 0 and ResourceLoader.exists(stars))
	m.set_shader_parameter("stars", load(stars) if open_sky and i == 0 and ResourceLoader.exists(stars) else null)
	m.set_shader_parameter("night", 0.0)
	m.set_shader_parameter("sky_tint", Color.WHITE)
	m.set_shader_parameter("rays", 0.0)


## Settings → «Яркость»: multiplies the picture of the world (not the HUD).
func _apply_brightness() -> void:
	var m := ($PostFX/Rect as ColorRect).material as ShaderMaterial
	m.set_shader_parameter("brightness", SaveManager.brightness)


## Settings → «Свечение» / «Тени блоков» (weak machines turn them off).
func apply_graphics() -> void:
	var m := ($PostFX/Rect as ColorRect).material as ShaderMaterial
	m.set_shader_parameter("bloom_strength", 0.55 if SaveManager.bloom else 0.0)
	if level:
		level.set_block_shadows(SaveManager.block_shadows)
	_apply_scenery()


## Settings → «Живость мира» on everything that lives quietly in the scene.
func _apply_scenery() -> void:
	var amount := SaveManager.scenery_amount()
	for layer in $Parallax.get_children():
		var spr := layer.get_child(0) as Sprite2D if layer.get_child_count() > 0 else null
		var pm := spr.material as ShaderMaterial if spr else null
		if pm:
			pm.set_shader_parameter("sway", 1.0 if amount > 0.0 else 0.0)
			pm.set_shader_parameter("cloud_speed", 0.0025 * (1.0 if amount > 0.0 else 0.0))
			pm.set_shader_parameter("life", amount)
	DungeonLevel._foliage_material().set_shader_parameter("amount", 1.2 * (1.0 if amount > 0.0 else 0.0))
	if _front:
		_front.visible = _front_wanted and amount >= 1.0
	for n in get_tree().get_nodes_in_group("scenery"):
		if n.has_method("set_amount"):
			n.set_amount(amount)


func _process(delta: float) -> void:
	# A fallen hero spectates the party until the next floor revives them.
	if Net.active and player != null and player.dead and net_players:
		for p: Player in party():
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
	overlay.set_panel_size(Vector2(220, 280 if GameState.expedition else 220))
	overlay.add_text(tr("Пауза"), 12)
	overlay.add_button(tr("Продолжить"), _toggle_pause).grab_focus()
	overlay.add_button(tr("Как играть"), func() -> void: add_child(InfoBook.how_to_play()))
	overlay.add_button(tr("Настройки"), open_settings)
	if GameState.expedition:
		overlay.add_button(tr("Журнал"), func() -> void:
			_toggle_pause()
			var j := JournalBook.new()
			add_child(j)
			j.open())
		if GameState.is_town():
			# Safe zones only: the town's overview (buildings and resources).
			overlay.add_button(tr("Город"), func() -> void:
				_toggle_pause()
				var jt := JournalBook.new()
				add_child(jt)
				jt.open(JournalBook.Tab.BUILDINGS))
	overlay.add_button(tr("Дерево навыков"), func() -> void:
		_toggle_pause()
		skill_tree.open())
	var safe_spot := (location != null and location.at_safe_spot(player)) or GameState.location_type() == &"camp"
	if GameState.expedition and (GameState.is_town() or safe_spot):
		overlay.add_button(tr("Сохранить и выйти"), func() -> void: GameFlow.save_and_quit())
	else:
		overlay.add_button(tr("В главное меню"), func() -> void: GameState.go_to_menu())
	if location != null and not safe_spot:
		overlay.add_text(tr("(сохранить и выйти можно у входа, выхода или костра; иначе продолжите с последней точки сохранения)"), 6)
	elif location != null:
		pass
	elif GameState.expedition and not GameState.is_town():
		overlay.add_text(tr("(в локации сохраняется только выход из неё: выйдя сейчас, вы сбежите из неё без награды)"), 6)
	else:
		overlay.add_text(tr("(забег продолжится с начала этажа)"), 7)
	# Esc resumes: handled by the overlay (ALWAYS), the game tree itself pauses.
	overlay.on_pause_key = _toggle_pause
	overlay.visible = true


func _on_spawn_items(pos: Vector2, stacks: Array) -> void:
	if level == null:
		return
	# A world session: loot is personal - every machine spawns its own drops
	# for its own hero, nobody else sees them (nothing to fight over).
	if Net.world_session:
		for entry: Dictionary in stacks:
			var lp: ItemPickup = PICKUP_SCENE.instantiate()
			lp.setup(entry["item"], entry["count"], Vector2(randf_range(-70.0, 70.0), randf_range(-170.0, -110.0)))
			level.add_entity(lp, pos)
		return
	# Co-op: loot is the host's (spawned there and broadcast to everyone). A
	# guest's own copy would be a phantom nobody else sees or can share.
	if Net.active and not Net.is_host:
		return
	for entry: Dictionary in stacks:
		var p: ItemPickup = PICKUP_SCENE.instantiate()
		p.setup(entry["item"], entry["count"], Vector2(randf_range(-70.0, 70.0), randf_range(-170.0, -110.0)))
		level.add_entity(p, pos)
		if Net.active and Net.is_host and net_sync:
			net_sync.broadcast_item(p)


## Host: an item everyone sees and anyone may take (thrown on the floor).
func spawn_shared(pos: Vector2, stacks: Array) -> void:
	if level == null:
		return
	for entry: Dictionary in stacks:
		var p: ItemPickup = PICKUP_SCENE.instantiate()
		p.setup(entry["item"], entry["count"], Vector2(randf_range(-40.0, 40.0), -120.0))
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
	# the wind and the birds of a location stay behind with it
	AudioManager.set_underwater(false)
	AudioManager.play_ambience(&"", 0)
	AudioManager.play_ambience(&"", 1)
	if Net.world_session:
		Net.set_scene_token("")


func _on_player_died() -> void:
	if Net.active:
		await _on_player_died_coop()
		return
	AudioManager.play_sting(&"death")
	book.close()
	skill_tree.close()
	await get_tree().create_timer(1.2).timeout
	if GameState.expedition:
		GameFlow.hero_died()  # the result screen tells what was lost
		return
	var hero := GameState.hero
	get_tree().paused = true
	var stats := GameState.run_stats.duplicate()
	var seconds := (Time.get_ticks_msec() - int(stats.get("start_ms", 0))) / 1000
	var reward := GameState.end_run()
	overlay.clear()
	overlay.set_panel_size(Vector2(340, 236))
	overlay.add_text(tr("Героиня погибла") if hero.female else tr("Герой погиб"), 14)
	overlay.add_text(tr("%s %s · уровень %d") % [hero.race.display_name, hero.class_data.display_name, hero.level], 8)
	var found: Array = stats.get("found", [0, 0, 0])
	overlay.add_control(_stats_grid([
		[tr("Этаж"), str(GameState.floor_number)], [tr("Время"), "%d:%02d" % [seconds / 60, seconds % 60]],
		[tr("Убито врагов"), str(GameState.kills)], [tr("Элиты / стражи"), "%d / %d" % [int(stats.get("elites", 0)), int(stats.get("bosses", 0))]],
		[tr("Золото собрано"), str(int(stats.get("gold", 0)))], [tr("Находки"), _found_text(found)],
		[tr("Лучшее комбо"), "×%d" % int(stats.get("best_combo", 0))],
	]))
	if not reward.is_empty() and (reward["shards"] > 0 or reward["gold"] > 0):
		var text := tr("Святилище Затмения: +%d осколков, +%d золота") % [reward["shards"], reward["gold"]]
		if not reward["parts"].is_empty():
			text += "\n(" + ", ".join(reward["parts"]) + ")"
		overlay.add_text(text, 7)
	overlay.add_button(tr("В главное меню"), func() -> void: GameState.go_to_menu()).grab_focus()
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
	overlay.add_text(tr("Затмение рассеяно"), 14)
	overlay.add_text(tr("Чёрное солнце угасло, и свет вернулся в подземелья.\n%s %s · уровень %d — %s.") % [
		hero.race.display_name, hero.class_data.display_name, hero.level,
		tr("героиня, разбившая Затмение") if hero.female else tr("герой, разбивший Затмение")], 7)
	overlay.add_control(_stats_grid([
		[tr("Этаж"), str(GameState.floor_number)], [tr("Время"), "%d:%02d" % [seconds / 60, seconds % 60]],
		[tr("Убито врагов"), str(GameState.kills)], [tr("Элиты / стражи"), "%d / %d" % [int(stats.get("elites", 0)), int(stats.get("bosses", 0))]],
		[tr("Золото собрано"), str(int(stats.get("gold", 0)))], [tr("Находки"), _found_text(stats.get("found", [0, 0, 0]))],
		[tr("Лучшее комбо"), "×%d" % int(stats.get("best_combo", 0))],
	]))
	overlay.add_text(tr("Награда за победу: +%d осколков Затмения.") % MetaProgress.SHARDS_VICTORY, 7)
	# The secret ending: everyone who knows the guardians' stories may let the
	# sun go instead of breaking it.
	if Codex.knows_all_guardians() and not stats.get("secret_ending", false):
		overlay.add_button(tr("Вспомнить их имена и вернуть свет"), _secret_ending).grab_focus()
	else:
		var gk := Codex.guardians_known()
		if not stats.get("secret_ending", false):
			overlay.add_text(tr("Летописец говорил о другом пути... (записи стражей: %d из %d)") % [gk.x, gk.y], 6)
	var finish := overlay.add_button(tr("Завершить поход") if GameState.expedition else tr("Завершить забег"), _finish_victory)
	if not Codex.knows_all_guardians():
		finish.grab_focus()
	if not GameState.expedition:
		overlay.add_button(tr("Спуститься глубже (бесконечный режим)"), func() -> void:
			get_tree().paused = false
			overlay.visible = false
			EventBus.message.emit(tr("Глубины зовут дальше. Награда за победу сохранится.")))
	overlay.visible = true


func _secret_ending() -> void:
	GameState.run_stats["secret_ending"] = true
	Codex.add(&"secret_endings")
	Codex.save_progress()
	overlay.visible = false
	var se := SecretEnding.new()
	add_child(se)
	se.finished.connect(func() -> void:
		overlay.clear()
		overlay.set_panel_size(Vector2(340, 150))
		overlay.add_text(tr("Рассвет над Аурелией"), 13)
		overlay.add_text(tr("Награда за тайную концовку: +%d осколков.") % MetaProgress.SHARDS_SECRET, 7)
		overlay.add_button(tr("Завершить поход") if GameState.expedition else tr("Завершить забег"), _finish_victory).grab_focus()
		if not GameState.expedition:
			overlay.add_button(tr("Спуститься глубже (бесконечный режим)"), func() -> void:
				get_tree().paused = false
				overlay.visible = false)
		overlay.visible = true)


func _finish_victory() -> void:
	if GameState.expedition:
		GameFlow.location_cleared()  # the last guardian: the road ends in victory
		return
	var reward := GameState.end_run()
	overlay.clear()
	overlay.set_panel_size(Vector2(340, 150))
	overlay.add_text(tr("Забег завершён победой"), 13)
	if not reward.is_empty():
		var text := tr("Святилище Затмения: +%d осколков, +%d золота") % [reward["shards"], reward["gold"]]
		if not reward["parts"].is_empty():
			text += "\n(" + ", ".join(reward["parts"]) + ")"
		overlay.add_text(text, 7)
	overlay.add_button(tr("В главное меню"), func() -> void:
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
		if Net.is_host and not Net.world_session:  # a world session moves by WorldNet.flow
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
	GameState.apply_eclipse(h)
	return h


## Co-op heroes (the container also holds their sparks, dust and trails).
func party() -> Array[Player]:
	var list: Array[Player] = []
	if net_players:
		for n in net_players.get_children():
			if n is Player:
				list.append(n)
	return list


func _net_player_name(peer_id: int) -> String:
	return String(Net.players.get(peer_id, {}).get("name", tr("Игрок")))


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
	# Our own id: attack / cast fx carry it, the others skip their own echo.
	player.peer_id = my_id
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
	if Net.world_session:
		var spot := ReviveSpot.new()
		spot.target = p
		p.add_child(spot)
	p.add_to_group("player")
	p.net_place(level.start_position() + Vector2(14, 0))
	var tag := UIStyle.outlined_label(_net_player_name(peer_id), 6, UIStyle.ally_color(peer_id))
	tag.position = Vector2(-20, -46)
	tag.size = Vector2(40, 10)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(tag)
	hud.add_ally(_net_player_name(peer_id), mirror)
	# Everyone (except the puppet's owner) learns about it from the host.
	if Net.is_host:
		Net.send(self, &"spawn_ally", [peer_id, info])


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
	if Net.world_session:
		# A world session: this machine stands here now (Net.send routes by it).
		Net.set_scene_token("%d:%d:%s" % [GameFlow.state, int(GameState.location.get("seed", 0)), GameState.location_type()])
	# Every floor: the guest asks the host for a fresh world snapshot —
	# spawn descriptors broadcast mid-transition may have been dropped.
	if not Net.is_host:
		if Net.world_session:
			# the host must stand here too before it can answer
			for i in 60:
				if Net.peer_in_scene(1) or not is_inside_tree():
					break
				await get_tree().create_timer(0.1).timeout
			if not is_inside_tree():
				return
		net_sync.net_hello.rpc_id(1)
	var sp := level.start_position()
	player.global_position = sp
	for p: Player in party():
		if p == player:
			continue
		p.net_place(sp + Vector2(14, 0))
	# A fallen hero rises on the next floor (co-op rule).
	if player.dead:
		player.revive()
	for p: Player in party():
		if p != player and p.dead:
			p.revive()


## A world session: an ally raised this fallen hero (35% health).
func revive_local() -> void:
	if player == null or not player.dead:
		return
	player.revive()
	player.hero.stats.hp = maxi(1, roundi(player.hero.stats.max_hp() * 0.35))
	player.hero.stats.hp_changed.emit(player.hero.stats.hp, player.hero.stats.max_hp())
	overlay.visible = false
	get_tree().paused = false
	EventBus.message.emit(tr("Вас подняли на ноги!"))


## The local hero fell: wait for the next floor unless everyone is down.
func _on_player_died_coop() -> void:
	AudioManager.play_sting(&"death")
	book.close()
	skill_tree.close()
	await get_tree().create_timer(1.0).timeout
	net_sync.broadcast_player_hp(Net.multiplayer.get_unique_id(), 0,
			GameState.hero.stats.max_hp() if GameState.hero else 0, true)
	var any_alive := false
	for p: Player in party():
		if p != player and not p.dead:
			any_alive = true
	if any_alive:
		get_tree().paused = true
		overlay.clear()
		overlay.set_panel_size(Vector2(340, 150))
		overlay.add_text(tr("Вы пали"), 14)
		overlay.add_text(tr("Возрождение на следующем этаже..."), 9)
		overlay.add_button(tr("Ждать (наблюдать)"), func() -> void:
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
	overlay.add_text(tr("Отряд пал"), 14)
	overlay.add_button(tr("В главное меню"), func() -> void:
		Net.leave()
		GameState.go_to_menu())
	overlay.visible = true


func _end_run_coop() -> void:
	if Net.world_session:
		GameFlow.hero_died()  # the whole party fell: the expedition is lost for everyone
		return
	GameState.end_run()
	net_run_ended.rpc()
	var hero := GameState.hero
	get_tree().paused = true
	overlay.clear()
	overlay.set_panel_size(Vector2(340, 150))
	overlay.add_text(tr("Отряд пал"), 14)
	overlay.add_button(tr("В главное меню"), func() -> void:
		Net.leave()
		GameState.go_to_menu())
	overlay.visible = true
