class_name Stats
extends RefCounted
## Hero stats component. Final value = race + class (+ growth per level)
## + equipment bonuses + temporary buffs. Recalculated whenever equipment or
## level changes; derived values are computed from the primary attributes.

signal stats_changed
signal hp_changed(hp: int, max_hp: int)
signal mana_changed(mana: int, max_mana: int)
signal died

const BASE_HP := 40.0
const HP_PER_VITALITY := 8.0
const BASE_MANA := 20.0
const MANA_PER_INTELLECT := 6.0
const BASE_SPEED := 110.0
const SPEED_PER_AGILITY := 1.5
const BASE_CRIT := 0.05
const CRIT_PER_AGILITY := 0.006
const ARMOR_PER_VITALITY := 0.5
const DAMAGE_PER_MAIN_ATTR := 0.08

var race: RaceData
var class_data: ClassData
var level: int = 1
## Damage of the equipped weapon (0 = unarmed: ClassData.base_damage is used)
## and the class penalty multiplier for untrained weapon types.
var weapon_base: float = 0.0
var weapon_penalty: float = 1.0

var hp: int = 1
var mana: int = 0

## stat name -> final value
var _values: Dictionary = {}
## source key -> bonus Dictionary (equipment, buffs, ...)
var _modifiers: Dictionary = {}


func setup(p_race: RaceData, p_class: ClassData, p_level: int = 1) -> void:
	race = p_race
	class_data = p_class
	level = p_level
	recalculate()
	hp = max_hp()
	mana = max_mana()
	hp_changed.emit(hp, max_hp())
	mana_changed.emit(mana, max_mana())


## Adds/replaces a named group of bonuses (e.g. "equipment", "buff_iron_skin").
func set_modifier(key: String, bonuses: Dictionary) -> void:
	if bonuses.is_empty():
		_modifiers.erase(key)
	else:
		_modifiers[key] = bonuses
	recalculate()


func remove_modifier(key: String) -> void:
	if _modifiers.has(key):
		_modifiers.erase(key)
		recalculate()


func has_modifier(key: String) -> bool:
	return _modifiers.has(key)


func recalculate() -> void:
	var primary := {}
	for stat in StatTypes.PRIMARY:
		var v := 0.0
		if class_data:
			v += float(class_data.base_stats.get(stat, 0))
			v += float(class_data.growth_per_level.get(stat, 0)) * (level - 1)
		if race:
			v += float(race.stat_bonuses.get(stat, 0))
		v += _modifier_sum(stat)
		primary[stat] = v

	var str_v: float = primary[StatTypes.STRENGTH]
	var agi_v: float = primary[StatTypes.AGILITY]
	var int_v: float = primary[StatTypes.INTELLECT]
	var vit_v: float = primary[StatTypes.VITALITY]
	var main_attr: float = primary.get(class_data.main_attribute if class_data else StatTypes.STRENGTH, str_v)

	_values = primary.duplicate()
	_values[StatTypes.MAX_HP] = BASE_HP + vit_v * HP_PER_VITALITY + _flat(StatTypes.MAX_HP)
	_values[StatTypes.MAX_MANA] = BASE_MANA + int_v * MANA_PER_INTELLECT + _flat(StatTypes.MAX_MANA)
	# Weapon damage scaled by the class main attribute (+8% per point).
	var base_dmg := weapon_base if weapon_base > 0.0 else float(class_data.base_damage if class_data else 3)
	_values[StatTypes.DAMAGE] = (base_dmg + _flat(StatTypes.DAMAGE)) * (1.0 + main_attr * DAMAGE_PER_MAIN_ATTR) * weapon_penalty
	_values[StatTypes.ARMOR] = vit_v * ARMOR_PER_VITALITY + _flat(StatTypes.ARMOR)
	_values[StatTypes.SPEED] = BASE_SPEED + agi_v * SPEED_PER_AGILITY + _flat(StatTypes.SPEED)
	_values[StatTypes.CRIT_CHANCE] = clampf(BASE_CRIT + agi_v * CRIT_PER_AGILITY + _flat(StatTypes.CRIT_CHANCE), 0.0, 0.75)
	for res in StatTypes.RESISTANCES:
		_values[res] = clampf(_flat(res), 0.0, 0.75)

	hp = mini(hp, max_hp())
	mana = mini(mana, max_mana())
	stats_changed.emit()
	hp_changed.emit(hp, max_hp())
	mana_changed.emit(mana, max_mana())


