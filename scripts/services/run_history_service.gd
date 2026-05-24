extends Node

var _records: Array = []


func record_encounter(payload: Dictionary) -> void:
	_records.append(payload.duplicate(true))
	if _records.size() > 50:
		_records.pop_front()


func get_recent(limit: int = 10) -> Array:
	var start := maxi(0, _records.size() - limit)
	return _records.slice(start)


func clear() -> void:
	_records.clear()
