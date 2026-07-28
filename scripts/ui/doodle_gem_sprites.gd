extends RefCounted

## Gem sprites: prefer project-specific generated gem textures, keep Loot_* only as relic fallback.

const LOOT_ROOT := "res://assets/demo/doodle-rpg/ALL SPRITES/Pickups and Items/"
const GEM_ROOT := "res://assets/ui/gem_icons_generated/"

const _GEM_TEXTURE_PATHS: Dictionary = {
	Constants.GEM_EXPLOSION: "%sgem_explosion.png" % GEM_ROOT,
	Constants.GEM_POISON: "%sgem_poison.png" % GEM_ROOT,
	Constants.GEM_GRAVITY: "%sgem_gravity.png" % GEM_ROOT,
	Constants.GEM_CONDUCTIVE: "%sgem_conductive.png" % GEM_ROOT,
	Constants.GEM_FIRE: "%sgem_fire.png" % GEM_ROOT,
	Constants.GEM_ICE: "%sgem_ice.png" % GEM_ROOT,
	Constants.GEM_SPLIT: "%sgem_split.png" % GEM_ROOT,
	Constants.GEM_LIGHT: "%sgem_light.png" % GEM_ROOT,
	Constants.GEM_COUNTER: "%sgem_counter.png" % GEM_ROOT,
	Constants.GEM_ECHO: "%sgem_echo.png" % GEM_ROOT,
	Constants.GEM_FLURRY: "%sgem_flurry.png" % GEM_ROOT,
	Constants.GEM_IMPACT: "%sgem_impact.png" % GEM_ROOT,
	Constants.GEM_TIDE: "%sgem_tide.png" % GEM_ROOT,
}

var _texture_cache: Dictionary = {}


func texture_for_gem_id(gem_id: String) -> Texture2D:
	var tex_path: String = str(_GEM_TEXTURE_PATHS.get(gem_id, ""))
	if not tex_path.is_empty():
		var custom_tex := _ensure_texture(tex_path)
		if custom_tex != null:
			return custom_tex
	return _ensure_texture("%sLoot_%d.png" % [LOOT_ROOT, 0])


func texture_for_relic_id(relic_id: String) -> Texture2D:
	var loot_idx: int = absi(relic_id.hash()) % 5
	return _ensure_texture("%sLoot_%d.png" % [LOOT_ROOT, loot_idx])


func modulate_for_gem_id(gem_id: String) -> Color:
	return Color.WHITE


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
