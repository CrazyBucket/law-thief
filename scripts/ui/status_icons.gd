## 与 Sprite2D 相同：Hframes=7 Vframes=5，frames 为 [col, row]
class_name StatusIcons
extends RefCounted

const ATLAS_JSON := "res://data/status_icon_atlas.json"
const SHEET_PATH := "res://assets/ui/status_icons.png"
const HFRAMES := 7
const VFRAMES := 5

static var _sheet: Texture2D = null
static var _atlas_cache: Dictionary = {}
static var _frame_map: Dictionary = {}


static func get_icon(status_id: String) -> AtlasTexture:
	_ensure_loaded()
	if not _frame_map.has(status_id):
		return null
	var coords: Vector2i = _frame_map[status_id]
	if _atlas_cache.has(coords):
		return _atlas_cache[coords]
	var sheet := _get_sheet()
	if sheet == null:
		return null
	var region := _frame_region(sheet, coords.x, coords.y)
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = region
	_atlas_cache[coords] = atlas
	return atlas


static func has_icon(status_id: String) -> bool:
	_ensure_loaded()
	return _frame_map.has(status_id)


static func draw_icon(canvas: CanvasItem, pos: Vector2, status_id: String, size: float = 14.0) -> bool:
	var tex := get_icon(status_id)
	if tex == null or tex.atlas == null:
		return false
	var src := tex.region
	if src.size.x <= 0.0 or src.size.y <= 0.0:
		return false
	var box := Vector2(size, size)
	var scale := minf(box.x / src.size.x, box.y / src.size.y)
	var draw_sz := Vector2(src.size.x * scale, src.size.y * scale)
	var offset := (box - draw_sz) * 0.5
	canvas.draw_texture_rect_region(tex.atlas, Rect2(pos + offset, draw_sz), src)
	return true


static func _ensure_loaded() -> void:
	if not _frame_map.is_empty():
		return
	var file := FileAccess.open(ATLAS_JSON, FileAccess.READ)
	if file == null:
		_use_builtin_fallback()
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		_use_builtin_fallback()
		return
	var frames: Dictionary = data.get("frames", {})
	for status_id in frames.keys():
		var cell: Array = frames[status_id]
		if cell.size() >= 2:
			_frame_map[str(status_id)] = Vector2i(int(cell[0]), int(cell[1]))
	if _frame_map.is_empty():
		_use_builtin_fallback()


static func _use_builtin_fallback() -> void:
	_frame_map = {
		Constants.STATUS_BURNING: Vector2i(0, 0),
		Constants.STATUS_PARALYZED: Vector2i(1, 0),
		Constants.STATUS_POISON: Vector2i(2, 0),
		Constants.STATUS_WET: Vector2i(5, 0),
		Constants.STATUS_ROOTED: Vector2i(1, 1),
		Constants.STATUS_ARMOR: Vector2i(6, 1),
		Constants.STATUS_EXPOSED: Vector2i(0, 2),
		Constants.STATUS_SLUGGISH: Vector2i(0, 3),
		Constants.STATUS_LAWLESS: Vector2i(6, 4),
		Constants.STATUS_SLOWED: Vector2i(1, 4),
		Constants.STATUS_VULNERABLE: Vector2i(3, 4),
	}


static func _frame_region(sheet: Texture2D, col: int, row: int) -> Rect2:
	var fw := float(sheet.get_width()) / float(HFRAMES)
	var fh := float(sheet.get_height()) / float(VFRAMES)
	return Rect2(float(col) * fw, float(row) * fh, fw, fh)


static func _get_sheet() -> Texture2D:
	if _sheet != null:
		return _sheet
	var loaded: Resource = load(SHEET_PATH)
	if loaded is Texture2D:
		_sheet = loaded as Texture2D
		return _sheet
	return null
