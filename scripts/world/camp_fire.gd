class_name CampFire
extends Area2D
## A traveller's fire on the surface of a location (a small camp): E sits
## down by it - some health and mana back (once per fire), and the location
## is saved here (LocationManager save point; «Сохранить и выйти» is allowed
## next to it).

const HEAL_SHARE := 0.35

var used := false
var _light: PointLight2D


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("camp_fires")
	collision_layer = 16
	collision_mask = 0
	monitoring = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(24, 20)
	shape.shape = rect
	shape.position = Vector2(0, -10)
	add_child(shape)
	var s := Sprite2D.new()
	s.texture = AssetPaths.tex("res://assets/sprites/surface/campfire.png")
	s.offset = Vector2(0, -6)
	add_child(s)
	_light = PointLight2D.new()
	_light.texture = AssetPaths.tex(AssetPaths.LIGHT)
	_light.color = Color(1.0, 0.7, 0.4)
	_light.energy = 0.9
	_light.texture_scale = 0.6
	_light.position = Vector2(0, -8)
	add_child(_light)
	var tw := create_tween().set_loops()
	tw.tween_property(_light, "energy", 1.1, 0.4)
	tw.tween_property(_light, "energy", 0.8, 0.5)
	# the fire crackles, heard only when close
	var crackle := AudioStreamPlayer2D.new()
	var stream = load(AssetPaths.AMBIENCE[&"amb_fire"]) if ResourceLoader.exists(AssetPaths.AMBIENCE[&"amb_fire"]) else null
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
		crackle.stream = stream
		crackle.bus = &"SFX"
		crackle.volume_db = -6.0
		crackle.max_distance = 240.0
		crackle.attenuation = 1.6
		crackle.autoplay = true
		crackle.position = Vector2(0, -6)
		add_child(crackle)


func can_interact() -> bool:
	return true


func get_prompt() -> String:
	return tr("Присесть у костра: сохраниться") if used else tr("Присесть у костра: отдых и сохранение")


func interact(_player: Node) -> void:
	var hero: Hero = GameState.hero
	if hero and not used:
		used = true
		var st := hero.stats
		st.hp = mini(st.max_hp(), st.hp + roundi(st.max_hp() * HEAL_SHARE))
		st.hp_changed.emit(st.hp, st.max_hp())
		st.mana = mini(st.max_mana(), st.mana + roundi(st.max_mana() * HEAL_SHARE))
		st.mana_changed.emit(st.mana, st.max_mana())
		EventBus.message.emit(tr("Вы отдохнули у костра."))
	AudioManager.play_sfx(&"cast_heal", global_position, -6.0)
	var lm := get_tree().get_first_node_in_group("location_manager") as LocationManager
	if lm and not GameFlow.is_guest():
		lm.save_at_fire(global_position)
		EventBus.message.emit(tr("Локация сохранена у костра."))
