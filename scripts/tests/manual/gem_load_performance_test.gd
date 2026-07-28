extends SceneTree

## 手动性能探针：固定场景下比较不同随身宝石数量的 HUD 刷新和标签解析成本。
## 不设跨机器阈值；输出用于同一机器、同一渲染配置下的优化前后对比。

const GemTransfer = preload("res://scripts/rules/gem_transfer.gd")
const GemTagResolver = preload("res://scripts/rules/gem_tag_resolver.gd")

const GEM_COUNTS: Array[int] = [5, 20, 50]
const GEM_IDS: Array[String] = [
	"gem_explosion",
	"gem_fire",
	"gem_poison",
	"gem_conductive",
	"gem_gravity",
	"gem_impact",
	"gem_ice",
	"gem_split",
	"gem_light",
	"gem_counter",
	"gem_echo",
	"gem_flurry",
]
const REFRESH_SAMPLES := 8
const CONTEXT_SAMPLES := 40


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Gem Load Performance Test ===")
	for gem_count in GEM_COUNTS:
		var battle_scene: Control = (load("res://scenes/battle/battle_scene.tscn") as PackedScene).instantiate()
		root.add_child(battle_scene)
		await process_frame
		var controller: BattleController = battle_scene.get("_controller")
		var state: GameState = controller.state
		var player: UnitState = state.get_player()
		assert(player != null, "performance probe requires a player")
		_mount_player_gems(state, player, gem_count)
		state.bump_revision()
		battle_scene.set("_inspect_uid", player.uid)
		battle_scene._refresh()
		await process_frame

		var refresh_samples := await _measure_refreshes(battle_scene)
		var context_samples := _measure_contexts(state, player)
		print(
			"GEM_LOAD_PERF slots=%d state_gems=%d refresh_avg_ms=%.3f refresh_p95_ms=%.3f context_avg_us=%.1f" % [
				gem_count,
				state.gems.size(),
				_average(refresh_samples),
				_percentile(refresh_samples, 0.95),
				_average(context_samples) * 1000.0,
			]
		)
		battle_scene.queue_free()
		await process_frame
	print("GEM_LOAD_PERFORMANCE_TEST_PASS")
	quit()


func _mount_player_gems(state: GameState, player: UnitState, gem_count: int) -> void:
	var registry: Node = root.get_node("DataRegistry")
	var filled := 0
	for slot in player.slots:
		if not slot.gem_uid.is_empty():
			filled += 1
	while filled < gem_count:
		var slot := SlotState.create(Constants.SLOT_RED)
		player.slots.append(slot)
		var gem_id: String = GEM_IDS[filled % GEM_IDS.size()]
		var gem_uid := "perf_gem_%d" % filled
		var gem: GemState = registry.create_gem_instance(gem_uid, gem_id)
		state.gems[gem_uid] = gem
		assert(GemTransfer.to_unit_slot(state, gem, player, slot), "probe gem should mount into its slot")
		filled += 1


func _measure_refreshes(battle_scene: Control) -> Array[float]:
	var samples: Array[float] = []
	for _sample in range(REFRESH_SAMPLES):
		var start_usec := Time.get_ticks_usec()
		battle_scene._refresh()
		samples.append(float(Time.get_ticks_usec() - start_usec) / 1000.0)
		await process_frame
	return samples


func _measure_contexts(state: GameState, player: UnitState) -> Array[float]:
	var samples: Array[float] = []
	for _sample in range(CONTEXT_SAMPLES):
		var start_usec := Time.get_ticks_usec()
		GemTagResolver.build_context(state, player, Constants.SLOT_RED, GemEffects.TIMING_ACTIVE)
		samples.append(float(Time.get_ticks_usec() - start_usec) / 1000.0)
	return samples


func _average(samples: Array[float]) -> float:
	if samples.is_empty():
		return 0.0
	var total := 0.0
	for sample in samples:
		total += sample
	return total / samples.size()


func _percentile(samples: Array[float], percent: float) -> float:
	if samples.is_empty():
		return 0.0
	var sorted := samples.duplicate()
	sorted.sort()
	var index := clampi(ceili(float(sorted.size()) * percent) - 1, 0, sorted.size() - 1)
	return sorted[index]
