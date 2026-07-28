class_name VfxPackFrames
extends RefCounted

const PACK_ROOT := "res://assets/vfx/foozle-pixel-magic-effects"

const EFFECT_EXPLOSION := "Explosion"
const EFFECT_SMALL_HIT := "Explosion"
const EFFECT_PROJECTILE := "Wind"
const EFFECT_PUFF := "Effect_PuffAndStars"
const EFFECT_HEAL_CHARGE := "Effect_Charged"
const EFFECT_GEM_SPARK := "Effect_PowerChords"

static var _paths_cache: Dictionary = {}


static func is_pack_available() -> bool:
	return DirAccess.open(PACK_ROOT) != null


static func clear_cache() -> void:
	_paths_cache.clear()


static func frame_paths(effect_top_folder: String) -> PackedStringArray:
	if effect_top_folder.is_empty():
		return PackedStringArray()
	var cached_variant: Variant = _paths_cache.get(effect_top_folder, null)
	if cached_variant is PackedStringArray:
		return cached_variant as PackedStringArray
	var built := _gather_sorted_png_paths(effect_top_folder)
	_paths_cache[effect_top_folder] = built
	return built


static func _gather_sorted_png_paths(effect_folder: String) -> PackedStringArray:
	var frames_root := PACK_ROOT.path_join(effect_folder)
	var frames_dir := DirAccess.open(frames_root)
	if frames_dir == null:
		return PackedStringArray()
	var pngs: Array[String] = []
	frames_dir.list_dir_begin()
	while true:
		var fname: String = frames_dir.get_next()
		if fname == "":
			break
		if fname.begins_with("."):
			continue
		if frames_dir.current_is_dir():
			continue
		if fname.to_lower().ends_with(".png"):
			pngs.append(frames_root.path_join(fname))
	frames_dir.list_dir_end()
	pngs.sort()
	var out_paths: PackedStringArray = PackedStringArray()
	for p_path in pngs:
		out_paths.append(p_path)
	return out_paths
