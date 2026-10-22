extends EventObject
## Cursed chest: double epic loot, but the opener is cursed and monsters
## jump out.


func _ready() -> void:
	super()
	sprite.modulate = Color(0.75, 0.5, 1.0)
	var p := CPUParticles2D.new()
	p.amount = 12
	p.lifetime = 1.2
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(7, 4)
	p.direction = Vector2.UP
	p.gravity = Vector2(0, -30)
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 15.0
	p.color = Color(0.7, 0.3, 1.0, 0.8)
	p.position = Vector2(0, -8)
	add_child(p)


func get_prompt() -> String:
	return "Открыть проклятый сундук (риск!)"


func _activate(player: Node) -> bool:
	sprite.play(&"opening")
	AudioManager.play_sfx(&"chest_open", global_position)
	var f := level.floor_number if level else 1
	_reward_item(&"special", f)
	_reward_item(&"special", f + 2)  # the curse pays off: one roll as if deeper
	player.status.apply(&"curse", 30.0, 1.0)
	EventBus.message.emit("Проклятие! Из тьмы лезут твари")
	_ambush(2 + f / 3, 0.5)
	return true
