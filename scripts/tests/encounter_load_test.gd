extends SceneTree

const BattleInvariantChecker = preload("res://scripts/debug/battle_invariant_checker.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var registry: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	for encounter_id in registry.get_encounter_ids():
		var state: GameState = registry.create_battle_state(encounter_id, 1, "encounter_load_contract")
		if state == null:
			push_error("failed to create encounter: %s" % encounter_id)
			quit(1)
			return
		var player := state.get_player()
		if player == null:
			push_error("missing player in encounter: %s" % encounter_id)
			quit(1)
			return
		if state.get_alive_enemies().is_empty():
			push_error("missing enemies in encounter: %s" % encounter_id)
			quit(1)
			return
		if state.encounter_id != encounter_id:
			push_error("encounter identity mismatch: expected=%s actual=%s" % [encounter_id, state.encounter_id])
			quit(1)
			return
		var invariant_errors := BattleInvariantChecker.check_all(state)
		if not invariant_errors.is_empty():
			push_error("invalid encounter %s: %s" % [encounter_id, invariant_errors])
			quit(1)
			return
		print("loaded %s: player@%s enemies=%d" % [encounter_id, player.pos, state.get_alive_enemies().size()])
	print("ENCOUNTER_LOAD_TEST_PASS")
	quit()
