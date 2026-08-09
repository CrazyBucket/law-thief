extends RefCounted

## Doodle RPG：Knight 行走/劈砍。通过 preload 脚本后 .new() 得到实例再调方法，
## 避免依赖 class_name / 静态方法在 GDScript 上的限制。

const KNIGHT_ROOT := "res://assets/demo/doodle-rpg/ALL SPRITES/Knight/"
const WALK_SUBPATH := "Walking w Sword/"
const SWING_SUBPATH := "Sword Swing/"
const HURT_SUBPATH := "hurt%d.png"

var _texture_cache: Dictionary = {}


func facing_from_grid_delta(delta: Vector2i) -> String:
	if delta.x == 0 and delta.y == 0:
		return "Forward"
	var sx := float(delta.x - delta.y)
	var sy := float(delta.x + delta.y)
	return facing_from_screen_delta(Vector2(sx, sy))


## 按棋盘屏幕位移选朝向（与 IsoCoordinates.grid_to_screen 一致）
func facing_from_screen_delta(screen_delta: Vector2) -> String:
	if screen_delta.length_squared() < 1.0:
		return "Forward"
	var deg := rad_to_deg(atan2(screen_delta.y, screen_delta.x))
	if deg < 0.0:
		deg += 360.0
	if deg < 22.5 or deg >= 337.5:
		return "Right"
	if deg < 67.5:
		return "DR"
	if deg < 112.5:
		return "Forward"
	if deg < 157.5:
		return "DL"
	if deg < 202.5:
		return "Left"
	if deg < 247.5:
		return "UL"
	if deg < 292.5:
		return "Up"
	return "UR"


func portrait_texture() -> Texture2D:
	return texture_walk("Forward", 0)


func texture_walk(facing: String, frame: int) -> Texture2D:
	var fi := clampi(frame, 0, 2)
	return _ensure_texture("%s%s%s%d.png" % [KNIGHT_ROOT, WALK_SUBPATH, facing, fi])


func texture_sword_swing(facing: String, frame: int) -> Texture2D:
	var fi := clampi(frame, 0, 2)
	return _ensure_texture("%s%s%s%d.png" % [KNIGHT_ROOT, SWING_SUBPATH, facing, fi])


func texture_hurt(facing: String) -> Texture2D:
	var hurt_index := 1
	match facing:
		"Left", "UL":
			hurt_index = 2
		"Up":
			hurt_index = 3
		"Right", "UR":
			hurt_index = 4
	return _ensure_texture("%s%s" % [KNIGHT_ROOT, HURT_SUBPATH % hurt_index])


func texture_shadow() -> Texture2D:
	return _ensure_texture("%s%s" % [KNIGHT_ROOT, "Shadow.png"])


func _ensure_texture(abs_path: String) -> Texture2D:
	var cached_variant: Variant = _texture_cache.get(abs_path, null)
	if cached_variant is Texture2D:
		return cached_variant as Texture2D
	var rl: Resource = ResourceLoader.load(abs_path, "", ResourceLoader.CACHE_MODE_REUSE)
	if rl != null and rl is Texture2D:
		var from_import: Texture2D = rl as Texture2D
		_texture_cache[abs_path] = from_import
		return from_import
	var decoded := Image.new()
	if decoded.load(abs_path) != OK:
		push_warning("[DoodleKnightSprites] 无法加载: %s" % abs_path)
		return null
	var raw_tex := ImageTexture.create_from_image(decoded)
	_texture_cache[abs_path] = raw_tex
	return raw_tex
