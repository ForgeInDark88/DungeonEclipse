class_name CheatOrb
extends Area2D
## TEST ONLY (will be removed): a glowing orb in the town - click it and the
## hero jumps straight to level 30 (full xp flow: level-up sounds, points).

const TARGET_LEVEL := 30


func _ready() -> void:
	add_to_group("interactable")
	collision_layer = 16  # the player's interact area scans this layer
	collision_mask = 0
	input_pickable = true
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(30, 34)
	shape.shape = rect
	shape.position = Vector2(0, -14)
	add_child(shape)
	var s := Sprite2D.new()
	s.texture = load("res://assets/sprites/fx/rune_orb.png")
	s.position = Vector2(0, -12)
	s.z_index = 8
	add_child(s)
	var light := PointLight2D.new()
	light.texture = AssetPaths.tex(AssetPaths.LIGHT)
	light.color = Color(0.75, 0.55, 1.0)
	light.energy = 1.4
	light.texture_scale = 0.5
	light.position = Vector2(0, -12)
	add_child(light)
	var tw := create_tween().set_loops()
	tw.tween_property(s, "position:y", -15.0, 0.9).set_trans(Tween.TRANS_SINE)
	tw.tween_property(s, "position:y", -9.0, 0.9).set_trans(Tween.TRANS_SINE)
	input_event.connect(_on_click)


## Both work: walk up and press the interact key, or just click the orb.
func get_prompt() -> String:
	return "Тест: выдать %d уровень" % TARGET_LEVEL


func can_interact() -> bool:
	return true


func interact(_player: Node) -> void:
	_grant()


func _on_click(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	_grant()


func _grant() -> void:
	var hero := GameState.hero
	if hero == null:
		return
	while hero.level < TARGET_LEVEL:
		hero.add_xp(hero.xp_to_next() - hero.xp + 1)
	EventBus.message.emit("Тест: уровень %d!" % hero.level)
	EventBus.screen_shake.emit(2.0)
	AudioManager.play_sting(&"victory", &"menu")
