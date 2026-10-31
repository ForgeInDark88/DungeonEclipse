class_name QuestLog
extends RefCounted
## The guild's orders for one run: a fixed chain of quests taken from the
## herald in town. Progress accumulates from EventBus signals; a finished
## quest is claimed at the herald for its reward, which unlocks the next one.

signal quests_changed

enum Type { KILL, REACH, BOSS, ELITE, LOOT }

## The chain, in order. "type" drives which signals count towards it.
const CHAIN: Array[Dictionary] = [
	{"id": &"first_blood", "title": "Первая кровь", "type": Type.KILL, "target": 10,
		"desc": "Подземелье кишит тварями. Убей 10 монстров — пусть затмение знает, что в городе есть кому постоять за себя.",
		"gold": 60, "shards": 0, "item": &"", "item_count": 0},
	{"id": &"into_dark", "title": "Во тьму", "type": Type.REACH, "target": 3,
		"desc": "Спустись на 3-й этаж. Дальше первой лестницы никто из новичков не доходит — докажи, что ты не новичок.",
		"gold": 100, "shards": 0, "item": &"health_potion", "item_count": 2},
	{"id": &"shadow_gatherer", "title": "Собиратель тени", "type": Type.LOOT, "target": 8,
		"desc": "Гильдии нужно снаряжение. Найди и подбери 8 предметов в подземелье.",
		"gold": 120, "shards": 0, "item": &"bomb", "item_count": 3},
	{"id": &"bone_breaker", "title": "Костолом", "type": Type.KILL, "target": 30,
		"desc": "30 монстров. Гильдия платит за счёт — и щедро платит тем, кто возвращается.",
		"gold": 200, "shards": 1, "item": &"", "item_count": 0},
	{"id": &"cave_heart", "title": "Сердце пещеры", "type": Type.BOSS, "target": 1,
		"desc": "Убей босса. Каждые несколько этажей подземелье рожает стража — убей одного и принеси гильдии его славу.",
		"gold": 250, "shards": 2, "item": &"", "item_count": 0},
	{"id": &"elite_hunt", "title": "Элитная охота", "type": Type.ELITE, "target": 3,
		"desc": "Элитные твари носят ауры и стоят за ними толпы. Сваляй трёх — гильдия оценит добычу.",
		"gold": 220, "shards": 1, "item": &"", "item_count": 0},
	{"id": &"deeper", "title": "Глубже", "type": Type.REACH, "target": 10,
		"desc": "Дойди до 10-го этажа. Ниже десяти лестниц не спускался даже тот, кто вырезал первую карту.",
		"gold": 300, "shards": 2, "item": &"health_potion", "item_count": 3},
	{"id": &"ash_and_ice", "title": "Пепел и лёд", "type": Type.REACH, "target": 16,
		"desc": "На глубине меняется сам камень: пепел и кристаллы. Дойди до 16-го этажа и расскажи, что увидишь.",
		"gold": 400, "shards": 3, "item": &"", "item_count": 0},
	{"id": &"dark_legion", "title": "Легион тьмы", "type": Type.KILL, "target": 100,
		"desc": "Сто монстров за забег. Легион тьмы должен знать: счёт ведётся.",
		"gold": 500, "shards": 3, "item": &"", "item_count": 0},
	{"id": &"eclipse", "title": "Затмение", "type": Type.BOSS, "target": 3,
		"desc": "Три стража за один спуск. Последний приказ гильдии в этом забеге — и самый щедрый.",
		"gold": 600, "shards": 5, "item": &"", "item_count": 0},
]

var index := 0
var progress := 0
var _connected := false


## Subscribes to the bus. Called once from GameState._ready; safe to call again.
func attach() -> void:
	if _connected:
		return
	_connected = true
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.item_collected.connect(_on_item_collected)
	EventBus.elite_killed.connect(_on_elite_killed)
	EventBus.boss_defeated.connect(_on_boss_defeated)
	EventBus.floor_changed.connect(_on_floor_changed)


func reset() -> void:
	index = 0
	progress = 0
	quests_changed.emit()


func current() -> Dictionary:
	return CHAIN[index] if index < CHAIN.size() else {}


func is_done() -> bool:
	var q := current()
	return not q.is_empty() and progress >= int(q["target"])


func all_done() -> bool:
	return index >= CHAIN.size()


## One step of the current quest, if the event matches its type.
func _bump(type: Type, n: int) -> void:
	if not GameState.run_active or all_done():
		return
	var q := current()
	if int(q["type"]) != type:
		return
	progress = mini(progress + n, int(q["target"]))
	if progress >= int(q["target"]):
		EventBus.message.emit(tr("Задание выполнено: «%s» — к глашатаю в город!") % q["title"])
		AudioManager.play_ui(&"level_up")
	quests_changed.emit()


func _on_enemy_killed(_enemy: EnemyData, _pos: Vector2) -> void:
	_bump(Type.KILL, 1)


func _on_elite_killed(_enemy: EnemyData) -> void:
	_bump(Type.ELITE, 1)


func _on_boss_defeated(_boss: BossData, _pos: Vector2) -> void:
	_bump(Type.BOSS, 1)


func _on_item_collected(item: ItemData, _pos: Vector2) -> void:
	if item.currency_value <= 0:  # gold piles don't count as loot
		_bump(Type.LOOT, 1)


## "Reach floor N": the deepest floor this run, town doesn't count.
func _on_floor_changed(f: int) -> void:
	if f <= GameState.TOWN_FLOOR or not GameState.run_active:
		return
	var q := current()
	if q.is_empty() or int(q["type"]) != Type.REACH:
		return
	progress = maxi(progress, f)
	if progress >= int(q["target"]) and progress == int(q["target"]):
		EventBus.message.emit(tr("Задание выполнено: «%s» — к глашатаю в город!") % q["title"])
		AudioManager.play_ui(&"level_up")
	quests_changed.emit()


## Hands out the reward of the finished quest and unlocks the next one.
## Returns the reward dictionary or {} when there is nothing to claim.
func claim(hero: Hero) -> Dictionary:
	var q := current()
	if q.is_empty() or progress < int(q["target"]):
		return {}
	var reward := {"gold": int(q["gold"]), "shards": int(q["shards"])}
	hero.gold += reward["gold"]
	hero.gold_changed.emit(hero.gold)
	if reward["shards"] > 0:
		MetaProgress.shards += reward["shards"]
		MetaProgress.save_progress()
		MetaProgress.changed.emit()
	var iid: StringName = q["item"]
	if iid != &"":
		var it := ItemDatabase.get_item(iid)
		if it:
			hero.inventory.add_item(it, maxi(1, int(q["item_count"])))
	index += 1
	progress = 0
	AudioManager.play_ui(&"ui_equip")
	quests_changed.emit()
	return reward
