class_name GemProjectileFrames
extends RefCounted

## Optional local Mini Magick Shoots 2 animations for elemental gem projectiles.
## The raw source frames are intentionally ignored because their licence forbids redistribution.
const PACK_ROOT := "res://assets/demo/mini-magick-shoots-2"

const ELEMENTS := ["fire", "poison", "arc", "ice", "explosion"]

static var _paths_cache: Dictionary = {}


static func is_pack_available() -> bool:
	return DirAccess.open(PACK_ROOT) != null


static func clear_cache() -> void:
	_paths_cache.clear()


static func frame_paths(element: String) -> PackedStringArray:
	if element not in ELEMENTS:
		return PackedStringArray()
	var cached: Variant = _paths_cache.get(element, null)
	if cached is PackedStringArray:
		return cached as PackedStringArray
	var frames := _gather_numeric_png_paths(element)
	_paths_cache[element] = frames
	return frames


static func _gather_numeric_png_paths(element: String) -> PackedStringArray:
	var frames_root := PACK_ROOT.path_join(element)
	var frames_dir := DirAccess.open(frames_root)
	if frames_dir == null:
		return PackedStringArray()
	var pngs: Array[String] = []
	frames_dir.list_dir_begin()
	while true:
		var filename := frames_dir.get_next()
		if filename.is_empty():
			break
		if filename.begins_with(".") or frames_dir.current_is_dir():
			continue
		if filename.to_lower().ends_with(".png"):
			pngs.append(frames_root.path_join(filename))
	frames_dir.list_dir_end()
	pngs.sort_custom(func(a: String, b: String) -> bool:
		return int(a.get_file().get_basename()) < int(b.get_file().get_basename())
	)
	var out_paths := PackedStringArray()
	for path in pngs:
		out_paths.append(path)
	return out_paths
