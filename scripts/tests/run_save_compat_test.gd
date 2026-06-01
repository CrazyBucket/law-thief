extends SceneTree


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Run Save Compat Test ===")
	var run_service: Node = Engine.get_main_loop().root.get_node("RunService")
	_test_current_save_is_compatible(run_service)
	_test_future_schema_is_rejected(run_service)
	_test_ruleset_mismatch_is_rejected(run_service)
	_test_missing_run_payload_is_rejected(run_service)
	print("RUN_SAVE_COMPAT_TEST_PASS")
	quit()


func _test_current_save_is_compatible(run_service: Node) -> void:
	var meta: Dictionary = run_service.get_save_compat_meta()
	var compat: Dictionary = run_service.inspect_run_save_compat({
		"save_schema_version": meta.get("save_schema_version", 1),
		"ruleset_version": meta.get("ruleset_version", 1),
		"run": {},
	})
	assert(compat.get("ok", false), "current save should be compatible")
	print("  [OK] current schema accepted")


func _test_future_schema_is_rejected(run_service: Node) -> void:
	var meta: Dictionary = run_service.get_save_compat_meta()
	var compat: Dictionary = run_service.inspect_run_save_compat({
		"save_schema_version": int(meta.get("save_schema_version", 1)) + 1,
		"ruleset_version": meta.get("ruleset_version", 1),
		"run": {},
	})
	assert(not compat.get("ok", true), "future schema should be rejected")
	print("  [OK] future schema rejected")


func _test_ruleset_mismatch_is_rejected(run_service: Node) -> void:
	var meta: Dictionary = run_service.get_save_compat_meta()
	var compat: Dictionary = run_service.inspect_run_save_compat({
		"save_schema_version": meta.get("save_schema_version", 1),
		"ruleset_version": int(meta.get("ruleset_version", 1)) + 1,
		"run": {},
	})
	assert(not compat.get("ok", true), "ruleset mismatch should be rejected")
	print("  [OK] ruleset mismatch rejected")


func _test_missing_run_payload_is_rejected(run_service: Node) -> void:
	var meta: Dictionary = run_service.get_save_compat_meta()
	var compat: Dictionary = run_service.inspect_run_save_compat({
		"save_schema_version": meta.get("save_schema_version", 1),
		"ruleset_version": meta.get("ruleset_version", 1),
	})
	assert(not compat.get("ok", true), "missing run payload should be rejected")
	print("  [OK] missing run payload rejected")
