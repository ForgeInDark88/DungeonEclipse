class_name DungeonLevel
extends Node2D
## One dungeon floor in the world: tile layers built from a LevelLayout,
## plus every entity of the floor (chests, enemies, door, drops, projectiles).
## Freed as a whole when the hero goes down to the next floor.

const TILE := 16
# Loaded lazily (not preload): these scenes' scripts reference DungeonLevel,
# preloading them here would create a load cycle.
const CHEST_SCENE := "res://scenes/world/chest.tscn"
const ENEMY_SCENE := "res://scenes/enemies/enemy.tscn"
const DOOR_SCENE := "res://scenes/world/exit_door.tscn"
const STAIRS_SCENE := "res://scenes/world/return_stairs.tscn"
const TORCH_SCENE := "res://scenes/world/wall_torch.tscn"
const DRIP_SCENE := "res://scenes/world/water_drip.tscn"
const TRAP_SCENE := "res://scenes/traps/trap.tscn"
const MERCHANT_SCENE := "res://scenes/npc/merchant.tscn"
const SMITH_SCENE := "res://scenes/npc/blacksmith.tscn"
const QUEST_SCENE := "res://scenes/npc/quest_giver.tscn"
const BOSS_SCENE := "res://scenes/bosses/boss.tscn"
## No traps this close (in cells) to the start.
const SAFE_START_RADIUS := 8
const T = LevelLayout.Tile

@onready var back: TileMapLayer = $Back
@onready var tiles: TileMapLayer = $Tiles
@onready var glow: TileMapLayer = $Glow
## Small details without collision: wall marks (behind) and floor / ceiling
## fringe (grass, pebbles, vines...). Rows AssetPaths.TILE_ROW_*_FRINGE / WALL_DETAIL.
@onready var back_detail: TileMapLayer = $BackDetail
@onready var detail: TileMapLayer = $Detail
@onready var entities: Node2D = $Entities

var layout: LevelLayout
var floor_number: int = 1
var biome: BiomeData
var rng := RandomNumberGenerator.new()
## LAN co-op: enemies get ids in spawn order — the same on every machine.
var net_seq := 0
## Cells of glowing ore veins (break them for loot).
var ore_cells: Dictionary = {}
## Minimap fog of war: 1 = explored.
var explored := PackedByteArray()
var explored_version := 0
## Monster navigation (walk graph + flying grid), see LevelNav.
var nav: LevelNav
var _nav_dirty := false
## Cells changed since the last navigation update (bounding box).
var _nav_area := Rect2i()
var _nav_timer := 0.0
## Cells whose look changed (explored or dug): the minimap redraws only these.
var changed_cells: Array[Vector2i] = []
## Exit seal: the exit opens after seal_required kills on this floor
## (GameState.seal_share() of the monsters placed by the generator).
var seal_required := 0
## Depth: solid blocks cast a soft shadow on the back wall (light from the
## top left) - two copies of the tile layer, black, offset down-right.
var _shadows: Array[TileMapLayer] = []
var seal_kills := 0
## A location of several layers (LocationBuilder): the bands of the level.
var location_mode := false
## While a band is being built: its origin in cells (cell_bottom / cell_center
## shift band cells to the level) and its own layout in `layout`.
var _origin := Vector2i.ZERO
var _composite: LevelLayout
## Row -> band index (-1: the rock between two bands).
var _row_band := PackedInt32Array()
## Nodes that read the level's layout in _ready (gates) wait for the end of
## the build (the layout is the band's while a band is built).
var _late: Array[Node] = []


func build(p_layout: LevelLayout, p_floor: int, seed_value: int, p_biome: BiomeData = null) -> void:
	layout = p_layout
	floor_number = p_floor
	biome = p_biome
	rng.seed = seed_value
	var ts := TilesetBuilder.get_tileset(biome.tileset_texture if biome else null)
	back.tile_set = ts
	tiles.tile_set = ts
	glow.tile_set = ts
	back_detail.tile_set = ts
	detail.tile_set = ts
	if biome:
		# The back wall sits a step darker than the blocks you stand on,
		# so the walkable world reads at a glance.
		var deep := biome.back_wall_modulate * Color(0.86, 0.86, 0.88, 1.0)
		back.modulate = deep
		back_detail.modulate = deep
	for k in 2:
		var sh := TileMapLayer.new()
		sh.name = "BlockShadow%d" % k
		sh.tile_set = ts
		sh.collision_enabled = false
		sh.navigation_enabled = false
		sh.z_index = -3
		sh.position = [Vector2(1, 1), Vector2(3, 4)][k]
		sh.modulate = Color(0, 0, 0, [0.32, 0.26][k])
		add_child(sh)
		move_child(sh, tiles.get_index())
		_shadows.append(sh)
	explored.resize(layout.width * layout.height)
	explored.fill(1 if layout.is_town else 0)
	if not layout.is_town:
		_place_ore()
	nav = LevelNav.new(layout)
	# Back wall with gaps: through them the parallax cave is visible.
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.08
	for y in layout.height:
		for x in layout.width:
			var cell := Vector2i(x, y)
			if not layout.is_town and not layout.is_surface and (noise.get_noise_2d(x, y) > -0.25 or _near_solid(cell)):
				back.set_cell(cell, _src(cell), Vector2i(_back_variant(cell), AssetPaths.TILE_ROW_BACKWALL))
			_apply_tile(cell, layout.get_tile(x, y))
	for y in layout.height:
		for x in layout.width:
			_apply_detail(Vector2i(x, y))
	if layout.is_town:
		_spawn_town()
		return
	if layout.is_camp:
		_spawn_camp()
		return
	if layout.is_event_room:
		_spawn_door()
		_spawn_specials()
		_spawn_ambience()
		_spawn_decorations()
		return
	if layout.is_arena:
		_spawn_boss()
		_spawn_lore()
		_spawn_ambience()
		_spawn_decorations()
		return
	_spawn_door()
	_spawn_return_stairs()
	_spawn_specials()
	_spawn_chests()
	_spawn_secret_walls()
	_spawn_lore()
	_spawn_fishing()
	_spawn_enemies()
	_setup_seal()
	_spawn_ambience()
	_spawn_decorations()
	_spawn_traps()
	nav._apply_dangers()


# ---------------------------------------------------------------- location
## A location of several layers in one level (LocationBuilder.build): the
## tiles of every band at once (each with its biome's tileset), then each
## band's things with its own depth, biome and rules, as if it were a level
## of its own. Portals between the bands come from layout.portal_cells.
func build_location(p_layout: LevelLayout, seed_value: int) -> void:
	layout = p_layout
	_composite = p_layout
	location_mode = true
	var first: Dictionary = layout.bands[0]
	floor_number = int(first["depth"])
	biome = first["biome"]
	rng.seed = seed_value
	_row_band.resize(layout.height)
	_row_band.fill(-1)
	var texs := []
	var deep: BiomeData = null
	for i in layout.bands.size():
		var b: Dictionary = layout.bands[i]
		var bb: BiomeData = b["biome"]
		texs.append(bb.tileset_texture if bb else null)
		var r: Rect2i = b["rect"]
		for y in range(r.position.y, r.end.y):
			_row_band[y] = i
		if deep == null and int(b["kind"]) != LocationInstance.Kind.SURFACE:
			deep = bb
	var ts := TilesetBuilder.get_tileset_multi(texs)
	for l: TileMapLayer in [back, tiles, glow, back_detail, detail]:
		l.tile_set = ts
	if deep:
		var dm := deep.back_wall_modulate * Color(0.86, 0.86, 0.88, 1.0)
		back.modulate = dm
		back_detail.modulate = dm
	for k in 2:
		var sh := TileMapLayer.new()
		sh.name = "BlockShadow%d" % k
		sh.tile_set = ts
		sh.collision_enabled = false
		sh.navigation_enabled = false
		sh.z_index = -3
		sh.position = [Vector2(1, 1), Vector2(3, 4)][k]
		sh.modulate = Color(0, 0, 0, [0.32, 0.26][k])
		add_child(sh)
		move_child(sh, tiles.get_index())
		_shadows.append(sh)
	explored.resize(layout.width * layout.height)
	explored.fill(0)
	_place_ore()
	nav = LevelNav.new(layout)
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.08
	for y in layout.height:
		var bi := _row_band[y]
		var open_sky := bi < 0 or int(layout.bands[bi]["kind"]) == LocationInstance.Kind.SURFACE
		var band_w := (layout.bands[bi]["rect"] as Rect2i).end.x if bi >= 0 else 0
		for x in layout.width:
			var cell := Vector2i(x, y)
			if x >= band_w and layout.get_tile(x, y) == T.EMPTY:
				continue  # outside every layer: nothing to draw
			if not open_sky and (noise.get_noise_2d(x, y) > -0.25 or _near_solid(cell)):
				back.set_cell(cell, _src(cell), Vector2i(_back_variant(cell), AssetPaths.TILE_ROW_BACKWALL))
			_apply_tile(cell, layout.get_tile(x, y))
	for y in layout.height:
		var bj := _row_band[y]
		if bj < 0:
			continue
		var bw := (layout.bands[bj]["rect"] as Rect2i).end.x
		for x in bw:
			_apply_detail(Vector2i(x, y))
	for i in layout.bands.size():
		_build_band(i, seed_value)
	for n in _late:
		add_child(n)
	_late.clear()
	nav._apply_dangers()


