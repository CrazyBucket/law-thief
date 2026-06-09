extends Node

const HISTORY_FILE_NAME := "run_history.json"
const HISTORY_VERSION := 2
const MAX_RECORDS := 100

var _records: Array[Dictionary] = []


func _ready() -> void:
	load_history()


func record_encounter(payload: Dictionary) -> void:
	var entry := payload.duplicate(true)
	entry["type"] = "encounter"
	entry["timestamp"] = int(Time.get_unix_time_from_system())
	_records.append(entry)
	if _records.size() > MAX_RECORDS:
		_records.pop_front()
	save_history()


func record_run(payload: Dictionary) -> void:
	var entry := payload.duplicate(true)
	entry["type"] = "run"
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
	var count := 0
	for entry in _records:
		if str(entry.get("type", "encounter")) == "run":
			count += 1
	return count


func get_total_wins() -> int:
	var wins := 0
	for entry in _records:
		if str(entry.get("type", "encounter")) == "run" and str(entry.get("result", "")) == "win":
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
	var dict := SaveService.read_json_file(path)
	if dict.is_empty():
		return
	var raw_records: Variant = dict.get("records", [])
	if raw_records is Array:
		for entry in raw_records:
			if entry is Dictionary:
				_records.append((entry as Dictionary).duplicate(true))


func save_history() -> void:
	var payload := {
		"version": HISTORY_VERSION,
		"records": _records,
	}
	if not SaveService.write_json_atomic(SaveService.slot_file_path(HISTORY_FILE_NAME), payload):
		return
	SaveService.touch_active_slot({
		"history_count": _records.size(),
		"win_count": get_total_wins(),
	})
