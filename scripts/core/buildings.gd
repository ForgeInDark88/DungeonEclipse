class_name Buildings
extends RefCounted
## Rules of the town's buildings (data/buildings) and what their levels and
## the residents give: costs (the mason makes them cheaper), requirements
## (a resident, a guardian, a blueprint), building and upgrading, prices,
## the warehouse and the hall of fame, bonuses carried into an expedition.

const RESIDENT_PROSPERITY := 2
const BOSS_PROSPERITY := 5
## Hall of fame: each trophy on display gives this much to every hero.
const TROPHY_HP := 4
const TROPHY_DAMAGE := 1


## A new town: start levels and the people who never left.
static func init_town(town: TownState) -> void:
	for b in ItemDatabase.buildings:
		town.buildings[String(b.id)] = b.start_level
	for id in ItemDatabase.npcs:
		var n: NpcData = ItemDatabase.npcs[id]
		if n.resident_from_start:
			town.add_resident(n.id)
	town.prosperity = prosperity(town)


static func town() -> TownState:
	return GameState.town


static func level(id: StringName) -> int:
	return town().building_level(id) if town() else 0


## Cost of level `lvl` of `b` with the residents' discounts.
static func cost(b: BuildingData, lvl: int) -> Dictionary:
	if lvl < 1 or lvl > b.costs.size():
		return {}
	var mult := 1.0 - build_discount()
	var out := {}
	var base: Dictionary = b.costs[lvl - 1]
	for k in base:
		out[k] = maxi(0 if int(base[k]) == 0 else 1, roundi(int(base[k]) * mult))
	return out


static func build_discount() -> float:
	var d := 0.0
	var t := town()
	if t:
		for id in t.residents:
			var n: NpcData = ItemDatabase.npcs.get(id)
			if n:
				d += n.build_discount
	return minf(d, 0.5)


## "" when the next level of `b` can be built now, else why not.
static func block_reason(b: BuildingData) -> String:
	var t := town()
	var next := t.building_level(b.id) + 1
	if next > b.max_level:
		return TranslationServer.translate("Построено полностью")
	var miss := requirement_missing(b, next)
	if miss != "":
		return miss
	var c := cost(b, next)
	var lack: Array[String] = []
	var hero := GameState.hero
	if int(c.get("gold", 0)) > (hero.gold if hero else 0):
		lack.append(TranslationServer.translate("золото %d") % (int(c["gold"]) - (hero.gold if hero else 0)))
	for k in c:
		if k != "gold" and t.resource(StringName(k)) < int(c[k]):
			lack.append("%s %d" % [TownResources.display_name(StringName(k)), int(c[k]) - t.resource(StringName(k))])
	if not lack.is_empty():
		return TranslationServer.translate("Не хватает: %s") % ", ".join(lack)
	return ""


## The resident / guardian / blueprint level `lvl` needs ("" = all there).
static func requirement_missing(b: BuildingData, lvl: int) -> String:
	var t := town()
	if lvl == 1 and b.requires_resident != &"" and not t.has_resident(b.requires_resident):
		var n: NpcData = ItemDatabase.npcs.get(b.requires_resident)
		return TranslationServer.translate("Нужен мастер: %s (%s). Ищите пленников в походах.") % [
			n.display_name if n else String(b.requires_resident), n.profession if n else ""]
	var boss_lvl := b.boss_level if b.boss_level > 0 else b.max_level
	if b.requires_boss != &"" and lvl >= boss_lvl and not b.requires_boss in t.bosses_defeated:
		var bd := ItemDatabase.boss_by_id(b.requires_boss)
		return TranslationServer.translate("Сначала победите стража: %s") % (bd.display_name if bd else String(b.requires_boss))
	if b.blueprint_level > 0 and lvl >= b.blueprint_level and not b.id in t.blueprints:
		return TranslationServer.translate("Нужен чертёж (его хранят стражи и логова)")
	return ""


