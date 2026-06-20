class_name IntentIcons
extends RefCounted

const ICON_DIR := "res://assets/ui/intent_icons_generated"

static var _icon_cache: Dictionary = {}
static var _missing: Dictionary = {}


static func get_icon(intent_type: String) -> Texture2D:
	if _icon_cache.has(intent_type):
		return _icon_cache[intent_type]
	if _missing.has(intent_type):
		return null
	var path := "%s/%s.png" % [ICON_DIR, intent_type]
	if not ResourceLoader.exists(path):
		_missing[intent_type] = true
		return null
	var loaded: Resource = load(path)
	if loaded is Texture2D:
		var tex := loaded as Texture2D
		_icon_cache[intent_type] = tex
		return tex
	_missing[intent_type] = true
	return null


static func has_icon(intent_type: String) -> bool:
	return get_icon(intent_type) != null


static func draw_icon(canvas: CanvasItem, pos: Vector2, intent_type: String, size: float = 14.0) -> bool:
	var tex := get_icon(intent_type)
	if tex == null:
		return false
	var tex_size := tex.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return false
	var box := Vector2(size, size)
	var scale := minf(box.x / tex_size.x, box.y / tex_size.y)
	var draw_sz := tex_size * scale
	var offset := (box - draw_sz) * 0.5
	canvas.draw_texture_rect(tex, Rect2(pos + offset, draw_sz), false)
	return true
