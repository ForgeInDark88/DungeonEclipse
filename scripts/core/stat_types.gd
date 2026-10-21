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

const PRIMARY: Array[String] = [STRENGTH, AGILITY, INTELLECT, VITALITY]
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
}


static func label(stat: String) -> String:
	return LABELS.get(stat, stat)


## Formats a value for UI: crit chance is stored as 0..1 and shown as percent.
static func format_value(stat: String, value: float, signed := false) -> String:
	var text: String
	if stat == CRIT_CHANCE:
		text = "%d%%" % roundi(value * 100.0)
	else:
		text = str(roundi(value))
	if signed and value > 0.0:
		text = "+" + text
	return text
