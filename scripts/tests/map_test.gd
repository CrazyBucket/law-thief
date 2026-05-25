extends SceneTree

const _MapNode := preload("res://scripts/map/map_node.gd")
const _AdventureMapGenerator := preload("res://scripts/map/adventure_map_generator.gd")

const MAP_SEED := 20260525
const STRESS_ROUNDS := 1
const FALLBACK_WARN_THRESHOLD := 10

const ROOM_LABELS: Dictionary = {
	"START":         "起点",
	"END":           "终点",
	"NORMAL_COMBAT": "普通战斗",
	"ELITE_COMBAT":  "精英战斗",
	"REST_SITE":     "营地",
	"SHOP":          "商店",
	"EVENT":         "随机事件",
}


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== 冒险地图生成测试 ===")
	_test_single_print()
	_test_topology()
	_test_rules_stress()
	print("MAP_TEST_PASS")
	quit()


# ── 单次生成并可视化打印 ──────────────────────────────────────────────────────

func _test_single_print() -> void:
	print("\n--- 单次地图生成（种子 %d）---" % MAP_SEED)
	var gen = _AdventureMapGenerator.new()
	var matrix: Array = gen.generate(MAP_SEED)
	_print_map(matrix, gen)


func _print_map(matrix: Array, gen) -> void:
	var gs: int = _AdventureMapGenerator.GRID_SIZE

	var header := "     "
	for x in range(gs):
		header += "  x=%-2d  " % x
	print(header)

	for y in range(gs - 1, -1, -1):
		var row := "y=%d |" % y
		for x in range(gs):
			var node = matrix[x][y]
			var label: String = ROOM_LABELS.get(node.room_type, node.room_type)
			row += " %-6s |" % label
		print(row)

	print("")

	print("--- 各层节点类型 ---")
	for layer in range(_AdventureMapGenerator.MAX_LAYER + 1):
		var nodes_in_layer: Array = _get_layer_nodes(matrix, layer)
		if nodes_in_layer.is_empty():
			continue
		var parts: Array = []
		for node in nodes_in_layer:
			var label: String = ROOM_LABELS.get(node.room_type, node.room_type)
			parts.append("(%d,%d)%s" % [node.grid_pos.x, node.grid_pos.y, label])
		print("  第%02d层: %s" % [layer, "  ".join(parts)])


# ── 拓扑完整性测试 ────────────────────────────────────────────────────────────

func _test_topology() -> void:
	print("\n--- 拓扑完整性测试 ---")
	var gen = _AdventureMapGenerator.new()
	var matrix: Array = gen.generate(MAP_SEED)
	var gs: int = _AdventureMapGenerator.GRID_SIZE

	var total := 0
	for x in range(gs):
		total += (matrix[x] as Array).size()
	assert(total == 64, "节点总数应为 64，实际为 %d" % total)
	print("  [OK] 节点总数 = 64")

	var starts: Array = _get_layer_nodes(matrix, 0)
	for n in starts:
		assert(n.room_type == "START", "第 0 层非起点：%s" % n.room_type)
	var ends: Array = _get_layer_nodes(matrix, _AdventureMapGenerator.MAX_LAYER)
	for n in ends:
		assert(n.room_type == "END", "第 14 层非终点：%s" % n.room_type)
	print("  [OK] 起终点层类型正确")

	for x in range(gs):
		for y in range(gs):
			var node = matrix[x][y]
			if node.layer > 0:
				assert(not node.parents.is_empty(),
					"节点(%d,%d) 应有 parent" % [x, y])
			if node.layer < _AdventureMapGenerator.MAX_LAYER:
				assert(not node.children.is_empty(),
					"节点(%d,%d) 应有 child" % [x, y])
	print("  [OK] 无孤岛节点")


# ── 约束规则压力测试 ──────────────────────────────────────────────────────────

func _test_rules_stress() -> void:
	print("\n--- 约束压力测试（%d 次）---" % STRESS_ROUNDS)
	var gen = _AdventureMapGenerator.new()
	var gs: int = _AdventureMapGenerator.GRID_SIZE
	var fallback_heavy_maps := 0

	for i in range(STRESS_ROUNDS):
		var matrix: Array = gen.generate(i)

		for x in range(gs):
			for y in range(gs):
				var node = matrix[x][y]

				assert(not (node.room_type == "ELITE_COMBAT" and node.layer < 4),
					"第%d层出现精英战斗（种子%d, 坐标(%d,%d)）" % [node.layer, i, x, y])

				for parent_pos: Vector2i in node.parents:
					var parent = matrix[parent_pos.x][parent_pos.y]
					if node.room_type in ["ELITE_COMBAT", "REST_SITE", "SHOP"]:
						assert(parent.room_type != node.room_type,
							"连续出现 %s（种子%d, 坐标(%d,%d)）" % [node.room_type, i, x, y])

				if node.room_type != "NORMAL_COMBAT":
					for parent_pos: Vector2i in node.parents:
						var parent = matrix[parent_pos.x][parent_pos.y]
						for sibling_pos: Vector2i in parent.children:
							var sibling = matrix[sibling_pos.x][sibling_pos.y]
							if sibling == node:
								continue
							assert(sibling.room_type != node.room_type,
								"同源兄弟类型相同 %s（种子%d, 坐标(%d,%d)&(%d,%d)）" % [
									node.room_type, i, x, y, sibling_pos.x, sibling_pos.y])

		if gen.fallback_count > FALLBACK_WARN_THRESHOLD:
			fallback_heavy_maps += 1

	print("  [OK] %d 次生成全部通过约束校验" % STRESS_ROUNDS)
	if fallback_heavy_maps > 0:
		print("  [WARN] %d 次生成触发兜底超过 %d 次，规则可能过于苛刻" % [
			fallback_heavy_maps, FALLBACK_WARN_THRESHOLD])


# ── 工具方法 ──────────────────────────────────────────────────────────────────

func _get_layer_nodes(matrix: Array, layer: int) -> Array:
	var result: Array = []
	for x in range(_AdventureMapGenerator.GRID_SIZE):
		for y in range(_AdventureMapGenerator.GRID_SIZE):
			var node = matrix[x][y]
			if node.layer == layer:
				result.append(node)
	return result
