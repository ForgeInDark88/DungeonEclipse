class_name TooltipText
extends RefCounted
## Builds BBCode for item, skill and hero tooltips.


static func _c(color: Color, text: String) -> String:
	return "[color=#%s]%s[/color]" % [color.to_html(false), text]


static func item(item: ItemData, hero: Hero, is_equipped := false) -> String:
	var lines: Array[String] = []
	lines.append("[font_size=10][b]%s[/b][/font_size]" % _c(item.rarity_color().darkened(0.35), item.display_name))
	lines.append(_c(UIStyle.INK_SOFT, "%s · %s" % [item.rarity_name(), item.subtitle()]))
	if item.description != "":
		lines.append("[i]%s[/i]" % item.description)

	var compare_to: EquipmentItemData = null
	if hero and item is EquipmentItemData and not is_equipped:
		compare_to = hero.equipment.compare_target(item)
	var keys: Array = item.stat_bonuses.keys()
	if compare_to:
		for k in compare_to.stat_bonuses:
			if k not in keys:
				keys.append(k)
	if not keys.is_empty():
		lines.append("")
	for k: String in keys:
		var v := float(item.stat_bonuses.get(k, 0.0))
		var line := "%s: %s" % [StatTypes.label(k), StatTypes.format_value(k, v, true)]
		if compare_to:
			var diff := v - float(compare_to.stat_bonuses.get(k, 0.0))
			if absf(diff) > 0.0001:
				var col := UIStyle.GOOD if diff > 0.0 else UIStyle.BAD
				line += "  " + _c(col, "(%s)" % StatTypes.format_value(k, diff, true))
		lines.append(line)
	if compare_to:
		lines.append(_c(UIStyle.INK_SOFT, "Сравнение с: %s" % compare_to.display_name))
	elif hero and item is EquipmentItemData and not is_equipped:
		lines.append(_c(UIStyle.GOOD, "Слот свободен"))

	if item is UsableItemData:
		for effect in (item as UsableItemData).effects:
			if effect and effect.describe() != "":
				lines.append(_c(UIStyle.GOOD, "• " + effect.describe()))
	if item.max_stack > 1:
		lines.append(_c(UIStyle.INK_SOFT, "Стак: до %d" % item.max_stack))
	lines.append("")
	if is_equipped:
		lines.append(_c(UIStyle.INK_SOFT, "ПКМ — снять"))
	elif item is EquipmentItemData:
		lines.append(_c(UIStyle.INK_SOFT, "ПКМ / двойной клик — надеть"))
	elif item is UsableItemData:
		lines.append(_c(UIStyle.INK_SOFT, "ПКМ / двойной клик — использовать"))
	return "\n".join(lines)


static func skill(skill: SkillData, level: int, hero_points: int) -> String:
	var lines: Array[String] = []
	lines.append("[font_size=10][b]%s[/b][/font_size]" % skill.display_name)
	lines.append(_c(UIStyle.INK_SOFT, "Уровень %d/%d · Мана %d · Перезарядка %.1f с" % [level, skill.max_level, skill.mana_cost, skill.cooldown]))
	if skill.description != "":
		lines.append("[i]%s[/i]" % skill.description)
	if skill.effect:
		lines.append(_c(UIStyle.GOOD, "• " + skill.effect.describe(level)))
		if level < skill.max_level:
			lines.append(_c(UIStyle.INK_SOFT, "След. ур.: " + skill.effect.describe(level + 1)))
	if hero_points > 0 and level < skill.max_level:
		lines.append(_c(UIStyle.GOOD, "Клик — улучшить (очков: %d)" % hero_points))
	return "\n".join(lines)


static func hero_stats(hero: Hero) -> String:
	var s := hero.stats
	var lines: Array[String] = []
	lines.append("[font_size=10][b]%s %s[/b][/font_size]" % [hero.race.display_name, hero.class_data.display_name])
	lines.append(_c(UIStyle.INK_SOFT, "Уровень %d · Опыт %d/%d · Очки навыков: %d" % [hero.level, hero.xp, hero.xp_to_next(), hero.skills.skill_points]))
	lines.append("")
	for stat in StatTypes.PRIMARY:
		lines.append("%s: [b]%s[/b]" % [StatTypes.label(stat), StatTypes.format_value(stat, s.get_value(stat))])
	lines.append("")
	lines.append("Здоровье: [b]%d / %d[/b]" % [s.hp, s.max_hp()])
	lines.append("Мана: [b]%d / %d[/b]" % [s.mana, s.max_mana()])
	for stat in [StatTypes.DAMAGE, StatTypes.ARMOR, StatTypes.SPEED, StatTypes.CRIT_CHANCE]:
		lines.append("%s: [b]%s[/b]" % [StatTypes.label(stat), StatTypes.format_value(stat, s.get_value(stat))])
	lines.append("")
	lines.append(_c(UIStyle.INK_SOFT, "Этаж %d · Убито врагов: %d" % [GameState.floor_number, GameState.kills]))
	return "\n".join(lines)
