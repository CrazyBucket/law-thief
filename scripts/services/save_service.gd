extends Node

const SLOT_COUNT := 3
const DEFAULT_SLOT_ID := 1
const MANAGER_PATH := "user://save_manager.json"
const _SLOT_FILES := ["profile.json", "run_save.json", "run_history.json"]
const _PersistencePathPolicy = preload("res://scripts/services/persistence_path_policy.gd")

var _bootstrapped: bool = false
var _active_slot_id: int = DEFAULT_SLOT_ID
var _slot_meta: Dictionary = {}

signal slot_changed(slot_id: int)


func _ready() -> void:
	_ensure_bootstrap()


func get_active_slot_id() -> int:
	_ensure_bootstrap()
	return _active_slot_id


func get_active_slot_label() -> String:
	return get_slot_label(get_active_slot_id())


func get_slot_label(slot_id: int) -> String:
	return "档案 %d" % _sanitize_slot_id(slot_id)


func get_slot_dir(slot_id: int = -1) -> String:
	var resolved_slot_id := _resolved_slot_id(slot_id)
	var save_root := _save_root_override()
	if not save_root.is_empty():
		return _join_path(save_root, "slot_%d" % resolved_slot_id)
	return "user://slot_%d" % resolved_slot_id


func slot_file_path(relative_path: String, slot_id: int = -1) -> String:
	var normalized := str(relative_path).trim_prefix("user://")
	return "%s/%s" % [get_slot_dir(slot_id), normalized]


func read_json_file(path: String) -> Dictionary:
	var resolved_path := _globalize_path(path)
	if not FileAccess.file_exists(resolved_path):
		return {}
	var file := FileAccess.open(resolved_path, FileAccess.READ)
	if file == null:
		return {}
	var length := file.get_length()
	var bytes := file.get_buffer(length)
	file.close()
	if bytes.size() != length:
		return {}
	var text := bytes.get_string_from_utf8()
	if text.is_empty() and length > 0:
		return {}
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	var data: Variant = json.get_data()
	if data is Dictionary:
		return (data as Dictionary).duplicate(true)
	return {}


func write_json_atomic(path: String, payload: Dictionary) -> bool:
	var global_path := _globalize_path(path)
	var dir_path := global_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir_path)
	var temp_path := "%s.tmp" % global_path
	var backup_path := "%s.bak" % global_path
	var safe_payload: Variant = _json_safe(payload)
	if not safe_payload is Dictionary:
		return false
	var json_str := JSON.stringify(safe_payload, "\t")
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(json_str)
	file.flush()
	file.close()
	var verify := read_json_file(temp_path)
	if verify.is_empty():
		DirAccess.remove_absolute(temp_path)
		return false
	if FileAccess.file_exists(global_path):
		if FileAccess.file_exists(backup_path):
			DirAccess.remove_absolute(backup_path)
		var rename_backup := DirAccess.rename_absolute(global_path, backup_path)
		if rename_backup != OK:
			DirAccess.remove_absolute(temp_path)
			return false
	var rename_final := DirAccess.rename_absolute(temp_path, global_path)
	if rename_final != OK:
		if not _copy_file(temp_path, global_path):
			if FileAccess.file_exists(temp_path):
				DirAccess.remove_absolute(temp_path)
			if FileAccess.file_exists(backup_path) and not FileAccess.file_exists(global_path):
				DirAccess.rename_absolute(backup_path, global_path)
			return false
	if FileAccess.file_exists(temp_path):
		DirAccess.remove_absolute(temp_path)
	return true


func _copy_file(from_path: String, to_path: String) -> bool:
	var source := FileAccess.open(from_path, FileAccess.READ)
	if source == null:
		return false
	var bytes := source.get_buffer(source.get_length())
	source.close()
	var target := FileAccess.open(to_path, FileAccess.WRITE)
	if target == null:
		return false
	target.store_buffer(bytes)
	target.flush()
	target.close()
	return not read_json_file(to_path).is_empty()


func _json_safe(value: Variant) -> Variant:
	if value is Vector2i:
		return {"x": value.x, "y": value.y}
	if value is Vector2:
		return {"x": value.x, "y": value.y}
	if value is Color:
		return value.to_html(true)
	if value is Dictionary:
		var out := {}
		for key in value.keys():
			out[str(key)] = _json_safe(value[key])
		return out
	if value is Array:
		var out: Array = []
		for item in value:
			out.append(_json_safe(item))
		return out
	return value


