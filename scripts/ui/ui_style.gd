class_name UIStyle
extends RefCounted
## Colors and small factories for the "book" UI style.

const INK := Color(0.25, 0.14, 0.08)
const INK_SOFT := Color(0.42, 0.29, 0.18)
const PARCHMENT := Color(0.96, 0.85, 0.59)
const GOLD := Color(0.96, 0.86, 0.3)
const GOOD := Color(0.15, 0.55, 0.15)
const BAD := Color(0.75, 0.15, 0.12)
const GOOD_HEX := "#1f8a1f"
const BAD_HEX := "#b3261e"
const INK_HEX := "#40240f"

const SLOT_SIZE := Vector2(26, 26)


static func frame(path: String, margin: int, pixel_scale: float = 1.0) -> PixelFrame:
	var f := PixelFrame.new()
	f.texture = AssetPaths.tex(path)
	f.margin = margin
	f.pixel_scale = pixel_scale
	f.set_anchors_preset(Control.PRESET_FULL_RECT)
	return f


static func label(text: String, font_size: int = 8, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Light text with a dark outline, readable over the game.
static func outlined_label(text: String, font_size: int = 8, color: Color = PARCHMENT) -> Label:
	var l := label(text, font_size, color)
	l.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.03))
	l.add_theme_constant_override("outline_size", 3)
	return l


static func texture_box(path: String, margin: int) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = AssetPaths.tex(path)
	sb.texture_margin_left = margin
	sb.texture_margin_top = margin
	sb.texture_margin_right = margin
	sb.texture_margin_bottom = margin
	sb.content_margin_left = margin + 2
	sb.content_margin_top = margin + 1
	sb.content_margin_right = margin + 2
	sb.content_margin_bottom = margin + 1
	return sb


static func portrait(race: RaceData, class_data: ClassData, size_px: Vector2) -> Control:
	var root := Control.new()
	root.custom_minimum_size = size_px
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var layers: Array = [race.portrait if race else null, class_data.portrait_overlay if class_data else null]
	if race and class_data:
		var hero_path := AssetPaths.hero_portrait_path(race.id, class_data.id)
		if ResourceLoader.exists(hero_path):
			var bg_path := AssetPaths.portrait_bg_path(class_data.id)
			layers = [load(bg_path) if ResourceLoader.exists(bg_path) else null,
					AssetPaths.hero_portrait_frame(load(hero_path), &"neutral0")]
	for tex: Texture2D in layers:
		var t := TextureRect.new()
		t.texture = tex
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.set_anchors_preset(Control.PRESET_FULL_RECT)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(t)
	return root
