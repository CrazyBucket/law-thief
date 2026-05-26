## 状态图标精灵图工具
## 精灵图：assets/ui/status_icons.png，7列×5行，每格约116px
class_name StatusIcons
extends RefCounted

const SHEET_PATH := "res://assets/ui/status_icons.png"
const COLS := 7
const ROWS := 5

static var _sheet: Texture2D = null
static var _atlas_cache: Dictionary = {}
static var _frame_map: Dictionary = {}


static func _ensure_frame_map() -> void:
	if not _frame_map.is_empty():
		return
	_frame_map = {
		Constants.STATUS_BURNING:   0,
		Constants.STATUS_PARALYZED: 1,
		Constants.STATUS_POISON:    2,
		Constants.STATUS_WET:       5,
		Constants.STATUS_ROOTED:    8,
		Constants.STATUS_ARMOR:     13,
		Constants.STATUS_EXPOSED:   14,
		Constants.STATUS_SLUGGISH:  21,
		Constants.STATUS_SLOWED:    29,
		Constants.STATUS_LAWLESS:   26,
	}


static func get_icon(status_id: String) -> AtlasTexture:
	_ensure_frame_map()
	if not _frame_map.has(status_id):
		return null
	var idx: int = _frame_map[status_id]
	if _atlas_cache.has(idx):
		return _atlas_cache[idx]
	var sheet := _get_sheet()
	if sheet == null:
		return null
	var cell_w: float = float(sheet.get_width()) / float(COLS)
	var cell_h: float = float(sheet.get_height()) / float(ROWS)
	var col: int = idx % COLS
	var row: int = idx / COLS
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(col * cell_w, row * cell_h, cell_w, cell_h)
	atlas.filter_clip = true
	_atlas_cache[idx] = atlas
	return atlas


static func has_icon(status_id: String) -> bool:
	_ensure_frame_map()
	return _frame_map.has(status_id)


static func draw_icon(canvas: CanvasItem, pos: Vector2, status_id: String, size: float = 14.0) -> bool:
	var tex := get_icon(status_id)
	if tex == null:
		return false
	canvas.draw_texture_rect(tex, Rect2(pos, Vector2(size, size)), false)
	return true


static func _get_sheet() -> Texture2D:
	if _sheet == null:
		_sheet = load(SHEET_PATH)
	return _sheet
