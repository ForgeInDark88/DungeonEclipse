class_name DecorPack
extends Resource
## A biome's generated decorations (tools/art/gen_decor_pack.py writes
## data/decor/<biome>_pack.tres). BiomeData.decor_pack adds them to the
## hand-made BiomeData.decorations; their weights are scaled so the whole
## pack weighs about as much as the hand-made list (the signature pieces
## stay common, the pack adds variety).

@export var id: StringName
@export var decorations: Array[DecorData] = []
