extends SceneTree

## 手动冷启动探针：分段记录内容目录、战斗状态、场景加载、实例化和首帧成本。
## 不设跨机器阈值；输出用于同一机器和构建配置下的前后对比。

const BATTLE_SCENE_PATH := "res://scenes/battle/battle_scene.tscn"
const BATTLE_SCRIPT_PATH := "res://scripts/ui/battle_scene.gd"
const BOARD_SCRIPT_PATH := "res://scripts/ui/isometric_board.gd"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Startup Performance Test ===")
	var registry: Node = root.get_node("DataRegistry")
	var registry_ms := float(registry.call("get_startup_load_duration_ms"))

	var state_started := Time.get_ticks_usec()
	var probe_state: GameState = registry.create_battle_state("tutorial_001", 1, "startup_probe", false)
	var state_ms := _elapsed_ms(state_started)
	assert(probe_state != null, "startup probe should create its deterministic battle state")

	var battle_script_started := Time.get_ticks_usec()
	var battle_script := load(BATTLE_SCRIPT_PATH) as Script
	var battle_script_load_ms := _elapsed_ms(battle_script_started)
	assert(battle_script != null, "startup probe should load the battle script")

	var board_script_started := Time.get_ticks_usec()
	var board_script := load(BOARD_SCRIPT_PATH) as Script
	var board_script_load_ms := _elapsed_ms(board_script_started)
	assert(board_script != null, "startup probe should load the board script")

	var load_started := Time.get_ticks_usec()
	var packed_scene := load(BATTLE_SCENE_PATH) as PackedScene
	var scene_load_ms := _elapsed_ms(load_started)
	assert(packed_scene != null, "startup probe should load the battle scene")

	var instantiate_started := Time.get_ticks_usec()
	var battle_scene := packed_scene.instantiate()
	var instantiate_ms := _elapsed_ms(instantiate_started)
	assert(battle_scene != null, "startup probe should instantiate the battle scene")

	var ready_started := Time.get_ticks_usec()
	root.add_child(battle_scene)
	await process_frame
	var first_frame_ms := _elapsed_ms(ready_started)
	var battle_ready_ms := float(battle_scene.call("get_startup_ready_duration_ms"))
	var start_battle_ms := float(battle_scene.call("get_startup_start_battle_duration_ms"))
	var board: Node = battle_scene.get_node("BoardLayer/IsometricBoard")
	var board_ready_ms := float(board.call("get_startup_ready_duration_ms"))
	var first_draw_metrics: Dictionary = board.call("get_startup_first_draw_metrics")

	var settle_started := Time.get_ticks_usec()
	await process_frame
	var second_frame_ms := _elapsed_ms(settle_started)
	var background_frame_ms: Array[float] = []
	for _frame_index in range(8):
		var frame_started := Time.get_ticks_usec()
		await process_frame
		background_frame_ms.append(_elapsed_ms(frame_started))
	var background_max_frame_ms := 0.0
	var background_total_ms := 0.0
	for frame_ms in background_frame_ms:
		background_max_frame_ms = maxf(background_max_frame_ms, frame_ms)
		background_total_ms += frame_ms
	for _settle_index in range(20):
		await process_frame
	var steady_draw_count_before := int(board.call("get_draw_count"))
	var steady_started := Time.get_ticks_usec()
	for _steady_index in range(60):
		await process_frame
	var steady_elapsed_seconds := maxf(float(Time.get_ticks_usec() - steady_started) / 1000000.0, 0.001)
	var steady_board_redraw_hz := float(int(board.call("get_draw_count")) - steady_draw_count_before) / steady_elapsed_seconds
	print(
		"STARTUP_PERF data_registry_ms=%.3f state_factory_ms=%.3f battle_script_load_ms=%.3f board_script_load_ms=%.3f scene_load_ms=%.3f total_scene_resource_ms=%.3f instantiate_ms=%.3f board_ready_ms=%.3f battle_ready_ms=%.3f start_battle_ms=%.3f first_draw_ms=%.3f draw_ground_ms=%.3f draw_unit_body_ms=%.3f draw_entity_ui_ms=%.3f draw_unit_ui_ms=%.3f first_frame_ms=%.3f second_frame_ms=%.3f background_max_frame_ms=%.3f background_total_ms=%.3f steady_board_redraw_hz=%.3f" % [
			registry_ms,
			state_ms,
			battle_script_load_ms,
			board_script_load_ms,
			scene_load_ms,
			battle_script_load_ms + board_script_load_ms + scene_load_ms,
			instantiate_ms,
			board_ready_ms,
			battle_ready_ms,
			start_battle_ms,
			float(first_draw_metrics.get("total_ms", 0.0)),
			float(first_draw_metrics.get("ground_ms", 0.0)),
			float(first_draw_metrics.get("unit_body_ms", 0.0)),
			float(first_draw_metrics.get("entity_ui_ms", 0.0)),
			float(first_draw_metrics.get("unit_ui_ms", 0.0)),
			first_frame_ms,
			second_frame_ms,
			background_max_frame_ms,
			background_total_ms,
			steady_board_redraw_hz,
		]
	)
	battle_scene.queue_free()
	await process_frame
	print("STARTUP_PERFORMANCE_TEST_PASS")
	quit()


func _elapsed_ms(started_usec: int) -> float:
	return float(Time.get_ticks_usec() - started_usec) / 1000.0
