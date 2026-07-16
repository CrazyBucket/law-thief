extends SceneTree

const _Applier = preload("res://scripts/ui/presentation_state_applier.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Presentation State Applier Test ===")
	var runtime := ScenarioBuilder.new("tutorial_001", 9301).finish()
	var display := runtime.clone()
	var display_player := display.get_player()
	var from_pos := display_player.pos
	var to_pos := _first_open_neighbor(display, display_player)
	assert(to_pos != from_pos, "test requires an open neighboring cell")

	var applier := _Applier.new()
	applier.set_states(display, runtime)
	applier.prime({
		"type": "move_step",
		"uid": display_player.uid,
		"from": from_pos,
		"to": to_pos,
	})
	assert(display_player.pos == to_pos)
	assert(display.get_unit_at(to_pos) == display_player, "display occupancy must follow the moved unit")
	assert(display.get_unit_at(from_pos) == null, "display occupancy must release the origin cell")

	var hp_before := display_player.hp
	applier.apply({
		"type": "damage",
		"uid": display_player.uid,
		"victim_uid": display_player.uid,
		"pos": Vector2i(7, 7),
		"damage": 2,
		"is_crit": false,
	})
	assert(display_player.hp == hp_before - 2, "damage must resolve by uid instead of a stale position")

	applier.apply({"type": "die", "uid": display_player.uid, "pos": to_pos, "reason": "test"})
	assert(not display_player.alive)
	assert(display.get_unit_at(to_pos) == null, "death must remove the display unit from occupancy")
	assert(BattleInvariantChecker.assert_valid(display, "presentation_state_applier"))
	print("PRESENTATION_STATE_APPLIER_TEST_PASS")
	quit()


func _first_open_neighbor(state: GameState, unit: UnitState) -> Vector2i:
	for cell in BoardUtils.neighbors4(unit.pos):
		if BoardUtils.unit_footprint_passable(state, unit, cell, unit.uid):
			return cell
	return unit.pos