func _build_band(i: int, seed_value: int) -> void:
	_enter_band(i)
	rng.seed = hash([seed_value, i])
	match int(layout_band(i)["kind"]):
		LocationInstance.Kind.ARENA:
			_spawn_boss()
			_spawn_lore()
			_spawn_ambience()
			_spawn_decorations()
		LocationInstance.Kind.SURFACE:
			_spawn_surface_props()
			_spawn_water()
			_spawn_surface_things()
			_spawn_secret_walls()
			_spawn_lore()
			_spawn_specials()
			_spawn_chests()
			_spawn_enemies()
		_:
			_spawn_specials()
			_spawn_chests()
			_spawn_secret_walls()
			_spawn_lore()
			_spawn_fishing()
			_spawn_enemies()
			_spawn_ambience()
			_spawn_decorations()
			_spawn_traps()
	_exit_band()


## The surface's trees, rocks, ruins and camps (behind or in front of the
## hero by their z), from layout.surface_props.
func _spawn_surface_props() -> void:
	for p in layout.surface_props:
		var tex := AssetPaths.tex("res://assets/sprites/surface/%s.png" % String(p["tex"]))
		if tex == null:
			continue
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = false
		s.offset = Vector2(-floorf(tex.get_width() / 2.0), -tex.get_height())
		s.z_index = int(p["z"])
		var name := String(p["tex"])
		if name.begins_with("tree") or name == "reeds":
			s.flip_h = (hash(p["cell"]) & 1) == 1
		if name.begins_with("tree") and name != "tree_dead" or name in ["bush", "reeds", "berry_bush"]:
			s.material = _foliage_material()  # a pixel of wind in the crowns
		add_entity(s, cell_bottom(p["cell"]))


static var _foliage: ShaderMaterial
## The ponds (ColorRects with assets/shaders/water.gdshader).
var water_bodies: Array[ColorRect] = []


## One shared material for every plant (assets/shaders/foliage_sway.gdshader).
static func _foliage_material() -> ShaderMaterial:
	if _foliage == null:
		_foliage = ShaderMaterial.new()
		_foliage.shader = load("res://assets/shaders/foliage_sway.gdshader")
	return _foliage


## A camp of the road (CampBuilder): its props, its spots, the trader,
## the companions freed on the way.
func _spawn_camp() -> void:
	_spawn_surface_props()
	_spawn_specials()
	for m in get_tree().get_nodes_in_group("merchants"):
		if "extra_rolls" in m:
			m.extra_rolls = Buildings.level(&"shop")
	for info in layout.town_people:
		var nd: NpcData = ItemDatabase.npcs.get(StringName(info["id"]))
		if nd:
			var npc := TownNpc.new()
			npc.setup(nd)
			add_entity(npc, cell_bottom(info["cell"]))
	if layout.camp_kind == &"cave":
		_spawn_ambience()


## Things to gather, barrels and crates (personal: every machine has its
## own; their place in the build order keeps the saved state's ids).
func _spawn_surface_things() -> void:
	for r in layout.resources:
		var n := ResourceNode.new()
		n.kind = StringName(r["kind"])
		n.depth = floor_number
		_net_seq_node(n)
		add_entity(n, cell_bottom(r["cell"]))
	for b in layout.breakables:
		var k := Breakable.new()
		k.look = StringName(b["look"])
		k.depth = floor_number
		_net_seq_node(k)
		add_entity(k, cell_bottom(b["cell"]))


## Ponds: a sheet of water over the dip, a lighter line on its surface.
func _spawn_water() -> void:
	var col := Color(0.3, 0.5, 0.75, 0.75)
	if biome is SurfaceBiomeData:
		col = (biome as SurfaceBiomeData).water_color
	for r: Rect2i in layout.water:
		var top := cell_bottom(Vector2i(r.position.x, r.position.y - 1)) + Vector2(-TILE / 2.0, 2)
		var size := Vector2(r.size.x * TILE, r.size.y * TILE + TILE / 2.0 - 2)
		var body := ColorRect.new()
		body.size = size
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# (the holder's z 2 puts it in front of the hero: a swimmer is seen through the water)
		var m := ShaderMaterial.new()
		m.shader = load("res://assets/shaders/water.gdshader")
		m.set_shader_parameter("shallow", Color(col.r, col.g, col.b, minf(col.a, 0.62)))
		m.set_shader_parameter("deep", Color(col.r * 0.35, col.g * 0.45, col.b * 0.6, 0.88))
		m.set_shader_parameter("size", size)
		m.set_shader_parameter("seed", float(r.position.x % 97))
		body.material = m
		var holder := Node2D.new()
		holder.z_index = 2
		holder.add_child(body)
		add_entity(holder, top)
		water_bodies.append(body)
		# a rod in the bank: fish the pond (surface only)
		if layout.is_surface and r.size.x >= 5:
			var spot := FishingSpot.new()
			spot.pond = true
			add_entity(spot, cell_bottom(Vector2i(r.position.x - 1, r.position.y - 1)))


## The water surface under or around a point (global): how deep the point
## is under it (px, 0 = at the surface), or -1 when it is not in water.
func water_depth_at(gpos: Vector2) -> float:
	for body: ColorRect in water_bodies:
		if not is_instance_valid(body):
			continue
		var r := Rect2(body.global_position, body.size)
		if r.grow_individual(0, 0, 0, 0).has_point(gpos):
			return gpos.y - (r.position.y + 2.0)
	return -1.0


## Something broke the surface at gpos: rings run out from it, drops fly.
func splash(gpos: Vector2, big := true) -> void:
	for body: ColorRect in water_bodies:
		if not is_instance_valid(body):
			continue
		var r := Rect2(body.global_position - Vector2(0, 10), body.size + Vector2(0, 10))
		if r.has_point(gpos):
			var m := body.material as ShaderMaterial
			var rx := gpos.x - body.global_position.x
			var tw := body.create_tween()
			tw.tween_method(func(age: float) -> void: m.set_shader_parameter("ripple", Vector3(rx, 0.0, age)), 0.0, 1.6, 1.6)
			Fx.splash(get_parent() if get_parent() else self, Vector2(gpos.x, body.global_position.y + 3), (m.get_shader_parameter("shallow") as Color), big)
			AudioManager.play_sfx(&"splash" if big else &"swim", gpos, -4.0 if big else -10.0, 0.15)
			return


## Rain on every pond (SurfaceSky weather).
func set_rain(amount: float) -> void:
	for body: ColorRect in water_bodies:
		if is_instance_valid(body):
			(body.material as ShaderMaterial).set_shader_parameter("rain", amount)


## The band dictionary (LevelLayout.bands) of index i.
func layout_band(i: int) -> Dictionary:
	return _composite.bands[i] if _composite and i >= 0 and i < _composite.bands.size() else {}


## While band i is built: its layout, depth and biome; cells shift by its
## origin. _exit_band() returns to the whole level.
func _enter_band(i: int) -> void:
	var b := layout_band(i)
	layout = b["layout"]
	_origin = b["origin"]
	floor_number = int(b["depth"])
	biome = b["biome"]


func _exit_band() -> void:
	layout = _composite
	_origin = Vector2i.ZERO
	var first := layout_band(0)
	floor_number = int(first["depth"])
	biome = first["biome"]


## Depth and biome of the band of a level cell for a spawn at play time
## (an ambush wave, a mimic); returns what to restore.
func _rules_at(cell: Vector2i) -> Array:
	var keep := [floor_number, biome]
	if location_mode and layout == _composite:  # (while a band is built, its rules hold)
		var b := layout_band(band_index_at_cell(cell))
		if not b.is_empty():
			floor_number = int(b["depth"])
			biome = b["biome"]
	return keep


func _restore_rules(keep: Array) -> void:
	floor_number = keep[0]
	biome = keep[1]


func _shift_rect(r: Rect2i) -> Rect2i:
	return Rect2i(r.position + _origin, r.size)


func _add_late(n: Node) -> void:
	if _origin != Vector2i.ZERO or (location_mode and layout != _composite):
		_late.append(n)
	else:
		add_child(n)


## Atlas source of a cell: its band's tileset (0 for an ordinary level).
func _src(cell: Vector2i) -> int:
	if not location_mode or cell.y < 0 or cell.y >= _row_band.size():
		return TilesetBuilder.SOURCE_ID
	var bi := _row_band[cell.y]
	if bi < 0:
		# The rock between two bands: the lower band's stone.
		for y in range(cell.y, _row_band.size()):
			if _row_band[y] >= 0:
				return _row_band[y]
		return 0
	return bi


func biome_at_cell(cell: Vector2i) -> BiomeData:
	if not location_mode:
		return biome
	var b := layout_band(band_index_at_cell(cell))
	return b["biome"] if not b.is_empty() else biome


func has_bands() -> bool:
	return location_mode


## Band index of a level cell / world position (-1: in the rock between).
func band_index_at_cell(cell: Vector2i) -> int:
	if not location_mode:
		return 0
	if cell.y < 0 or cell.y >= _row_band.size():
		return -1
	return _row_band[cell.y]


