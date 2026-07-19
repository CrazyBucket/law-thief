class_name EncounterExportService
extends RefCounted

const EncounterCodec = preload("res://scripts/debug/battle_editor_encounter_codec.gd")
const EncounterContentDiagnostics = preload("res://scripts/debug/encounter_content_diagnostics.gd")


static func export(state: GameState, payload: Dictionary) -> Dictionary:
	var generated := bool(payload.get("generated", false))
	var encounter := state.generated_encounter_blueprint.duplicate(true) if generated else EncounterCodec.export_from_state(state)
	if encounter.is_empty():
		return _fail("current battle was not procedurally generated")
	var encounter_id := str(payload.get("encounter_id", ""))
	if encounter_id.is_empty():
		if generated:
			var generation: Dictionary = encounter.get("generation", {})
			encounter_id = "generated_v%d_seed%d" % [int(generation.get("version", 0)), int(generation.get("seed", state.run_seed))]
		else:
			encounter_id = "editor_export_%s" % state.encounter_id
	var safe_id := _safe_id(encounter_id)
	var export_dir := ProjectSettings.globalize_path("user://exported_encounters")
	var dir_error := DirAccess.make_dir_recursive_absolute(export_dir)
	if dir_error != OK:
		return _fail("failed to create encounter export directory: %s" % error_string(dir_error))
	var export_path := export_dir.path_join("%s.json" % safe_id)
	var file := FileAccess.open(export_path, FileAccess.WRITE)
	if file == null:
		return _fail("failed to open encounter export: %s" % error_string(FileAccess.get_open_error()))
	file.store_string(JSON.stringify(encounter, "\t") + "\n")
	file = null
	return {
		"ok": true,
		"message": "exported encounter %s to %s" % [safe_id, export_path],
		"lines": JSON.stringify(encounter, "\t").split("\n"),
		"warnings": [] if generated else EncounterContentDiagnostics.refresh_messages(state),
		"encounter": encounter,
		"encounter_id": safe_id,
		"export_path": export_path,
	}


static func _safe_id(value: String) -> String:
	var safe := ""
	var allowed := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
	for index in range(value.length()):
		var character := value.substr(index, 1)
		safe += character if allowed.contains(character) else "_"
	return safe if not safe.is_empty() else "encounter_export"


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
