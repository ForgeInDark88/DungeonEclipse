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
const TILES := SPRITES_DIR + "tiles/dungeon_tiles.png"
const EXIT_DOOR := SPRITES_DIR + "props/exit_door.png"
const LIGHT := SPRITES_DIR + "fx/light.png"
const PIXEL := SPRITES_DIR + "fx/pixel.png"
const FIREBALL := SPRITES_DIR + "fx/fireball.png"
const KNIFE := SPRITES_DIR + "fx/knife.png"
const DARK_BOLT := SPRITES_DIR + "fx/dark_bolt.png"
const BOMB := SPRITES_DIR + "items/bomb.png"

# Atlas coordinates inside TILES (16x16 cells).
const TILE_BEDROCK := Vector2i(0, 0)
const TILE_BRICK := Vector2i(1, 0)
const TILE_PLATFORM := Vector2i(2, 0)
const TILE_LADDER := Vector2i(3, 0)
const TILE_BACKWALL := Vector2i(4, 0)


static func tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	push_warning("Missing texture: %s" % path)
	return null