func band_index_at(p: Vector2) -> int:
	var c := to_local(p)
	return band_index_at_cell(Vector2i(floori(c.x / TILE), floori(c.y / TILE)))


## The band's rectangle in world px (the whole level without bands).
func band_rect_px(p: Vector2) -> Rect2:
	if not location_mode:
		return bounds_px()
	var b := layout_band(band_index_at(p))
	if b.is_empty():
		return bounds_px()
	var r: Rect2i = b["rect"]
	return Rect2(to_global(Vector2(r.position * TILE)), Vector2(r.size * TILE))


func same_band(a: Vector2, b: Vector2) -> bool:
	return not location_mode or band_index_at(a) == band_index_at(b)


## Town: buildings and props along the street, lamps, the merchant and the
## blacksmith, the dungeon gate with two torches, fireflies.
func _spawn_town() -> void:
	for p in layout.town_props:
		var tex: Texture2D = load(AssetPaths.TOWN_DIR + String(p["tex"]) + ".png")
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = false
		s.offset = Vector2(-floorf(tex.get_width() / 2.0), -tex.get_height())
		s.z_index = p["z"]
		add_entity(s, cell_bottom(p["cell"]))
		if p["lamp"]:
			var light := PointLight2D.new()
			light.texture = AssetPaths.tex(AssetPaths.LIGHT)
			light.color = Color(1.0, 0.8, 0.5)
			light.energy = 1.1 * (1.7 if Buildings.is_night() else 1.0)
			light.texture_scale = 0.7
			light.position = Vector2(0, -tex.get_height() + 6)
			s.add_child(light)
			var ft := create_tween().set_loops()
			var fbase := light.energy
			ft.tween_method(func(phase: float) -> void:
				light.energy = fbase + sin(phase) * 0.06 + sin(phase * 2.3) * 0.04,
				0.0, TAU, randf_range(1.8, 2.6)).set_trans(Tween.TRANS_LINEAR)
	_spawn_specials()
	# The expedition loop's town: buildings on their foundations, its people.
	for info in layout.town_buildings:
		var bd := ItemDatabase.building(StringName(info["id"]))
		if bd:
			var tb := TownBuilding.new()
			tb.setup(bd)
			add_entity(tb, cell_bottom(info["cell"]))
	for info in layout.town_people:
		var nd: NpcData = ItemDatabase.npcs.get(StringName(info["id"]))
		if nd:
			var npc := TownNpc.new()
			npc.setup(nd)
			for k in (info.get("schedule", {}) as Dictionary):
				npc.schedule[k] = cell_bottom(Vector2i(int(info["schedule"][k]), info["cell"].y)).x
			add_entity(npc, cell_bottom(info["cell"]))
	var gate := DungeonGate.new()
	add_entity(gate, cell_bottom(layout.exit_cell))
	for dx in [-28, 28]:
		var torch := (load(TORCH_SCENE) as PackedScene).instantiate()
		add_entity(torch, cell_bottom(layout.exit_cell) + Vector2(dx, -30))
	var flies := CPUParticles2D.new()
	flies.amount = 40
	flies.lifetime = 6.0
	flies.preprocess = 6.0
	flies.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	flies.emission_rect_extents = Vector2(layout.width * TILE / 2.0, 40)
	flies.gravity = Vector2.ZERO
	flies.direction = Vector2(0, -1)
	flies.spread = 180.0
	flies.initial_velocity_min = 3.0
	flies.initial_velocity_max = 10.0
	flies.scale_amount_min = 1.0
	flies.scale_amount_max = 2.0
	flies.color = biome.ambient_particles if biome else Color(0.85, 1, 0.55)
	add_entity(flies, to_global(Vector2(layout.width * TILE / 2.0, (layout.height - 8) * TILE)))


## Exit seal: every kill on the floor counts (each machine counts its own
## enemy_killed events; the host also broadcasts its count for late joiners).
func _setup_seal() -> void:
	seal_required = ceili(layout.enemy_cells.size() * GameState.seal_share())
	seal_kills = 0
	EventBus.enemy_killed.connect(_on_seal_kill)
	_emit_seal.call_deferred()


func is_sealed() -> bool:
	return seal_kills < seal_required


func _on_seal_kill(_d: EnemyData, _p: Vector2) -> void:
	if not is_sealed():
		return
	seal_kills += 1
	if Net.active and Net.is_host:
		var ns := get_tree().get_first_node_in_group("net_game") as NetSync
		if ns:
			Net.send(ns, &"seal_state", [seal_kills])
	_seal_progress()


## A fight started on purpose (a road event): the exit stays sealed until
## these `count` monsters are dead.
func seal_for_fight(count: int) -> void:
	seal_required = count
	seal_kills = 0
	if not EventBus.enemy_killed.is_connected(_on_seal_kill):
		EventBus.enemy_killed.connect(_on_seal_kill)
	_emit_seal()


## Clients: the host's count (late join, kills the client did not see).
func set_seal_kills(kills: int) -> void:
	if kills > seal_kills:
		seal_kills = mini(kills, seal_required)
		_seal_progress()


func _seal_progress() -> void:
	_emit_seal()
	if not is_sealed():
		EventBus.message.emit(tr("Печать снята! Выход открыт."))
		AudioManager.play_sfx(&"portal")


func _emit_seal() -> void:
	EventBus.seal_changed.emit(seal_kills, seal_required)


## Arena: the boss; door and reward chest appear when it dies.
func _spawn_boss() -> void:
	var data := ItemDatabase.boss_for_floor(floor_number)
	if data == null:
		_spawn_door()
		return
	var b: Boss = (load(BOSS_SCENE) as PackedScene).instantiate()
	b.setup(data, floor_number)
	_net_tag(b)
	var pos := cell_bottom(layout.boss_cell)
	if data.behavior == EnemyData.Behavior.FLYER:
		pos.y -= TILE * 4
	add_entity(b, pos)
	_spawn_arena_hazards()
	EventBus.boss_defeated.connect(_on_boss_defeated, CONNECT_ONE_SHOT)


## Lava, water, embers and the void of the boss's arena (every machine builds
## them from the layout; only the host's copies hurt).
func _spawn_arena_hazards() -> void:
	var dmg := 4 + roundi(floor_number * 0.7)
	for h: Dictionary in layout.arena_hazards:
		var x0: int = h["x0"]
		var x1: int = h["x1"]
		var bottom := cell_bottom(Vector2i(x0, h["row"]))
		var center := Vector2(to_global(Vector2((x0 + x1 + 1) * TILE * 0.5, 0)).x, bottom.y)
		var style: BossHazard.Style = h["style"]
		var dtype := 4 if style == BossHazard.Style.VOID else 1
		BossHazard.spawn(entities, style, center, Vector2((x1 - x0 + 1) * TILE, h["h"]), -1.0,
				Vector2.ZERO, dmg if h["damage"] else 0, dtype)


func _on_boss_defeated(_boss: BossData, _pos: Vector2) -> void:
	if not is_inside_tree():
		return
	if location_mode:
		var bi := band_index_at(_pos)
		for i in layout.bands.size():
			if int(layout.bands[i]["kind"]) == LocationInstance.Kind.ARENA:
				bi = i
		_enter_band(bi)
		_boss_reward(_boss)
		_exit_band()
		get_tree().call_group("location_manager", "on_boss_beaten")
		return
	_spawn_door()
	_boss_reward(_boss)


func _boss_reward(_boss: BossData) -> void:
	var chest: Chest = (load(CHEST_SCENE) as PackedScene).instantiate()
	chest.tier = 2
	chest.floor_number = floor_number
	chest.unlocked_by_default = true
	chest.table_override = &"boss"  # boss loot: the main source of legendary items
	# (Arenas differ: a dais or a pit may take the middle - find a free spot.)
	var spot := _free_cell_near(Vector2i(layout.width / 2, layout.boss_cell.y))
	for dx in range(4, 14):
		if spot.x >= 0:
			break
		for c in [Vector2i(layout.width / 2 + dx, layout.boss_cell.y), Vector2i(layout.width / 2 - dx, layout.boss_cell.y)]:
			if layout.get_tile(c.x, c.y) == LevelLayout.Tile.EMPTY and LevelLayout.is_solid(layout.get_tile(c.x, c.y + 1)):
				spot = c
				break
	if spot.x < 0:
		spot = layout.start_cell
	add_entity(chest, cell_bottom(spot))
	# The relic altar beside the chest: a choice of one relic from three
	# (personal - every machine builds its own).
	if not _boss.final:
		var altar_cell := Vector2i(-1, -1)
		for dx in [3, -3, 4, -4, 5, -5, 2, -2, 6, -6]:
			var c := Vector2i(spot.x + dx, spot.y)
			if layout.get_tile(c.x, c.y) == LevelLayout.Tile.EMPTY and LevelLayout.is_solid(layout.get_tile(c.x, c.y + 1)):
				altar_cell = c
				break
		if altar_cell.x >= 0:
			add_entity(RelicAltar.new(), cell_bottom(altar_cell))
	if layout.exit_cell.x >= 0:
		Fx.sparks(entities, cell_bottom(layout.exit_cell) + Vector2(0, -16), Color(0.7, 0.4, 1.0), 30, 120.0)
	EventBus.message.emit(tr("Затмение рассеяно! Свет возвращается в подземелья.") if _boss.final else tr("Страж повержен! Открылся проход."))


