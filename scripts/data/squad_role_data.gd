class_name SquadRoleData
extends Resource
## A support role in a monster squad (the squad leader). Squads appear from
## `min_floor`; the leader works for the allies around it (`radius`), so the
## group has to be taken apart in the right order. Add a .tres to data/squad_roles/.

enum Kind {
	HEALER,  ## heals the most wounded ally in range every `interval` s (power = share of its max HP)
	SHIELD,  ## allies in range take `power` less damage (0.4 = -40%)
	BANNER,  ## allies in range move and hit `power` faster / harder
}

@export var id: StringName
## Shown before the monster's name: "Лекарь", "Щитоносец"...
@export var title: String = ""
@export_multiline var description: String = ""
@export var kind: Kind = Kind.HEALER
@export var color: Color = Color.WHITE
@export var radius: float = 90.0
@export var power: float = 0.15
@export var interval: float = 3.0
## The leader itself is tougher.
@export var hp_mult: float = 1.3
@export var min_floor: int = 2
@export var weight: float = 1.0
