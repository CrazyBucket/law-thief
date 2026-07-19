extends RefCounted

## 6×6 精灵表，每帧 46×33；行对应朝向，列对应动画帧

const ROOT := "res://assets/units/slimes/"
const COLS := 6
const FRAME_W := 46
const FRAME_H := 33
const IDLE_FRAMES := 6
const WALK_FRAMES := 6
const STRIKE_FRAMES := 6
const TARGET_CONTENT_HEIGHT := 52.0
const FOOT_PAD_PX := 2
const UNIT_VARIANTS := {
	"unit_fission_slime": "green",
	"unit_small_slime_blue": "blue",
	"unit_small_slime_dark": "dark",
	"unit_small_slime_green": "green",
	"unit_small_slime_pink": "pink",
	"unit_small_slime_white": "white",
	"unit_small_slime_yellow": "yellow",
}

const _FACING_TO_ROW: Dictionary = {
	"Forward": 0,
	"DL": 1,
	"DR": 2,
	"Up": 3,
	"UL": 4,
	"UR": 5,
	"Left": 1,
	"Right": 2,
}

var _variant: String = "green"
var _sheet_cache: Dictionary = {}
var _pose_cache: Dictionary = {}


func _init(variant: String = "green") -> void:
	_variant = variant


static func supports_unit(unit_def_id: String) -> bool:
	return UNIT_VARIANTS.has(unit_def_id)


static func variant_for_unit(unit_def_id: String) -> String:
	return str(UNIT_VARIANTS.get(unit_def_id, "green"))


func portrait_texture() -> Texture2D:
	return pose_frame("Forward", "Idle", 0).get("texture", null)


func pose_frame(facing: String, anim: String, frame: int) -> Dictionary:
	var row := _row_for_facing(facing, anim)
	var frame_count := _frame_count(anim)
	var fi := clampi(frame, 0, frame_count - 1)
	var cache_key := "%s#%d#%d" % [_variant, row, fi]
	if _pose_cache.has(cache_key):
		return _pose_cache[cache_key]
	var sheet := _ensure_sheet()
	if sheet == null:
		return {}
	var bbox := _frame_bbox(sheet, row, fi)
	if bbox.size.x <= 0.0 or bbox.size.y <= 0.0:
		return {}
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = bbox
	var scale := TARGET_CONTENT_HEIGHT / float(bbox.size.y)
	var draw_size := Vector2(bbox.size.x * scale, bbox.size.y * scale)
	var result := {
		"texture": atlas,
		"draw_size": draw_size,
	}
	_pose_cache[cache_key] = result
	return result


func _row_for_facing(facing: String, _anim: String) -> int:
	return int(_FACING_TO_ROW.get(facing, 0))


func _frame_count(anim: String) -> int:
	match anim:
		"Walk":
			return WALK_FRAMES
		"Strike":
			return STRIKE_FRAMES
		_:
			return IDLE_FRAMES


func _sheet_path() -> String:
	return "%sslimes_%s.png" % [ROOT, _variant]


func _ensure_sheet() -> Texture2D:
	var abs_path := _sheet_path()
	if _sheet_cache.has(abs_path):
		return _sheet_cache[abs_path] as Texture2D
	var rl: Resource = ResourceLoader.load(abs_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if rl != null and rl is Texture2D:
		_sheet_cache[abs_path] = rl
		return rl as Texture2D
	var decoded := Image.new()
	if decoded.load(abs_path) != OK:
		push_warning("[SlimeSprites] 无法加载: %s" % abs_path)
		return null
	var tex := ImageTexture.create_from_image(decoded)
	_sheet_cache[abs_path] = tex
	return tex


func _frame_bbox(sheet: Texture2D, row: int, col: int) -> Rect2:
	var img := sheet.get_image()
	if img == null:
		return Rect2()
	if img.is_compressed():
		img.decompress()
	var x0 := col * FRAME_W
	var y0 := row * FRAME_H
	var min_x := x0 + FRAME_W
	var min_y := y0 + FRAME_H
	var max_x := -1
	var max_y := -1
	for y in range(y0, y0 + FRAME_H):
		for x in range(x0, x0 + FRAME_W):
			if img.get_pixel(x, y).a <= 0.08:
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		return Rect2(float(x0), float(y0), float(FRAME_W), float(FRAME_H))
	var crop_h := max_y - min_y + 1 + mini(FOOT_PAD_PX, y0 + FRAME_H - max_y - 1)
	return Rect2(float(min_x), float(min_y), float(max_x - min_x + 1), float(crop_h))
