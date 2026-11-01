class_name EventData
extends Resource
## A choice on the road (an «event» node of the expedition map): a text on
## parchment and 2–4 answers. An answer may need something (EventRunner
## .check: class, stat, item, gold, resident, flag) and has outcomes rolled
## by chance, each with its effects (EventRunner.apply). Every event keeps a
## safe answer next to a risky one with a better reward.
## Add a .tres to data/road_events/ (tools/gen_road_events.py).
##
## options: [{"text": "...", "requires": "", "hint": "",
##            "outcomes": [{"chance": 0.6, "text": "...", "effects": {...}}]}]
## effects: gold, xp (scaled by depth), hp_pct / mana_pct (± share of max),
##   heal_full, item (id), loot (loot table rolled at depth), take_item (id),
##   pact (id | "blessing" | "curse"), resource ({id: n}), shards,
##   rescue ("any" | npc id | "refugee"), flag (story flag for the town),
##   fight ("elite" | "level": the event turns into a fight location),
##   rumours (signs of this map become readable).

@export var id: StringName
@export var title: String = ""
@export_multiline var text: String = ""
## Region ids where it happens (empty = everywhere).
@export var regions: Array[StringName] = []
@export var min_depth: int = 1
@export var max_depth: int = 99
@export var weight: float = 1.0
## The scenery of the event in its room (assets/sprites/road_events/<prop>.png,
## tools/gen_town_loop_art.py): the hero walks up to it to choose.
@export var prop: StringName = &"shrine"
@export var options: Array[Dictionary] = []