## Deterministic 0..3 variant per cell.
func _variant(cell: Vector2i) -> int:
	return absi(hash(cell * 7 + Vector2i(floor_number, 3))) % 4


## Back wall: mostly plain blocks (0, 1); a crack (2) or a niche (3) only
## now and then (2 in 96 / 1 in 96), so details do not turn into a pattern.
func _back_variant(cell: Vector2i) -> int:
	var h := absi(hash(cell * 13 + Vector2i(floor_number, 11))) % 96
	return 3 if h == 95 else 2 if h >= 93 else h % 2


## A gap in the back wall gets a crumbling rim from the wall next to it.
func _rim_back_gap(cell: Vector2i) -> void:
	const DIRS: Array[Vector2i] = [Vector2i.DOWN, Vector2i.UP, Vector2i.RIGHT, Vector2i.LEFT]
	const COLS: Array[int] = [1, 0, 3, 2]  # atlas column: wall above, below, left, right
	for k in DIRS.size():
		if back.get_cell_source_id(cell + DIRS[k]) >= 0:
			back_detail.set_cell(cell, _src(cell), Vector2i(COLS[k], AssetPaths.TILE_ROW_BACK_EDGE))
			return


func _near_solid(cell: Vector2i) -> bool:
	for d in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if LevelLayout.is_solid(layout.get_tile(cell.x + d.x, cell.y + d.y)):
			return true
	return false


func _place_ore() -> void:
	ore_cells.clear()
	var chance := (biome.ore_chance if biome else 0.04) * float(GameState.location_mod("ore", 1.0))
	for y in range(1, layout.height - 1):
		for x in range(1, layout.width - 1):
			if layout.get_tile(x, y) != T.BRICK:
				continue
			# Only visible bricks (touching an open cell) become ore.
			var exposed := false
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if not LevelLayout.is_solid(layout.get_tile(x + d.x, y + d.y)):
					exposed = true
			var bb := biome_at_cell(Vector2i(x, y))
			var c_here := chance if not location_mode else (bb.ore_chance if bb else 0.04) * float(GameState.location_mod("ore", 1.0))
			if exposed and rng.randf() < c_here:
				ore_cells[Vector2i(x, y)] = true


## Picks the atlas tile for a cell from its neighbours (autotiling): exposed
## top / bottom edges, platform ends, random variants, ore.
func _apply_tile(cell: Vector2i, kind: int) -> void:
	glow.erase_cell(cell)
	var v := _variant(cell)
	match kind:
		T.EMPTY:
			tiles.erase_cell(cell)
		T.BEDROCK:
			tiles.set_cell(cell, _src(cell), Vector2i(v, AssetPaths.TILE_ROW_BEDROCK))
		T.BRICK:
			var coords: Vector2i
			if ore_cells.has(cell):
				coords = AssetPaths.TILE_ORE
				glow.set_cell(cell, _src(cell), AssetPaths.TILE_ORE_GLOW)
			elif not LevelLayout.is_solid(layout.get_tile(cell.x, cell.y - 1)):
				coords = Vector2i(v, AssetPaths.TILE_ROW_BRICK_TOP)
			elif not LevelLayout.is_solid(layout.get_tile(cell.x, cell.y + 1)):
				coords = Vector2i(v, AssetPaths.TILE_ROW_BRICK_BOTTOM)
			else:
				# Mostly plain bricks, sometimes cracked.
				coords = Vector2i(2 if v == 3 else v % 2, AssetPaths.TILE_ROW_BRICK)
			tiles.set_cell(cell, _src(cell), coords)
		T.PLATFORM:
			var left := layout.get_tile(cell.x - 1, cell.y) == T.PLATFORM
			var right := layout.get_tile(cell.x + 1, cell.y) == T.PLATFORM
			var c := AssetPaths.TILE_PLATFORM_MID
			if not left:
				c = AssetPaths.TILE_PLATFORM_LEFT
			elif not right:
				c = AssetPaths.TILE_PLATFORM_RIGHT
			tiles.set_cell(cell, _src(cell), c)
		T.LADDER:
			tiles.set_cell(cell, _src(cell), AssetPaths.TILE_LADDER, 0)
		T.LADDER_TOP:
			tiles.set_cell(cell, _src(cell), AssetPaths.TILE_LADDER, TilesetBuilder.LADDER_TOP_ALT)
	for sh in _shadows:
		if kind == T.EMPTY or kind == T.LADDER or kind == T.LADDER_TOP:
			sh.erase_cell(cell)
		else:
			sh.set_cell(cell, _src(cell), tiles.get_cell_atlas_coords(cell))


## Settings → «Тени блоков».
func set_block_shadows(on: bool) -> void:
	for sh in _shadows:
		sh.visible = on


## Fringe and wall marks of a cell, from its neighbours (stable per cell).
func _apply_detail(cell: Vector2i) -> void:
	detail.erase_cell(cell)
	back_detail.erase_cell(cell)
	if back.get_cell_source_id(cell) < 0:
		_rim_back_gap(cell)
	if layout.get_tile(cell.x, cell.y) != T.EMPTY:
		return
	var h := absi(hash(cell * 17 + Vector2i(floor_number, 5)))
	var roll := float(h % 1000) / 1000.0
	var v := (h / 1000) % 4
	var bb := biome_at_cell(cell)
	var floor_k := bb.floor_fringe if bb else 0.45
	var ceil_k := bb.ceiling_fringe if bb else 0.3
	var wall_k := bb.wall_details if bb else 0.03
	if layout.get_tile(cell.x, cell.y + 1) == T.BRICK and roll < floor_k:
		detail.set_cell(cell, _src(cell), Vector2i(v, AssetPaths.TILE_ROW_FLOOR_FRINGE))
	elif LevelLayout.is_solid(layout.get_tile(cell.x, cell.y - 1)) and roll < ceil_k:
		detail.set_cell(cell, _src(cell), Vector2i(v, AssetPaths.TILE_ROW_CEIL_FRINGE))
	elif back.get_cell_source_id(cell) >= 0 and roll > 1.0 - wall_k:
		back_detail.set_cell(cell, _src(cell), Vector2i(v, AssetPaths.TILE_ROW_WALL_DETAIL))


## Re-picks the tile of a cell and its neighbours (after digging).
func _refresh_around(cell: Vector2i) -> void:
	for d in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var c: Vector2i = cell + d
		if layout.in_bounds(c.x, c.y):
			_apply_tile(c, layout.get_tile(c.x, c.y))
			_apply_detail(c)


## Navigation is rebuilt shortly after digging / bombs / ropes: a burst of
## broken bricks costs one rebuild, not one per brick.
func _physics_process(delta: float) -> void:
	if not _nav_dirty or nav == null:
		return
	_nav_timer -= delta
	if _nav_timer <= 0.0:
		_nav_dirty = false
		nav.update_area(_nav_area)
		AIDebug.log_event(self, "nav", tr("граф навигации обновлён (v%d)") % nav.version)


func _mark_nav_dirty(cell: Vector2i) -> void:
	var r := Rect2i(cell, Vector2i.ONE)
	if not _nav_dirty:
		_nav_timer = 0.2
		_nav_area = r
	else:
		_nav_area = _nav_area.merge(r)
	_nav_dirty = true


# ------------------------------------------------------------- exploration
## Marks cells around a world position as explored (minimap).
func reveal_around(world_pos: Vector2, radius: int) -> void:
	var c := world_to_cell(world_pos)
	var changed := false
	for y in range(c.y - radius, c.y + radius + 1):
		for x in range(c.x - radius, c.x + radius + 1):
			if layout.in_bounds(x, y) and (x - c.x) * (x - c.x) + (y - c.y) * (y - c.y) <= radius * radius:
				var i := y * layout.width + x
				if explored[i] == 0:
					explored[i] = 1
					changed = true
					changed_cells.append(Vector2i(x, y))
	if changed:
		explored_version += 1


func reveal_all() -> void:
	explored.fill(1)
	explored_version += 1


func is_explored(cell: Vector2i) -> bool:
	return layout.in_bounds(cell.x, cell.y) and explored[cell.y * layout.width + cell.x] == 1


# ------------------------------------------------------------- coordinates
func world_to_cell(p: Vector2) -> Vector2i:
	var local := to_local(p)
	return Vector2i(floori(local.x / TILE), floori(local.y / TILE))


## World position of the bottom-center of a cell (where feet stand).
func cell_bottom(cell: Vector2i) -> Vector2:
	cell += _origin
	return to_global(Vector2(cell.x * TILE + TILE / 2.0, (cell.y + 1) * TILE))


func cell_center(cell: Vector2i) -> Vector2:
	cell += _origin
	return to_global(Vector2(cell.x * TILE + TILE / 2.0, cell.y * TILE + TILE / 2.0))


func start_position() -> Vector2:
	return cell_bottom(layout.start_cell)


func bounds_px() -> Rect2:
	return Rect2(global_position, Vector2(layout.width * TILE, layout.height * TILE))


