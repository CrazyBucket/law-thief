extends SceneTree

const _MapNode := preload("res://scripts/map/map_node.gd")
const _AdventureMapGenerator := preload("res://scripts/map/adventure_map_generator.gd")
const AdventureProgressionConfig = preload("res://scripts/core/adventure_progression_config.gd")

const MAP_SEED := 20260525
const STRESS_ROUNDS := 1
const FALLBACK_WARN_THRESHOLD := 10

var _failed := false


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== 冒险地图生成测试 ===")
	_test_topology()
	_test_event_properties()
	_test_rules_stress()
	if _failed:
		push_error("MAP_TEST_FAIL")
		quit(1)
		return
	print("MAP_TEST_PASS")
	quit(0)


# ── 拓扑完整性测试 ────────────────────────────────────────────────────────────

func _test_topology() -> void:
	print("\n--- 拓扑完整性测试 ---")
	var gen = _AdventureMapGenerator.new()
	var matrix: Array = gen.generate(MAP_SEED)
	var gs: int = gen.get_grid_size()

	var total := 0
	for x in range(gs):
		total += (matrix[x] as Array).size()
	_expect(total == gs * gs, "节点总数应为 %d，实际为 %d" % [gs * gs, total])
	print("  [OK] 节点总数 = %d" % total)

	var starts: Array = _get_layer_nodes(matrix, 0)
	for n in starts:
		_expect(n.room_type == "START", "第 0 层非起点：%s" % n.room_type)
	var ends: Array = _get_layer_nodes(matrix, gen.get_max_layer())
	for n in ends:
		_expect(n.room_type == "END", "终点层房间类型错误：%s" % n.room_type)
	print("  [OK] 起终点层类型正确")

	for x in range(gs):
		for y in range(gs):
			var node = matrix[x][y]
			if node.layer > 0:
				_expect(not node.parents.is_empty(),
					"节点(%d,%d) 应有 parent" % [x, y])
			if node.layer < gen.get_max_layer():
				_expect(not node.children.is_empty(),
					"节点(%d,%d) 应有 child" % [x, y])
	print("  [OK] 无孤岛节点")


func _test_event_properties() -> void:
	var gen = _AdventureMapGenerator.new()
	var matrix: Array = gen.generate(MAP_SEED)
	var found_event := false
	for x in range(gen.get_grid_size()):
		for y in range(gen.get_grid_size()):
			var node = matrix[x][y]
			if node.room_type != "EVENT":
				continue
			found_event = true
			var event_id := str(node.properties.get("event_id", ""))
			_expect(not event_id.is_empty(), "event node should carry event_id property")
	_expect(found_event, "map should generate at least one event node for property test")
	print("  [OK] 事件节点已分配 event_id")


# ── 约束规则压力测试 ──────────────────────────────────────────────────────────

func _test_rules_stress() -> void:
	print("\n--- 约束压力测试（%d 次）---" % STRESS_ROUNDS)
	var gen = _AdventureMapGenerator.new()
	var gs: int = gen.get_grid_size()
	var elite_min_layer := int((AdventureProgressionConfig.map_config()["room_rules"]["ELITE_COMBAT"] as Dictionary)["min_layer"])
	var fallback_heavy_maps := 0

	for i in range(STRESS_ROUNDS):
		var matrix: Array = gen.generate(i)

		for x in range(gs):
			for y in range(gs):
				var node = matrix[x][y]

				_expect(not (node.room_type == "ELITE_COMBAT" and node.layer < elite_min_layer),
					"第%d层出现精英战斗（种子%d, 坐标(%d,%d)）" % [node.layer, i, x, y])

				for parent_pos: Vector2i in node.parents:
					var parent = matrix[parent_pos.x][parent_pos.y]
					if node.room_type in ["ELITE_COMBAT", "REST_SITE", "SHOP"]:
						_expect(parent.room_type != node.room_type,
							"连续出现 %s（种子%d, 坐标(%d,%d)）" % [node.room_type, i, x, y])

				if node.room_type != "NORMAL_COMBAT":
					for parent_pos: Vector2i in node.parents:
						var parent = matrix[parent_pos.x][parent_pos.y]
						for sibling_pos: Vector2i in parent.children:
							var sibling = matrix[sibling_pos.x][sibling_pos.y]
							if sibling == node:
								continue
							_expect(sibling.room_type != node.room_type,
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
	for x in range(matrix.size()):
		for y in range((matrix[x] as Array).size()):
			var node = matrix[x][y]
			if node.layer == layer:
				result.append(node)
	return result


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
