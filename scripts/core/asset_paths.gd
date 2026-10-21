class_name AssetPaths
extends RefCounted
## Single place for every texture path used by code.
## Data resources (.tres) reference their own icons; replacing a PNG file with
## the same name swaps the art without touching code or data.

const UI_DIR := "res://assets/ui/"
const SPRITES_DIR := "res://assets/sprites/"

# --- UI (book style) ---
const BOOK := UI_DIR + "book.png"
const BOOK_PANEL := UI_DIR + "book_panel.png"
const SLOT := UI_DIR + "slot.png"
const SLOT_EMPTY := UI_DIR + "slot_empty.png"
const SLOT_HOVER := UI_DIR + "slot_hover.png"
const BAR_FRAME := UI_DIR + "bar_frame.png"
const BAR_HP := UI_DIR + "bar_hp.png"
const BAR_MANA := UI_DIR + "bar_mana.png"
const BAR_XP := UI_DIR + "bar_xp.png"
const DOT_FULL := UI_DIR + "dot_full.png"
const DOT_EMPTY := UI_DIR + "dot_empty.png"
const TOOLTIP := UI_DIR + "tooltip.png"
const DOLL := UI_DIR + "doll.png"

# --- World ---
const TILES := SPRITES_DIR + "tiles/tiles_catacombs.png"  # fallback biome tileset
const SHADOW := SPRITES_DIR + "fx/shadow.png"
const RIVET := UI_DIR + "rivet.png"
const EXIT_DOOR := SPRITES_DIR + "props/exit_door.png"
const LIGHT := SPRITES_DIR + "fx/light.png"
const PIXEL := SPRITES_DIR + "fx/pixel.png"
const FIREBALL := SPRITES_DIR + "fx/fireball.png"
const KNIFE := SPRITES_DIR + "fx/knife.png"
const DARK_BOLT := SPRITES_DIR + "fx/dark_bolt.png"
const BOMB := SPRITES_DIR + "items/bomb.png"

# --- Animated sheets (grid PNG + SpriteSheetLayout .tres, see docs/ANIMATION_GUIDE.md) ---
const ANIM_DIR := "res://data/animations/"
const HERO_LAYOUT := ANIM_DIR + "hero_layout.tres"
const TORCH_SHEET := SPRITES_DIR + "props/torch_sheet.png"
const TORCH_LAYOUT := ANIM_DIR + "torch_layout.tres"
const CHEST_LAYOUT := ANIM_DIR + "chest_layout.tres"
const CHEST_SHEETS: Array[String] = [
	SPRITES_DIR + "props/chest_wood_sheet.png",
	SPRITES_DIR + "props/chest_iron_sheet.png",
	SPRITES_DIR + "props/chest_gold_sheet.png",
]
const PORTAL_SHEET := SPRITES_DIR + "props/portal_sheet.png"
const PORTAL_LAYOUT := ANIM_DIR + "portal_layout.tres"
const DROP_SHEET := SPRITES_DIR + "fx/drop_sheet.png"
const DROP_LAYOUT := ANIM_DIR + "drop_layout.tres"
const EXPLOSION_SHEET := SPRITES_DIR + "fx/explosion_sheet.png"
const EXPLOSION_LAYOUT := ANIM_DIR + "explosion_layout.tres"
const DUST_SHEET := SPRITES_DIR + "fx/dust_sheet.png"
const DUST_LAYOUT := ANIM_DIR + "dust_layout.tres"
const HIT_SHEET := SPRITES_DIR + "fx/hit_sheet.png"
const HIT_LAYOUT := ANIM_DIR + "hit_layout.tres"
const SHARD := SPRITES_DIR + "fx/shard.png"
const FALLBACK_WEAPON := SPRITES_DIR + "items/rusty_sword.png"

# --- Shaders ---
const SHADER_FLASH := "res://assets/shaders/flash.gdshader"
const SHADER_POST_FX := "res://assets/shaders/post_fx.gdshader"

# Biome tileset atlas (16x16 cells, 4 columns): rows of variants.
# The texture itself comes from BiomeData.tileset_texture.
const TILE_ROW_BEDROCK := 0
const TILE_ROW_BRICK := 1  # columns 0-1 plain, 2 cracked, 3 ore
const TILE_ROW_BRICK_TOP := 2  # exposed top (moss / dust / magma)
const TILE_ROW_BRICK_BOTTOM := 3  # exposed bottom (ceiling)
const TILE_PLATFORM_LEFT := Vector2i(0, 4)
const TILE_PLATFORM_MID := Vector2i(1, 4)
const TILE_PLATFORM_RIGHT := Vector2i(2, 4)
const TILE_LADDER := Vector2i(3, 4)
const TILE_ROW_BACKWALL := 5
const TILE_ORE_GLOW := Vector2i(0, 6)
const TILE_ORE := Vector2i(3, 1)


static func layout(path: String) -> SpriteSheetLayout:
	if ResourceLoader.exists(path):
		return load(path) as SpriteSheetLayout
	push_warning("Missing sheet layout: %s" % path)
	return null


static func flash_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SHADER_FLASH)
	return m


static func tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	push_warning("Missing texture: %s" % path)
	return null