func kind_at(p: Vector2) -> int:
	var c := world_to_cell(p)
	return layout.get_tile(c.x, c.y)


func is_ladder_at(p: Vector2) -> bool:
	return LevelLayout.is_ladder(kind_at(p))


func is_ground_at(p: Vector2) -> bool:
	return LevelLayout.is_ground(kind_at(p))


func is_solid_at(p: Vector2) -> bool:
	return LevelLayout.is_solid(kind_at(p))


## Ladder column center x for a world position (to snap while climbing).
func ladder_center_x(p: Vector2) -> float:
	return cell_center(world_to_cell(p)).x


# ------------------------------------------------------------ modification
## Breaks a brick tile. Bedrock (outer border) is indestructible, and the town
## keeps its street: bombs, pickaxes and blasts do no damage there.
func break_tile(cell: Vector2i, effects := true) -> bool:
	if Net.active and not Net.is_host:
		var ns := get_tree().get_first_node_in_group("net_game") as NetSync
		if ns:
			ns.request_tile_break.rpc_id(1, cell)
		return false
	if layout.is_town:
		return false
	if layout.get_tile(cell.x, cell.y) != T.BRICK:
		return false
	layout.set_tile(cell.x, cell.y, T.EMPTY)
	_mark_nav_dirty(cell)
	changed_cells.append(cell)
	var was_ore := ore_cells.erase(cell)
	_refresh_around(cell)
	if Net.active and Net.is_host:
		var ns := get_tree().get_first_node_in_group("net_game") as NetSync
		if ns:
			Net.send(ns, &"tile_broken", [cell])
	if was_ore:
		var ore := ItemDatabase.get_item(biome.ore_item if biome else &"iron_ore")
		if ore:
			EventBus.spawn_items.emit(cell_center(cell), [{"item": ore, "count": rng.randi_range(1, 2)}])
		Fx.sparks(entities, cell_center(cell), Color(1.0, 0.85, 0.4), 12, 90.0)
		# An expedition carries the vein's stone and iron home to the town.
		GameFlow.gain_resource(&"iron" if rng.randf() < 0.45 else &"stone", 1, cell_center(cell))
	if effects:
		AudioManager.play_sfx(&"dig", cell_center(cell))
		_debris(cell_center(cell))
		Fx.shards(entities, cell_center(cell), Color(0.6, 0.45, 0.36), 8)
		# Sometimes there is something inside the wall.
		if not was_ore and rng.randf() < 0.06:
			var ore := ItemDatabase.get_item(&"iron_ore") if rng.randf() < 0.6 else ItemDatabase.get_item(&"gold_coin")
			if ore:
				EventBus.spawn_items.emit(cell_center(cell), [{"item": ore, "count": 1}])
	return true


func apply_remote_tile(cell: Vector2i, kind: int) -> void:
	if layout == null or cell.x < 0 or cell.y < 0 or cell.x >= layout.width or cell.y >= layout.height:
		return
	if layout.get_tile(cell.x, cell.y) == kind:
		return
	layout.set_tile(cell.x, cell.y, kind)
	_mark_nav_dirty(cell)
	changed_cells.append(cell)
	if kind != T.BRICK:
		ore_cells.erase(cell)
	_refresh_around(cell)


func explode(center: Vector2, radius: float) -> void:
	if Net.active and not Net.is_host:
		var ns := get_tree().get_first_node_in_group("net_game") as NetSync
		if ns:
			ns.request_tile_explosion.rpc_id(1, center, radius)
		return
	EventBus.noise.emit(center, 260.0)
	var c := world_to_cell(center)
	var r := ceili(radius / TILE)
	var broke := false
	for y in range(c.y - r, c.y + r + 1):
		for x in range(c.x - r, c.x + r + 1):
			if cell_center(Vector2i(x, y)).distance_to(center) <= radius:
				broke = break_tile(Vector2i(x, y), false) or broke
	if broke:
		_debris(center, 24)
		Fx.shards(entities, center, Color(0.6, 0.45, 0.36), 16)


## Hangs a rope (ladder tiles) from `cell` upward. Returns number of cells.
func place_rope(cell: Vector2i, max_length: int) -> int:
	if Net.active and not Net.is_host:
		# A guest never mutates shared tiles directly; the host does it.
		return 0
	var count := 0
	var placed: Array[Vector2i] = []
	var y := cell.y
	# Also cover the cell at the feet so the rope can be grabbed from the ground.
	if layout.get_tile(cell.x, y + 1) == T.EMPTY:
		y += 1
	while count < max_length and layout.get_tile(cell.x, y) == T.EMPTY:
		layout.set_tile(cell.x, y, T.LADDER)
		_mark_nav_dirty(Vector2i(cell.x, y))
		changed_cells.append(Vector2i(cell.x, y))
		_refresh_around(Vector2i(cell.x, y))
		placed.append(Vector2i(cell.x, y))
		count += 1
		y -= 1
	if count > 0 and Net.active and Net.is_host:
		var ns := get_tree().get_first_node_in_group("net_game") as NetSync
		if ns:
			Net.send(ns, &"ropes_placed", [placed])
	return count


func add_entity(node: Node2D, world_pos: Vector2) -> void:
	entities.add_child(node)
	node.global_position = world_pos


func _debris(pos: Vector2, amount: int = 10) -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = amount
	p.lifetime = 0.6
	p.explosiveness = 1.0
	p.spread = 180.0
	p.direction = Vector2.UP
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 110.0
	p.gravity = Vector2(0, 400)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	p.color = Color(0.45, 0.33, 0.27)
	entities.add_child(p)
	p.global_position = pos
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)


# ----------------------------------------------------------------- spawning
func _spawn_door() -> void:
	var door := (load(DOOR_SCENE) as PackedScene).instantiate()
	add_entity(door, cell_bottom(layout.exit_cell))


## Co-op: deterministic identity for shops and chests (same order everywhere).
func _net_seq_node(node: Node) -> void:
	# The location's own id (saved layer state: opened, disarmed...), always.
	loc_seq += 1
	node.set_meta(&"loc", loc_seq)
	if not Net.active:
		return
	net_seq += 1
	node.net_seq = net_seq


## Co-op: hand out the next enemy net id (own counter! Enemies exist only
## on the host, so sharing net_seq with world nodes would shift every
## chest/merchant/trap number on the client).
var enemy_seq := 0
## Ids of the location's things in build order (every machine, net or not):
## the saved layer state names chests, traps and the fallen by them.
var loc_seq := 0
var loc_enemy := 0


## Co-op: hand out the next net id; clients get puppets instead of AI.
func _net_tag(e: Enemy) -> void:
	loc_enemy += 1
	e.set_meta(&"loc", loc_enemy)
	if not Net.active:
		return
	enemy_seq += 1
	e.net_id = enemy_seq
	e.puppet = not Net.is_host
	get_tree().call_group("net_game", "register_enemy_node", e)


## Drowned Vaults: two pools to fish in, on free floor spots away from the
## entrance and the exit (same spots on every co-op machine).
func _spawn_fishing() -> void:
	if biome == null or biome.id != &"drowned_vaults":
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(floor_number, 4242))
	var candidates: Array[Vector2i] = []
	for y in range(1, layout.height - 1):
		for x in range(1, layout.width - 2):
			var c := Vector2i(x, y)
			if layout.get_tile(x, y) == LevelLayout.Tile.EMPTY and layout.get_tile(x + 1, y) == LevelLayout.Tile.EMPTY \
					and LevelLayout.is_solid(layout.get_tile(x, y + 1)) and LevelLayout.is_solid(layout.get_tile(x + 1, y + 1)) \
					and c.distance_to(layout.start_cell) > 8.0 and c.distance_to(layout.exit_cell) > 6.0 \
					and (layout.lore_cell.x < 0 or c.distance_to(layout.lore_cell) > 4.0):
				candidates.append(c)
	var placed: Array[Vector2i] = []
	for i in 40:
		if placed.size() >= 2 or candidates.is_empty():
			break
		var c: Vector2i = candidates[rng.randi_range(0, candidates.size() - 1)]
		if placed.any(func(p: Vector2i) -> bool: return p.distance_to(c) < 20.0):
			continue
		placed.append(c)
		var spot := FishingSpot.new()
		add_entity(spot, cell_bottom(c) + Vector2(TILE * 0.5, 0))


## The floor's note of the chronicle (ItemDatabase.lore_for_floor).
func _spawn_lore() -> void:
	if layout.lore_cell.x < 0:
		return
	var note := ItemDatabase.lore_for_floor(floor_number)
	if note == null:
		return
	var n := LoreNote.new()
	n.lore = note
	add_entity(n, cell_bottom(layout.lore_cell))


## Stairs back to town near the floor entrance (every normal floor).
func _spawn_return_stairs() -> void:
	if GameState.expedition:
		return  # an expedition goes home through a camp or after a guardian
	var cell := _free_cell_near(layout.start_cell)
	if cell.x < 0:
		return
	add_entity((load(STAIRS_SCENE) as PackedScene).instantiate(), cell_bottom(cell))


