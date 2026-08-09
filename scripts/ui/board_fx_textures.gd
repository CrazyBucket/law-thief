extends RefCounted

var _texture_cache: Dictionary = {}


func texture_at(res_path: String) -> Texture2D:
	var cached_variant: Variant = _texture_cache.get(res_path, null)
	if cached_variant is Texture2D:
		return cached_variant as Texture2D
	if ResourceLoader.exists(res_path, "Texture2D"):
		var loaded: Resource = ResourceLoader.load(res_path, "", ResourceLoader.CACHE_MODE_REUSE)
		if loaded is Texture2D:
			var tex2d := loaded as Texture2D
			_texture_cache[res_path] = tex2d
			return tex2d
	var decoded := Image.new()
	if decoded.load(res_path) != OK:
		push_warning("[BoardFxTextures] 无法加载: %s" % res_path)
		return null
	var raw_tex := ImageTexture.create_from_image(decoded)
	_texture_cache[res_path] = raw_tex
	return raw_tex
