class_name AdventureMapGenerator extends RefCounted

const _MapNode := preload("res://scripts/map/map_node.gd")
const AdventureProgressionConfig = preload("res://scripts/core/adventure_progression_config.gd")

var map_matrix: Array = []
var fallback_count: int = 0

var _rng: RandomNumberGenerator
var _map_config: Dictionary
var _grid_size: int
var _max_layer: int
var _room_rules: Dictionary


func _init(map_config: Dictionary = {}) -> void:
	_map_config = map_config.duplicate(true) if not map_config.is_empty() else AdventureProgressionConfig.map_config()
	_grid_size = int(_map_config["grid_size"])
	_max_layer = (_grid_size - 1) * 2
	_room_rules = (_map_config["room_rules"] as Dictionary).duplicate(true)


func get_grid_size() -> int:
	return _grid_size


func get_max_layer() -> int:
	return _max_layer


func generate(seed_value: int) -> Array:
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value
	fallback_count = 0
	_init_topology()
	_populate_rooms()
	return map_matrix


func get_node(x: int, y: int):
	if x < 0 or x >= _grid_size or y < 0 or y >= _grid_size:
		return null
	return map_matrix[x][y]


# 阶段 1：构建物理骨架与拓扑连接（只存坐标，规避引用循环）
func _init_topology() -> void:
	map_matrix.clear()
	for x in range(_grid_size):
		var col: Array = []
		for y in range(_grid_size):
			col.append(_MapNode.new(x, y))
		map_matrix.append(col)

	for x in range(_grid_size):
		for y in range(_grid_size):
			var current = map_matrix[x][y]
			if x + 1 < _grid_size:
				current.children.append(Vector2i(x + 1, y))
				map_matrix[x + 1][y].parents.append(current.grid_pos)
			if y + 1 < _grid_size:
				current.children.append(Vector2i(x, y + 1))
				map_matrix[x][y + 1].parents.append(current.grid_pos)


# 阶段 2：按层级顺序流式填充房间类型
func _populate_rooms() -> void:
	var flat_nodes: Array = []
	for x in range(_grid_size):
		for y in range(_grid_size):
			flat_nodes.append(map_matrix[x][y])

	flat_nodes.sort_custom(func(a, b) -> bool:
		return a.layer < b.layer
	)

	for node in flat_nodes:
		var candidates: Array[String] = []
		for type_id: String in _room_rules.keys():
			if _is_valid(node, type_id):
				candidates.append(type_id)

		if candidates.is_empty():
			node.room_type = str(_map_config["fallback_room_type"])
			fallback_count += 1
		else:
			node.room_type = _weighted_pick(candidates)
		_assign_properties(node)


func _assign_properties(node) -> void:
	node.properties.clear()
	if node.room_type == "EVENT":
		var event_pool: Array = _map_config["event_pool"]
		var idx: int = (node.grid_pos.x + node.grid_pos.y + node.layer) % event_pool.size()
		node.properties["event_id"] = event_pool[idx]


func _is_valid(node, type_id: String) -> bool:
	var rules: Dictionary = _room_rules[type_id]

	if rules.has("fixed_layer"):
		var fixed_layer := 0 if str(rules["fixed_layer"]) == "start" else _max_layer
		return node.layer == fixed_layer

	# 非特殊节点不能占用起点/终点层
	if node.layer == 0 or node.layer == _max_layer:
		return false

	# 楼层区间限制
	if rules.has("min_layer") and node.layer < rules["min_layer"]:
		return false
	if rules.has("max_layer") and node.layer > rules["max_layer"]:
		return false

	# 防连续：检查所有父节点
	if rules.get("no_consecutive", false):
		for parent_pos: Vector2i in node.parents:
			var parent = map_matrix[parent_pos.x][parent_pos.y]
			if parent.room_type == type_id:
				return false

	# NORMAL_COMBAT 作为无限制兜底类型，豁免同源排他
	if type_id == "NORMAL_COMBAT":
		return true

	# 同源排他：同一父节点的已赋值兄弟节点不得与自己类型相同
	for parent_pos: Vector2i in node.parents:
		var parent = map_matrix[parent_pos.x][parent_pos.y]
		for sibling_pos: Vector2i in parent.children:
			var sibling = map_matrix[sibling_pos.x][sibling_pos.y]
			if sibling == node:
				continue
			if not sibling.room_type.is_empty() and sibling.room_type == type_id:
				return false

	return true


func _weighted_pick(candidates: Array[String]) -> String:
	var total := 0
	for type_id: String in candidates:
		total += int((_room_rules[type_id] as Dictionary)["weight"])

	var roll := _rng.randi() % total
	var acc := 0
	for type_id: String in candidates:
		acc += int((_room_rules[type_id] as Dictionary)["weight"])
		if roll < acc:
			return type_id

	return candidates[0]
