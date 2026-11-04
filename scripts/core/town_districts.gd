class_name TownDistricts
extends RefCounted
## Which districts of the town are open (data/districts): the ones open
## from the start, the ones whose prosperity / residents goal the town has
## reached, and any whose own building already stands. Derived from the
## TownState (nothing extra to save); TownState.flags["districts_open"]
## remembers what was announced in the news.


static func all() -> Array[DistrictData]:
	return ItemDatabase.districts


static func is_open(d: DistrictData, town: TownState) -> bool:
	if d.open_from_start or town == null:
		return d.open_from_start or town == null
	if d.prosperity > 0 and town.prosperity >= d.prosperity:
		return true
	if d.residents > 0 and town.residents.size() >= d.residents:
		return true
	if d.opens_with_building:
		for b in ItemDatabase.buildings:
			if b.slot >= d.x_from and b.slot < d.x_to and town.building_level(b.id) > 0:
				return true
	return false


static func of_x(x: int) -> DistrictData:
	for d in all():
		if x >= d.x_from and x < d.x_to:
			return d
	return null


static func of_building(b: BuildingData) -> DistrictData:
	return of_x(b.slot)


## Why a closed district is closed ("Процветание 14 или 2 жителя").
static func unlock_text(d: DistrictData) -> String:
	if d.unlock_text != "":
		return TranslationServer.translate(d.unlock_text)
	var parts: Array[String] = []
	if d.prosperity > 0:
		parts.append(TranslationServer.translate("процветание %d") % d.prosperity)
	if d.residents > 0:
		parts.append(TranslationServer.translate("жителей: %d") % d.residents)
	return TranslationServer.translate("Квартал откроется: %s") % TranslationServer.translate(" или ").join(parts)


## Districts newly open since the last visit (for the town's news); marks
## them announced.
static func newly_open(town: TownState) -> Array[DistrictData]:
	var out: Array[DistrictData] = []
	if town == null:
		return out
	var first_visit := not town.flags.has("districts_open")
	var known: Array = town.flags.get("districts_open", [])
	for d in all():
		if is_open(d, town) and not String(d.id) in known:
			known.append(String(d.id))
			if not d.open_from_start and not first_visit:
				out.append(d)  # (a town seen for the first time: no news, it was always so)
	town.flags["districts_open"] = known
	return out
