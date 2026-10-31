class_name EclipseLevels
extends RefCounted
## Levels of the Eclipse: the challenge after the first victory. Level N
## carries the trials of levels 1..N (they stack) on top of the chosen
## difficulty and pays more shards. Winning on level N unlocks level N + 1
## (MetaProgress.eclipse_unlocked).

const MAX := 10
## Extra Sanctum shards per level (x1.2, x1.4 ... x3.0).
const SHARD_STEP := 0.2

## [name, what it adds, effects (run_effect keys) / special keys]
const LEVELS := [
	["Тень", "Монстры крепче: +15% здоровья", {"enemy_hp": 0.15}],
	["Сумрак", "Элиты встречаются в 1,5 раза чаще", {"elite_mult": 1.5}],
	["Багровый свет", "Монстры бьют сильнее: +15% урона", {"enemy_damage": 0.15}],
	["Голод", "Лечение слабее на 25%", {"heal_mult": 0.75}],
	["Шипы", "Ловушки бьют вдвое сильнее", {"trap_mult": 2.0}],
	["Стражи гнева", "Стражи этажей: +30% здоровья", {"boss_hp": 0.3}],
	["Орда", "Монстров на этажах на 30% больше", {"monster_count": 0.3}],
	["Печать", "Печати выхода нужно на 15% больше убийств", {"seal_add": 0.15}],
	["Нищета", "Забег начинается без зелий", {"no_potions": 1.0}],
	["Чёрное солнце", "Всё злее: монстры +25% здоровья и урона, стражи ещё +30%", {"enemy_hp": 0.25, "enemy_damage": 0.25, "boss_hp": 0.3}],
]


static func level_name(level: int) -> String:
	return LEVELS[level - 1][0] if level >= 1 and level <= MAX else "Без Затмения"


## Sum (or product for *_mult keys) of a key over levels 1..level.
static func value(level: int, key: String) -> float:
	var mult := key.ends_with("_mult")
	var v := 1.0 if mult else 0.0
	for i in clampi(level, 0, MAX):
		var eff: Dictionary = LEVELS[i][2]
		if eff.has(key):
			v = v * float(eff[key]) if mult else v + float(eff[key])
	return v


## What level N adds up to (for the selector).
static func describe(level: int) -> String:
	if level <= 0:
		return "Обычный забег. Победа над Затмением открывает его уровни."
	var lines: Array[String] = []
	for i in level:
		lines.append("%d. %s" % [i + 1, LEVELS[i][1]])
	lines.append("Осколков Святилища: ×%.1f" % shard_mult(level))
	return "\n".join(lines)


## One line: what this level adds (the earlier ones stay) and the reward.
static func short(level: int) -> String:
	if level <= 0:
		return "Без испытаний Затмения."
	return "+ %s%s · осколков ×%.1f" % [LEVELS[level - 1][1], " (и все прежние)" if level > 1 else "", shard_mult(level)]


static func shard_mult(level: int) -> float:
	return 1.0 + SHARD_STEP * clampi(level, 0, MAX)
