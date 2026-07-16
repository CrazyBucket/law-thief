extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Battle Query Cache Test ===")
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001", 4242)
	var query = ctrl.get("_query_svc")

	ctrl.select_action(Constants.ACTION_MOVE)
	var move_first := ctrl.get_highlights()
	assert(not move_first.reachable.is_empty(), "tutorial player should have reachable cells")
	assert(not query.get("_reachable_cache_key").is_empty(), "move query should populate the range cache")
	move_first.reachable.clear()
	var move_second := ctrl.get_highlights()
	assert(not move_second.reachable.is_empty(), "callers must not be able to mutate cached reachable cells")
	var route_target: Vector2i = move_second.reachable[0]
	var move_hover := ctrl.get_highlights(route_target)
	assert(not move_hover.routes.is_empty(), "hover-specific move routes must still be computed on cache hits")
	var old_move_key: Array = query.get("_reachable_cache_key").duplicate()
	var blocker: UnitState = ctrl.state.get_alive_enemies()[0]
	ctrl.state.move_unit(blocker, route_target)
	var move_after_mutation := ctrl.get_highlights()
	assert(query.get("_reachable_cache_key") != old_move_key, "state revision must invalidate cached movement without controller bookkeeping")
	assert(route_target not in move_after_mutation.reachable, "recomputed movement must observe the new blocker")

	ctrl.select_action(Constants.ACTION_ATTACK)
	var attack_first := ctrl.get_highlights()
	assert(not attack_first.attack_range.is_empty(), "tutorial player should have attack range cells")
	assert(not query.get("_attack_range_cache_key").is_empty(), "attack query should populate the range cache")
	attack_first.attack_range.clear()
	var attack_second := ctrl.get_highlights()
	assert(not attack_second.attack_range.is_empty(), "callers must not be able to mutate cached attack range")

	ctrl.invalidate_highlight_cache()
	assert(query.get("_reachable_cache_key").is_empty(), "explicit invalidation should clear the move cache")
	assert(query.get("_attack_range_cache_key").is_empty(), "explicit invalidation should clear the attack cache")

	print("BATTLE_QUERY_CACHE_TEST_PASS")
	quit()