## Closest standing spot to `from`: empty cell on solid ground, a couple of
## tiles away so the hero does not spawn inside it. (-1, -1) when none.
func _free_cell_near(from: Vector2i) -> Vector2i:
	for off: Vector2i in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(3, 0), Vector2i(-3, 0),
			Vector2i(1, 0), Vector2i(-1, 0), Vector2i(2, -1), Vector2i(-2, -1)]:
		var c := from + off
		if layout.get_tile(c.x, c.y) == LevelLayout.Tile.EMPTY \
				and LevelLayout.is_solid(layout.get_tile(c.x, c.y + 1)):
			return c
	return Vector2i(-1, -1)


## Merchant and random-event rooms reserved by the generator.
func _spawn_specials() -> void:
	for info in layout.specials:
		match info["type"]:
			&"merchant":
				var m: Merchant = (load(MERCHANT_SCENE) as PackedScene).instantiate()
				m.floor_number = maxi(1, floor_number)  # the town shop sells first-floor goods
				if GameState.expedition and layout.is_town:
					m.floor_number = Buildings.shop_depth()  # the regions the town has opened
				_net_seq_node(m)
				add_entity(m, cell_bottom(info["cell"]))
			&"smith":
				add_entity((load(SMITH_SCENE) as PackedScene).instantiate(), cell_bottom(info["cell"]))
			&"quest":
				add_entity((load(QUEST_SCENE) as PackedScene).instantiate(), cell_bottom(info["cell"]))
			&"chronicler":
				add_entity(Chronicler.new(), cell_bottom(info["cell"]))
			&"event":
				_spawn_event(info)
			&"camp_fire":
				add_entity(CampFire.new(), cell_bottom(info["cell"]))
			&"elite_pack":
				_spawn_elite_pack(info)
			&"camp_spot":
				var cs := CampSpot.new()
				cs.kind = StringName(info["kind"])
				add_entity(cs, cell_bottom(info["cell"]))
			&"carriage", &"memorial", &"roof_cache", &"district_notice":
				var ts := TownSpot.new()
				ts.kind = StringName(info["type"])
				ts.district = StringName(info.get("district", &""))
				add_entity(ts, cell_bottom(info["cell"]))
			&"key_drop":
				# the key of a locked way down (personal: every machine its own)
				var key := ItemDatabase.get_item(&"key")
				if key:
					EventBus.spawn_items.emit.call_deferred(cell_bottom(info["cell"]) + Vector2(10, -8), [{"item": key, "count": 1}])
			&"dummy":
				# Training dummy at the barracks: local on every machine
				# (no net id), each player trains on their own copy.
				var dummy: Enemy = (load(ENEMY_SCENE) as PackedScene).instantiate()
				dummy.setup(load(AssetPaths.TRAINING_DUMMY) as EnemyData, maxi(1, floor_number))
				add_entity(dummy, cell_bottom(info["cell"]))
			&"road_event":
				var spot := EventSpot.new()
				spot.level = self
				for c in info["cells"]:
					spot.fight_cells.append(c)
				add_entity(spot, cell_bottom(info["cell"]))
			&"rescue":
				var cage := RescueCage.new()
				cage.level = self
				cage.npc_id = StringName(GameState.location.get("npc", &"refugee"))
				add_entity(cage, cell_bottom(info["cell"]))
				var cells: Array[Vector2i] = []
				for c in info["cells"]:
					cells.append(c)
				if cells.is_empty():
					cells.append(info["cell"])
				if Net.active and not Net.is_host:
					cage.remote = true  # the guards are the host's (they arrive as shells)
				else:
					cage.guard(spawn_ambush_wave(cells, 3 + floor_number / 8, true))
			&"miniboss":
				_spawn_miniboss(info)
			&"ambush":
				_spawn_ambush(info)


## The floor guardian: the toughest monster of the floor as a boosted elite
## in a room whose doors slam shut behind the hero.
func _spawn_miniboss(info: Dictionary) -> void:
	var pool := ItemDatabase.enemies_for_floor(floor_number, biome.id if biome else &"")
	if pool.is_empty():
		return
	var champ_data: EnemyData = pool[0]
	for e in pool:
		if e.max_hp > champ_data.max_hp:
			champ_data = e
	var elite: EliteAffixData = null
	var weights: Array[float] = []
	for e in ItemDatabase.elites:
		if e.min_floor <= floor_number:
			weights.append(e.weight)
	if not weights.is_empty():
		var pick := LootTable._weighted_index(weights, rng)
		var n := 0
		for e in ItemDatabase.elites:
			if e.min_floor <= floor_number:
				if n == pick:
					elite = e
					break
				n += 1
	if Net.active and not Net.is_host:
		# No champion shell of our own; run a network-driven gate copy so the
		# room seals and reopens together with the host.
		var guest_gate := MinibossGate.new()
		guest_gate.networked = true
		guest_gate.level = self
		guest_gate.champion = null
		guest_gate.room_cells = _shift_rect(info["room"])
		guest_gate.gate_id = _gate_seq
		_gate_seq += 1
		_add_late(guest_gate)
		return  # RNG already burned; the champion shell arrives via spawn_enemy
	var champion := (load(ENEMY_SCENE) as PackedScene).instantiate()
	champion.setup(champ_data, floor_number, elite, true)
	_net_tag(champion)
	champion.held = true  # waits in its room until the gate slams
	add_entity(champion, cell_bottom(info["cell"]))
	_net_broadcast_enemy(champion, elite, true, true)
	var gate := MinibossGate.new()
	gate.level = self
	gate.champion = champion
	gate.room_cells = _shift_rect(info["room"])
	gate.gate_id = _gate_seq
	_gate_seq += 1
	_add_late(gate)


## Gates of this floor in build order (the same on every machine): their ids.
var _gate_seq := 0


func _spawn_ambush(info: Dictionary) -> void:
	var gate := MinibossGate.new()
	gate.level = self
	gate.ambush = true
	gate.networked = Net.active and not Net.is_host
	gate.champion = null
	gate.room_cells = _shift_rect(info["room"])
	gate.gate_id = _gate_seq
	_gate_seq += 1
	for c in info["cells"]:
		gate.ambush_cells.append(c + _origin)
	_add_late(gate)


## Host: one wave of an ambush (the last one brings an elite).
func spawn_ambush_wave(cells: Array[Vector2i], count: int, with_elite: bool) -> Array[Enemy]:
	var out: Array[Enemy] = []
	if not cells.is_empty():
		var keep := _rules_at(cells[0])
		out = _ambush_wave(cells, count, with_elite)
		_restore_rules(keep)
	return out


func _ambush_wave(cells: Array[Vector2i], count: int, with_elite: bool) -> Array[Enemy]:
	var out: Array[Enemy] = []
	var pool := ItemDatabase.enemies_for_floor(floor_number, biome.id if biome else &"")
	if pool.is_empty() or cells.is_empty():
		return out
	for k in count:
		var data: EnemyData = pool[randi() % pool.size()]
		var elite: EliteAffixData = null
		if with_elite and k == 0:
			var ok := ItemDatabase.elites.filter(func(a: EliteAffixData) -> bool: return a.min_floor <= floor_number)
			if not ok.is_empty():
				elite = ok[randi() % ok.size()]
		var e := _spawn_floor_enemy(data, elite, cells[k % cells.size()], null)
		if e:
			e.global_position.x += (k / cells.size()) * 6.0
			out.append(e)
	return out


func _spawn_event(info: Dictionary) -> void:
	var pool: Array[RoomEventData] = []
	var weights: Array[float] = []
	for e in ItemDatabase.room_events:
		if e.min_floor <= floor_number and e.scene != "":
			pool.append(e)
			weights.append(e.weight)
	if pool.is_empty():
		return
	var pick_rng := RandomNumberGenerator.new()
	pick_rng.seed = info.get("roll", 0)
	var data: RoomEventData = pool[LootTable._weighted_index(weights, pick_rng)]
	var node: Node2D = (load(data.scene) as PackedScene).instantiate()
	if node.has_method("setup_event"):
		node.setup_event(self, info)
	if node is EventObject:
		_net_seq_node(node)
	add_entity(node, cell_bottom(info["cell"]))


func _spawn_chests() -> void:
	for info in layout.chests:
		var chest := (load(CHEST_SCENE) as PackedScene).instantiate()
		chest.tier = info["tier"]
		chest.mimic = info.get("mimic", false)
		chest.floor_number = floor_number
		_net_seq_node(chest)
		add_entity(chest, cell_bottom(info["cell"]))


# ------------------------------------------------------------ secrets
## cell -> wall index into layout.secret_walls.
var _secret_cells := {}
var _secret_lists: Array = []


func _spawn_secret_walls() -> void:
	if not location_mode:
		_secret_cells.clear()
		_secret_lists.clear()
	for i in layout.secret_walls.size():
		var wall: Array[Vector2i] = []
		for cell: Vector2i in layout.secret_walls[i]:
			wall.append(cell + _origin)
		var k := _secret_lists.size()
		_secret_lists.append(wall)
		for cell: Vector2i in layout.secret_walls[i]:
			_secret_cells[cell + _origin] = k
			var crack := SecretCrack.new()
			crack.level = self
			crack.cell = cell + _origin
			crack.first = cell == layout.secret_walls[i][0]
			add_entity(crack, cell_center(cell))


