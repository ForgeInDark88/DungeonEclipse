extends EventObject
## Prisoner in a cage: free them for a reward... unless it is a trap.

const TRAP_CHANCE := 0.15


func get_prompt() -> String:
	return "Освободить узника"


func _activate(player: Node) -> bool:
	used_anim = &"open"
	AudioManager.play_sfx(&"chest_locked", global_position)
	if randf() < TRAP_CHANCE:
		EventBus.message.emit("«Спасибо, глупец!» — это была ловушка!")
		_ambush(1, 1.0)
		return true
	var hero: Hero = player.hero
	match randi() % 3:
		0:
			var gold := 30 + 10 * (level.floor_number if level else 1)
			hero.add_gold(gold)
			EventBus.message.emit("Узник благодарит и отдаёт %d золота" % gold)
		1:
			_reward_item(&"special", level.floor_number if level else 1)
			EventBus.message.emit("Узник отдаёт припрятанное снаряжение")
		2:
			hero.add_xp(20 + 5 * (level.floor_number if level else 1))
			player.status.apply(&"regen", 10.0, 2.0)
			EventBus.message.emit("Узник делится знаниями о подземелье")
	Fx.sparks(get_parent(), global_position + Vector2(0, -12), Color(1.0, 0.9, 0.5), 16, 60.0)
	return true
