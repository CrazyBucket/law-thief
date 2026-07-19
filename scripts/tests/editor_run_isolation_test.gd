extends SceneTree


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var run_service: Node = root.get_node("RunService")
	run_service.start_run(303, 404)
	var run: RunState = run_service.get_run()
	run.player_max_hp = 12
	run.player_hp = 0
	run_service.acquire_relic("relic_prism")
	var run_snapshot: Dictionary = run_service.snapshot_active_run()
	run_service.begin_temporary_run()
	var editor_ctrl := BattleController.new()
	editor_ctrl.start_encounter("tutorial_001", 42, "", false)
	var editor_player := editor_ctrl.state.get_player()
	var data_registry: Node = root.get_node("DataRegistry")
	var default_max_hp := int(data_registry.get_unit_def("unit_player").get("max_hp", 0))
	assert(editor_player.hp == default_max_hp, "editor battle should ignore saved player HP")
	assert(editor_player.max_hp == default_max_hp, "editor battle should ignore saved player max HP")
	assert(not run_service.has_relic("relic_prism"), "editor battle should not inherit saved relics")
	run_service.restore_run_snapshot(run_snapshot)
	run = run_service.get_run()
	assert(run.player_hp == 0 and run.player_max_hp == 12, "editor battle must not alter the active run")
	assert(run_service.has_relic("relic_prism"), "editor battle must restore saved relics")
	var normal_ctrl := BattleController.new()
	normal_ctrl.start_encounter("tutorial_001", 42)
	assert(normal_ctrl.state.get_player().hp == 0, "normal battle should still restore the active run")
	run_service.end_run()
	print("EDITOR_RUN_ISOLATION_TEST_PASS")
	quit()
