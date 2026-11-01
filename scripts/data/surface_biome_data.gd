class_name SurfaceBiomeData
extends BiomeData
## The open land of a region (data/surface/*.tres), the top layer of its
## locations: BiomeData's tiles, sky and light plus what SurfaceGenerator
## grows on it and the weather over it. RegionData.surface_biomes names
## which ones a region has.

@export_group("Land")
## Props standing on the ground (assets/sprites/surface/<name>.png).
@export var trees: Array[StringName] = [&"tree_oak"]
@export var rocks: Array[StringName] = [&"rock_big", &"rock_small"]
@export var small: Array[StringName] = [&"bush"]
## Trees per screen (some of them climbable: a trunk to a crown ledge).
@export var tree_density: float = 4.0
## Chance per screen of a cliff (a ladder or a climb up), a ravine with a
## bridge, a pond.
@export var cliff_chance: float = 0.35
@export var ravine_chance: float = 0.25
@export var pond_chance: float = 0.3
@export var water_color: Color = Color(0.3, 0.5, 0.75, 0.75)
## Rise of the land: 1 flat .. 3 rugged.
@export_range(1, 3) var roughness: int = 2

@export_group("Weather")
## Weather kinds and weights: none, rain, fog, wind, ash, snow.
@export var weather: Dictionary = {"none": 3.0, "rain": 1.0, "fog": 1.0, "wind": 1.0}

@export_group("Sound")
## Ambience loops (AudioManager SFX ids; a missing file stays silent).
@export var ambience_day: StringName = &"amb_birds"
@export var ambience_night: StringName = &"amb_night"
