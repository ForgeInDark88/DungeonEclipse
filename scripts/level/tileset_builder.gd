class_name TilesetBuilder
extends RefCounted
## Builds the dungeon TileSet in code from the atlas in AssetPaths.TILES.
## Physics layer 0 = solid walls (collision layer "world"),
## physics layer 1 = one-way platforms (collision layer "platforms").

const SOURCE_ID := 0
const LADDER_TOP_ALT := 1
const TILE := 16

static var _cache: TileSet


static func get_tileset() -> TileSet:
	if _cache == null:
		_cache = _build()
	return _cache


static func _build() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)
	ts.set_physics_layer_collision_mask(0, 0)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(1, 2)
	ts.set_physics_layer_collision_mask(1, 0)

	var src := TileSetAtlasSource.new()
	src.texture = AssetPaths.tex(AssetPaths.TILES)
	src.texture_region_size = Vector2i(TILE, TILE)
	ts.add_source(src, SOURCE_ID)
	for coords in [AssetPaths.TILE_BEDROCK, AssetPaths.TILE_BRICK, AssetPaths.TILE_PLATFORM,
			AssetPaths.TILE_LADDER, AssetPaths.TILE_BACKWALL]:
		src.create_tile(coords)
	src.create_alternative_tile(AssetPaths.TILE_LADDER, LADDER_TOP_ALT)

	var h := TILE / 2.0
	var full := PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)])
	var thin := PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, -h + 4), Vector2(-h, -h + 4)])
	for coords in [AssetPaths.TILE_BEDROCK, AssetPaths.TILE_BRICK]:
		var td := src.get_tile_data(coords, 0)
		td.add_collision_polygon(0)
		td.set_collision_polygon_points(0, 0, full)
	for td in [src.get_tile_data(AssetPaths.TILE_PLATFORM, 0), src.get_tile_data(AssetPaths.TILE_LADDER, LADDER_TOP_ALT)]:
		td.add_collision_polygon(1)
		td.set_collision_polygon_points(1, 0, thin)
		td.set_collision_polygon_one_way(1, 0, true)
	return ts


## Atlas coords + alternative id for a LevelLayout tile; coords (-1,-1) = empty.
static func tile_for(kind: int) -> Array:
	match kind:
		LevelLayout.Tile.BEDROCK:
			return [AssetPaths.TILE_BEDROCK, 0]
		LevelLayout.Tile.BRICK:
			return [AssetPaths.TILE_BRICK, 0]
		LevelLayout.Tile.PLATFORM:
			return [AssetPaths.TILE_PLATFORM, 0]
		LevelLayout.Tile.LADDER:
			return [AssetPaths.TILE_LADDER, 0]
		LevelLayout.Tile.LADDER_TOP:
			return [AssetPaths.TILE_LADDER, LADDER_TOP_ALT]
	return [Vector2i(-1, -1), 0]
