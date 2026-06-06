extends SceneTree

const WaterAutotileClass := preload("res://scripts/map/water_autotile.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_test_shape("single", [Vector2i(0, 0)], 4, 0, {Vector2i(0, 0): Vector4i(7, 7, 7, 7)})
	_test_shape("domino", [Vector2i(0, 0), Vector2i(1, 0)], 6, 0, {
		Vector2i(0, 0): Vector4i(7, 3, 6, 7),
		Vector2i(1, 0): Vector4i(3, 7, 7, 6),
	})
	_test_shape("square", [
		Vector2i(0, 0), Vector2i(1, 0),
		Vector2i(0, 1), Vector2i(1, 1),
	], 8, 0, {
		Vector2i(0, 0): Vector4i(7, 3, 0, 3),
		Vector2i(1, 0): Vector4i(3, 7, 3, 0),
		Vector2i(0, 1): Vector4i(6, 0, 6, 7),
		Vector2i(1, 1): Vector4i(0, 6, 7, 6),
	})
	_test_shape("L", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)], 8, 1, {
		Vector2i(0, 0): Vector4i(7, 3, 2, 3),
		Vector2i(1, 0): Vector4i(3, 7, 7, 4),
		Vector2i(0, 1): Vector4i(6, 4, 7, 7),
	})
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("WATER_AUTOTILE_TEST_PASS")
	quit()


func _test_shape(
	label: String,
	cells: Array[Vector2i],
	expected_edges: int,
	expected_corners: int,
	expected_states: Dictionary = {}
) -> void:
	var water := {}
	for cell in cells:
		water[cell] = true
	var edges := WaterAutotileClass.exposed_edge_count(water)
	var corners := WaterAutotileClass.inner_corner_count(water)
	_require(edges == expected_edges, "%s exposed edges: expected %d, got %d" % [label, expected_edges, edges])
	_require(corners == expected_corners, "%s inner corners: expected %d, got %d" % [label, expected_corners, corners])
	for pos: Vector2i in expected_states:
		var actual := WaterAutotileClass.states(pos, water)
		_require(actual == expected_states[pos], "%s state at %s: expected %s, got %s" % [
			label, pos, expected_states[pos], actual,
		])
	_assert_no_shared_edges(label, water)
	print("  [OK] %s edges=%d corners=%d states=%s" % [label, edges, corners, _state_summary(cells, water)])


func _assert_no_shared_edges(label: String, water: Dictionary) -> void:
	for pos: Vector2i in water:
		var state := WaterAutotileClass.states(pos, water)
		_require(not water.has(pos + WaterAutotileClass.BACK_RIGHT) or (not bool(state.x & 1) and not bool(state.y & 1)),
			"%s has an internal back-right edge at %s" % [label, pos])
		_require(not water.has(pos + WaterAutotileClass.BACK_LEFT) or (not bool(state.x & 4) and not bool(state.w & 1)),
			"%s has an internal back-left edge at %s" % [label, pos])
		_require(not water.has(pos + WaterAutotileClass.FRONT_RIGHT) or (not bool(state.y & 4) and not bool(state.z & 1)),
			"%s has an internal front-right edge at %s" % [label, pos])
		_require(not water.has(pos + WaterAutotileClass.FRONT_LEFT) or (not bool(state.z & 4) and not bool(state.w & 4)),
			"%s has an internal front-left edge at %s" % [label, pos])


func _state_summary(cells: Array[Vector2i], water: Dictionary) -> String:
	var parts: Array[String] = []
	for pos in cells:
		var state := WaterAutotileClass.states(pos, water)
		parts.append("%s:%d/%d/%d/%d" % [pos, state.x, state.y, state.z, state.w])
	return ", ".join(parts)


func _require(condition: bool, message: String) -> void:
	if condition:
		return
	failures.append(message)
