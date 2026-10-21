class_name SkillSet
extends RefCounted
## The hero's skills: level per skill, cooldowns and skill points.
## Slot index = position in the HUD skill row (8 slots, first four on Q/E/R/F).

signal changed
signal cooldown_started(index: int, duration: float)

const SLOT_COUNT := 8

var skills: Array[SkillData] = []
var levels: Array[int] = []
var cooldowns: Array[float] = []
var skill_points: int = 0


func setup(list: Array[SkillData]) -> void:
	skills.clear()
	for s in list:
		if skills.size() < SLOT_COUNT:
			skills.append(s)
	levels.resize(skills.size())
	levels.fill(1)
	cooldowns.resize(skills.size())
	cooldowns.fill(0.0)
	changed.emit()


func get_skill(index: int) -> SkillData:
	return skills[index] if index >= 0 and index < skills.size() else null


func get_level(index: int) -> int:
	return levels[index] if index >= 0 and index < levels.size() else 0


func can_upgrade(index: int) -> bool:
	var s := get_skill(index)
	return s != null and skill_points > 0 and levels[index] < s.max_level


func upgrade(index: int) -> bool:
	if not can_upgrade(index):
		return false
	levels[index] += 1
	skill_points -= 1
	changed.emit()
	return true


func add_points(amount: int) -> void:
	skill_points += amount
	changed.emit()


func tick(delta: float) -> void:
	for i in cooldowns.size():
		if cooldowns[i] > 0.0:
			cooldowns[i] = maxf(0.0, cooldowns[i] - delta)


func is_ready(index: int) -> bool:
	return index < cooldowns.size() and cooldowns[index] <= 0.0


func start_cooldown(index: int) -> void:
	var s := get_skill(index)
	if s == null:
		return
	cooldowns[index] = s.cooldown
	cooldown_started.emit(index, s.cooldown)


## 0..1, how much of the cooldown is left (for the HUD overlay).
func cooldown_ratio(index: int) -> float:
	var s := get_skill(index)
	if s == null or s.cooldown <= 0.0:
		return 0.0
	return cooldowns[index] / s.cooldown
