class_name AdventureProgressionConfig
extends RefCounted

const AdventureConfigValidator = preload("res://scripts/services/adventure_config_validator.gd")
const CONFIG_PATH := "res://resources/adventure/adventure_progression.json"

static var _loaded := false
static var _config: Dictionary = {}


static func reload() -> void:
	_loaded = false
	_config = {}
	_ensure_loaded()


static func get_config() -> Dictionary:
	_ensure_loaded()
	return _config.duplicate(true)


static func chapter_count() -> int:
	return int(_required_value("chapter_count"))


static func chapter_seed_stride() -> int:
	return int(_required_value("chapter_seed_stride"))


static func map_config() -> Dictionary:
	return (_required_value("map") as Dictionary).duplicate(true)


static func combat_encounters(room_type: String) -> Array[String]:
	var pools := _required_value("combat_encounters") as Dictionary
	var raw_pool: Variant = pools.get(room_type, null)
	if not raw_pool is Array:
		push_error("AdventureProgressionConfig: unknown combat room type: %s" % room_type)
		return []
	var result: Array[String] = []
	for encounter_id in raw_pool as Array:
		result.append(str(encounter_id))
	return result


static func boss_encounter(chapter: int) -> String:
	var bosses := _required_value("boss_encounters") as Array
	if bosses.is_empty():
		push_error("AdventureProgressionConfig: boss encounter list is empty")
		return ""
	return str(bosses[clampi(chapter - 1, 0, bosses.size() - 1)])


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var raw := _load_json(CONFIG_PATH)
	var errors := AdventureConfigValidator.validate_adventure_progression(raw)
	AdventureConfigValidator.ensure_valid(CONFIG_PATH, errors)
	_config = raw.duplicate(true) if errors.is_empty() else {}


static func _required_value(key: String) -> Variant:
	_ensure_loaded()
	if _config.has(key):
		return _config[key]
	push_error("AdventureProgressionConfig: required value missing: %s" % key)
	return 0


static func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		push_error("AdventureProgressionConfig: JSON parse error: %s" % json.get_error_message())
		return {}
	var data: Variant = json.get_data()
	return (data as Dictionary).duplicate(true) if data is Dictionary else {}
