extends SceneTree

const Policy = preload("res://scripts/services/persistence_path_policy.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Persistence Isolation Test ===")
	_test_resolution_policy()
	_test_live_process_is_sandboxed()
	print("PERSISTENCE_ISOLATION_TEST_PASS")
	quit()


func _test_resolution_policy() -> void:
	var test_args := PackedStringArray(["--headless", "--script", "res://scripts/tests/ui_compile_test.gd"])
	var test_root := Policy.resolve_save_root("", test_args, 42)
	assert(test_root.replace("\\", "/").ends_with("/artifacts/verify/userdata/standalone/ui_compile_test_42/save"), "test scripts should receive a deterministic process sandbox")

	var tool_args := PackedStringArray(["--script=res://scripts/tools/ui_visual_probe.gd"])
	var tool_root := Policy.resolve_save_root("", tool_args, 73)
	assert(tool_root.replace("\\", "/").ends_with("/artifacts/verify/userdata/standalone/ui_visual_probe_73/save"), "tool scripts should receive a process sandbox")

	var explicit_root := Policy.resolve_save_root("D:/isolated/root/", test_args, 99)
	assert(explicit_root == "D:/isolated/root", "explicit save roots must take precedence and normalize trailing separators")
	assert(Policy.resolve_save_root("", PackedStringArray(["--path", "."]), 7).is_empty(), "normal game startup must keep the default user path")
	print("  [OK] command-line persistence policy")


func _test_live_process_is_sandboxed() -> void:
	var save_service: Node = root.get_node("SaveService")
	var settings_service: Node = root.get_node("SettingsService")
	var save_root := Policy.save_root()
	assert(not save_root.is_empty(), "a test process must never resolve to the player persistence root")
	var normalized_root := save_root.replace("\\", "/").trim_suffix("/")
	var slot_dir := str(save_service.call("get_slot_dir")).replace("\\", "/")
	var settings_path := str(settings_service.call("get_settings_path")).replace("\\", "/")
	assert(slot_dir.begins_with(normalized_root + "/"), "slot data must remain inside the resolved sandbox")
	assert(settings_path.begins_with(normalized_root + "/"), "settings must share the resolved sandbox")
	assert(not slot_dir.begins_with("user://") and settings_path != Policy.DEFAULT_SETTINGS_PATH, "test persistence must not fall back to player user:// files")

	var marker_path := str(save_service.call("slot_file_path", "persistence_isolation_probe.json"))
	assert(bool(save_service.call("write_json_atomic", marker_path, {"sandboxed": true})), "sandbox marker should be writable")
	assert(FileAccess.file_exists(marker_path), "sandbox marker should stay inside the test root")
	settings_service.call("set_value", "show_tutorial", bool(settings_service.call("get_value", "show_tutorial")))
	assert(FileAccess.file_exists(settings_path), "settings writes should stay inside the test root")
	print("  [OK] live persistence root %s" % normalized_root)
