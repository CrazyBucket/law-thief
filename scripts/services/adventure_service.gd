extends Node

const _AdventureMapGenerator := preload("res://scripts/map/adventure_map_generator.gd")
const _AdventureRoomDisplay := preload("res://scripts/map/adventure_room_display.gd")
const _AdventureBoardGenerator := preload("res://scripts/map/adventure_board_generator.gd")
const _MapNode := preload("res://scripts/map/map_node.gd")

const MAP_SCENE := "res://scenes/map/adventure_map.tscn"
const PLACEHOLDER_SCENE := "res://scenes/adventure/room_placeholder.tscn"
const BATTLE_SCENE := "res://scenes/battle/battle_scene.tscn"

const COMBAT_ENCOUNTERS: Dictionary = {
	"NORMAL_COMBAT": ["template_a", "template_b", "template_c"],
	"ELITE_COMBAT": ["template_d", "template_b"],
}

var map_seed: int = 20260525
var map_matrix: Array = []
var current_pos: Vector2i = Vector2i.ZERO
var run_active: bool = false
var pending_room_type: String = ""
var pending_room_label: String = ""


func start_new_run(seed_value: int = -1) -> void:
	if seed_value < 0:
		seed_value = int(Time.get_unix_time_from_system()) % 100000
	map_seed = seed_value
	RunService.start_run(map_seed, map_seed)
	var gen := _AdventureMapGenerator.new()
	map_matrix = gen.generate(map_seed)
	current_pos = Vector2i.ZERO
	run_active = true
	pending_room_type = "START"
	pending_room_label = "🏁 起点"
	_sync_run_progress()
	DebugService.log_info("Adventure run started seed=%d" % map_seed)


func build_board_state() -> GameState:
	return _AdventureBoardGenerator.build(map_matrix, map_seed)


func get_node_at(cell: Vector2i):
	return _get_node(cell.x, cell.y)


func get_current_node():
	return _get_node(current_pos.x, current_pos.y)


func get_reachable_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var node = get_current_node()
	if node == null:
		return result
	for child_pos: Vector2i in node.children:
		result.append(child_pos)
	return result


func can_enter_cell(cell: Vector2i) -> bool:
	if not run_active:
		return false
	var node = _get_node(cell.x, cell.y)
	if node == null:
		return false
	if cell == current_pos:
		return false
	for child_pos: Vector2i in get_current_node().children:
		if child_pos == cell:
			return true
	return false


func enter_cell(cell: Vector2i) -> void:
	if not can_enter_cell(cell):
		return
	current_pos = cell
	var node = get_current_node()
	if node == null:
		return
	pending_room_type = node.room_type
	var display: Dictionary = _AdventureRoomDisplay.get_display(node.room_type)
	pending_room_label = "%s %s" % [display["glyph"], display["label"]]
	_sync_run_progress()
	_navigate_to_room(node.room_type)


func get_room_scene_path(room_type: String) -> String:
	match room_type:
		"NORMAL_COMBAT", "ELITE_COMBAT":
			return BATTLE_SCENE
		"REST_SITE", "SHOP", "EVENT", "END":
			return PLACEHOLDER_SCENE
		_:
			return PLACEHOLDER_SCENE


func finish_room_and_return() -> void:
	_sync_run_progress()
	get_tree().change_scene_to_file(MAP_SCENE)


func resume_loaded_run() -> bool:
	if not RunService.is_run_active():
		return false
	var progress := RunService.get_progress_payload()
	if progress.is_empty():
		_restore_generated_map(RunService.get_run().map_seed, Vector2i.ZERO)
		_sync_run_progress()
		return true
	return import_progress(progress)


func reload_for_active_slot() -> void:
	reset_local_state()
	resume_loaded_run()


func reset_local_state() -> void:
	map_seed = 20260525
	map_matrix = []
	current_pos = Vector2i.ZERO
	run_active = false
	pending_room_type = ""
	pending_room_label = ""


func export_progress() -> Dictionary:
	return {
		"map_seed": map_seed,
		"current_map_pos": _vec_to_dict(current_pos),
		"run_active": run_active,
		"pending_room_type": pending_room_type,
		"pending_room_label": pending_room_label,
		"map_matrix": _serialize_map_matrix(),
	}