func set_active_slot(slot_id: int) -> void:
	_ensure_bootstrap()
	var resolved_slot_id := _sanitize_slot_id(slot_id)
	if resolved_slot_id == _active_slot_id:
		return
	var profile_service = get_node_or_null("/root/ProfileService")
	if profile_service != null and profile_service.has_method("flush_profile"):
		profile_service.flush_profile()
	_active_slot_id = resolved_slot_id
	_save_manager()
	_reload_slot_services()
	slot_changed.emit(_active_slot_id)


func clear_slot(slot_id: int = -1) -> void:
	var resolved_slot_id := _resolved_slot_id(slot_id)
	for file_name in _SLOT_FILES:
		var file_path := _globalize_path(slot_file_path(file_name, resolved_slot_id))
		if FileAccess.file_exists(file_path):
			DirAccess.remove_absolute(file_path)
	_slot_meta[str(resolved_slot_id)] = {}
	_save_manager()
	if resolved_slot_id == _active_slot_id:
		_reload_slot_services()


func get_slot_summaries() -> Array[Dictionary]:
	_ensure_bootstrap()
	var summaries: Array[Dictionary] = []
	for slot_id in range(1, SLOT_COUNT + 1):
		summaries.append(_build_slot_summary(slot_id))
	return summaries


func peek_slot_summary(slot_id: int) -> Dictionary:
	_ensure_bootstrap()
	return _build_slot_summary(slot_id)


func has_slot_data(slot_id: int = -1) -> bool:
	var resolved_slot_id := _resolved_slot_id(slot_id)
	for file_name in _SLOT_FILES:
		if FileAccess.file_exists(slot_file_path(file_name, resolved_slot_id)):
			return true
	return false


func touch_active_slot(meta_patch: Dictionary = {}) -> void:
	_ensure_bootstrap()
	var slot_key := str(_active_slot_id)
	var meta: Dictionary = _slot_meta.get(slot_key, {}).duplicate(true)
	for key in meta_patch.keys():
		meta[key] = meta_patch[key]
	meta["last_played_at"] = int(Time.get_unix_time_from_system())
	_slot_meta[slot_key] = meta
	_save_manager()


func _ensure_bootstrap() -> void:
	if _bootstrapped:
		return
	_load_manager()
	_bootstrapped = true


func _load_manager() -> void:
	_active_slot_id = DEFAULT_SLOT_ID
	_slot_meta = {}
	if not FileAccess.file_exists(_manager_path()):
		_save_manager()
		return
	var dict := read_json_file(_manager_path())
	if dict.is_empty():
		return
	_active_slot_id = _sanitize_slot_id(int(dict.get("active_slot_id", DEFAULT_SLOT_ID)))
	var raw_meta: Variant = dict.get("slot_meta", {})
	if raw_meta is Dictionary:
		_slot_meta = (raw_meta as Dictionary).duplicate(true)


func _save_manager() -> void:
	var payload := {
		"active_slot_id": _active_slot_id,
		"slot_meta": _slot_meta,
	}
	write_json_atomic(_manager_path(), payload)


func _reload_slot_services() -> void:
	var run_service = get_node_or_null("/root/RunService")
	if run_service != null:
		run_service.reload_for_active_slot()
	var profile_service = get_node_or_null("/root/ProfileService")
	if profile_service != null:
		profile_service.reload_for_active_slot()
	var history_service = get_node_or_null("/root/RunHistoryService")
	if history_service != null:
		history_service.reload_for_active_slot()
	var adventure_service = get_node_or_null("/root/AdventureService")
	if adventure_service != null:
		adventure_service.reload_for_active_slot()
	var game_service = get_node_or_null("/root/GameService")
	if game_service != null:
		game_service.reset_session_state()
	var achievement_service = get_node_or_null("/root/AchievementService")
	if achievement_service != null:
		achievement_service.refresh_progress_flags()


