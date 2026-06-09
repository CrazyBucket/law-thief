class_name AdventureMapGenerator extends RefCounted

const _MapNode := preload("res://scripts/map/map_node.gd")

const GRID_SIZE := 8
const MAX_LAYER := 14

const ROOM_CONFIG: Dictionary = {
	"START":         {"allowed_layers": [0]},
	"END":           {"allowed_layers": [14]},
	"NORMAL_COMBAT": {"weight": 50},
	"ELITE_COMBAT":  {"weight": 12, "min_layer": 4, "no_consecutive": true},
	"REST_SITE":     {"weight": 12, "no_consecutive": true},
	"SHOP":          {"weight":  8, "no_consecutive": true},
	"EVENT":         {"weight": 20},
}

var map_matrix: Array = []
var fallback_count: int = 0

var _rng: RandomNumberGenerator


func generate(seed_value: int) -> Array:
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value
	fallback_count = 0
	_init_topology()
	_populate_rooms()
	return map_matrix


func get_node(x: int, y: int):
	if x < 0 or x >= GRID_SIZE or y < 0 or y >= GRID_SIZE:
		return null
	return map_matrix[x][y]


# 阶段 1：构建物理骨架与拓扑连接（只存坐标，规避引用循环）
func _init_topology() -> void:
	map_matrix.clear()
	for x in range(GRID_SIZE):
		var col: Array = []
		for y in range(GRID_SIZE):
			col.append(_MapNode.new(x, y))
		map_matrix.append(col)

	for x in range(GRID_SIZE):
		for y in range(GRID_SIZE):
			var current = map_matrix[x][y]
			if x + 1 < GRID_SIZE:
				current.children.append(Vector2i(x + 1, y))
				map_matrix[x + 1][y].parents.append(current.grid_pos)
			if y + 1 < GRID_SIZE:
				current.children.append(Vector2i(x, y + 1))
				map_matrix[x][y + 1].parents.append(current.grid_pos)


# 阶段 2：按层级顺序流式填充房间类型
func _populate_rooms() -> void:
	var flat_nodes: Array = []
	for x in range(GRID_SIZE):
		for y in range(GRID_SIZE):
			flat_nodes.append(map_matrix[x][y])

	flat_nodes.sort_custom(func(a, b) -> bool:
		return a.layer < b.layer
	)

	for node in flat_nodes:
		var candidates: Array[String] = []
		for type_id: String in ROOM_CONFIG.keys():
			if _is_valid(node, type_id):
				candidates.append(type_id)

		if candidates.is_empty():
			node.room_type = "NORMAL_COMBAT"
			fallback_count += 1
		else:
			node.room_type = _weighted_pick(candidates)
		_assign_properties(node)


func _assign_properties(node) -> void:
	node.properties.clear()
	if node.room_type == "EVENT":
		var event_pool: Array[String] = ["event_debug_cache", "event_debug_relief"]
		var idx: int = (node.grid_pos.x + node.grid_pos.y + node.layer) % event_pool.size()
		node.properties["event_id"] = event_pool[idx]


func _is_valid(node, type_id: String) -> bool:
	var rules: Dictionary = ROOM_CONFIG[type_id]

	# 强制楼层锁定
	if rules.has("allowed_layers"):
		if node.layer not in rules["allowed_layers"]:
			return false
		return true

	# 非特殊节点不能占用起点/终点层
	if node.layer == 0 or node.layer == MAX_LAYER:
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
		total += ROOM_CONFIG[type_id].get("weight", 10)

	var roll := _rng.randi() % total
	var acc := 0
	for type_id: String in candidates:
		acc += ROOM_CONFIG[type_id].get("weight", 10)
		if roll < acc:
			return type_id

	return candidates[0]
