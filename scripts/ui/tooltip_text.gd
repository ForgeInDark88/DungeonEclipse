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
	if item is WeaponItemData:
		lines.append_array(_weapon_lines(item as WeaponItemData, compare_to as WeaponItemData, hero))
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
	if item.has_durability and item.is_instance():
		var low := item.durability <= item.max_durability / 5
		var dur_text := "Прочность: %d / %d" % [item.durability, item.max_durability]
		if item.is_broken():
			dur_text += " — СЛОМАНО (нужен ремонт)"
		lines.append(_c(UIStyle.BAD if low else UIStyle.INK_SOFT, dur_text))
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


## Damage per second the hero would have with this weapon.
static func weapon_dps(w: WeaponItemData, hero: Hero) -> float:
	if hero == null:
		return w.effective_damage() * w.attack_speed
	var current := hero.weapon()
	var stats := hero.stats
	# Main attribute scaling, without the bonuses of the currently held weapon.
	var main := stats.get_value(hero.class_data.main_attribute)
	if current:
		main -= float(current.active_bonuses().get(hero.class_data.main_attribute, 0.0))
	main += float(w.active_bonuses().get(hero.class_data.main_attribute, 0.0))
	var dmg := w.effective_damage() * (1.0 + main * Stats.DAMAGE_PER_MAIN_ATTR)
	var speed := w.attack_speed
	if not hero.class_data.allows_weapon(w):
		dmg *= ClassData.WRONG_WEAPON_DAMAGE
		speed *= ClassData.WRONG_WEAPON_SPEED
	return dmg * speed


static func _diff(value: float, other: float, fmt: String) -> String:
	var d := value - other
	if absf(d) < 0.005:
		return ""
	return "  " + _c(UIStyle.GOOD if d > 0.0 else UIStyle.BAD, "(" + ("+" if d > 0.0 else "") + fmt % d + ")")


static func _weapon_lines(w: WeaponItemData, other: WeaponItemData, hero: Hero) -> Array[String]:
	var lines: Array[String] = [""]
	var has_other := other != null
	lines.append("Урон оружия: [b]%.1f[/b]%s" % [w.effective_damage(),
			_diff(w.effective_damage(), other.effective_damage(), "%.1f") if has_other else ""])
	lines.append("Скорость: %.2f уд/с%s" % [w.attack_speed, _diff(w.attack_speed, other.attack_speed, "%.2f") if has_other else ""])
	var dps := weapon_dps(w, hero)
	lines.append("DPS: [b]%.1f[/b]%s" % [dps, _diff(dps, weapon_dps(other, hero), "%.1f") if has_other else ""])
	var reach_label := "Дальность" if not w.is_ranged() else "Дальность выстрела"
	lines.append("%s: %d%s" % [reach_label, roundi(w.reach), _diff(w.reach, other.reach, "%.0f") if has_other else ""])
	lines.append("Тип урона: %s" % _c(w.damage_color().darkened(0.45), WeaponItemData.DAMAGE_TYPE_NAMES[w.damage_type]))
	if w.knockback >= 180.0:
		lines.append(_c(UIStyle.INK_SOFT, "Сильный отброс"))
	for a in w.affixes:
		var label: String = (a.prefix_forms.get(w.gender, a.prefix_forms.get("m", "")) if a.is_prefix() else a.suffix).capitalize()
		lines.append(_c(Color(0.45, 0.25, 0.65), "◆ %s: %s" % [label, a.description]))
	for e in w.on_hit_effects:
		if e and e.describe() != "":
			lines.append(_c(UIStyle.GOOD, "• При попадании: " + e.describe()))
	if hero and not hero.class_data.allows_weapon(w):
		lines.append(_c(UIStyle.BAD, "%s плохо владеет этим оружием: −%d%% урона, −%d%% скорости" % [hero.class_data.display_name,
				roundi((1.0 - ClassData.WRONG_WEAPON_DAMAGE) * 100), roundi((1.0 - ClassData.WRONG_WEAPON_SPEED) * 100)]))
	elif hero:
		lines.append(_c(UIStyle.GOOD, "Подходит классу %s" % hero.class_data.display_name))
	return lines


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
	var res: Array[String] = []
	for r in StatTypes.RESISTANCES:
		if s.get_value(r) > 0.0:
			res.append("%s %s" % [StatTypes.label(r), StatTypes.format_value(r, s.get_value(r))])
	if not res.is_empty():
		lines.append(", ".join(res))
	lines.append("")
	lines.append(_c(UIStyle.INK_SOFT, "Этаж %d · Убито врагов: %d" % [GameState.floor_number, GameState.kills]))
	return "\n".join(lines)