## Builds / upgrades `b` one level: pays, levels up, saves. False if blocked.
static func build(b: BuildingData) -> bool:
	if block_reason(b) != "":
		return false
	var t := town()
	var next := t.building_level(b.id) + 1
	var c := cost(b, next)
	GameState.hero.gold -= int(c.get("gold", 0))
	GameState.hero.gold_changed.emit(GameState.hero.gold)
	for k in c:
		if k != "gold":
			t.add_resource(StringName(k), -int(c[k]))
	t.set_building_level(b.id, next)
	t.prosperity = prosperity(t)
	t.news.append(TranslationServer.translate("Построено: %s, уровень %d") % [b.display_name, next])
	return true


static func prosperity(t: TownState) -> int:
	var p := 0
	for b in ItemDatabase.buildings:
		p += maxi(0, t.building_level(b.id) - b.start_level) * b.prosperity
	p += t.residents.size() * RESIDENT_PROSPERITY + t.bosses_defeated.size() * BOSS_PROSPERITY + t.trophies.size()
	p += int(t.stats.get("refugees", 0))
	return p


# ------------------------------------------------------------- effects
## Shop prices: residents' discounts and the big shop.
static func price_mult() -> float:
	var t := town()
	if t == null or not GameState.expedition:
		return 1.0
	var d := 0.0
	for id in t.residents:
		var n: NpcData = ItemDatabase.npcs.get(id)
		if n:
			d += n.discount
	if level(&"shop") >= 3:
		d += 0.1
	return clampf(1.0 - d, 0.6, 1.0)


## Gold the smith asks: cheaper with every smithy level past the first.
static func smith_mult() -> float:
	if town() == null or not GameState.expedition:
		return 1.0
	return 1.0 - 0.15 * maxi(0, level(&"smithy") - 1)


static func warehouse_slots() -> int:
	return 4 * level(&"warehouse")


static func trophy_slots() -> int:
	return 3 * level(&"hall")


## Experience multiplier (library level 3).
static func xp_mult() -> float:
	return 1.1 if town() and GameState.expedition and level(&"library") >= 3 else 1.0


## Depth of the goods in the town shop: the regions the town has opened.
static func shop_depth() -> int:
	var t := town()
	if t == null:
		return 1
	var r: int = mini(t.region_unlocked, ItemDatabase.regions.size() - 1)
	var reg: RegionData = ItemDatabase.regions[r] if not ItemDatabase.regions.is_empty() else null
	var d := reg.depth_from if reg else 1
	return d + (3 if level(&"shop") >= 2 else 0)


## The hall's trophies as a stat bonus (set on the hero in town and before
## every expedition).
static func apply_trophies(hero: Hero) -> void:
	var t := town()
	if hero == null or t == null:
		return
	var n := t.trophies.size()
	hero.stats.set_modifier("trophies", {StatTypes.MAX_HP: TROPHY_HP * n, StatTypes.DAMAGE: TROPHY_DAMAGE * n} if n > 0 else {})


## Gifts of the town for the road (called when an expedition begins).
static func on_expedition_start(hero: Hero) -> void:
	if hero == null:
		return
	apply_trophies(hero)
	if level(&"temple") >= 3:
		hero.stats.set_modifier("blessing", {StatTypes.MAX_HP: roundi(hero.stats.max_hp() * 0.1)})
		hero.stats.hp = hero.stats.max_hp()
	if level(&"alchemist") >= 3:
		var potion := ItemDatabase.get_item(&"health_potion")
		if potion:
			hero.inventory.add_item(potion, 1)


## The road is over: the temple's blessing fades, the hired companion leaves.
static func on_expedition_end(hero: Hero) -> void:
	if hero:
		hero.stats.set_modifier("blessing", {})
	GameState.set_pet(null)


# -------------------------------------------------------------- day / night
## The town's time of day moves on with every expedition: morning, day,
## evening, night (lamps and windows glow brighter at night).
const PHASES := ["Утро", "День", "Вечер", "Ночь"]
const PHASE_TINT := [Color(1.0, 0.93, 0.86), Color(1.0, 1.0, 1.0), Color(1.0, 0.78, 0.62), Color(0.5, 0.55, 0.85)]


static func day_phase() -> int:
	var t := town()
	return int(t.stats.get("expeditions", 0)) % PHASES.size() if t else 1


static func is_night() -> bool:
	return GameState.expedition and GameState.is_town() and day_phase() == 3


static func phase_name() -> String:
	return TranslationServer.translate(PHASES[day_phase()])
