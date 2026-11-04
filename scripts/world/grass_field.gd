class_name GrassField
extends Node2D
## Grass in front of the heroes along the ground of the surface: blades
## bend in the wind and lean away from a hero walking through them. Only
## the blades in view are drawn, every frame (a couple of hundred lines).
## The colour and density come from the biome (SurfaceBiomeData.grass_color,
## grass_density). Pure decoration.

const PER_CELL := 3
var level: DungeonLevel
var active := true
var color := Color(0.45, 0.72, 0.3)
var _blades: Dictionary = {}  # column -> Array of [x, y, height, tone]
var _heroes: Array = []


func setup(p_level: DungeonLevel, band: int, p_color: Color, density: float, seed_value: int) -> void:
	level = p_level
	color = p_color
	top_level = true
	global_position = Vector2.ZERO
	z_index = 3  # in front of the heroes (and their feet)
	var b := level.layout_band(band)
	if b.is_empty():
		return
	var sub: LevelLayout = b["layout"]
	var origin: Vector2i = b["origin"]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var water := {}
	for r: Rect2i in sub.water:
		for x in range(r.position.x - 1, r.end.x + 1):
			water[x] = true
	for x in sub.width:
		if water.has(x):
			continue
		for y in range(1, sub.height):
			var t := sub.get_tile(x, y)
			if LevelLayout.is_solid(t):
				if t != LevelLayout.Tile.BRICK or sub.get_tile(x, y - 1) != LevelLayout.Tile.EMPTY:
					break
				var base := level.cell_bottom(Vector2i(x, y - 1) + origin)
				var list: Array = []
				for k in PER_CELL:
					if rng.randf() < density:
						list.append([base.x - DungeonLevel.TILE / 2.0 + (k + rng.randf()) * DungeonLevel.TILE / PER_CELL,
								base.y + 1.0, rng.randf_range(2.0, 6.0), rng.randf_range(0.8, 1.2)])
				_blades[x + origin.x] = list
				break


func _process(_delta: float) -> void:
	visible = active
	if active:
		_heroes = get_tree().get_nodes_in_group("player")
		queue_redraw()


func _draw() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var half := get_viewport_rect().size / cam.zoom / 2.0
	var c := cam.get_screen_center_position()
	var c0 := int(floor((c.x - half.x) / DungeonLevel.TILE)) - 1
	var c1 := int(ceil((c.x + half.x) / DungeonLevel.TILE)) + 1
	var t := Time.get_ticks_msec() / 1000.0
	var dark := color.darkened(0.3)
	var light := color.lightened(0.25)
	for col in range(c0, c1 + 1):
		if not _blades.has(col):
			continue
		for bl in _blades[col]:
			var x: float = bl[0]
			var y: float = bl[1]
			var hgt: float = bl[2]
			if absf(y - c.y) > half.y + 20.0:
				continue
			var bend := sin(t * 1.4 + x * 0.09) * 0.8 + sin(t * 3.1 + x * 0.31) * 0.3
			for h in _heroes:
				var p := h as Node2D
				if p == null or not is_instance_valid(p):
					continue
				var dx := x - p.global_position.x
				if absf(dx) < 10.0 and absf(p.global_position.y - y) < 14.0:
					bend += signf(dx) * (10.0 - absf(dx)) * 0.45  # pushed aside
			var tip := Vector2(x + bend, y - hgt)
			var mid := Vector2(x + bend * 0.4, y - hgt * 0.5)
			draw_line(Vector2(x, y), mid, dark * Color(bl[3], bl[3], bl[3]), 1.0)
			draw_line(mid, tip, light * Color(bl[3], bl[3], bl[3]), 1.0)
