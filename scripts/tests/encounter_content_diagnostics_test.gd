extends SceneTree

const Codec = preload("res://scripts/debug/battle_editor_encounter_codec.gd")
const Diagnostics = preload("res://scripts/debug/encounter_content_diagnostics.gd")
const Snapshot = preload("res://scripts/testkit/state_snapshot.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Encounter Content Diagnostics Test ===")
	var registry: Node = root.get_node("DataRegistry")
	var state := registry.call("create_battle_state_from_editor_payload",
		"empty_enemy_warning_test",
		_editor_payload(false),
		701
	) as GameState
	assert(state != null, "unmarked editor payload should still load")
	assert(state.content_warnings.size() == 1, "unmarked empty-gem enemy should produce one non-blocking warning")
	var warning: Dictionary = state.content_warnings[0]
	assert(str(warning.get("code", "")) == Diagnostics.EMPTY_ENEMY_GEMS, "warning should use the stable diagnostic code")
	assert(str(warning.get("unit_def_id", "")) == "unit_patrol_guard", "warning should identify the authored enemy definition")
	assert(warning.get("pos", Vector2i.ZERO) == Vector2i(4, 4), "warning should identify the editor position")
	assert(Diagnostics.format_warning(warning).contains("allow_empty_gems=true"), "warning should explain the explicit opt-out")
	assert(state.clone().content_warnings == state.content_warnings, "display-state clones should preserve authoring diagnostics")
	var snapshot := Snapshot.capture(state, [], false)
	assert((snapshot.get("content_warnings", []) as Array).size() == 1, "debug snapshots should expose content warnings")
	assert((snapshot.get("invariants", []) as Array).is_empty(), "diagnostics must not invalidate battle state")
	assert((snapshot.get("event_violations", []) as Array).is_empty(), "diagnostics must not fabricate combat events")

	var exported := Codec.export_from_state(state)
	var exported_enemy: Dictionary = (exported.get("enemies", []) as Array)[0]
	var exported_slots: Array = exported_enemy.get("slots", [])
	assert(exported_slots.size() == 3, "editor export must preserve all explicitly empty enemy slots")
	for slot in exported_slots:
		assert(not (slot as Dictionary).has("gem_id"), "empty enemy slots should round-trip without invented gems")

	var controller := BattleController.new()
	controller.start_encounter("tutorial_001", 701)
	controller.state = state
	var warning_export := controller.run_editor_command("export encounter empty_enemy_warning_test")
	assert(warning_export.get("ok", false), "editor export should remain non-blocking when warnings exist")
	assert((warning_export.get("warnings", []) as Array).size() == 1, "editor export should surface the structured warning")

	var allowed_state := registry.call("create_battle_state_from_editor_payload",
		"allowed_empty_enemy_test",
		_editor_payload(true),
		702
	) as GameState
	assert(allowed_state != null, "explicitly allowed empty-gem payload should load")
	var allowed_enemy: UnitState = allowed_state.get_alive_enemies()[0]
	assert(allowed_enemy.has_tag(Diagnostics.ALLOW_EMPTY_TAG), "encounter marker should propagate to runtime unit metadata")
	assert(allowed_state.content_warnings.is_empty(), "explicit marker should suppress only the authoring warning")
	var allowed_export := Codec.export_from_state(allowed_state)
	var allowed_export_enemy: Dictionary = (allowed_export.get("enemies", []) as Array)[0]
	assert(bool(allowed_export_enemy.get("allow_empty_gems", false)), "editor export should preserve the explicit marker")

	var json_round_trip: Variant = JSON.parse_string(JSON.stringify(allowed_export))
	assert(json_round_trip is Dictionary, "editor export should remain strict JSON")
	var parsed_round_trip := Codec.parse_import(json_round_trip as Dictionary)
	var restored_state := registry.call("create_battle_state_from_editor_payload", "allowed_empty_enemy_restored", parsed_round_trip, 703) as GameState
	assert(restored_state != null and restored_state.content_warnings.is_empty(), "JSON editor round-trip should preserve the warning exemption")
	assert(restored_state.get_alive_enemies()[0].has_tag(Diagnostics.ALLOW_EMPTY_TAG), "round-trip marker should reach the restored unit")
	assert(BattleInvariantChecker.assert_valid(restored_state, "encounter_content_diagnostics.round_trip"))
	assert(EventValidator.assert_valid([], "encounter_content_diagnostics.no_events"))

	var allowed_def: Dictionary = registry.get_unit_def("unit_patrol_guard")
	allowed_def["allow_empty_gems"] = true
	var unit_from_def := UnitState.from_def("allowed_def_enemy", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i.ZERO, allowed_def)
	assert(unit_from_def.has_tag(Diagnostics.ALLOW_EMPTY_TAG), "unit definition marker should propagate to runtime metadata")
	print("ENCOUNTER_CONTENT_DIAGNOSTICS_TEST_PASS")
	quit(0)


func _editor_payload(allow_empty: bool) -> Dictionary:
	var enemy := {
		"def_id": "unit_patrol_guard",
		"pos": Vector2i(4, 4),
		"slots": [
			{"slot_type": Constants.SLOT_RED},
			{"slot_type": Constants.SLOT_BLUE},
			{"slot_type": Constants.SLOT_BLACK},
		],
	}
	if allow_empty:
		enemy["allow_empty_gems"] = true
	return {
		"schema_version": 2,
		"player_spawn": Vector2i(1, 1),
		"floor_seed": 700,
		"enemies": [enemy],
		"entities": [],
		"tiles": [],
	}