func is_secret_wall(cell: Vector2i) -> bool:
	return _secret_cells.has(cell) and layout.get_tile(cell.x, cell.y) == T.BRICK


## A hit on a cracked wall brings the whole passage down.
func break_secret(cell: Vector2i) -> void:
	if not _secret_cells.has(cell):
		return
	for c: Vector2i in _secret_lists[_secret_cells[cell]]:
		break_tile(c, true)


## A point of interest's leader: the strongest local monster as a champion
## with an elite affix (a better reward), and the treasure it guards.
func _spawn_elite_pack(info: Dictionary) -> void:
	var pool := ItemDatabase.enemies_for_floor(floor_number, biome.id if biome else &"")
	pool = pool.filter(func(e: EnemyData) -> bool: return not e.neutral)
	if pool.is_empty():
		return
	pool.sort_custom(func(a: EnemyData, b: EnemyData) -> bool: return a.max_hp > b.max_hp)
	var data: EnemyData = pool[rng.randi_range(0, mini(1, pool.size() - 1))]
	var ok := ItemDatabase.elites.filter(func(a: EliteAffixData) -> bool: return a.min_floor <= floor_number)
	var elite: EliteAffixData = ok[rng.randi_range(0, ok.size() - 1)] if not ok.is_empty() else null
	if Net.active and not Net.is_host:
		return  # rolls burnt; the champion arrives as the host's shell
	var e := (load(ENEMY_SCENE) as PackedScene).instantiate() as Enemy
	e.setup(data, floor_number, elite, true)
	_net_tag(e)
	add_entity(e, cell_bottom(info["cell"]))
	_net_broadcast_enemy(e, elite, true)


## Host: a monster comes back at a world position (surface respawns).
func spawn_enemy_at(data: EnemyData, pos: Vector2) -> Enemy:
	if data == null:
		return null
	var keep := _rules_at(world_to_cell(pos + Vector2(0, -2)))
	var e := (load(ENEMY_SCENE) as PackedScene).instantiate() as Enemy
	e.setup(data, floor_number)
	_restore_rules(keep)
	_net_tag(e)
	add_entity(e, pos)
	_net_broadcast_enemy(e, null, false)
	return e


## A mimic jumps out of a chest (host / single player; guests get it as an
## enemy descriptor like any other monster).
func spawn_mimic(pos: Vector2) -> void:
	var data := ItemDatabase.enemy_by_id(&"mimic")
	if data == null:
		return
	var e: Enemy = (load(ENEMY_SCENE) as PackedScene).instantiate()
	var keep := _rules_at(world_to_cell(pos))
	e.setup(data, floor_number)
	_restore_rules(keep)
	_net_tag(e)
	add_entity(e, pos)
	_net_broadcast_enemy(e, null, false)
	e.hear(pos)


## Decoration only: wall torches (one per room at most) and ceiling drips.
func _spawn_ambience() -> void:
	var rw := LevelGenerator.ROOM_W
	var rh := LevelGenerator.ROOM_H
	for ry in range(layout.height / rh):
		for rx in range(layout.width / rw):
			if rng.randf() < 0.75:
				var x := rx * rw + rng.randi_range(3, rw - 4)
				var y := (ry + 1) * rh - 4
				if layout.get_tile(x, y) == T.EMPTY and layout.get_tile(x, y + 1) == T.EMPTY:
					var torch: WallTorch = (load(TORCH_SCENE) as PackedScene).instantiate()
					if biome:
						torch.light_color = biome.torch_color
					add_entity(torch, cell_bottom(Vector2i(x, y)))
			if rng.randf() < 0.6:
				var x := rx * rw + rng.randi_range(2, rw - 3)
				var y := ry * rh + 1
				if layout.get_tile(x, y) == T.EMPTY and LevelLayout.is_solid(layout.get_tile(x, y - 1)):
					var drip: WaterDrip = (load(DRIP_SCENE) as PackedScene).instantiate()
					drip.level = self
					add_entity(drip, cell_center(Vector2i(x, y)) + Vector2(0, -6))


## Bones, cobwebs, crystals, statues... from BiomeData.decorations.
func _spawn_decorations() -> void:
	if biome == null or biome.decorations.is_empty():
		return
	var weights: Array[float] = []
	for d in biome.decorations:
		weights.append(d.weight)
	var rooms := (layout.width / LevelGenerator.ROOM_W) * (layout.height / LevelGenerator.ROOM_H)
	var count := roundi(rooms * biome.decor_per_room)
	var used := {}
	var tries := 0
	while count > 0 and tries < count * 20:
		tries += 1
		var data: DecorData = biome.decorations[LootTable._weighted_index(weights, rng)]
		var cell := Vector2i(rng.randi_range(1, layout.width - 2), rng.randi_range(1, layout.height - 2))
		if used.has(cell) or layout.get_tile(cell.x, cell.y) != T.EMPTY or cell == layout.exit_cell:
			continue
		var tall := data.texture.get_height() > TILE
		var wide := data.texture.get_width() > TILE
		var cell2 := cell + Vector2i.RIGHT
		if wide and (used.has(cell2) or layout.get_tile(cell2.x, cell2.y) != T.EMPTY or cell2 == layout.exit_cell):
			continue
		var pos: Vector2
		match data.placement:
			DecorData.Placement.FLOOR:
				if layout.get_tile(cell.x, cell.y + 1) != T.BRICK or (tall and layout.get_tile(cell.x, cell.y - 1) != T.EMPTY):
					continue
				if wide and (layout.get_tile(cell2.x, cell2.y + 1) != T.BRICK
						or (tall and layout.get_tile(cell2.x, cell2.y - 1) != T.EMPTY)):
					continue
				pos = cell_bottom(cell)
			DecorData.Placement.CEILING:
				if not LevelLayout.is_solid(layout.get_tile(cell.x, cell.y - 1)):
					continue
				pos = cell_center(cell) - Vector2(0, TILE / 2.0)
			DecorData.Placement.WALL:
				# On the back wall, 2-3 cells above a floor (eye level), not on gaps.
				if back.get_cell_source_id(cell) < 0 or layout.get_tile(cell.x, cell.y + 1) != T.EMPTY:
					continue
				if not (layout.get_tile(cell.x, cell.y + 2) == T.BRICK or layout.get_tile(cell.x, cell.y + 3) == T.BRICK):
					continue
				if wide and back.get_cell_source_id(cell2) < 0:
					continue
				pos = cell_center(cell)
		if wide:
			pos.x += TILE / 2.0
			used[cell2] = true
		used[cell] = true
		var deco := Decoration.new()
		deco.data = data
		if data.placement == DecorData.Placement.WALL and biome:
			deco.wall_tint = biome.back_wall_modulate.lerp(Color.WHITE, 0.45)
		add_entity(deco, pos)
		count -= 1


## Traps from ItemDatabase.traps_for_floor(): more on deeper floors.
func _spawn_traps() -> void:
	var pool := ItemDatabase.traps_for_floor(floor_number, biome.id if biome else &"")
	if pool.is_empty():
		return
	var weights: Array[float] = []
	for t in pool:
		weights.append(t.weight)
	var rooms := (layout.width / LevelGenerator.ROOM_W) * (layout.height / LevelGenerator.ROOM_H)
	var count := mini(2 + floor_number, rooms + 2)
	var used := {}
	for c in layout.chests:
		used[c["cell"]] = true
	used[layout.exit_cell] = true
	# No trap right under a monster's spawn point (and its first steps).
	for c in layout.enemy_cells:
		for dx in range(-1, 2):
			used[c + Vector2i(dx, 0)] = true
	for info in layout.specials:
		for dx in range(-3, 4):
			used[info["cell"] + Vector2i(dx, 0)] = true
	var walls: Array[Trap] = []
	var plates: Array[Trap] = []
	var tries := 0
	while count > 0 and tries < 400:
		tries += 1
		var data: TrapData = pool[LootTable._weighted_index(weights, rng)]
		var placed := _place_trap(data, used)
		if placed:
			count -= 1
			if data.kind == TrapData.Kind.ARROW_WALL:
				walls.append(placed)
			elif data.kind == TrapData.Kind.PRESSURE_PLATE:
				plates.append(placed)
	# Plates fire the nearest arrow wall in their row.
	for plate in plates:
		for w in walls:
			if absf(w.global_position.y - plate.global_position.y) < 2.0 and absf(w.global_position.x - plate.global_position.x) < TILE * 12:
				plate.linked = w