func _build_slot_summary(slot_id: int) -> Dictionary:
	var resolved_slot_id := _sanitize_slot_id(slot_id)
	var slot_key := str(resolved_slot_id)
	var meta: Dictionary = _slot_meta.get(slot_key, {}).duplicate(true)
	var profile_data := _read_json_file(slot_file_path("profile.json", resolved_slot_id))
	var run_data := _read_json_file(slot_file_path("run_save.json", resolved_slot_id))
	var history_data := _read_json_file(slot_file_path("run_history.json", resolved_slot_id))
	var flags: Array = []
	if profile_data.get("flags", []) is Array:
		flags = profile_data.get("flags", [])
	var records: Array = []
	if history_data.get("records", []) is Array:
		records = history_data.get("records", [])
	var run_payload: Dictionary = {}
	if run_data.get("run", {}) is Dictionary:
		run_payload = run_data.get("run", {})
	var progress_payload: Dictionary = {}
	if run_data.get("progress", {}) is Dictionary:
		progress_payload = run_data.get("progress", {})
	var wins := 0
	for record in records:
		if record is Dictionary and str(record.get("type", "encounter")) == "run" and str(record.get("result", "")) == "win":
			wins += 1
	var seen_relics := 0
	for flag in flags:
		if str(flag).begins_with("seen_relic_"):
			seen_relics += 1
	var has_run := not run_payload.is_empty()
	var has_data := has_run or not flags.is_empty() or not records.is_empty()
	var invalid_reason := str(meta.get("run_invalid_reason", ""))
	var owned_relic_count := 0
	var raw_owned_relics: Variant = run_payload.get("owned_relics", [])
	if raw_owned_relics is Array:
		owned_relic_count = (raw_owned_relics as Array).size()
	var current_chapter := maxi(1, int(run_payload.get("current_chapter", 1)))
	var status := "空白档案"
	var subtitle := "尚未开始"
	if has_run:
		status = "进行中"
		subtitle = "第 %d 章 · 持有遗物 %d" % [current_chapter, owned_relic_count]
	elif not invalid_reason.is_empty():
		status = "进行中的这一局已失效"
		subtitle = invalid_reason
	elif has_data:
		status = "历史档案"
		subtitle = "累计胜利 %d 场" % wins
	var last_played_at := int(meta.get("last_played_at", 0))
	return {
		"slot_id": resolved_slot_id,
		"label": get_slot_label(resolved_slot_id),
		"is_active": resolved_slot_id == _active_slot_id,
		"has_run": has_run,
		"has_data": has_data,
		"run_invalid_reason": invalid_reason,
		"status": status,
		"subtitle": subtitle,
		"flag_count": flags.size(),
		"seen_relic_count": seen_relics,
		"history_count": records.size(),
		"win_count": wins,
		"owned_relic_count": owned_relic_count,
		"last_played_text": _format_timestamp(last_played_at),
	}


func _read_json_file(path: String) -> Dictionary:
	return read_json_file(path)


func _manager_path() -> String:
	var save_root := _save_root_override()
	if save_root.is_empty():
		return MANAGER_PATH
	return _join_path(save_root, "save_manager.json")


func _save_root_override() -> String:
	return _PersistencePathPolicy.save_root()


func _join_path(base_path: String, relative_path: String) -> String:
	var normalized_base := base_path.trim_suffix("/").trim_suffix("\\")
	if normalized_base.is_empty():
		return relative_path
	return "%s/%s" % [normalized_base, relative_path.trim_prefix("/").trim_prefix("\\")]


func _globalize_path(path: String) -> String:
	if _is_absolute_path(path):
		return path
	return ProjectSettings.globalize_path(path)


func _is_absolute_path(path: String) -> bool:
	if path.begins_with("/") or path.begins_with("\\\\"):
		return true
	return path.length() >= 3 and path.substr(1, 1) == ":" and path.substr(2, 1) in ["\\", "/"]


func _format_timestamp(timestamp: int) -> String:
	if timestamp <= 0:
		return "未记录"
	var dt := Time.get_datetime_dict_from_unix_time(timestamp)
	return "%02d-%02d %02d:%02d" % [
		int(dt.get("month", 1)),
		int(dt.get("day", 1)),
		int(dt.get("hour", 0)),
		int(dt.get("minute", 0)),
	]


func _resolved_slot_id(slot_id: int) -> int:
	return _active_slot_id if slot_id <= 0 else _sanitize_slot_id(slot_id)


func _sanitize_slot_id(slot_id: int) -> int:
	return clampi(slot_id, 1, SLOT_COUNT)
