extends Node

const PROFILE_FILE_NAME := "profile.json"
const PROFILE_VERSION := 1

var _flags: Dictionary = {}
var _dirty: bool = false
var _save_scheduled: bool = false


func _ready() -> void:
	load_profile()


func unlock_flag(flag: String) -> void:
	if _mark_flag_unlocked(flag):
		_schedule_save()


func unlock_flags(flags: Array[String]) -> int:
	var added := 0
	for flag in flags:
		if _mark_flag_unlocked(flag):
			added += 1
	if added > 0:
		_schedule_save()
	return added


func unlock_all_for_active_slot() -> Dictionary:
	var added_conditions := 0
	for cond in DataRegistry.get_relic_unlock_condition_ids():
		if _flags.has(cond):
			continue
		_flags[cond] = true
		added_conditions += 1
		_dirty = true
	var added_seen_relics := 0
	for relic_id in DataRegistry.get_relic_ids():
		var flag := "seen_relic_%s" % relic_id
		if _flags.has(flag):
			continue
		_flags[flag] = true
		added_seen_relics += 1
		_dirty = true
	var added_enemies := 0
	for unit_id in DataRegistry.get_unit_def_ids():
		if unit_id == "unit_player":
			continue
		for prefix in ["enemy_seen_", "enemy_killed_"]:
			var enemy_flag := "%s%s" % [prefix, unit_id]
			if _flags.has(enemy_flag):
				continue
			_flags[enemy_flag] = true
			added_enemies += 1
			_dirty = true
	var added_achievements := 0
	for flag in AchievementService.get_all_achievement_flag_ids():
		if _flags.has(flag):
			continue
		_flags[flag] = true
		added_achievements += 1
		_dirty = true
	var added_boss_flags := 0
	for encounter_id in DataRegistry.get_encounter_ids():
		var boss_flag := "boss_%s" % str(encounter_id)
		if _flags.has(boss_flag):
			continue
		_flags[boss_flag] = true
		added_boss_flags += 1
		_dirty = true
	if _dirty:
		save_profile()
	AchievementService.refresh_progress_flags()
	DebugService.log_info("ProfileService: unlock_all_for_active_slot")
	return {
		"unlock_conditions": added_conditions,
		"seen_relics": added_seen_relics,
		"seen_enemies": added_enemies,
		"achievements": added_achievements,
		"boss_flags": added_boss_flags,
	}


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
	_save_scheduled = false
	load_profile()


func flush_profile() -> void:
	_save_scheduled = false
	if _dirty:
		save_profile()


func save_profile() -> void:
	_save_scheduled = false
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
	_save_scheduled = false
	_dirty = false
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


func _exit_tree() -> void:
	flush_profile()


func _mark_flag_unlocked(flag: String) -> bool:
	if flag.is_empty() or _flags.has(flag):
		return false
	_flags[flag] = true
	_dirty = true
	DebugService.log_info("ProfileService: unlock_flag %s" % flag)
	return true


func _schedule_save() -> void:
	if _save_scheduled:
		return
	_save_scheduled = true
	call_deferred("_flush_scheduled_save")


func _flush_scheduled_save() -> void:
	_save_scheduled = false
	if _dirty:
		save_profile()


func _strip_prefix(flags: Array[String], prefix: String) -> Array[String]:
	var result: Array[String] = []
	for flag in flags:
		result.append(flag.trim_prefix(prefix))
	return result