func import_progress(progress: Dictionary) -> bool:
	if progress.is_empty():
		return false
	map_seed = int(progress.get("map_seed", map_seed))
	current_pos = _dict_to_vec(progress.get("current_map_pos", {}), Vector2i.ZERO)
	run_active = bool(progress.get("run_active", true))
	pending_room_type = str(progress.get("pending_room_type", ""))
	pending_room_label = str(progress.get("pending_room_label", ""))
	var raw_map: Variant = progress.get("map_matrix", [])
	if raw_map is Array and not (raw_map as Array).is_empty():
		map_matrix = _deserialize_map_matrix(raw_map as Array)
		return true
	_restore_generated_map(map_seed, current_pos)
	return true


func _navigate_to_room(room_type: String) -> void:
	match room_type:
		"NORMAL_COMBAT", "ELITE_COMBAT":
			var pool: Array = COMBAT_ENCOUNTERS.get(room_type, ["tutorial_001"])
			var idx: int = (current_pos.x + current_pos.y + map_seed) % pool.size()
			GameService.adventure_return = true
			GameService.pending_room_id = "%d_%d" % [current_pos.x, current_pos.y]
			GameService.start_battle(pool[idx])
			RunService.save_run()
			get_tree().change_scene_to_file(BATTLE_SCENE)
		_:
			RunService.save_run()
			get_tree().change_scene_to_file(PLACEHOLDER_SCENE)


func _restore_generated_map(seed_value: int, target_pos: Vector2i) -> void:
	var gen := _AdventureMapGenerator.new()
	map_matrix = gen.generate(seed_value)
	map_seed = seed_value
	current_pos = target_pos
	run_active = true
	if pending_room_label.is_empty():
		var current_node = get_current_node()
		if current_node != null:
			var display: Dictionary = _AdventureRoomDisplay.get_display(current_node.room_type)
			pending_room_label = "%s %s" % [display["glyph"], display["label"]]


func _serialize_map_matrix() -> Array:
	var columns: Array = []
	for column in map_matrix:
		var out_column: Array = []
		for node in column:
			out_column.append({
				"x": node.grid_pos.x,
				"y": node.grid_pos.y,
				"layer": node.layer,
				"room_type": node.room_type,
				"parents": _vec_array_to_dicts(node.parents),
				"children": _vec_array_to_dicts(node.children),
			})
		columns.append(out_column)
	return columns


func _deserialize_map_matrix(raw_columns: Array) -> Array:
	var columns: Array = []
	for raw_column in raw_columns:
		var out_column: Array = []
		if raw_column is Array:
			for raw_node in raw_column:
				if not raw_node is Dictionary:
					continue
				var dict := raw_node as Dictionary
				var node = _MapNode.new(int(dict.get("x", 0)), int(dict.get("y", 0)))
				node.layer = int(dict.get("layer", node.layer))
				node.room_type = str(dict.get("room_type", ""))
				node.parents = _dicts_to_vec_array(dict.get("parents", []))
				node.children = _dicts_to_vec_array(dict.get("children", []))
				out_column.append(node)
		columns.append(out_column)
	return columns


func _vec_array_to_dicts(points: Array) -> Array:
	var result: Array = []
	for point in points:
		result.append(_vec_to_dict(point))
	return result


func _dicts_to_vec_array(raw_points: Variant) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not raw_points is Array:
		return result
	for point in raw_points:
		result.append(_dict_to_vec(point, Vector2i.ZERO))
	return result


func _vec_to_dict(point: Vector2i) -> Dictionary:
	return {"x": point.x, "y": point.y}


func _dict_to_vec(raw_value: Variant, fallback: Vector2i) -> Vector2i:
	if raw_value is Dictionary:
		return Vector2i(int(raw_value.get("x", fallback.x)), int(raw_value.get("y", fallback.y)))
	return fallback


func _sync_run_progress() -> void:
	if not RunService.is_run_active():
		return
	RunService.set_progress_payload(export_progress())


func _get_node(x: int, y: int):
	if map_matrix.is_empty():
		return null
	if x < 0 or x >= map_matrix.size():
		return null
	var col: Array = map_matrix[x]
	if y < 0 or y >= col.size():
		return null
	return col[y]
