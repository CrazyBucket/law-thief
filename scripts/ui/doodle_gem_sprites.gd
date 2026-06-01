extends RefCounted

## Doodle RPG Pickups：Loot_0~4 宝石贴图，与 Knight 共用加载回退策略。

const LOOT_ROOT := "res://assets/demo/doodle-rpg/ALL SPRITES/Pickups and Items/"

const _GEM_LOOT_INDEX: Dictionary = {
	Constants.GEM_EXPLOSION: 1,
	Constants.GEM_POISON: 3,
	Constants.GEM_GRAVITY: 4,
	Constants.GEM_CONDUCTIVE: 0,
	Constants.GEM_FIRE: 2,
	Constants.GEM_ICE: 4,
	Constants.GEM_SPLIT: 0,
}

const _GEM_MODULATE: Dictionary = {
	Constants.GEM_CONDUCTIVE: Color(1.12, 1.08, 0.52),
	Constants.GEM_ICE: Color(0.62, 1.05, 1.18),
	Constants.GEM_SPLIT: Color(0.92, 0.88, 1.05),
}

var _texture_cache: Dictionary = {}


func texture_for_gem_id(gem_id: String) -> Texture2D:
	var loot_idx: int = int(_GEM_LOOT_INDEX.get(gem_id, 0))
	return _ensure_texture("%sLoot_%d.png" % [LOOT_ROOT, loot_idx])


func texture_for_relic_id(relic_id: String) -> Texture2D:
	var loot_idx: int = absi(relic_id.hash()) % 5
	return _ensure_texture("%sLoot_%d.png" % [LOOT_ROOT, loot_idx])


func modulate_for_gem_id(gem_id: String) -> Color:
	return _GEM_MODULATE.get(gem_id, Color.WHITE)


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
		push_warning("[DoodleGemSprites] 无法加载: %s" % abs_path)
		return null
	var raw_tex := ImageTexture.create_from_image(decoded)
	_texture_cache[abs_path] = raw_tex
	return raw_tex
