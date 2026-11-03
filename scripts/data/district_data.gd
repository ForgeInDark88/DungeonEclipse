class_name DistrictData
extends Resource
## A district of the town (data/districts/*.tres, ordered by `x_from`): a
## stretch of the street with its own buildings (BuildingData.slot inside
## it), props and people's places. A district opens as the town grows
## (TownDistricts.is_open): until then a palisade closes it and scaffolding
## stands behind it. Add a file to add a district.

@export var id: StringName
@export var display_name: String = ""
## Cells of the street it covers (TownBuilder.HUB_WIDTH wide in all).
@export var x_from: int = 0
@export var x_to: int = 40
## A terrace: the street here is this many cells higher (stairs at both ends).
@export var raise: int = 0
## Open from the start of a new town.
@export var open_from_start: bool = false
## Opens when any of these is reached (0 = not a condition).
@export var prosperity: int = 0
@export var residents: int = 0
## Or when one of its own buildings stands (old saves, a built temple...).
@export var opens_with_building: bool = true
## Where the townsfolk go by the hour in this district (cells): the market
## in the morning, the workshops by day, the tavern in the evening.
@export var gathering: StringName = &""
## Props of the district: [{"tex": name in assets/sprites/town, "x": cell, "z": int, "lamp": bool}].
@export var props: Array[Dictionary] = []
## Houses of the people (cells): filled one by one as people move in.
@export var houses: Array[int] = []
## Shown on the palisade while closed ("" = from the conditions).
@export var unlock_text: String = ""
