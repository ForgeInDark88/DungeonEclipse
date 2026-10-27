class_name ExitDoor
extends Area2D
## Passage to the next floor. Sealed until enough of the floor's monsters
## are dead (DungeonLevel seal): the portal is dark and chained, the prompt
## shows the count, and it bursts open when the seal breaks.

var _sealed := false
var _kills := 0
var _required := 0
var _seal_fx: Node2D
@onready var _portal: AnimatedSprite2D = $Portal
@onready var _light: PointLight2D = $PointLight2D


func _ready() -> void:
	add_to_group("interactable")
	AssetPaths.layout(AssetPaths.PORTAL_LAYOUT).apply_to(_portal, AssetPaths.tex(AssetPaths.PORTAL_SHEET))
	_portal.play(&"swirl")
	# Pulsing portal light.
	var tw := create_tween().set_loops()
	tw.tween_property(_light, "energy", 1.4, 0.8).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_light, "energy", 0.6, 0.8).set_trans(Tween.TRANS_SINE)
	EventBus.seal_changed.connect(_on_seal_changed)
	var level := get_parent()
	while level != null and not (level is DungeonLevel):
		level = level.get_parent()
	if level != null:
		_on_seal_changed(level.seal_kills, level.seal_required, true)


func _on_seal_changed(kills: int, required: int, initial := false) -> void:
	_kills = kills
	_required = required
	var sealed := required > 0 and kills < required
	if sealed == _sealed and not initial:
		return
	var was := _sealed
	_sealed = sealed
	if sealed:
		_portal.modulate = Color(0.45, 0.25, 0.3)
		_portal.speed_scale = 0.3
		_light.color = Color(0.9, 0.25, 0.3)
		if _seal_fx == null:
			_seal_fx = SealChains.new()
			_seal_fx.position = Vector2(0, -16)
			add_child(_seal_fx)
	else:
		_portal.speed_scale = 1.0
		_light.color = Color(0.7, 0.4, 1.0)
		if _seal_fx:
			_seal_fx.queue_free()
			_seal_fx = null
		if was:
			var tw := create_tween()
			_portal.modulate = Color(2.0, 1.6, 2.4)
			tw.tween_property(_portal, "modulate", Color.WHITE, 0.6)
			Fx.sparks(get_parent(), global_position + Vector2(0, -16), Color(0.75, 0.45, 1.0), 26, 110.0)
			EventBus.screen_shake.emit(3.0)
		else:
			_portal.modulate = Color.WHITE


func get_prompt() -> String:
	if _sealed:
		return "Выход запечатан: убито %d из %d" % [_kills, _required]
	return "Спуститься глубже (этаж %d)" % (GameState.floor_number + 1)


func interact(player: Node) -> void:
	if _sealed:
		EventBus.message.emit("Печать держится: нужно убить ещё %d врагов" % (_required - _kills))
		AudioManager.play_sfx(&"dig", global_position, -6.0)
		return
	AudioManager.play_sfx(&"portal")
	if Net.active and not Net.is_host:
		var ns := get_tree().get_first_node_in_group("net_game") as NetSync
		if ns:
			ns.request_floor.rpc_id(1, &"next")
		return
	if Net.active and Net.is_host:
		# Co-op: the whole living party must be gathered at the door.
		var ns := get_tree().get_first_node_in_group("net_game") as NetSync
		if ns and not ns.party_at(player.global_position, 220.0):
			EventBus.message.emit("Все живые герои должны подойти к выходу!")
			return
	GameState.next_floor()


## Red chains across the sealed portal with a glowing lock rune.
class SealChains extends Node2D:
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var pulse := 0.6 + 0.4 * sin(_t * 3.0)
		var chain := Color(0.55, 0.5, 0.55)
		for k in 2:
			var a := Vector2(-11, -12 + k * 18)
			var b := Vector2(11, -4 + k * 2)
			if k == 1:
				a = Vector2(-11, -2)
				b = Vector2(11, -14)
			var steps := 7
			for i in steps + 1:
				var p := a.lerp(b, float(i) / steps)
				draw_rect(Rect2(p - Vector2(1, 1), Vector2(3, 2)), chain if i % 2 == 0 else chain.darkened(0.3))
		draw_circle(Vector2(0, -8), 4.0, Color(0.25, 0.05, 0.08))
		draw_arc(Vector2(0, -8), 4.0, 0.0, TAU, 12, Color(1.0, 0.3, 0.3, pulse), 1.0)
		draw_rect(Rect2(Vector2(-1, -10), Vector2(2, 4)), Color(1.0, 0.45, 0.4, pulse))
