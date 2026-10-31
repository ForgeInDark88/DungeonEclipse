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
## Branch tree of the class (ClassData.tree_layout / branch_names).
var layout: Dictionary = {}
var branch_names: Array[String] = []
## The committed branch of the three (-1 = not chosen yet). The first point
## spent on a non-starting skill locks the hero into that branch; the other
## two close until a respec.
var chosen_branch := -1
## Gold per hero level to forget every skill and get the points back.
const RESPEC_GOLD_PER_LEVEL := 25


## Nothing is learned at setup: the hero starts with zero skills and earns
## everything through the tree (the run opens with one point to spend —
## the first learned skill also commits the branch).
func setup(list: Array[SkillData], p_layout: Dictionary = {}, p_branches: Array[String] = []) -> void:
	all = list.duplicate()
	layout = p_layout
	branch_names = p_branches
	ranks.clear()
	cooldowns.clear()
	skills.clear()
	skills.resize(SLOT_COUNT)
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

func has_branches() -> bool:
	return not layout.is_empty()


func _slot(s: SkillData) -> Dictionary:
	return layout.get(String(s.id), {}) if s else {}


func branch_of(s: SkillData) -> int:
	return int(_slot(s).get("branch", -1))


func row_of(s: SkillData) -> int:
	return int(_slot(s).get("row", s.tree_row)) if has_branches() else s.tree_row


func choice_of(s: SkillData) -> String:
	return String(_slot(s).get("choice", ""))


func required_level(s: SkillData) -> int:
	return int(_slot(s).get("level", s.required_level)) if has_branches() else s.required_level


## Points that must be spent in the skill's branch before it opens.
func required_points(s: SkillData) -> int:
	return int(_slot(s).get("points", 0))


## Tier-0 gateway of a branch (no branch points needed, hero level 1).
func is_starting(s: SkillData) -> bool:
	if has_branches():
		return required_points(s) == 0 and required_level(s) <= 1 and choice_of(s) == ""
	return s.is_starting()


## Skill points spent in a branch.
func spent_in(branch: int) -> int:
	var n := 0
	for s in all:
		if branch_of(s) == branch and is_learned(s):
			n += rank(s)
	return n


## The learned skill that closed this one (same choice group), or null.
func chosen_rival(s: SkillData) -> SkillData:
	var group := choice_of(s)
	if group == "":
		return null
	for o in all:
		if o != s and choice_of(o) == group and is_learned(o):
			return o
	return null


func respec_cost(hero_level: int) -> int:
	return RESPEC_GOLD_PER_LEVEL * hero_level


## Points that a respec would give back.
func spent_total() -> int:
	var n := 0
	for s in all:
		if is_learned(s):
			n += rank(s)
	return n


## Forgets every skill; the points come back and the branch choice frees.
func reset() -> int:
	var back := spent_total()
	for s in all:
		if not is_learned(s):
			continue
		ranks.erase(s.id)
		var i := skills.find(s)
		if i >= 0:
			skills[i] = null
	chosen_branch = -1
	skill_points += back
	changed.emit()
	return back

func rank(s: SkillData) -> int:
	return int(ranks.get(s.id, 0)) if s else 0


func is_learned(s: SkillData) -> bool:
	return rank(s) > 0


func prerequisites_met(s: SkillData) -> bool:
	if has_branches():
		return true
	for r in s.requires:
		if r and not is_learned(r):
			return false
	return true


## Why `s` cannot be learned / raised now ("" = it can).
func block_reason(s: SkillData, hero_level: int) -> String:
	if rank(s) >= s.max_level:
		return tr("Максимальный уровень")
	if not is_learned(s):
		var b := branch_of(s)
		if chosen_branch >= 0 and b >= 0 and b != chosen_branch:
			return tr("Путь выбран: «%s»") % branch_name_of(b)
		var rival := chosen_rival(s)
		if rival:
			return tr("Выбран другой путь: %s") % rival.display_name
		var need := required_points(s) - spent_in(b)
		if need > 0:
			return tr("Вложите ещё %d очк. в ветвь «%s»") % [need, branch_name_of(b)]
		if hero_level < required_level(s):
			return tr("Нужен уровень героя %d") % required_level(s)
		if not prerequisites_met(s):
			var names: Array[String] = []
			for r in s.requires:
				if r and not is_learned(r):
					names.append(r.display_name)
			return tr("Сначала изучите: ") + ", ".join(names)
	if skill_points <= 0:
		return tr("Нет очков навыков")
	return ""


func branch_name_of(b: int) -> String:
	return branch_names[b] if b >= 0 and b < branch_names.size() else "?"


## Learns a skill (rank 1) or raises its rank; costs one skill point.
## The first learned skill commits the hero to its branch.
func learn(s: SkillData, hero_level: int) -> bool:
	if s == null or not (s in all) or block_reason(s, hero_level) != "":
		return false
	if not is_learned(s):
		skill_points -= 1
		_learn_free(s)
		if chosen_branch < 0 and branch_of(s) >= 0:
			chosen_branch = branch_of(s)
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
