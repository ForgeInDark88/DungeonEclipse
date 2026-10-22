extends EventObject
## Altar of fate: offers three pacts (a blessing, usually tied to a curse)
## for the rest of the run. One can be taken; refusing keeps the altar.

const OFFERS := 3
## Chance that an offer is a blessing without a curse.
const PURE_CHANCE := 0.2

var _offers: Array = []  # [{"blessing": RunPactData, "curse": RunPactData or null}]


func setup_event(p_level: DungeonLevel, info: Dictionary) -> void:
	super(p_level, info)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(info.get("roll", 0)) + 77
	var floor_number := p_level.floor_number if p_level else 1
	var blessings := _pool(RunPactData.Kind.BLESSING, floor_number)
	var curses := _pool(RunPactData.Kind.CURSE, floor_number)
	for i in OFFERS:
		if blessings.is_empty():
			break
		var b: RunPactData = blessings.pop_at(rng.randi() % blessings.size())
		var c: RunPactData = null
		if not curses.is_empty() and rng.randf() >= PURE_CHANCE:
			c = curses.pop_at(rng.randi() % curses.size())
		_offers.append({"blessing": b, "curse": c})


## Pacts of one kind not taken yet this run.
func _pool(kind: RunPactData.Kind, floor_number: int) -> Array:
	return ItemDatabase.pacts.filter(func(p: RunPactData) -> bool:
		return p.kind == kind and p.min_floor <= floor_number and not GameState.pacts.has(p))


func get_prompt() -> String:
	return "Алтарь судьбы: выбрать дар"


func _activate(player: Node) -> bool:
	if _offers.is_empty():
		EventBus.message.emit("Алтарь молчит")
		return true
	var book := PactBook.new()
	get_tree().current_scene.add_child(book)
	book.open(_offers, func(offer: Dictionary) -> void: _take(offer, player))
	return false


func _take(offer: Dictionary, player: Node) -> void:
	GameState.add_pact(offer["blessing"])
	if offer["curse"]:
		GameState.add_pact(offer["curse"])
	Fx.sparks(get_parent(), global_position + Vector2(0, -12), Color(0.6, 0.7, 1.0), 26, 90.0)
	AudioManager.play_sfx(&"skill_cast", global_position)
	if player and is_instance_valid(player) and player.get("visual"):
		player.visual.flash(Color(0.6, 0.7, 1.0), 0.4)
	EventBus.message.emit("Судьба принята: %s" % (offer["blessing"] as RunPactData).display_name)
	finish()
