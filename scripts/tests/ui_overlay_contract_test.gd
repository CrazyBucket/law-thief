extends SceneTree


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== UI Overlay Contract Test ===")
	_test_move_hover_route()
	_test_enemy_intent_route()
	print("UI_OVERLAY_CONTRACT_TEST_PASS")
	quit()


func _test_move_hover_route() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001", 7)
	var player := ctrl.state.get_player()
	assert(player != null, "player should exist")
	ctrl.select_action(Constants.ACTION_MOVE)
	var initial := ctrl.get_highlights()
	var target := _first_cell_after(initial.get("reachable", []), player.pos)
	assert(target.x >= 0, "move highlights should include at least one destination")
	var highlights := ctrl.get_highlights(target)
	assert(_has_overlay_cell(highlights, "move", target), "move overlay should include hovered destination")
	var route := _find_route(highlights, "move")
	assert(not route.is_empty(), "move hover should expose route data")
	var path: Array = route.get("path", [])
	assert(path.size() >= 2, "move route should contain start and destination")
	assert(path[0] == player.pos, "move route should start at player position")
	assert(path[path.size() - 1] == target, "move route should end at hovered destination")
	assert(not bool(route.get("arrow_reverse", false)), "move route arrow should point along the movement direction")
	print("  [OK] move hover route overlay")


func _test_enemy_intent_route() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("stone_bow_test", 42)
	var state := ctrl.state
	var bow := _find_unit_by_def(state, "unit_stone_bow_guard")
	var player := state.get_player()
	assert(bow != null and player != null, "bow/player should exist")
	bow.pos = Vector2i(5, 2)
	player.pos = Vector2i(1, 2)
	var prop := EntityState.create("ui_overlay_block_prop", Constants.ENTITY_PROP, Vector2i(3, 2))
	state.add_entity(prop)
	state.rebuild_occupancy()
	IntentSystem.refresh_unit_intent(state, bow)
	assert(bow.intent != null and not bow.intent.path.is_empty(), "blocked bow should preview a movement path")
	ctrl.selected_unit_uid = bow.uid
	var highlights := ctrl.get_highlights()
	var route := _find_route(highlights, "intent")
	assert(not route.is_empty(), "selected enemy intent should expose route data")
	var path: Array = route.get("path", [])
	assert(path[0] == bow.pos, "intent route should start at enemy position")
	assert(path[path.size() - 1] == bow.intent.path[bow.intent.path.size() - 1], "intent route should end at preview path destination")
	assert(_has_overlay_cell(highlights, "intent_path", bow.intent.path[0]), "intent path should be drawn by unified overlays")
	print("  [OK] selected enemy intent route overlay")


func _first_cell_after(cells: Array, origin: Vector2i) -> Vector2i:
	for raw_cell in cells:
		var cell: Vector2i = raw_cell
		if cell != origin:
			return cell
	return Vector2i(-1, -1)


func _has_overlay_cell(highlights: Dictionary, kind: String, cell: Vector2i) -> bool:
	for raw_overlay in highlights.get("overlays", []):
		if not raw_overlay is Dictionary:
			continue
		var overlay: Dictionary = raw_overlay
		if str(overlay.get("kind", "")) == kind and cell in overlay.get("cells", []):
			return true
	return false


func _find_route(highlights: Dictionary, kind: String) -> Dictionary:
	for raw_route in highlights.get("routes", []):
		if raw_route is Dictionary and str(raw_route.get("kind", "")) == kind:
			return raw_route
	return {}


func _find_unit_by_def(state: GameState, def_id: String) -> UnitState:
	for unit in state.units.values():
		if unit.unit_def_id == def_id:
			return unit
	return null
