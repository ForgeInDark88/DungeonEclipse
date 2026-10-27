extends EventObject
## Blood altar: sacrifice 20% of max HP for a random reward.

const SACRIFICE := 0.2


func get_prompt() -> String:
	return "Принести жертву: −%d%% здоровья за дар" % roundi(SACRIFICE * 100)


func can_activate(player: Node) -> bool:
	var hero: Hero = player.hero
	if hero.stats.hp <= roundi(hero.stats.max_hp() * SACRIFICE) + 1:
		EventBus.message.emit("Слишком мало крови для жертвы")
		return false
	return true


func _activate(player: Node) -> bool:
	var hero: Hero = player.hero
	var cost := roundi(hero.stats.max_hp() * SACRIFICE)
	if hero.stats.hp <= cost + 1:
		EventBus.message.emit("Слишком мало крови для жертвы")
		return false
	hero.stats.lose_hp(cost)
	player.visual.flash(Color(0.8, 0.1, 0.1), 0.4)
	Fx.sparks(get_parent(), global_position + Vector2(0, -12), Color(0.9, 0.1, 0.2), 24, 90.0)
	AudioManager.play_sfx(&"skill_cast", global_position)
	var roll := randf()
	if roll < 0.4:
		_reward_item(&"special", level.floor_number if level else 1)
		EventBus.message.emit("Алтарь принимает жертву и дарит сокровище")
	elif roll < 0.7:
		var stat: String = StatTypes.PRIMARY.pick_random()
		var key := "altar_%d" % Time.get_ticks_msec()
		hero.stats.set_modifier(key, {stat: 2})
		EventBus.message.emit("Дар алтаря: %s +2 до конца забега" % StatTypes.label(stat))
	else:
		var gold := 40 + 15 * (level.floor_number if level else 1)
		hero.add_gold(gold)
		EventBus.message.emit("Алтарь дарит %d золота" % gold)
	return true
