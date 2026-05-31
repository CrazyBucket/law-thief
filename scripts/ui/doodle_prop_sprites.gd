class_name DoodlePropSprites
extends RefCounted

const TILES_ROOT := "res://assets/demo/doodle-rpg/ALL SPRITES/Tiles/"

const _PROP_BASES: Array[String] = [
	"Post1", "Post2",
	"DecorRock1", "DecorRock2", "DecorRock3", "DecorRock4", "DecorRock5", "DecorRock6",
	"LargeRock1", "LargeRock2",
	"Statue1", "Pedestal", "Log1", "Log2",
]

var _texture_cache: Dictionary = {}
var _foot_ratio_cache: Dictionary = {}
var _sprite_ids: PackedStringArray = PackedStringArray()


func _init() -> void:
	if not _sprite_ids.is_empty():
		return
	for base_name in _PROP_BASES:
		for frame in range(2):
			_sprite_ids.append("%s_%d" % [base_name, frame])


static func pick_sprite_id(seed: int, pos: Vector2i, uid: String = "") -> String:
	var inst := DoodlePropSprites.new()
	var hash_val := absi(hash(str(seed, pos.x, pos.y, uid)))
	if inst._sprite_ids.is_empty():
		return "DecorRock1_0"
	return inst._sprite_ids[hash_val % inst._sprite_ids.size()]


func texture_for_sprite_id(sprite_id: String) -> Texture2D:
	if sprite_id.is_empty():
		return null
	return _ensure_texture("%s%s.png" % [TILES_ROOT, sprite_id])


func foot_ratio_for_sprite_id(sprite_id: String) -> float:
	if sprite_id.is_empty():
		return 1.0
	var abs_path := "%s%s.png" % [TILES_ROOT, sprite_id]
	if _foot_ratio_cache.has(abs_path):
		return float(_foot_ratio_cache[abs_path])
	var ratio := _measure_foot_ratio(abs_path)
	_foot_ratio_cache[abs_path] = ratio
	return ratio


func _ensure_texture(abs_path: String) -> Texture2D:
	var cached_variant: Variant = _texture_cache.get(abs_path, null)
	if cached_variant is Texture2D:
		return cached_variant as Texture2D
	var rl: Resource = ResourceLoader.load(abs_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if rl != null and rl is Texture2D:
		var from_import: Texture2D = rl as Texture2D
		_texture_cache[abs_path] = from_import
		return from_import
	var decoded := Image.new()
	if decoded.load(abs_path) != OK:
		push_warning("[DoodlePropSprites] 无法加载: %s" % abs_path)
		return null
	var raw_tex := ImageTexture.create_from_image(decoded)
	_texture_cache[abs_path] = raw_tex
	return raw_tex


func _measure_foot_ratio(abs_path: String) -> float:
	var decoded := Image.new()
	if decoded.load(abs_path) != OK:
		return 1.0
	var w := decoded.get_width()
	var h := decoded.get_height()
	if w <= 0 or h <= 0:
		return 1.0
	var max_y := -1
	for y in range(h):
		for x in range(w):
			if decoded.get_pixel(x, y).a > 0.08:
				max_y = maxi(max_y, y)
	if max_y < 0:
		return 1.0
	return float(max_y + 1) / float(h)
