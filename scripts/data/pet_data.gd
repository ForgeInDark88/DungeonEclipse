class_name PetData
extends Resource
## A pet (familiar) hatched from an egg (HatchPetEffect). It follows the hero
## from floor to floor until the end of the run, attacks monsters the hero
## can see and brings gold coins. Add a .tres to data/pets/.

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
@export_file("*.png") var sheet: String = ""
@export var tint: Color = Color.WHITE
## Damage per hit on hero level 1 (+15% per hero level).
@export var damage: int = 4
## WeaponItemData.DamageType (0 = physical).
@export var damage_type: int = 0
@export var attack_cooldown: float = 1.2
## Monsters this far from the hero are attacked (px).
@export var attack_range: float = 150.0
@export var speed: float = 150.0
## Status put on hit ("" = none), its time and strength.
@export var status: StringName = &""
@export var status_duration: float = 2.0
@export var status_power: float = 1.0
## Gold coins this close to the pet are collected (px).
@export var gold_radius: float = 110.0