func _place_trap(data: TrapData, used: Dictionary) -> Trap:
	var cell := Vector2i(rng.randi_range(2, layout.width - 3), rng.randi_range(2, layout.height - 3))
	if used.has(cell) or layout.get_tile(cell.x, cell.y) != T.EMPTY:
		return null
	if Vector2(cell).distance_to(Vector2(layout.start_cell)) < SAFE_START_RADIUS:
		return null
	var below := layout.get_tile(cell.x, cell.y + 1)
	var trap: Trap = (load(TRAP_SCENE) as PackedScene).instantiate()
	trap.setup(data, floor_number)
	var pos: Vector2
	match data.kind:
		TrapData.Kind.SPIKES, TrapData.Kind.PRESSURE_PLATE, TrapData.Kind.ACID_POOL:
			if below != T.BRICK or LevelLayout.is_ladder(layout.get_tile(cell.x, cell.y - 1)):
				trap.free()
				return null
			pos = cell_bottom(cell)
		TrapData.Kind.FALLING_ROCK:
			if not LevelLayout.is_solid(layout.get_tile(cell.x, cell.y - 1)):
				trap.free()
				return null
			# Something to fall on within a few cells.
			var floor_found := false
			for dy in range(1, 7):
				if LevelLayout.is_ground(layout.get_tile(cell.x, cell.y + dy)):
					floor_found = true
					break
			if not floor_found:
				trap.free()
				return null
			pos = cell_bottom(cell) - Vector2(0, TILE)
		TrapData.Kind.ARROW_WALL:
			# Mounted in front of a wall, on the floor level of a corridor.
			if below != T.BRICK:
				trap.free()
				return null
			var left_wall := LevelLayout.is_solid(layout.get_tile(cell.x - 1, cell.y))
			var right_wall := LevelLayout.is_solid(layout.get_tile(cell.x + 1, cell.y))
			if left_wall == right_wall:
				trap.free()
				return null
			trap.facing = 1.0 if left_wall else -1.0
			pos = cell_bottom(cell)
	used[cell] = true
	_net_seq_node(trap)
	add_entity(trap, pos)
	_mark_trap_danger(data, cell, trap.facing)
	return trap


## Tells the monster navigation where this trap hurts.
func _mark_trap_danger(data: TrapData, cell: Vector2i, facing: float) -> void:
	if _origin != Vector2i.ZERO:
		# nav covers the whole level: band cells shift to it.
		var keep := layout
		layout = _composite
		_mark_trap_danger_at(data, cell + _origin, facing)
		layout = keep
		return
	_mark_trap_danger_at(data, cell, facing)


func _mark_trap_danger_at(data: TrapData, cell: Vector2i, facing: float) -> void:
	match data.kind:
		TrapData.Kind.SPIKES, TrapData.Kind.ACID_POOL, TrapData.Kind.PRESSURE_PLATE:
			nav.set_danger(cell, LevelNav.Danger.FORBIDDEN, 50.0)
		TrapData.Kind.ARROW_WALL:
			var x := cell.x
			for i in 10:
				x += int(facing)
				if LevelLayout.is_solid(layout.get_tile(x, cell.y)):
					break
				nav.set_danger(Vector2i(x, cell.y), LevelNav.Danger.COSTLY, 6.0)
		TrapData.Kind.FALLING_ROCK:
			for dy in range(1, 8):
				var c := Vector2i(cell.x, cell.y + dy)
				nav.set_danger(c, LevelNav.Danger.COSTLY, 10.0)
				if LevelLayout.is_ground(layout.get_tile(c.x, c.y + 1)):
					break


func _spawn_enemies() -> void:
	var pool := ItemDatabase.enemies_for_floor(floor_number, biome.id if biome else &"")
	if pool.is_empty():
		return
	var weights: Array[float] = []
	for e in pool:
		weights.append(e.spawn_weight)
	# Elites: 6% on floor 1, +2.5% per floor, at most 35%.
	# Difficulty scales the chance (at most 60%).
	var elite_chance := minf(minf(0.06 + 0.025 * (floor_number - 1), 0.35) * GameState.elite_chance_mult(), 0.6)
	var elite_pool: Array[EliteAffixData] = []
	var elite_weights: Array[float] = []
	for e in ItemDatabase.elites:
		if e.min_floor <= floor_number:
			elite_pool.append(e)
			elite_weights.append(e.weight)
	# Squads: from floor 2 some monsters lead a group with a support role
	# (healer, shieldbearer, bannerman) and bring 1-2 companions.
	var squad_chance := 0.0 if floor_number < 2 else minf(0.1 + 0.025 * (floor_number - 2), 0.3)
	var roles: Array[SquadRoleData] = []
	var role_weights: Array[float] = []
	for r in ItemDatabase.squad_roles:
		if r.min_floor <= floor_number:
			roles.append(r)
			role_weights.append(r.weight)
	var taken := {}
	for cell in layout.enemy_cells:
		taken[cell] = true
	for cell in layout.enemy_cells:
		var data: EnemyData = pool[LootTable._weighted_index(weights, rng)]
		var elite: EliteAffixData = null
		if not elite_pool.is_empty() and rng.randf() < elite_chance:
			elite = elite_pool[LootTable._weighted_index(elite_weights, rng)]
		# Every roll happens before the client early-out: RNG stays in sync.
		var role: SquadRoleData = null
		var mates: Array = []  # [EnemyData, cell]
		if not roles.is_empty() and rng.randf() < squad_chance:
			role = roles[LootTable._weighted_index(role_weights, rng)]
			var count := rng.randi_range(1, 2)
			for k in count:
				var mate_data: EnemyData = pool[LootTable._weighted_index(weights, rng)]
				var mate_cell := _squad_cell(cell, k, taken)
				if mate_cell != Vector2i(-1, -1):
					taken[mate_cell] = true
					mates.append([mate_data, mate_cell])
		if Net.active and not Net.is_host:
			continue  # shells arrive as host descriptors
		if data.neutral:
			elite = null  # a deer is a deer (rolls above kept the RNG in step)
			role = null
			mates.clear()
		_spawn_floor_enemy(data, elite, cell, role)
		for m in mates:
			_spawn_floor_enemy(m[0], null, m[1], null)


func _spawn_floor_enemy(data: EnemyData, elite: EliteAffixData, cell: Vector2i, role: SquadRoleData) -> Enemy:
	var enemy := (load(ENEMY_SCENE) as PackedScene).instantiate()
	enemy.setup(data, floor_number, elite)
	if role:
		enemy.assign_role(role)
	_net_tag(enemy)
	var pos := cell_bottom(cell)
	if data.behavior == EnemyData.Behavior.FLYER:
		pos.y -= TILE * 2
	add_entity(enemy, pos)
	_net_broadcast_enemy(enemy, elite, false)
	return enemy


## A free standable cell next to a squad leader for companion `k` (1-3 cells
## to either side on the same floor), or (-1, -1).
func _squad_cell(cell: Vector2i, k: int, taken: Dictionary) -> Vector2i:
	for off in ([1, -1, 2, -2, 3, -3] if k % 2 == 0 else [-1, 1, -2, 2, -3, 3]):
		var c := cell + Vector2i(off, 0)
		if taken.has(c):
			continue
		if layout.get_tile(c.x, c.y) != T.EMPTY or not LevelLayout.is_ground(layout.get_tile(c.x, c.y + 1)):
			continue
		if c.distance_to(layout.start_cell) < SAFE_START_RADIUS:
			continue
		return c
	return Vector2i(-1, -1)


## Host → clients: a live enemy descriptor for the client shells.
func _net_broadcast_enemy(e: Enemy, elite: EliteAffixData, champion: bool, held := false) -> void:
	if not Net.active or not Net.is_host:
		return
	var ns := get_tree().get_first_node_in_group("net_game") as NetSync
	if ns:
		Net.send(ns, &"spawn_enemy", [e.net_id, String(e.data.id), e.global_position,
				elite.id if elite else StringName(), champion, held, e.hp, e.role.id if e.role else StringName()])


## Cracks over a secret wall cell: a jagged dark crack, a faint draft of light
## and dust trickling out now and then. Gone when the brick is.
class SecretCrack extends Node2D:
	var level: DungeonLevel
	var cell: Vector2i
	var first := false
	var _t := 0.0
	var _dust := 0.0

	func _ready() -> void:
		z_index = 1
		_dust = randf_range(1.0, 4.0)

	func _process(delta: float) -> void:
		_t += delta
		if level == null or level.layout.get_tile(cell.x, cell.y) != LevelLayout.Tile.BRICK:
			if first and level != null:
				EventBus.message.emit(tr("Открыт тайный проход!"))
				AudioManager.play_sfx(&"chest_open", global_position)
			queue_free()
			return
		_dust -= delta
		if _dust <= 0.0:
			_dust = randf_range(2.5, 5.0)
			Fx.sparks(get_parent(), global_position + Vector2(randf_range(-4, 4), 6), Color(0.7, 0.62, 0.5), 3, 25.0)
		queue_redraw()

	func _draw() -> void:
		var c := Color(0.08, 0.05, 0.05, 0.9)
		var pts := PackedVector2Array([Vector2(-1, -8), Vector2(1, -4), Vector2(-2, -1), Vector2(2, 2), Vector2(0, 5), Vector2(1, 8)])
		draw_polyline(pts, c, 1.0)
		draw_line(Vector2(-2, -1), Vector2(-6, 1), c, 1.0)
		draw_line(Vector2(2, 2), Vector2(6, 0), c, 1.0)
		draw_line(Vector2(1, -4), Vector2(4, -7), c, 1.0)
		# a draft of light seeping through the crack
		var a := 0.25 + 0.15 * sin(_t * 2.0)
		draw_line(Vector2(0, -3), Vector2(1, 3), Color(1.0, 0.9, 0.6, a), 1.0)
