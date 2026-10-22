extends Node
## Lifetime statistics shared by achievements, the bestiary and the item
## encyclopedia ("Летопись" in the main menu). Listens to EventBus only, so
## gameplay code never calls it directly. Stored in [codex] of user://meta.cfg.

const ACHIEVEMENT_DIR := "res://data/achievements"
const SECTION := "codex"
## Counters an AchievementData can watch. "floor", "bestiary" and
## "items_known" keep the best value, the rest are sums.
const COUNTERS: Array[StringName] = [&"kills", &"elites", &"bosses", &"floor", &"chests", &"epic_items",
	&"gold", &"traps", &"events", &"purchases", &"deaths", &"bestiary", &"items_known", &"runs"]

var counters: Dictionary = {}
## enemy / boss id -> kills
var enemy_kills: Dictionary = {}
## item id -> times found
var items_found: Dictionary = {}
## achievement id -> unix time of unlocking
var achieved: Dictionary = {}
var achievements: Array[AchievementData] = []
var _dirty := false


func _ready() -> void:
	for res in ItemDatabase.load_dir(ACHIEVEMENT_DIR):
		if res is AchievementData:
			achievements.append(res)
	achievements.sort_custom(func(a: AchievementData, b: AchievementData) -> bool: return a.order < b.order)
	load_progress()
	add_child(AchievementToast.new())
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.elite_killed.connect(func(_d: EnemyData) -> void: add(&"elites"))
	EventBus.boss_defeated.connect(func(_b: BossData, _p: Vector2) -> void: add(&"bosses"))
	EventBus.floor_changed.connect(func(n: int) -> void: record_max(&"floor", n))
	EventBus.chest_opened.connect(func(_c: Node) -> void: add(&"chests"))
	EventBus.item_collected.connect(func(item: ItemData, _p: Vector2) -> void: discover_item(item))
	EventBus.item_bought.connect(func(item: ItemData) -> void:
		add(&"purchases")
		discover_item(item))
	EventBus.gold_earned.connect(func(amount: int) -> void: add(&"gold", amount))
	EventBus.trap_disarmed.connect(func(_t: TrapData) -> void: add(&"traps"))
	EventBus.event_completed.connect(func(_e: Node) -> void: add(&"events"))
	EventBus.player_died.connect(func() -> void: add(&"deaths"))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if _dirty:
			save_progress()


func load_progress() -> void:
	var cfg := ConfigFile.new()
	if not FileAccess.file_exists(SaveManager.META_PATH) or cfg.load(SaveManager.META_PATH) != OK:
		return
	counters = cfg.get_value(SECTION, "counters", {})
	enemy_kills = cfg.get_value(SECTION, "enemy_kills", {})
	items_found = cfg.get_value(SECTION, "items_found", {})
	achieved = cfg.get_value(SECTION, "achieved", {})


func save_progress() -> void:
	var cfg := ConfigFile.new()
	if FileAccess.file_exists(SaveManager.META_PATH):
		cfg.load(SaveManager.META_PATH)  # keep the other sections
	cfg.set_value(SECTION, "counters", counters)
	cfg.set_value(SECTION, "enemy_kills", enemy_kills)
	cfg.set_value(SECTION, "items_found", items_found)
	cfg.set_value(SECTION, "achieved", achieved)
	cfg.save(SaveManager.META_PATH)
	_dirty = false


## Copy of the whole state (tests restore the player's real progress with it).
func snapshot() -> Array:
	return [counters.duplicate(), enemy_kills.duplicate(), items_found.duplicate(), achieved.duplicate()]


func restore(snap: Array) -> void:
	counters = snap[0]
	enemy_kills = snap[1]
	items_found = snap[2]
	achieved = snap[3]
	save_progress()


func get_counter(id: StringName) -> int:
	return int(counters.get(id, 0))


func add(id: StringName, amount: int = 1) -> void:
	counters[id] = get_counter(id) + amount
	_dirty = true
	_check(id)


func record_max(id: StringName, value: int) -> void:
	if value > get_counter(id):
		counters[id] = value
		_dirty = true
		_check(id)


func _on_enemy_killed(data: EnemyData, _pos: Vector2) -> void:
	if data == null:
		return
	enemy_kills[data.id] = int(enemy_kills.get(data.id, 0)) + 1
	add(&"kills")
	record_max(&"bestiary", enemy_kills.size())


func discover_item(item: ItemData) -> void:
	if item == null:
		return
	items_found[item.id] = int(items_found.get(item.id, 0)) + 1
	if item.rarity == ItemData.Rarity.EPIC:
		add(&"epic_items")
	record_max(&"items_known", items_found.size())


func is_enemy_known(id: StringName) -> bool:
	return int(enemy_kills.get(id, 0)) > 0


func is_item_known(id: StringName) -> bool:
	return int(items_found.get(id, 0)) > 0


func is_achieved(a: AchievementData) -> bool:
	return achieved.has(a.id)


func progress(a: AchievementData) -> int:
	return mini(get_counter(a.counter), a.target)


func _check(counter: StringName) -> void:
	for a in achievements:
		if a.counter != counter or achieved.has(a.id) or get_counter(counter) < a.target:
			continue
		achieved[a.id] = int(Time.get_unix_time_from_system())
		if a.reward_shards > 0:
			MetaProgress.shards += a.reward_shards
			MetaProgress.save_progress()
		save_progress()
		EventBus.achievement_unlocked.emit(a)
