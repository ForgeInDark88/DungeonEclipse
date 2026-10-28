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
## Slot frame with an empty window, laid over icons so they always sit inside the frame.
const SLOT_BORDER := UI_DIR + "slot_border.png"
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
## Status icons: STATUS_ICON_DIR + "<status id>.png" (8x8).
const STATUS_ICON_DIR := UI_DIR + "status/"
const SHIELD_BUBBLE := SPRITES_DIR + "fx/shield_bubble.png"
const TRAP_ROCK := SPRITES_DIR + "traps/rock.png"
const TRAP_CRACK := SPRITES_DIR + "traps/ceiling_crack.png"
const MERCHANT_SHEET := SPRITES_DIR + "npc/merchant_sheet.png"
const BLACKSMITH_SHEET := SPRITES_DIR + "npc/blacksmith_sheet.png"
## Heroic close-up portraits per race x class (tools/gen_hero_portraits.py):
## hero_<race>_<class>.png is a sheet of HERO_PORTRAIT_FRAMES (64x64 each)
## over bg_<class>.png. When a pair has none, the old layers
## (RaceData.portrait + ClassData.portrait_overlay) are used.
const PORTRAITS_DIR := SPRITES_DIR + "portraits/"
const HERO_PORTRAIT_SIZE := 64
const HERO_PORTRAIT_FRAMES: Array[StringName] = [&"neutral0", &"neutral1", &"blink_half", &"blink", &"glance",
		&"hurt0", &"hurt1", &"wounded0", &"wounded1", &"fierce0", &"fierce1"]
## Pets: one sheet per pet (PetData.sheet), shared frame layout.
const PET_SCENE := "res://scenes/pets/pet.tscn"
const PET_LAYOUT := "res://data/animations/pet_layout.tres"
const MERCHANT_LAYOUT := ANIM_DIR + "merchant_layout.tres"
const COIN_ICON := UI_DIR + "coin.png"
## Sanctum of the Eclipse currency (meta progression).
const ECLIPSE_SHARD_ICON := SPRITES_DIR + "items/eclipse_shard.png"
const BARRIER_SHEET := SPRITES_DIR + "events/barrier_sheet.png"
const BARRIER_LAYOUT := ANIM_DIR + "barrier_layout.tres"
const LEVER_SHEET := SPRITES_DIR + "events/lever_sheet.png"
const LEVER_LAYOUT := ANIM_DIR + "lever_layout.tres"
## Puzzle runes: 4 symbols of 8x8 in a row.
const RUNES := SPRITES_DIR + "events/runes.png"
const EXIT_DOOR := SPRITES_DIR + "props/exit_door.png"
const LIGHT := SPRITES_DIR + "fx/light.png"
## Town buildings and props (tools/gen_town.py): TOWN_DIR + name + ".png".
const TOWN_DIR := SPRITES_DIR + "town/"
const TOWN_BIOME := "res://data/town/town.tres"
const TRAINING_DUMMY := "res://data/town/training_dummy.tres"
## Mouse cursor during the run (aiming).
const CROSSHAIR := "res://assets/ui/crosshair.png"
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