func _flat(stat: String) -> float:
	var v := 0.0
	if race:
		v += float(race.stat_bonuses.get(stat, 0))
	return v + _modifier_sum(stat)


func _modifier_sum(stat: String) -> float:
	var v := 0.0
	for bonuses: Dictionary in _modifiers.values():
		v += float(bonuses.get(stat, 0))
	return v


func get_value(stat: String) -> float:
	return _values.get(stat, 0.0)


## Same formulas, evaluated as if `remove_bonuses` were replaced by `add_bonuses`.
## Used by tooltips to preview equipment changes.
func preview_value(stat: String, add_bonuses: Dictionary, remove_bonuses: Dictionary) -> float:
	var saved := _modifiers.duplicate()
	_modifiers["__preview_add"] = add_bonuses
	var neg := {}
	for k in remove_bonuses:
		neg[k] = -float(remove_bonuses[k])
	_modifiers["__preview_remove"] = neg
	var saved_hp := hp
	var saved_mana := mana
	_recalc_silent()
	var result := get_value(stat)
	_modifiers = saved
	_recalc_silent()
	hp = saved_hp
	mana = saved_mana
	return result


func _recalc_silent() -> void:
	set_block_signals(true)
	recalculate()
	set_block_signals(false)


func max_hp() -> int:
	return roundi(get_value(StatTypes.MAX_HP))


func max_mana() -> int:
	return roundi(get_value(StatTypes.MAX_MANA))


func damage() -> float:
	return get_value(StatTypes.DAMAGE)


func armor() -> float:
	return get_value(StatTypes.ARMOR)


func speed() -> float:
	return get_value(StatTypes.SPEED)


func crit_chance() -> float:
	return get_value(StatTypes.CRIT_CHANCE)


func is_dead() -> bool:
	return hp <= 0


## Applies armor reduction and returns the HP actually lost.
func take_damage(amount: int) -> int:
	if is_dead():
		return 0
	var reduced := maxi(1, roundi(amount * 100.0 / (100.0 + armor() * 4.0)))
	hp = maxi(0, hp - reduced)
	hp_changed.emit(hp, max_hp())
	if hp == 0:
		died.emit()
	return reduced


## Resistance (0..0.75) against a WeaponItemData.DamageType.
func resistance(damage_type: int) -> float:
	var key: String = StatTypes.DAMAGE_TYPE_RES[damage_type] if damage_type >= 0 and damage_type < StatTypes.DAMAGE_TYPE_RES.size() else ""
	return get_value(key) if key != "" else 0.0


## HP loss that ignores armor (poison, burning, traps' true damage).
func lose_hp(amount: int) -> int:
	if is_dead() or amount <= 0:
		return 0
	hp = maxi(0, hp - amount)
	hp_changed.emit(hp, max_hp())
	if hp == 0:
		died.emit()
	return amount


func heal(amount: int) -> void:
	hp = mini(max_hp(), hp + amount)
	hp_changed.emit(hp, max_hp())


func spend_mana(amount: int) -> bool:
	if mana < amount:
		return false
	mana -= amount
	mana_changed.emit(mana, max_mana())
	return true


func restore_mana(amount: int) -> void:
	mana = mini(max_mana(), mana + amount)
	mana_changed.emit(mana, max_mana())


func set_level(new_level: int) -> void:
	level = new_level
	recalculate()
	hp = max_hp()
	mana = max_mana()
	hp_changed.emit(hp, max_hp())
	mana_changed.emit(mana, max_mana())
