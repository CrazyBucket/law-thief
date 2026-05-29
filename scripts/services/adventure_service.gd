extends Node

const _AdventureMapGenerator := preload("res://scripts/map/adventure_map_generator.gd")
const _AdventureRoomDisplay := preload("res://scripts/map/adventure_room_display.gd")
const _AdventureBoardGenerator := preload("res://scripts/map/adventure_board_generator.gd")

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
	get_tree().change_scene_to_file(MAP_SCENE)


func _navigate_to_room(room_type: String) -> void:
	match room_type:
		"NORMAL_COMBAT", "ELITE_COMBAT":
			var pool: Array = COMBAT_ENCOUNTERS.get(room_type, ["tutorial_001"])
			var idx: int = (current_pos.x + current_pos.y + map_seed) % pool.size()
			GameService.adventure_return = true
			GameService.pending_room_id = "%d_%d" % [current_pos.x, current_pos.y]
			GameService.start_battle(pool[idx])
			get_tree().change_scene_to_file(BATTLE_SCENE)
		_:
			get_tree().change_scene_to_file(PLACEHOLDER_SCENE)


func _get_node(x: int, y: int):
	if map_matrix.is_empty():
		return null
	if x < 0 or x >= map_matrix.size():
		return null
	var col: Array = map_matrix[x]
	if y < 0 or y >= col.size():
		return null
	return col[y]
