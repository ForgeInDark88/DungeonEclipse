class_name TilesetBuilder
extends RefCounted
## Builds a TileSet from a biome atlas (layout: AssetPaths.TILE_* constants).
## Physics layer 0 = solid walls (collision layer "world"),
## physics layer 1 = one-way platforms (collision layer "platforms").

const SOURCE_ID := 0
const LADDER_TOP_ALT := 1
const TILE := 16
const COLUMNS := 4

static var _cache: Dictionary = {}  # texture path -> TileSet


static func get_tileset(texture: Texture2D = null) -> TileSet:
	if texture == null:
		texture = AssetPaths.tex(AssetPaths.TILES)
	var key := texture.resource_path
	if not _cache.has(key):
		_cache[key] = _build(texture)
	return _cache[key]


static func clear_cache() -> void:
	_cache.clear()


static func _build(texture: Texture2D) -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)
	ts.set_physics_layer_collision_mask(0, 0)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(1, 2)
	ts.set_physics_layer_collision_mask(1, 0)

	var src := TileSetAtlasSource.new()
	src.texture = texture
	src.texture_region_size = Vector2i(TILE, TILE)
	ts.add_source(src, SOURCE_ID)
	var rows := int(texture.get_height()) / TILE
	for y in rows:
		for x in COLUMNS:
			src.create_tile(Vector2i(x, y))
	src.create_alternative_tile(AssetPaths.TILE_LADDER, LADDER_TOP_ALT)

	var h := TILE / 2.0
	var full := PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)])
	var thin := PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, -h + 4), Vector2(-h, -h + 4)])
	for y in [AssetPaths.TILE_ROW_BEDROCK, AssetPaths.TILE_ROW_BRICK, AssetPaths.TILE_ROW_BRICK_TOP, AssetPaths.TILE_ROW_BRICK_BOTTOM]:
		for x in COLUMNS:
			var td := src.get_tile_data(Vector2i(x, y), 0)
			td.add_collision_polygon(0)
			td.set_collision_polygon_points(0, 0, full)
	var one_way: Array[TileData] = [src.get_tile_data(AssetPaths.TILE_LADDER, LADDER_TOP_ALT)]
	for c in [AssetPaths.TILE_PLATFORM_LEFT, AssetPaths.TILE_PLATFORM_MID, AssetPaths.TILE_PLATFORM_RIGHT]:
		one_way.append(src.get_tile_data(c, 0))
	for td in one_way:
		td.add_collision_polygon(1)
		td.set_collision_polygon_points(1, 0, thin)
		td.set_collision_polygon_one_way(1, 0, true)
	return ts
