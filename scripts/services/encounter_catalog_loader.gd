class_name EncounterCatalogLoader
extends RefCounted


## File access and validation are injected so loading has no dependency on registry state.
static func load_raw_entries(
	dir_path: String,
	existing_ids: Dictionary,
	read_json: Callable,
	validate: Callable,
	report_errors: Callable
) -> Dictionary:
	var entries: Dictionary = {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return entries
	var file_names: Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			file_names.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	file_names.sort()
	for catalog_file_name in file_names:
		var encounter_id := catalog_file_name.get_basename()
		var path := dir_path.path_join(catalog_file_name)
		var raw: Dictionary = read_json.call(path) if read_json.is_valid() else {}
		var errors: Array[String] = validate.call(encounter_id, raw) if validate.is_valid() else ["missing encounter validator"]
		if existing_ids.has(encounter_id) or entries.has(encounter_id):
			errors.append("encounters.%s duplicates an already loaded id" % encounter_id)
		if report_errors.is_valid():
			report_errors.call(path, errors)
		if errors.is_empty():
			entries[encounter_id] = raw
	return entries
