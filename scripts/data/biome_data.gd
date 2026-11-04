class_name BiomeData
extends Resource
## A dungeon biome: tileset, parallax, palette, lighting, post effects and
## decorations. Biomes change every GameState.FLOORS_PER_BIOME floors in
## `order`; add a .tres to data/biomes/ to add one.
## Tileset atlas layout: see docs/ANIMATION_GUIDE.md ("Биомы").

@export var id: StringName
@export var display_name: String = ""
@export var order: int = 0
@export var tileset_texture: Texture2D

@export_group("Parallax (far → near)")
## Paths, not textures: a background loads when its biome is entered
## (parallax_textures), not with the data base at start (docs/PERFORMANCE.md).
@export_file("*.png") var parallax_far: String = ""
@export_file("*.png") var parallax_mid: String = ""
@export_file("*.png") var parallax_near: String = ""

@export_group("Light and color")
## Soft general light of the biome (CanvasModulate of the world). Bright on
## purpose: monsters, traps and items must always be readable.
@export var ambient: Color = Color(1.0, 0.98, 0.95)
## Background (back wall, parallax) is a bit darker: depth, not darkness.
@export var back_wall_modulate: Color = Color(0.85, 0.8, 0.84)
## Warm glow of the decorative wall torches (they do not change visibility).
@export var torch_color: Color = Color(1.0, 0.62, 0.3)
@export var ambient_particles: Color = Color(0.8, 0.75, 0.7)
## How the ambient particles move: dust (drifts down), spores (float, glow),
## pollen (wind), embers (rise, glow), sparkles (twinkle, glow).
@export var particle_style: StringName = &"dust"
## Share of floor / ceiling / back wall cells with small detail tiles.
@export_range(0.0, 1.0) var floor_fringe: float = 0.45
@export_range(0.0, 1.0) var ceiling_fringe: float = 0.3
@export_range(0.0, 1.0) var wall_details: float = 0.03
@export var fog_color: Color = Color(0.5, 0.5, 0.6)
@export_range(0.0, 1.0) var fog_amount: float = 0.08
@export var grade_tint: Color = Color.WHITE
@export var saturation: float = 1.0
@export var contrast: float = 1.0

@export_group("Decorations")
@export var decorations: Array[DecorData] = []
## Generated props of the biome (tools/art/gen_decor_pack.py), added to
## `decorations` by all_decorations().
@export var decor_pack: DecorPack
## Decorations per room (average).
@export var decor_per_room: float = 3.0
## Share of wall bricks that become glowing ore.
@export var ore_chance: float = 0.04
## Item that ore veins drop.
@export var ore_item: StringName = &"iron_ore"

@export_group("Audio")
## Music id from AssetPaths.MUSIC.
@export var music: StringName = &"catacombs"
## Under the open sky (the town; every SurfaceBiomeData is): full daylight,
## drifting clouds, swaying foliage, the hour on the backgrounds.
@export var open_sky: bool = false
## Flooded pits on the floors (LevelGenerator._flood): how many, their
## water, and whether leeches live in it (they cling to swimmers).
@export var flooded_pools: int = 0
@export var pool_color: Color = Color(0.16, 0.42, 0.46, 0.78)
@export var pool_leeches: bool = false


func is_open_sky() -> bool:
	return open_sky or self is SurfaceBiomeData
## Footstep sound on bricks in this biome (platforms/ladders always use wood).
@export var step_sound: StringName = &"step_stone"


## The three background layers far -> near, loaded now; null where a biome
## has none (the layer is hidden). A missing file gives the placeholder.
func parallax_textures() -> Array:
	var out := []
	for p in [parallax_far, parallax_mid, parallax_near]:
		out.append(AssetPaths.tex(p) if p != "" else null)
	return out


var _all_decor: Array[DecorData] = []


## The hand-made decorations and the biome's decor pack together.
func all_decorations() -> Array[DecorData]:
	if _all_decor.is_empty():
		_all_decor.append_array(decorations)
		if decor_pack:
			_all_decor.append_array(decor_pack.decorations)
	return _all_decor
