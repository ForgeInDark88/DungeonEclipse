class_name NpcData
extends Resource
## A person of the town. Some live there from the start, most are freed on
## expeditions (rescue nodes) and move in: they open a building (BuildingData
## .requires_resident), lower prices, talk. Add a .tres to data/npcs/.
##
## `dialogs` is a list of talks, the first one whose condition holds (and
## that is not read yet, if `once`) is the current one:
##   {"id": "intro", "when": "", "once": true, "text": "...",
##    "options": [{"text": "...", "reply": "...", "flag": "some_flag"}]}
## Conditions (`when`, several joined by " & "): "" (always),
## "boss:<id>", "flag:<id>", "!flag:<id>", "building:<id>:<level>",
## "resident:<id>", "expeditions:<n>".

@export var id: StringName
@export var display_name: String = ""
@export var profession: String = ""
@export var order: int = 0
## Lives in town from the start (no rescue needed).
@export var resident_from_start := false
## Building where they work / live (&"" = they stroll the square).
@export var home: StringName
## Placeholder sprite (20×30) and portrait (48×48), tools/gen_placeholders.py loop.
@export var sprite: Texture2D
@export var portrait: Texture2D
## Shop prices go down by this share while they live in town.
@export var discount: float = 0.0
## Building costs go down by this share while they live in town.
@export var build_discount: float = 0.0
## Rescues of this person appear from this depth on.
@export var depth_min: int = 1
## Their words when freed (rescue node).
@export_multiline var rescue_text: String = ""
@export var dialogs: Array[Dictionary] = []
