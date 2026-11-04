class_name EnemyData
extends Resource
## A monster type. One generic enemy scene reads all of this.

enum Behavior { WALKER, FLYER, RANGED }

@export var id: StringName
@export var display_name: String = ""
## Bestiary text (Codex).
@export_multiline var description: String = ""
@export var texture: Texture2D
## Animated sheet (idle, walk/fly, windup, attack, hurt, death) + its layout.
## If empty, the static `texture` is used.
@export var sheet: Texture2D
@export var sheet_layout: SpriteSheetLayout
@export var behavior: Behavior = Behavior.WALKER
@export var collision_size: Vector2 = Vector2(12, 12)
@export var max_hp: int = 20
@export var damage: int = 5
@export var armor: int = 0
@export var speed: float = 40.0
@export var chase_speed: float = 70.0
@export var aggro_range: float = 120.0
@export var attack_range: float = 16.0
@export var attack_cooldown: float = 1.0
## WALKER: hops while chasing (slimes).
@export var jumps: bool = false
## RANGED: projectile texture and speed.
@export var projectile_texture: Texture2D
@export var projectile_speed: float = 140.0
@export var xp_reward: int = 10
@export var loot_table: LootTable
@export_range(0.0, 1.0) var loot_chance: float = 0.35
## Gold dropped on death (scaled by floor).
@export var gold_min: int = 1
@export var gold_max: int = 4
## First floor where it may spawn, and spawn weight.
@export var min_floor: int = 1
@export var spawn_weight: float = 1.0
## Biome ids where it appears (empty = everywhere).
@export var biomes: Array[StringName] = []
## Where it lives: &"dungeon" (floors), &"surface" (the open land of
## locations, data/surface biomes) or &"any".
@export var habitat: StringName = &"dungeon"
## Surface life: a neutral animal ignores the hero until hurt (deer, crows);
## a sleeper dozes until a hero comes close or a noise wakes it; a night
## creature comes out only at night (LocationManager).
@export var neutral: bool = false
@export var sleeper: bool = false
@export var night_only: bool = false
@export var tint: Color = Color.WHITE
## Russian gender of the name (m/f/n) for elite prefixes.
@export var gender: String = "m"

@export_group("Special abilities")
## Flies through walls (ghosts): no world collision, no line-of-sight checks.
@export var phases_through_walls: bool = false
## Waits on the ceiling and drops on the hero passing below (spiders).
@export var ceiling_ambush: bool = false
## Melee hits damage everything in this radius (golem slam). 0 = normal hit.
@export var aoe_radius: float = 0.0
## Summoners: raise these instead of shooting every other attack.
@export var summon: EnemyData
@export var max_summons: int = 3
## Fakes (boss illusions): no XP, gold, loot or kill count on death.
@export var no_rewards: bool = false
## Training dummy in the town: never attacks, never dies, shows damage per second.
@export var training_dummy: bool = false
@export_group("Statuses and elements")
## Resistances by stat key: {"res_fire": 0.5, "res_poison": 1.0}.
@export var resistances: Dictionary = {}
## Statuses that never apply (e.g. golems are immune to poison).
@export var status_immunities: Array[StringName] = []
## Applied to the hero when this monster hits (melee or projectile).
@export var on_hit_effects: Array[HitEffect] = []
@export_group("Sounds (ids from AssetPaths.SFX)")
@export var sound_hurt: StringName = &"enemy_hurt"
@export var sound_death: StringName = &"enemy_death"
@export var sound_attack: StringName = &""
## Voice family (tools/audio/gen_sfx.py, docs/AUDIO_LIST.md): bone, slime,
## beast, hiss, winged, spirit, human, brute, stone, frost, water, plant,
## void, mimic. Gives the monster its own <voice>_aggro / _attack / _hurt /
## _death and the sound of a blow on it; empty = the sound_* fields above.
@export var voice: StringName = &""

## What a blow on this kind of body sounds like.
const HIT_BY_VOICE := {&"bone": &"hit_bone", &"stone": &"hit_stone", &"slime": &"hit_slime", &"water": &"hit_slime",
	&"plant": &"hit_wood", &"mimic": &"hit_wood", &"frost": &"hit_stone", &"spirit": &"hit_spirit", &"void": &"hit_spirit"}


func _voiced(kind: String, fallback: StringName) -> StringName:
	if voice != &"":
		var id := StringName("%s_%s" % [voice, kind])
		if AssetPaths.SFX.has(id):
			return id
	return fallback


func hurt_sound() -> StringName:
	return _voiced("hurt", sound_hurt)


func death_sound() -> StringName:
	return _voiced("death", sound_death)


func aggro_sound() -> StringName:
	return _voiced("aggro", &"")


## The swing / bite / spit of a melee or ranged attack.
func attack_sound() -> StringName:
	return _voiced("attack", sound_attack)


func hit_sound(crit := false) -> StringName:
	if crit:
		return &"hit_crit"
	var id: StringName = HIT_BY_VOICE.get(voice, &"hit_flesh")
	return id if AssetPaths.SFX.has(id) else &"hit_flesh"
