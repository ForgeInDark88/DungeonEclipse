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
## CanvasModulate of the world (how dark the dungeon is).
@export var darkness: Color = Color(0.15, 0.13, 0.19)
@export var back_wall_modulate: Color = Color(0.6, 0.55, 0.65)
@export var torch_color: Color = Color(1.0, 0.62, 0.3)
@export var hero_light_color: Color = Color(1.0, 0.86, 0.65)
@export var ambient_particles: Color = Color(0.8, 0.75, 0.7)
@export var fog_color: Color = Color(0.5, 0.5, 0.6)
@export_range(0.0, 1.0) var fog_amount: float = 0.08
@export var grade_tint: Color = Color.WHITE
@export var saturation: float = 1.0
@export var contrast: float = 1.0
@export_range(0.0, 1.0) var vignette: float = 0.35

@export_group("Decorations")
@export var decorations: Array[DecorData] = []
## Decorations per room (average).
@export var decor_per_room: float = 3.0
## Share of wall bricks that become glowing ore.
@export var ore_chance: float = 0.04
## Item that ore veins drop.
@export var ore_item: StringName = &"iron_ore"
