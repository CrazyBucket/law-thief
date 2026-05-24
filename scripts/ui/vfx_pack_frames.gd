class_name VfxPackFrames
extends RefCounted

const PACK_ROOT := "res://assets/demo/vfx-free-pack"
const FPS_SUBDIR := "60fps"

const EFFECT_EXPLOSION := "Effect_Explosion"
const EFFECT_SMALL_HIT := "Effect_SmallHit"
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
	var frames_root := "%s/%s/%s/%s" % [PACK_ROOT, effect_folder, FPS_SUBDIR, "Frames"]
	var d_variants := DirAccess.open(frames_root)
	if d_variants == null:
		return PackedStringArray()
	var variant_names: Array[String] = []
	d_variants.list_dir_begin()
	while true:
		var entry: String = d_variants.get_next()
		if entry == "":
			break
		if entry.begins_with("."):
			continue
		if d_variants.current_is_dir():
			variant_names.append(entry)
	d_variants.list_dir_end()
	if variant_names.is_empty():
		return PackedStringArray()
	variant_names.sort()
	var variant_path := frames_root.path_join(variant_names[0])
	var d_frames := DirAccess.open(variant_path)
	if d_frames == null:
		return PackedStringArray()
	var pngs: Array[String] = []
	d_frames.list_dir_begin()
	while true:
		var fname: String = d_frames.get_next()
		if fname == "":
			break
		if fname.begins_with("."):
			continue
		if d_frames.current_is_dir():
			continue
		if fname.to_lower().ends_with(".png"):
			pngs.append(variant_path.path_join(fname))
	d_frames.list_dir_end()
	pngs.sort()
	var out_paths: PackedStringArray = PackedStringArray()
	for p_path in pngs:
		out_paths.append(p_path)
	return out_paths
