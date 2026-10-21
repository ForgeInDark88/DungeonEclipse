class_name SpriteSheetLayout
extends Resource
## Layout of an animated sprite sheet: one row per animation, one column per
## frame, every frame `frame_size` pixels. Any PNG drawn on this grid can be
## turned into SpriteFrames with build_frames(). See docs/ANIMATION_GUIDE.md.

@export var frame_size := Vector2i(32, 32)
## Pixel inside a frame that is placed at the node origin (usually the feet).
@export var origin := Vector2(16, 32)
## name -> {"row": int, "frames": int, "fps": float, "loop": bool}
@export var animations: Dictionary = {}
## Optional: name -> PackedVector2Array, hand position per frame relative to
## the origin (where held weapons / items are attached).
@export var hand_points: Dictionary = {}
## Optional: name -> PackedFloat32Array, held item angle per frame (degrees,
## 0 = pointing forward/right).
@export var hand_angles: Dictionary = {}

## texture -> SpriteFrames (per layout instance, freed with the resource).
var _cache: Dictionary = {}


func build_frames(texture: Texture2D) -> SpriteFrames:
	if texture == null:
		return null
	var key: Variant = texture.resource_path if texture.resource_path != "" else texture.get_instance_id()
	if _cache.has(key):
		return _cache[key]
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var tex_size := Vector2i(texture.get_size())
	for anim_name: String in animations:
		var a: Dictionary = animations[anim_name]
		var row := int(a.get("row", 0))
		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, float(a.get("fps", 8.0)))
		frames.set_animation_loop(anim_name, bool(a.get("loop", true)))
		for i in int(a.get("frames", 1)):
			var region := Rect2i(Vector2i(i * frame_size.x, row * frame_size.y), frame_size)
			if region.end.x > tex_size.x or region.end.y > tex_size.y:
				push_warning("Sheet %s is smaller than layout %s (anim %s)" % [texture.resource_path, resource_path, anim_name])
				break
			var at := AtlasTexture.new()
			at.atlas = texture
			at.region = Rect2(region)
			frames.add_frame(anim_name, at)
	_cache[key] = frames
	return frames


func has_animation(anim_name: String) -> bool:
	return animations.has(anim_name)


func duration(anim_name: String) -> float:
	var a: Dictionary = animations.get(anim_name, {})
	if a.is_empty():
		return 0.0
	return float(a.get("frames", 1)) / maxf(0.01, float(a.get("fps", 8.0)))


func hand_point(anim_name: String, frame: int) -> Vector2:
	var pts: PackedVector2Array = hand_points.get(anim_name, PackedVector2Array())
	if pts.is_empty():
		return Vector2(4, -12)
	return pts[clampi(frame, 0, pts.size() - 1)]


func hand_angle(anim_name: String, frame: int) -> float:
	var angs: PackedFloat32Array = hand_angles.get(anim_name, PackedFloat32Array())
	if angs.is_empty():
		return 20.0
	return angs[clampi(frame, 0, angs.size() - 1)]


## Configures an AnimatedSprite2D so that `origin` sits at the node origin.
func apply_to(sprite: AnimatedSprite2D, texture: Texture2D) -> void:
	sprite.sprite_frames = build_frames(texture)
	sprite.centered = false
	sprite.offset = -origin
