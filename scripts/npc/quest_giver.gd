class_name QuestGiver
extends Area2D
## The guild herald on the town street: hands out the run's quest chain.
## Interact opens the quest book; finished quests are claimed here.

@onready var _sprite: Sprite2D = $Sprite


func _ready() -> void:
	add_to_group("interactable")
	collision_layer = 16
	collision_mask = 0
	monitoring = false
	# A slow lamp flicker keeps the herald alive without moving his feet.
	var light: PointLight2D = $PointLight2D
	var tw := create_tween().set_loops()
	tw.tween_property(light, "energy", 1.05, 1.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(light, "energy", 0.75, 1.6).set_trans(Tween.TRANS_SINE)


func get_prompt() -> String:
	if GameState.quests.all_done():
		return "Глашатай гильдии"
	if GameState.quests.is_done():
		return "Сдать задание глашатаю"
	return "Приказы гильдии"


func interact(_player: Node) -> void:
	AudioManager.play_ui(&"ui_book_open")
	EventBus.quest_requested.emit(self, _player)
