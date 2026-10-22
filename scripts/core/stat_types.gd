class_name StatTypes
extends RefCounted
## Names of every stat. Item / race / class bonuses are Dictionaries keyed by
## these strings, e.g. {"strength": 2, "armor": 5}.

# Primary attributes
const STRENGTH := "strength"
const AGILITY := "agility"
const INTELLECT := "intellect"
const VITALITY := "vitality"

# Derived values (items may also add to them directly)
const MAX_HP := "max_hp"
const MAX_MANA := "max_mana"
const DAMAGE := "damage"
const ARMOR := "armor"
const SPEED := "speed"
const CRIT_CHANCE := "crit_chance"

# Resistances 0..0.75 (fraction of damage of that type ignored)
const RES_FIRE := "res_fire"
const RES_ICE := "res_ice"
const RES_POISON := "res_poison"
const RES_MAGIC := "res_magic"

const PRIMARY: Array[String] = [STRENGTH, AGILITY, INTELLECT, VITALITY]
const RESISTANCES: Array[String] = [RES_FIRE, RES_ICE, RES_POISON, RES_MAGIC]
## WeaponItemData.DamageType -> resistance stat ("" = physical: armor).
const DAMAGE_TYPE_RES: Array[String] = ["", RES_FIRE, RES_ICE, RES_POISON, RES_MAGIC]
const DERIVED: Array[String] = [MAX_HP, MAX_MANA, DAMAGE, ARMOR, SPEED, CRIT_CHANCE]

const LABELS := {
	STRENGTH: "Сила",
	AGILITY: "Ловкость",
	INTELLECT: "Интеллект",
	VITALITY: "Выносливость",
	MAX_HP: "Здоровье",
	MAX_MANA: "Мана",
	DAMAGE: "Урон",
	ARMOR: "Броня",
	SPEED: "Скорость",
	CRIT_CHANCE: "Шанс крита",
	RES_FIRE: "Сопр. огню",
	RES_ICE: "Сопр. холоду",
	RES_POISON: "Сопр. яду",
	RES_MAGIC: "Сопр. магии",
}


static func label(stat: String) -> String:
	return LABELS.get(stat, stat)


## Formats a value for UI: crit chance is stored as 0..1 and shown as percent.
static func format_value(stat: String, value: float, signed := false) -> String:
	var text: String
	if stat == CRIT_CHANCE or stat in RESISTANCES:
		text = "%d%%" % roundi(value * 100.0)
	else:
		text = str(roundi(value))
	if signed and value > 0.0:
		text = "+" + text
	return text
