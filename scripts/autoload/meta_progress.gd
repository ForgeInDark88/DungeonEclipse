extends Node
## Meta progression between runs (Sanctum of the Eclipse): eclipse shards and
## banked gold earned at the end of every run buy permanent upgrades
## (data/meta/*.tres) and unlock races / classes (RaceData/ClassData.unlock_*).
## Stored in the [sanctum] section of user://meta.cfg (SaveManager owns [meta]).

signal changed

const META_DIR := "res://data/meta"
const SECTION := "sanctum"
## Share of the run's collected gold that goes to the Sanctum bank.
const GOLD_BANK_SHARE := 0.25
## Shards for depth: one per this many floors reached.
const FLOORS_PER_SHARD := 2
const SHARDS_PER_BOSS := 3
## Item id of the shard pickup (elites drop it, see EliteAffixData.shard_drop).
const SHARD_ITEM := &"eclipse_shard"

var shards: int = 0
var gold: int = 0
## upgrade id -> level
var levels: Dictionary = {}
## Ids of bought races / classes.
var unlocked: Array[StringName] = []
var upgrades: Array[MetaUpgradeData] = []
## When false, upgrades are never applied (tests keep runs independent of the player's save).
var apply_upgrades := true


func _ready() -> void:
	for res in ItemDatabase.load_dir(META_DIR):
		if res is MetaUpgradeData:
			upgrades.append(res)
	upgrades.sort_custom(func(a: MetaUpgradeData, b: MetaUpgradeData) -> bool: return a.order < b.order)
	load_progress()


func load_progress() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SaveManager.META_PATH) != OK:
		return
	shards = cfg.get_value(SECTION, "shards", 0)
	gold = cfg.get_value(SECTION, "gold", 0)
	levels = cfg.get_value(SECTION, "levels", {})
	unlocked.assign(cfg.get_value(SECTION, "unlocked", []))


func save_progress() -> void:
	var cfg := ConfigFile.new()
	if FileAccess.file_exists(SaveManager.META_PATH):
		cfg.load(SaveManager.META_PATH)  # keep the other sections
	cfg.set_value(SECTION, "shards", shards)
	cfg.set_value(SECTION, "gold", gold)
	cfg.set_value(SECTION, "levels", levels)
	cfg.set_value(SECTION, "unlocked", Array(unlocked))
	cfg.save(SaveManager.META_PATH)


## Wipes the Sanctum (tests).
func reset() -> void:
	shards = 0
	gold = 0
	levels = {}
	unlocked.clear()
	changed.emit()


func level_of(id: StringName) -> int:
	return int(levels.get(id, 0))


func can_afford(shard_cost: int, gold_cost: int) -> bool:
	return shards >= shard_cost and gold >= gold_cost


func _pay(shard_cost: int, gold_cost: int) -> bool:
	if not can_afford(shard_cost, gold_cost):
		return false
	shards -= shard_cost
	gold -= gold_cost
	return true


func buy_upgrade(up: MetaUpgradeData) -> bool:
	var next := level_of(up.id) + 1
	if next > up.max_level or not _pay(up.shard_cost(next), up.gold_cost(next)):
		return false
	levels[up.id] = next
	save_progress()
	changed.emit()
	return true


## `what` is a RaceData or ClassData.
func is_unlocked(what: Resource) -> bool:
	return (what.unlock_shards <= 0 and what.unlock_gold <= 0) or what.id in unlocked


func unlock(what: Resource) -> bool:
	if is_unlocked(what) or not _pay(what.unlock_shards, what.unlock_gold):
		return false
	unlocked.append(what.id)
	save_progress()
	changed.emit()
	return true


## Stat bonuses of all bought upgrades (Stats modifier "meta").
func stat_bonuses() -> Dictionary:
	var total := {}
	for up in upgrades:
		var lv := level_of(up.id)
		for k in up.stat_bonuses:
			total[k] = float(total.get(k, 0.0)) + float(up.stat_bonuses[k]) * lv
	return total


## Applies bought upgrades to a freshly created hero. Daily runs pass
## `use_upgrades = false`: an equal start for everybody.
func apply_to(hero: Hero, use_upgrades := true) -> void:
	if not apply_upgrades or not use_upgrades:
		return
	hero.stats.set_modifier("meta", stat_bonuses())
	for up in upgrades:
		var lv := level_of(up.id)
		if lv <= 0:
			continue
		if up.start_gold > 0:
			hero.gold += up.start_gold * lv
		for item_id: StringName in up.starting_items:
			var item := ItemDatabase.get_item(item_id)
			if item:
				var n := int(up.starting_items[item_id]) * lv
				if item.is_stackable():
					hero.inventory.add_item(item, n)
				else:
					for i in n:
						hero.inventory.add_item(ItemFactory.create(item))
	hero.stats.hp = hero.stats.max_hp()
	hero.stats.mana = hero.stats.max_mana()
	hero.stats.recalculate()


## Rewards for a finished run; adds them to the Sanctum and saves.
## Returns {"shards": int, "gold": int, "parts": Array[String]} for the death screen.
func finish_run(hero: Hero, floor_reached: int, stats: Dictionary) -> Dictionary:
	var parts: Array[String] = []
	var from_items := 0
	if hero:
		for stack in hero.inventory.slots:
			if stack and stack.item.shard_value > 0:
				from_items += stack.item.shard_value * stack.count
	if from_items > 0:
		parts.append("осколки и печати: %d" % from_items)
	var from_depth := floor_reached / FLOORS_PER_SHARD
	if from_depth > 0:
		parts.append("глубина: %d" % from_depth)
	var from_bosses := int(stats.get("bosses", 0)) * SHARDS_PER_BOSS
	if from_bosses > 0:
		parts.append("стражи: %d" % from_bosses)
	var s := from_items + from_depth + from_bosses
	var g := roundi(int(stats.get("gold", 0)) * GOLD_BANK_SHARE)
	shards += s
	gold += g
	save_progress()
	changed.emit()
	return {"shards": s, "gold": g, "parts": parts}
