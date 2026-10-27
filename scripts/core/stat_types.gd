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

# Special values (items, relics): HP regenerated per second, extra gold from
# monsters (0.2 = +20%), jumps in the air.
const HP_REGEN := "hp_regen"
const GOLD_FIND := "gold_find"
const EXTRA_JUMPS := "extra_jumps"

const PRIMARY: Array[String] = [STRENGTH, AGILITY, INTELLECT, VITALITY]
const RESISTANCES: Array[String] = [RES_FIRE, RES_ICE, RES_POISON, RES_MAGIC]
## WeaponItemData.DamageType -> resistance stat ("" = physical: armor).
const DAMAGE_TYPE_RES: Array[String] = ["", RES_FIRE, RES_ICE, RES_POISON, RES_MAGIC]
const DERIVED: Array[String] = [MAX_HP, MAX_MANA, DAMAGE, ARMOR, SPEED, CRIT_CHANCE]
const SPECIAL: Array[String] = [HP_REGEN, GOLD_FIND, EXTRA_JUMPS]

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
	HP_REGEN: "Регенерация HP/с",
	GOLD_FIND: "Добыча золота",
	EXTRA_JUMPS: "Доп. прыжки",
}


## Element of a resistance key for "weak to ...": огонь, лёд, яд, магия.
static func element_name(res_key: String) -> String:
	return {RES_FIRE: "огонь", RES_ICE: "лёд", RES_POISON: "яд", RES_MAGIC: "магия"}.get(res_key, res_key)


static func label(stat: String) -> String:
	return LABELS.get(stat, stat)


## Formats a value for UI: crit chance is stored as 0..1 and shown as percent.
static func format_value(stat: String, value: float, signed := false) -> String:
	var text: String
	if stat == CRIT_CHANCE or stat == GOLD_FIND or stat in RESISTANCES:
		text = "%d%%" % roundi(value * 100.0)
	elif stat == HP_REGEN:
		text = "%.1f" % value
	else:
		text = str(roundi(value))
	if signed and value > 0.0:
		text = "+" + text
	return text
