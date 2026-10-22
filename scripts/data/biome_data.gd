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
@export var parallax_far: Texture2D
@export var parallax_mid: Texture2D
@export var parallax_near: Texture2D

@export_group("Light and color")
## Soft general light of the biome (CanvasModulate of the world). Bright on
## purpose: monsters, traps and items must always be readable.
@export var ambient: Color = Color(1.0, 0.98, 0.95)
## Background (back wall, parallax) is a bit darker: depth, not darkness.
@export var back_wall_modulate: Color = Color(0.85, 0.8, 0.84)
## Warm glow of the decorative wall torches (they do not change visibility).
@export var torch_color: Color = Color(1.0, 0.62, 0.3)
@export var ambient_particles: Color = Color(0.8, 0.75, 0.7)
@export var fog_color: Color = Color(0.5, 0.5, 0.6)
@export_range(0.0, 1.0) var fog_amount: float = 0.08
@export var grade_tint: Color = Color.WHITE
@export var saturation: float = 1.0
@export var contrast: float = 1.0

@export_group("Decorations")
@export var decorations: Array[DecorData] = []
## Decorations per room (average).
@export var decor_per_room: float = 3.0
## Share of wall bricks that become glowing ore.
@export var ore_chance: float = 0.04
## Item that ore veins drop.
@export var ore_item: StringName = &"iron_ore"

@export_group("Audio")
## Music id from AssetPaths.MUSIC.
@export var music: StringName = &"catacombs"
## Footstep sound on bricks in this biome (platforms/ladders always use wood).
@export var step_sound: StringName = &"step_stone"
