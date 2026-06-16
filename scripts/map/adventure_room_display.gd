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
	"START": {"glyph": "🏁", "label": "起点", "color": UiPalette.ROOM_START},
	"END": {"glyph": "👑", "label": "终点", "color": UiPalette.ROOM_END},
	"NORMAL_COMBAT": {"glyph": "⚔", "label": "战", "color": UiPalette.ROOM_COMBAT},
	"ELITE_COMBAT": {"glyph": "💀", "label": "精", "color": UiPalette.ROOM_ELITE},
	"REST_SITE": {"glyph": "🏕", "label": "营", "color": UiPalette.ROOM_REST},
	"SHOP": {"glyph": "🛒", "label": "店", "color": UiPalette.ROOM_SHOP},
	"EVENT": {"glyph": "🎁", "label": "遗", "color": UiPalette.ROOM_EVENT},
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


static func get_display(room_type: String, chapter: int = 1, chapter_count: int = 3) -> Dictionary:
	if room_type == "END":
		var safe_chapter := maxi(1, chapter)
		var safe_total := maxi(1, chapter_count)
		if safe_chapter >= safe_total:
			return {
				"glyph": "👑",
				"label": "终局 Boss",
				"color": UiPalette.ROOM_END,
			}
		return {
			"glyph": "🚪",
			"label": "大关出口",
			"color": UiPalette.ROOM_EXIT,
		}
	return ROOM_DISPLAY.get(room_type, {"glyph": "?", "label": room_type, "color": UiPalette.ROOM_UNKNOWN})
