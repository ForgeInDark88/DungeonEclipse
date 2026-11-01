class_name LocationBuilder
extends RefCounted
## Turns a LocationInstance into one level: every layer is generated on its
## own (SurfaceGenerator for the surface, LevelGenerator for the floors and
## the arena) and the layers are stacked top to bottom into one LevelLayout,
## GAP rows of bedrock between them. Each layer keeps its own layout, depth
## and biome in `layout.bands`; DungeonLevel.build_location spawns each band
## with its own rules. One level holds the whole location, so the party may
## stand in different layers at once and the host simulates them all (the
## layers without anybody in them sleep, LocationManager).
##
## Deterministic: the same instance always gives the same tiles and cells.

const T = LevelLayout.Tile
## Rows between two layers: no sight, no sound, no path across.
const GAP := 40
## The surface's biome until regions name their own (stage 15).
const SURFACE_BIOME := "res://data/town/town.tres"


static func build(li: LocationInstance) -> LevelLayout:
	var subs: Array = []
	for i in li.layers.size():
		subs.append(_layer_layout(li, i))
	var w := 0
	var h := 0
	for s: LevelLayout in subs:
		w = maxi(w, s.width)
		h += s.height + GAP
	h -= GAP
	# The space between the layers stays empty: no tiles, no collision
	# shapes, no graph nodes (each layer is closed by its own bedrock rim
	# and the camera never leaves its layer).
	var out := LevelLayout.new(w, h, T.EMPTY)
	var y0 := 0
	for i in subs.size():
		var s: LevelLayout = subs[i]
		var origin := Vector2i(0, y0)
		for y in s.height:
			for x in s.width:
				out.set_tile(x, y + y0, s.get_tile(x, y))
		var layer: Dictionary = li.layers[i]
		out.bands.append({"layer": i, "rect": Rect2i(origin, Vector2i(s.width, s.height)), "origin": origin,
				"layout": s, "depth": int(layer["depth"]), "kind": int(layer["kind"]),
				"biome": layer_biome(li, i), "id": StringName(layer["id"])})
		for pid in s.portal_cells:
			out.portal_cells[pid] = (s.portal_cells[pid] as Vector2i) + origin
		for pid in s.portal_kinds:
			out.portal_kinds[pid] = s.portal_kinds[pid]
		y0 += s.height + GAP
	var first: Dictionary = out.bands[0]
	out.start_cell = (first["layout"] as LevelLayout).start_cell + (first["origin"] as Vector2i)
	out.exit_cell = Vector2i(-1, -1)
	return out


static func layer_biome(li: LocationInstance, i: int) -> BiomeData:
	if int(li.layers[i]["kind"]) == LocationInstance.Kind.SURFACE:
		var sb: BiomeData = ItemDatabase.surface_biomes.get(StringName(li.layers[i].get("biome", &"")))
		return sb if sb else load(SURFACE_BIOME) as BiomeData
	var b := ItemDatabase.biome_by_id(li.biome)
	return b if b else ItemDatabase.biome_for_floor(int(li.layers[i]["depth"]))


static func _layer_layout(li: LocationInstance, i: int) -> LevelLayout:
	var layer: Dictionary = li.layers[i]
	var depth := int(layer["depth"])
	var seed_value := int(layer["seed"])
	var kind := int(layer["kind"])
	var ports := li.portals_of(i)
	if kind == LocationInstance.Kind.SURFACE:
		var sides := ports.filter(func(p: Dictionary) -> bool: return StringName(p["kind"]) == LocationInstance.SIDE).size()
		var sbd := layer_biome(li, i) as SurfaceBiomeData
		var sg := SurfaceGenerator.new()
		sg.node_type = li.node_type
		return sg.generate(depth, seed_value, sides, int(layer.get("screens", -1)), sbd)
	var gen := LevelGenerator.new()
	# The floor's place in the dungeon: the prisoner waits on the last one.
	# (a rescue node with a surface keeps its prisoner in the bandits' camp)
	GameState.location["band_last"] = bool(layer.get("last", false)) and not (li.node_type == &"rescue" and li.has_surface())
	var s: LevelLayout
	if kind == LocationInstance.Kind.ARENA:
		s = gen.generate_arena(depth, seed_value)
	else:
		s = gen.generate(depth, seed_value)
	GameState.location.erase("band_last")
	var has_down := false
	for p in ports:
		var pid := StringName(p["id"])
		match StringName(p["kind"]):
			LocationInstance.UP, LocationInstance.MAP:
				if pid.contains("_side_"):
					s.portal_cells[pid] = _far_spot(s, seed_value + pid.hash())
				else:
					s.portal_cells[pid] = s.start_cell
			LocationInstance.DOWN:
				s.portal_cells[pid] = s.exit_cell
				has_down = true
			LocationInstance.ARENA_EXIT:
				s.portal_cells[pid] = s.exit_cell
	if kind == LocationInstance.Kind.DUNGEON and not has_down and s.exit_cell.x >= 0:
		# The bottom of a dungeon without a guardian: its treasure.
		s.chests.append({"cell": s.exit_cell, "tier": 2})
	return s


## A standing cell far from the start and the exit (a side way in).
static func _far_spot(s: LevelLayout, seed_value: int) -> Vector2i:
	var cands: Array[Vector2i] = []
	for y in range(1, s.height - 1):
		for x in range(1, s.width - 1):
			if s.get_tile(x, y) == T.EMPTY and s.get_tile(x, y - 1) == T.EMPTY \
					and LevelLayout.is_solid(s.get_tile(x, y + 1)):
				var c := Vector2i(x, y)
				if c.distance_to(s.start_cell) > 20.0 and c.distance_to(s.exit_cell) > 8.0 \
						and not s.chests.any(func(ch: Dictionary) -> bool: return ch["cell"] == c) \
						and not c in s.enemy_cells:
					cands.append(c)
	if cands.is_empty():
		return s.start_cell
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# Only where the hero can walk from the start (not behind a secret wall).
	var nav := LevelNav.new(s)
	for attempt in 40:
		var c: Vector2i = cands[rng.randi_range(0, cands.size() - 1)]
		if not nav.ground_path(s.start_cell, c, 2).is_empty():
			return c
	return s.start_cell
