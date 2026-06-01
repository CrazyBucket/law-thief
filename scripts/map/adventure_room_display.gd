class_name AdventureRoomDisplay extends RefCounted

const ROOM_TO_TILE: Dictionary = {
	"START": Constants.TILE_ROOM_START,
	"END": Constants.TILE_ROOM_END,
	"NORMAL_COMBAT": Constants.TILE_ROOM_COMBAT,
	"ELITE_COMBAT": Constants.TILE_ROOM_ELITE,
	"REST_SITE": Constants.TILE_ROOM_REST,
	"SHOP": Constants.TILE_ROOM_SHOP,
	"EVENT": Constants.TILE_ROOM_EVENT,
}

const ROOM_DISPLAY: Dictionary = {
	"START": {"glyph": "🏁", "label": "起点", "color": Color(0.45, 0.85, 0.55)},
	"END": {"glyph": "👑", "label": "终点", "color": Color(0.95, 0.75, 0.25)},
	"NORMAL_COMBAT": {"glyph": "⚔", "label": "战", "color": Color(0.92, 0.38, 0.38)},
	"ELITE_COMBAT": {"glyph": "💀", "label": "精", "color": Color(0.75, 0.25, 0.55)},
	"REST_SITE": {"glyph": "🏕", "label": "营", "color": Color(0.35, 0.72, 0.95)},
	"SHOP": {"glyph": "🛒", "label": "店", "color": Color(0.95, 0.82, 0.42)},
	"EVENT": {"glyph": "🎁", "label": "遗", "color": Color(0.65, 0.55, 0.95)},
}


static func tile_id_for(room_type: String) -> String:
	return ROOM_TO_TILE.get(room_type, Constants.TILE_FLOOR)


static func room_type_from_tile(tile_id: String) -> String:
	for room_type: String in ROOM_TO_TILE.keys():
		if ROOM_TO_TILE[room_type] == tile_id:
			return room_type
	return ""


static func is_room_tile(tile_id: String) -> bool:
	return tile_id in Constants.ROOM_TILE_IDS


static func get_display(room_type: String) -> Dictionary:
	return ROOM_DISPLAY.get(room_type, {"glyph": "?", "label": room_type, "color": Color(0.6, 0.6, 0.65)})
