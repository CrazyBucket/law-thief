extends RefCounted

## Sscary - The Female Adventurer (Free)：条带 8 帧 × 48×64，有效像素远小于帧框

const ROOT := "res://assets/units/female-adventurer/"
const FRAME_W := 48
const FRAME_H := 64
const WALK_FRAMES := 8
const IDLE_FRAMES := 8
const DASH_FRAMES := 8
const TARGET_CONTENT_HEIGHT := 56.0
const FOOT_PAD_PX := 2

const _FACING_TO_DIR: Dictionary = {
	"Forward": "Down",
	"Up": "Up",
	"DR": "Right_Down",
	"DL": "Left_Down",
	"UR": "Right_Up",
	"UL": "Left_Up",
	"Right": "Right_Down",
	"Left": "Left_Down",
}

var _strip_cache: Dictionary = {}
var _pose_cache: Dictionary = {}


func portrait_texture() -> Texture2D:
	return pose_frame("Forward", "Idle", 0).get("texture", null)


func pose_frame(facing: String, anim: String, frame: int) -> Dictionary:
	var rel_path := _anim_rel_path(anim, facing)
	var frame_count := _frame_count(anim)
	var fi := clampi(frame, 0, frame_count - 1)
	var cache_key := "%s#%d" % [rel_path, fi]
	if _pose_cache.has(cache_key):
		return _pose_cache[cache_key]
	var strip := _ensure_strip("%s%s" % [ROOT, rel_path])
	if strip == null:
		return {}
	var bbox := _content_bbox(strip, fi)
	if bbox.size.x <= 0 or bbox.size.y <= 0:
		return {}
	var atlas := AtlasTexture.new()
	atlas.atlas = strip
	atlas.region = bbox
	var scale := TARGET_CONTENT_HEIGHT / float(bbox.size.y)
	var draw_size := Vector2(bbox.size.x * scale, bbox.size.y * scale)
	var result := {
		"texture": atlas,
		"draw_size": draw_size,
	}
	_pose_cache[cache_key] = result
	return result


func texture_shadow() -> Texture2D:
	return _ensure_strip("%sShadow.png" % ROOT)


func _frame_count(anim: String) -> int:
	match anim:
		"Walk":
			return WALK_FRAMES
		"Dash":
			return DASH_FRAMES
		_:
			return IDLE_FRAMES


func _anim_rel_path(anim: String, facing: String) -> String:
	var dir_name := _dir(facing)
	match anim:
		"Walk":
			return "Walk/walk_%s.png" % dir_name
		"Dash":
			return "Dash/Dash_%s.png" % dir_name
		_:
			return "Idle/Idle_%s.png" % dir_name


func _dir(facing: String) -> String:
	return str(_FACING_TO_DIR.get(facing, "Down"))


func _content_bbox(strip: Texture2D, frame_idx: int) -> Rect2:
	var img := strip.get_image()
	if img == null:
		return Rect2()
	if img.is_compressed():
		img.decompress()
	var x0 := frame_idx * FRAME_W
	var min_x := x0 + FRAME_W
	var min_y := FRAME_H
	var max_x := -1
	var max_y := -1
	for y in range(FRAME_H):
		for x in range(x0, x0 + FRAME_W):
			if img.get_pixel(x, y).a <= 0.08:
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		return Rect2(x0, 0, FRAME_W, FRAME_H)
	var crop_h := max_y - min_y + 1 + mini(FOOT_PAD_PX, FRAME_H - max_y - 1)
	return Rect2(float(min_x), float(min_y), float(max_x - min_x + 1), float(crop_h))


func _ensure_strip(abs_path: String) -> Texture2D:
	if _strip_cache.has(abs_path):
		return _strip_cache[abs_path] as Texture2D
	var rl: Resource = ResourceLoader.load(abs_path, "", ResourceLoader.CACHE_MODE_REUSE)
	if rl != null and rl is Texture2D:
		_strip_cache[abs_path] = rl
		return rl as Texture2D
	var decoded := Image.new()
	if decoded.load(abs_path) != OK:
		push_warning("[FemaleAdventurerSprites] 无法加载: %s" % abs_path)
		return null
	var tex := ImageTexture.create_from_image(decoded)
	_strip_cache[abs_path] = tex
	return tex
