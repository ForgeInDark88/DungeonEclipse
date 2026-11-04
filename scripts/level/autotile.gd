class_name Autotile
extends RefCounted
## 47-variant ("blob") wall tiles (tools/art/gen_autotiles.py draws them).
## A wall cell's look comes from its 8 neighbours: which of them are solid.
## Bits: N=1 NE=2 E=4 SE=8 S=16 SW=32 W=64 NW=128; a diagonal counts only
## when both its sides are solid. The 47 reduced masks, sorted ascending,
## are the tile order of tiles_<biome>_blob.png (8 columns, 6 rows per
## variant, variant 1 below variant 0).

const N := 1
const NE := 2
const E := 4
const SE := 8
const S := 16
const SW := 32
const W := 64
const NW := 128
const ALL := 255
const COLUMNS := 8
const ROWS_PER_VARIANT := 6
const VARIANTS := 2

static var _index: PackedInt32Array  # raw mask (0..255) -> tile index (0..46)


static func reduce(m: int) -> int:
	if not (m & N and m & E):
		m &= ~NE
	if not (m & S and m & E):
		m &= ~SE
	if not (m & S and m & W):
		m &= ~SW
	if not (m & N and m & W):
		m &= ~NW
	return m


static func index_of(mask: int) -> int:
	if _index.is_empty():
		var reduced := {}
		for m in 256:
			reduced[reduce(m)] = true
		var order: Array = reduced.keys()
		order.sort()
		_index.resize(256)
		for m in 256:
			_index[m] = order.find(reduce(m))
	return _index[mask & ALL]


## Atlas coordinates of the tile for `mask` in brick variant `variant`.
static func coords(mask: int, variant: int) -> Vector2i:
	var i := index_of(mask)
	return Vector2i(i % COLUMNS, (variant % VARIANTS) * ROWS_PER_VARIANT + i / COLUMNS)


## The mask of `cell`: solid(x, y) says whether a neighbour is wall.
static func mask_at(cell: Vector2i, solid: Callable) -> int:
	var m := 0
	if solid.call(cell.x, cell.y - 1):
		m |= N
	if solid.call(cell.x + 1, cell.y - 1):
		m |= NE
	if solid.call(cell.x + 1, cell.y):
		m |= E
	if solid.call(cell.x + 1, cell.y + 1):
		m |= SE
	if solid.call(cell.x, cell.y + 1):
		m |= S
	if solid.call(cell.x - 1, cell.y + 1):
		m |= SW
	if solid.call(cell.x - 1, cell.y):
		m |= W
	if solid.call(cell.x - 1, cell.y - 1):
		m |= NW
	return m
