extends Node

const HISTORY_FILE_NAME := "run_history.json"
const HISTORY_VERSION := 1
const MAX_RECORDS := 100

var _records: Array[Dictionary] = []


func _ready() -> void:
	load_history()


func record_encounter(payload: Dictionary) -> void:
	var entry := payload.duplicate(true)
	entry["timestamp"] = int(Time.get_unix_time_from_system())
	_records.append(entry)
	if _records.size() > MAX_RECORDS:
		_records.pop_front()
	save_history()


func get_recent(limit: int = 10) -> Array[Dictionary]:
	var start := maxi(0, _records.size() - limit)
	var result: Array[Dictionary] = []
	for entry in _records.slice(start):
		if entry is Dictionary:
			result.append((entry as Dictionary).duplicate(true))
	return result


func get_total_runs() -> int:
	return _records.size()


func get_total_wins() -> int:
	var wins := 0
	for entry in _records:
		if str(entry.get("result", "")) == "win":
			wins += 1
	return wins


func get_encounter_win_count(encounter_id: String) -> int:
	var wins := 0
	for entry in _records:
		if str(entry.get("encounter_id", "")) == encounter_id and str(entry.get("result", "")) == "win":
			wins += 1
	return wins


func get_summary() -> Dictionary:
	return {
		"total_runs": get_total_runs(),
		"total_wins": get_total_wins(),
	}


func clear() -> void:
	_records.clear()
	save_history()


func reload_for_active_slot() -> void:
	load_history()


func load_history() -> void:
	_records.clear()
	var path := SaveService.slot_file_path(HISTORY_FILE_NAME)
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return
	var data: Variant = json.get_data()
	if not data is Dictionary:
		return
	var raw_records: Variant = (data as Dictionary).get("records", [])
	if raw_records is Array:
		for entry in raw_records:
			if entry is Dictionary:
				_records.append((entry as Dictionary).duplicate(true))


func save_history() -> void:
	var slot_dir := ProjectSettings.globalize_path(SaveService.get_slot_dir())
	DirAccess.make_dir_recursive_absolute(slot_dir)
	var path := SaveService.slot_file_path(HISTORY_FILE_NAME)
	var payload := {
		"version": HISTORY_VERSION,
		"records": _records,
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	SaveService.touch_active_slot({
		"history_count": _records.size(),
		"win_count": get_total_wins(),
	})
