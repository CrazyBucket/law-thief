extends SceneTree

const _Loader = preload("res://scripts/services/encounter_catalog_loader.gd")

var _reported_errors: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var entries := _Loader.load_raw_entries(
		"res://tests/fixtures/encounters/",
		{},
		Callable(self, "_read_json"),
		Callable(self, "_accept"),
		Callable(self, "_report")
	)
	assert(not entries.is_empty())
	var first_id := str(entries.keys()[0])
	assert(entries.has(first_id))
	assert(_reported_errors.is_empty())
	var duplicate_entries := _Loader.load_raw_entries(
		"res://tests/fixtures/encounters/",
		entries,
		Callable(self, "_read_json"),
		Callable(self, "_accept"),
		Callable(self, "_report")
	)
	assert(duplicate_entries.is_empty())
	assert(not _reported_errors.is_empty())
	print("ENCOUNTER_CATALOG_LOADER_TEST_PASS")
	quit()


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	return JSON.parse_string(file.get_as_text()) as Dictionary if file != null else {}


func _accept(_encounter_id: String, _raw: Dictionary) -> Array[String]:
	return []


func _report(_path: String, errors: Array[String]) -> void:
	if not errors.is_empty():
		_reported_errors.append_array(errors)
