extends SceneTree

const TARGET_SCENE := "res://tests/fixtures/scenes/transition_target.tscn"
const SILHOUETTE_PATH := "res://assets/ui/transitions/star_silhouette.png"

var _manager: Node
var _overlay: ColorRect
var _signals: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_manager = root.get_node("TransitionManager")
	_overlay = _manager.get_node("TransitionLayer/Overlay") as ColorRect
	_connect_signal_trace()
	_test_initial_contract()
	await _test_scene_prefetch_contract()
	await _test_checkerboard_cover_reveal()
	await _test_silhouette_contract()
	await _test_scene_change_contracts()
	_manager.reset_immediately()
	print("TRANSITION_MANAGER_TEST_PASS")
	quit(0)


func _test_initial_contract() -> void:
	_manager.reset_immediately()
	assert(not _manager.is_transitioning(), "transition manager should start idle")
	assert(not _manager.is_covered(), "transition manager should start uncovered")
	assert(not _overlay.visible, "idle transition overlay should be hidden")
	assert(_overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE, "idle overlay must not block input")
	assert(ResourceLoader.exists(TARGET_SCENE, "PackedScene"), "transition target fixture should be loadable")
	assert(ResourceLoader.exists(SILHOUETTE_PATH, "Texture2D"), "default silhouette raster should be imported")
	var invalid_style: bool = await _manager.cover(999, 0.0)
	assert(not invalid_style and not _manager.is_transitioning(), "unknown styles must fail without changing state")
	var idle_reveal: bool = await _manager.reveal(0.0)
	assert(not idle_reveal, "reveal should reject an uncovered idle manager")


func _test_scene_prefetch_contract() -> void:
	assert(_manager.prefetch_scene(TARGET_SCENE) == OK, "existing scenes should accept background prefetch")
	while ResourceLoader.load_threaded_get_status(TARGET_SCENE) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await process_frame
	assert(
		ResourceLoader.load_threaded_get_status(TARGET_SCENE) == ResourceLoader.THREAD_LOAD_LOADED,
		"prefetched scene should remain ready for the later transition"
	)
	assert(_manager.prefetch_scene(TARGET_SCENE) == OK, "prefetching an already loaded request should be idempotent")


func _test_checkerboard_cover_reveal() -> void:
	_signals.clear()
	var covered: bool = await _manager.cover(_manager.Style.CHECKERBOARD, 0.0, {
		"columns": 1,
		"rows": 99,
		"stagger": 1.0,
		"edge_width": -1.0,
		"cover_color": Color("112233"),
	})
	assert(covered, "checkerboard cover should start from idle")
	assert(_manager.is_transitioning() and _manager.is_covered(), "completed cover should remain held")
	assert(_manager.current_style() == _manager.Style.CHECKERBOARD, "current style should track the held cover")
	assert(_overlay.visible and _overlay.mouse_filter == Control.MOUSE_FILTER_STOP, "held cover must block input")
	assert(_signals == ["start:0", "midpoint:0"], "cover should emit start then midpoint")
	var material := _overlay.material as ShaderMaterial
	assert(material != null, "checkerboard cover should install a shader material")
	assert(material.get_shader_parameter("grid_size") == Vector2(2, 64), "checkerboard grid options should be clamped")
	assert(is_equal_approx(float(material.get_shader_parameter("stagger")), 0.35), "checkerboard stagger should be clamped")
	assert(is_zero_approx(float(material.get_shader_parameter("edge_width"))), "checkerboard edge width should be clamped")
	assert(material.get_shader_parameter("cover_color") == Color("112233"), "cover color should reach the shader")
	var busy_result: int = await _manager.change_scene(TARGET_SCENE, _manager.Style.CHECKERBOARD, 0.0)
	assert(busy_result == ERR_BUSY, "a held transition must reject reentrant scene changes")
	var revealed: bool = await _manager.reveal(0.0)
	assert(revealed, "held checkerboard should reveal")
	assert(_signals == ["start:0", "midpoint:0", "finished:0"], "reveal should emit the matching finish signal")
	_assert_idle("checkerboard reveal")


func _test_silhouette_contract() -> void:
	_signals.clear()
	var covered: bool = await _manager.cover(_manager.Style.SILHOUETTE, 0.0, {
		"center": Vector2(-2.0, 3.0),
		"maximum_scale": 9.0,
		"fill_start": 0.0,
		"mask_channel": 99,
	})
	assert(covered, "silhouette cover should start from idle")
	var material := _overlay.material as ShaderMaterial
	assert(material.get_shader_parameter("mask_texture") is Texture2D, "silhouette shader should receive a raster mask")
	assert(material.get_shader_parameter("center") == Vector2(0.0, 1.0), "silhouette center should be normalized")
	assert(is_equal_approx(float(material.get_shader_parameter("maximum_scale")), 4.0), "silhouette scale should be clamped")
	assert(is_equal_approx(float(material.get_shader_parameter("fill_start")), 0.25), "silhouette fill threshold should be clamped")
	assert(int(material.get_shader_parameter("mask_channel")) == 2, "silhouette mask channel should be clamped")
	assert(float(material.get_shader_parameter("mask_aspect")) > 0.0, "silhouette mask aspect should be valid")
	_manager.reset_immediately()
	_assert_idle("silhouette reset")


func _test_scene_change_contracts() -> void:
	var missing_error: int = await _manager.change_scene("res://tests/fixtures/scenes/missing_transition_target.tscn")
	assert(missing_error == ERR_FILE_NOT_FOUND, "missing target scenes should be rejected before covering")
	var direction_error: int = await _manager.change_scene(TARGET_SCENE, _manager.Style.CHECKERBOARD, 0.0, {}, 99)
	assert(direction_error == ERR_INVALID_PARAMETER, "unknown transition directions should be rejected")
	_assert_idle("invalid scene changes")

	_signals.clear()
	var out_error: int = await _manager.change_scene(
		TARGET_SCENE,
		_manager.Style.CHECKERBOARD,
		0.0,
		{"columns": 8},
		_manager.Direction.OUT
	)
	assert(out_error == OK, "out transition should change to an existing scene")
	assert(current_scene != null and current_scene.name == "TransitionTarget", "out transition should install the target scene")
	assert(_signals == ["start:0", "midpoint:0", "finished:0"], "out scene change should emit one complete lifecycle")
	_assert_idle("out scene change")

	_signals.clear()
	var in_error: int = await _manager.change_scene(
		TARGET_SCENE,
		_manager.Style.SILHOUETTE,
		0.0,
		{},
		_manager.Direction.IN
	)
	assert(in_error == OK, "in transition should change to an existing scene")
	assert(current_scene != null and current_scene.name == "TransitionTarget", "in transition should install the target scene")
	assert(_signals == ["start:1", "midpoint:1", "finished:1"], "in scene change should emit one complete lifecycle")
	_assert_idle("in scene change")


func _connect_signal_trace() -> void:
	_manager.transition_started.connect(func(style: int) -> void: _signals.append("start:%d" % style))
	_manager.transition_midpoint.connect(func(style: int) -> void: _signals.append("midpoint:%d" % style))
	_manager.transition_finished.connect(func(style: int) -> void: _signals.append("finished:%d" % style))


func _assert_idle(context: String) -> void:
	assert(not _manager.is_transitioning(), "%s should leave the manager idle" % context)
	assert(not _manager.is_covered(), "%s should leave the manager uncovered" % context)
	assert(not _overlay.visible, "%s should hide the overlay" % context)
	assert(_overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE, "%s should release pointer input" % context)
