class_name SkillSet
extends RefCounted
## The hero's skills: the class skill tree (`all`), learned ranks, skill points,
## cooldowns and the 8 HUD slots with active skills (first four on Q/E/R/F,
## the rest on Z/X/C/V). Slot index = position in the HUD skill row.

signal changed
signal cooldown_started(index: int, duration: float)

const SLOT_COUNT := 8

## Every skill of the class (the tree).
var all: Array[SkillData] = []
## Active skills in the HUD slots (null = empty).
var skills: Array[SkillData] = []
## skill id -> learned rank (absent = not learned)
var ranks: Dictionary = {}
## skill id -> seconds left
var cooldowns: Dictionary = {}
var skill_points: int = 0


func setup(list: Array[SkillData]) -> void:
	all = list.duplicate()
	ranks.clear()
	cooldowns.clear()
	skills.clear()
	skills.resize(SLOT_COUNT)
	for s in all:
		if s.is_starting():
			_learn_free(s)
	changed.emit()


func _learn_free(s: SkillData) -> void:
	ranks[s.id] = 1
	if not s.is_passive():
		var free := skills.find(null)
		if free >= 0:
			skills[free] = s


# --- HUD slots (API used by the player and the HUD) ---------------------------

func get_skill(index: int) -> SkillData:
	return skills[index] if index >= 0 and index < skills.size() else null


func get_level(index: int) -> int:
	var s := get_skill(index)
	return rank(s) if s else 0


func can_upgrade(index: int) -> bool:
	var s := get_skill(index)
	return s != null and skill_points > 0 and rank(s) < s.max_level


func upgrade(index: int) -> bool:
	if not can_upgrade(index):
		return false
	return _raise(get_skill(index))


# --- Tree ---------------------------------------------------------------------

func rank(s: SkillData) -> int:
	return int(ranks.get(s.id, 0)) if s else 0


func is_learned(s: SkillData) -> bool:
	return rank(s) > 0


func prerequisites_met(s: SkillData) -> bool:
	for r in s.requires:
		if r and not is_learned(r):
			return false
	return true


## Why `s` cannot be learned / raised now ("" = it can).
func block_reason(s: SkillData, hero_level: int) -> String:
	if rank(s) >= s.max_level:
		return "Максимальный уровень"
	if not is_learned(s):
		if hero_level < s.required_level:
			return "Нужен уровень героя %d" % s.required_level
		if not prerequisites_met(s):
			var names: Array[String] = []
			for r in s.requires:
				if r and not is_learned(r):
					names.append(r.display_name)
			return "Сначала изучите: " + ", ".join(names)
	if skill_points <= 0:
		return "Нет очков навыков"
	return ""


## Learns a skill (rank 1) or raises its rank; costs one skill point.
func learn(s: SkillData, hero_level: int) -> bool:
	if s == null or not (s in all) or block_reason(s, hero_level) != "":
		return false
	if not is_learned(s):
		skill_points -= 1
		_learn_free(s)
		changed.emit()
		return true
	return _raise(s)


func _raise(s: SkillData) -> bool:
	ranks[s.id] = rank(s) + 1
	skill_points -= 1
	changed.emit()
	return true


func add_points(amount: int) -> void:
	skill_points += amount
	changed.emit()


func passives() -> Array[SkillData]:
	var out: Array[SkillData] = []
	for s in all:
		if s.is_passive() and is_learned(s):
			out.append(s)
	return out


# --- Cooldowns ----------------------------------------------------------------

func tick(delta: float) -> void:
	for id in cooldowns:
		if cooldowns[id] > 0.0:
			cooldowns[id] = maxf(0.0, cooldowns[id] - delta)


func is_ready(index: int) -> bool:
	return cooldown_left(index) <= 0.0


func cooldown_left(index: int) -> float:
	var s := get_skill(index)
	return float(cooldowns.get(s.id, 0.0)) if s else 0.0


func start_cooldown(index: int) -> void:
	var s := get_skill(index)
	if s == null:
		return
	cooldowns[s.id] = s.cooldown
	cooldown_started.emit(index, s.cooldown)


## 0..1, how much of the cooldown is left (for the HUD overlay).
func cooldown_ratio(index: int) -> float:
	var s := get_skill(index)
	if s == null or s.cooldown <= 0.0:
		return 0.0
	return cooldown_left(index) / s.cooldown
