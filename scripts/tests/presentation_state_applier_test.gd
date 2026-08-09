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
	var hp_after_normal_hit := display_player.hp
	StatusRules.apply_shield(display, display_player, 4, 0)
	applier.apply({
		"type": "damage",
		"uid": display_player.uid,
		"victim_uid": display_player.uid,
		"pos": to_pos,
		"damage": 0,
		"shield_damage": 3,
		"remaining_shield": 1,
		"is_crit": false,
	})
	assert(display_player.hp == hp_after_normal_hit, "shield-only presentation must preserve hp")
	assert(StatusRules.get_shield(display_player) == 1, "shield-only presentation must shrink the shield")
	applier.apply({
		"type": "damage",
		"uid": display_player.uid,
		"victim_uid": display_player.uid,
		"pos": to_pos,
		"damage": 2,
		"shield_damage": 1,
		"remaining_shield": 0,
		"is_crit": false,
	})
	assert(display_player.hp == hp_after_normal_hit - 2, "overflow presentation must apply hp damage")
	assert(StatusRules.get_shield(display_player) == 0, "overflow presentation must remove a depleted shield")

	var missing_hp_segments := BattleUiTheme.combined_hp_bar_ratios(5, 10, 2)
	assert(is_equal_approx(missing_hp_segments.x, 0.5), "shield must not compress the missing-hp scale")
	assert(is_equal_approx(missing_hp_segments.y, 0.2), "shield width should use the max-hp scale")
	var overflow_segments := BattleUiTheme.combined_hp_bar_ratios(10, 10, 5)
	assert(is_equal_approx(overflow_segments.x, 2.0 / 3.0), "effective hp above max should expand the scale")
	assert(is_equal_approx(overflow_segments.y, 1.0 / 3.0), "overflow shield should remain fully visible")

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