# --- Audio (see docs/AUDIO_LIST.md) ---
const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
## Sound id -> file. Any id used by code or data (UsableItemData.use_sound,
## EnemyData.sound_*) must be listed here.
const SFX := {
	&"ui_click": SFX_DIR + "ui_click.wav",
	&"ui_hover": SFX_DIR + "ui_hover.wav",
	&"ui_book_open": SFX_DIR + "ui_book_open.wav",
	&"ui_book_close": SFX_DIR + "ui_book_close.wav",
	&"ui_equip": SFX_DIR + "ui_equip.wav",
	&"level_up": SFX_DIR + "level_up.wav",
	&"cast_swing_heavy": SFX_DIR + "cast_swing_heavy.wav",
	&"cast_swing_wide": SFX_DIR + "cast_swing_wide.wav",
	&"cast_swing_quick": SFX_DIR + "cast_swing_quick.wav",
	&"cast_blades": SFX_DIR + "cast_blades.wav",
	&"cast_fire": SFX_DIR + "cast_fire.wav",
	&"cast_fire_wave": SFX_DIR + "cast_fire_wave.wav",
	&"cast_sun": SFX_DIR + "cast_sun.wav",
	&"cast_frost": SFX_DIR + "cast_frost.wav",
	&"cast_frost_big": SFX_DIR + "cast_frost_big.wav",
	&"cast_void": SFX_DIR + "cast_void.wav",
	&"cast_bolt": SFX_DIR + "cast_bolt.wav",
	&"cast_holy": SFX_DIR + "cast_holy.wav",
	&"cast_holy_ray": SFX_DIR + "cast_holy_ray.wav",
	&"cast_shadow": SFX_DIR + "cast_shadow.wav",
	&"cast_quake": SFX_DIR + "cast_quake.wav",
	&"cast_bash": SFX_DIR + "cast_bash.wav",
	&"cast_shout": SFX_DIR + "cast_shout.wav",
	&"cast_shield": SFX_DIR + "cast_shield.wav",
	&"cast_heal": SFX_DIR + "cast_heal.wav",
	&"cast_throw": SFX_DIR + "cast_throw.wav",
	&"meteor_fall": SFX_DIR + "meteor_fall.wav",
	&"meteor_impact": SFX_DIR + "meteor_impact.wav",
	&"cast_exec": SFX_DIR + "cast_exec.wav",
	&"cast_nova": SFX_DIR + "cast_nova.wav",
	&"cast_holy_smite": SFX_DIR + "cast_holy_smite.wav",
	&"cast_shadow_strike": SFX_DIR + "cast_shadow_strike.wav",
	&"step_stone": SFX_DIR + "step_stone.wav",
	&"step_wood": SFX_DIR + "step_wood.wav",
	&"step_soft": SFX_DIR + "step_soft.wav",
	&"jump": SFX_DIR + "jump.wav",
	&"land": SFX_DIR + "land.wav",
	&"dash": SFX_DIR + "dash.wav",
	&"attack_sword": SFX_DIR + "attack_sword.wav",
	&"attack_axe": SFX_DIR + "attack_axe.wav",
	&"attack_spear": SFX_DIR + "attack_spear.wav",
	&"attack_dagger": SFX_DIR + "attack_dagger.wav",
	&"attack_bow": SFX_DIR + "attack_bow.wav",
	&"attack_staff": SFX_DIR + "attack_staff.wav",
	&"attack_mace": SFX_DIR + "attack_mace.wav",
	&"hit_flesh": SFX_DIR + "hit_flesh.wav",
	&"hit_crit": SFX_DIR + "hit_crit.wav",
	&"player_hurt": SFX_DIR + "player_hurt.wav",
	&"player_death": SFX_DIR + "player_death.wav",
	&"enemy_hurt": SFX_DIR + "enemy_hurt.wav",
	&"enemy_death": SFX_DIR + "enemy_death.wav",
	&"enemy_shoot": SFX_DIR + "enemy_shoot.wav",
	&"chest_open": SFX_DIR + "chest_open.wav",
	&"chest_locked": SFX_DIR + "chest_locked.wav",
	&"pickup_common": SFX_DIR + "pickup_common.wav",
	&"pickup_rare": SFX_DIR + "pickup_rare.wav",
	&"pickup_epic": SFX_DIR + "pickup_epic.wav",
	&"coin": SFX_DIR + "coin.wav",
	&"potion_drink": SFX_DIR + "potion_drink.wav",
	&"item_use": SFX_DIR + "item_use.wav",
	&"dig": SFX_DIR + "dig.wav",
	&"explosion": SFX_DIR + "explosion.wav",
	&"portal": SFX_DIR + "portal.wav",
	&"boss_gong": SFX_DIR + "boss_gong.wav",
	&"boss_roar": SFX_DIR + "boss_roar.wav",
	&"boss_toll": SFX_DIR + "boss_toll.wav",
	&"skill_cast": SFX_DIR + "skill_cast.wav",
}
## Weapon type (WeaponItemData.WeaponType) -> swing sound id.
const WEAPON_SFX: Array[StringName] = [&"attack_sword", &"attack_axe", &"attack_spear", &"attack_dagger", &"attack_bow", &"attack_staff", &"attack_mace", &"attack_bow", &"attack_staff"]
const MUSIC := {
	&"menu": MUSIC_DIR + "music_menu.ogg",
	&"town": MUSIC_DIR + "music_town.ogg",
	&"catacombs": MUSIC_DIR + "music_catacombs.ogg",
	&"fungal": MUSIC_DIR + "music_fungal.ogg",
	&"ruins": MUSIC_DIR + "music_ruins.ogg",
	&"lava": MUSIC_DIR + "music_lava.ogg",
	&"mirror_halls": MUSIC_DIR + "music_mirror_halls.ogg",
	&"ashen_halls": MUSIC_DIR + "music_ashen_halls.ogg",
	&"crystal_depths": MUSIC_DIR + "music_crystal_depths.ogg",
	&"boss": MUSIC_DIR + "music_boss.ogg",
	&"boss_bone_king": MUSIC_DIR + "music_boss_bone_king.ogg",
	&"boss_flame_witch": MUSIC_DIR + "music_boss_flame_witch.ogg",
	&"boss_illusionist": MUSIC_DIR + "music_boss_illusionist.ogg",
	&"boss_crystal_titan": MUSIC_DIR + "music_boss_crystal_titan.ogg",
	&"boss_ashen_king": MUSIC_DIR + "music_boss_ashen_king.ogg",
	&"drowned_vaults": MUSIC_DIR + "music_drowned_vaults.ogg",
	&"boss_drowned_bell": MUSIC_DIR + "music_boss_drowned_bell.ogg",
	&"world_roots": MUSIC_DIR + "music_world_roots.ogg",
	&"obsidian_abyss": MUSIC_DIR + "music_obsidian_abyss.ogg",
	&"eclipse_heart": MUSIC_DIR + "music_eclipse_heart.ogg",
	&"boss_eclipse": MUSIC_DIR + "music_boss_eclipse.ogg",
	&"ending": MUSIC_DIR + "music_ending.ogg",
	&"victory": MUSIC_DIR + "music_victory.ogg",
	&"death": MUSIC_DIR + "music_death.ogg",
}
## When a track file is missing, these ids are tried instead (then silence).
const MUSIC_FALLBACK := {
	&"boss_bone_king": &"boss",
	&"boss_flame_witch": &"boss",
	&"boss_illusionist": &"boss",
	&"mirror_halls": &"ruins",
	&"boss_eclipse": &"boss",
}
## Tracks played once (not looped): AudioManager.play_sting().
const MUSIC_ONE_SHOT: Array[StringName] = [&"victory", &"death", &"ending"]

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
## Detail rows (no collision): floor fringe above a floor brick, ceiling
## fringe under a ceiling, small marks on the back wall. 4 variants each.
const TILE_ROW_FLOOR_FRINGE := 7
const TILE_ROW_CEIL_FRINGE := 8
const TILE_ROW_WALL_DETAIL := 9
const TILE_ROW_BACK_EDGE := 10  # crumbling rims of the back wall gaps: wall above, below, left, right
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


## Close-up sheet; a heroine uses hero_<race>_<class>_f.png (the male one if missing).
static func hero_portrait_path(race_id: StringName, class_id: StringName, female := false) -> String:
	var path := PORTRAITS_DIR + "hero_%s_%s.png" % [race_id, class_id]
	if female:
		var f := PORTRAITS_DIR + "hero_%s_%s_f.png" % [race_id, class_id]
		if ResourceLoader.exists(f):
			return f
	return path


## One frame of a hero portrait sheet (see HERO_PORTRAIT_FRAMES).
static func hero_portrait_frame(sheet: Texture2D, frame: StringName) -> AtlasTexture:
	var a := AtlasTexture.new()
	a.atlas = sheet
	var i := maxi(0, HERO_PORTRAIT_FRAMES.find(frame))
	a.region = Rect2(i * HERO_PORTRAIT_SIZE, 0, HERO_PORTRAIT_SIZE, HERO_PORTRAIT_SIZE)
	return a


static func portrait_bg_path(class_id: StringName) -> String:
	return PORTRAITS_DIR + "bg_%s.png" % class_id


static func tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	push_warning("Missing texture: %s" % path)
	return null
