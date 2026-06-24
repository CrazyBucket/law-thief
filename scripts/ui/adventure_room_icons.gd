class_name AdventureRoomIcons
extends RefCounted

const ICON_DIR := "res://assets/ui/map_room_icons"

static var _icon_cache: Dictionary = {}
static var _missing: Dictionary = {}


static func get_icon(icon_id: String) -> Texture2D:
	if icon_id.is_empty():
		return null
	if _icon_cache.has(icon_id):
		return _icon_cache[icon_id]
	if _missing.has(icon_id):
		return null
	var path := "%s/%s.png" % [ICON_DIR, icon_id]
	if not ResourceLoader.exists(path):
		_missing[icon_id] = true
		return null
	var loaded: Resource = load(path)
	if loaded is Texture2D:
		var tex := loaded as Texture2D
		_icon_cache[icon_id] = tex
		return tex
	_missing[icon_id] = true
	return null
