class_name TownResources
extends RefCounted
## Building materials of the town (TownState.resources): found in
## locations (mines, crates, bosses), spent on buildings (BuildingData.cost).
## Icons: assets/ui/res/<id>.png (tools/gen_placeholders.py loop).

const ALL := {
	&"wood": "Дерево",
	&"stone": "Камень",
	&"iron": "Железо",
	&"herbs": "Травы",
	&"crystal": "Лунный кристалл",
}


static func display_name(id: StringName) -> String:
	return TranslationServer.translate(ALL.get(id, String(id)))


static func icon(id: StringName) -> Texture2D:
	return AssetPaths.tex(AssetPaths.UI_DIR + "res/%s.png" % id)


## "Дерево 3, Железо 1" for a {id: amount} dictionary.
static func describe(amounts: Dictionary) -> String:
	var parts: Array[String] = []
	for k in amounts:
		if int(amounts[k]) != 0:
			parts.append("%s %d" % [display_name(StringName(k)), int(amounts[k])])
	return ", ".join(parts)
