extends SceneTree


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Save Service Atomic Test ===")
	var save_service: Node = root.get_node("SaveService")
	var path: String = str(save_service.slot_file_path("atomic_test.json"))
	var ok_first: bool = bool(save_service.write_json_atomic(path, {"value": 1, "nested": {"ok": true}}))
	assert(ok_first, "first atomic write should succeed")
	var first: Dictionary = save_service.read_json_file(path)
	assert(int(first.get("value", 0)) == 1, "first atomic write should be readable")
	var ok_second: bool = bool(save_service.write_json_atomic(path, {"value": 2}))
	assert(ok_second, "second atomic write should succeed")
	var second: Dictionary = save_service.read_json_file(path)
	assert(int(second.get("value", 0)) == 2, "second atomic write should replace file")
	var backup_path := "%s.bak" % ProjectSettings.globalize_path(path)
	assert(FileAccess.file_exists(backup_path), "atomic rewrite should leave a backup")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(backup_path)
	print("SAVE_SERVICE_ATOMIC_TEST_PASS")
	quit()
