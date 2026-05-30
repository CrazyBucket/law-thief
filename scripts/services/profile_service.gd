extends Node

const PROFILE_FILE_NAME := "profile.json"
const PROFILE_VERSION := 1

var _flags: Dictionary = {}
var _dirty: bool = false


func _ready() -> void:
	load_profile()


func unlock_flag(flag: String) -> void:
	if _flags.has(flag):
		return
	_flags[flag] = true
	_dirty = true
	DebugService.log_info("ProfileService: unlock_flag %s" % flag)
	save_profile()


func is_flag_unlocked(flag: String) -> bool:
	return _flags.has(flag)


func get_unlock_flags() -> Array[String]:
	var result: Array[String] = []
	for key in _flags.keys():
		result.append(str(key))
	result.sort()
	return result


func get_flags_with_prefix(prefix: String) -> Array[String]:
	var result: Array[String] = []
	for key in _flags.keys():
		if str(key).begins_with(prefix):
			result.append(str(key))
	result.sort()
	return result


func mark_seen_relic(relic_id: String) -> void:
	unlock_flag("seen_relic_%s" % relic_id)


func has_seen_relic(relic_id: String) -> bool:
	return is_flag_unlocked("seen_relic_%s" % relic_id)


func get_seen_relic_ids() -> Array[String]:
	return _strip_prefix(get_flags_with_prefix("seen_relic_"), "seen_relic_")


func mark_enemy_seen(unit_def_id: String) -> void:
	unlock_flag("enemy_seen_%s" % unit_def_id)


func mark_enemy_killed(unit_def_id: String) -> void:
	unlock_flag("enemy_killed_%s" % unit_def_id)


func get_seen_enemy_ids() -> Array[String]:
	return _strip_prefix(get_flags_with_prefix("enemy_seen_"), "enemy_seen_")


func get_killed_enemy_ids() -> Array[String]:
	return _strip_prefix(get_flags_with_prefix("enemy_killed_"), "enemy_killed_")


func get_unlocked_achievement_ids() -> Array[String]:
	return _strip_prefix(get_flags_with_prefix("achievement_"), "achievement_")


func get_summary() -> Dictionary:
	return {
		"flag_count": _flags.size(),
		"seen_relic_count": get_seen_relic_ids().size(),
		"seen_enemy_count": get_seen_enemy_ids().size(),
		"achievement_count": get_unlocked_achievement_ids().size(),
	}


func reload_for_active_slot() -> void:
	load_profile()


func save_profile() -> void:
	var slot_dir := ProjectSettings.globalize_path(SaveService.get_slot_dir())
	DirAccess.make_dir_recursive_absolute(slot_dir)
	var data := {
		"version": PROFILE_VERSION,
		"flags": _flags.keys(),
	}
	var json_str := JSON.stringify(data, "\t")
	var file := FileAccess.open(SaveService.slot_file_path(PROFILE_FILE_NAME), FileAccess.WRITE)
	if file == null:
		push_warning("ProfileService: cannot write active slot profile")
		return
	file.store_string(json_str)
	file.close()
	_dirty = false
	SaveService.touch_active_slot({
		"flag_count": _flags.size(),
		"seen_relic_count": get_seen_relic_ids().size(),
		"seen_enemy_count": get_seen_enemy_ids().size(),
	})


func load_profile() -> void:
	_flags.clear()
	var path := SaveService.slot_file_path(PROFILE_FILE_NAME)
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("ProfileService: cannot read active slot profile")
		return
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning("ProfileService: JSON parse error in active slot profile")
		return
	var data: Variant = json.get_data()
	if not data is Dictionary:
		return
	var raw_flags: Variant = (data as Dictionary).get("flags", [])
	if raw_flags is Array:
		for flag in raw_flags:
			_flags[str(flag)] = true
	DebugService.log_info("ProfileService: loaded %d flags" % _flags.size())


func _strip_prefix(flags: Array[String], prefix: String) -> Array[String]:
	var result: Array[String] = []
	for flag in flags:
		result.append(flag.trim_prefix(prefix))
	return result
