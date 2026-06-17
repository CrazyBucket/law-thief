extends SceneTree


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== Enemy Initial Gem Contract Test ===")
	var registry: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	for encounter_id in registry.get_encounter_ids():
		for seed_value in [1, 2, 7, 42, 99]:
			var state: GameState = registry.create_battle_state(encounter_id, seed_value)
			if state == null:
				push_error("failed to create encounter: %s" % encounter_id)
				quit(1)
				return
			for enemy in state.get_alive_enemies():
				if _enemy_allows_empty_gems(enemy):
					continue
				if enemy.slots.is_empty():
					continue
				if not _unit_has_gem(enemy):
					push_error(
						"%s seed %d spawned %s without an initial gem" % [
							encounter_id,
							seed_value,
							enemy.unit_def_id,
						]
					)
					quit(1)
					return
	print("ENEMY_INITIAL_GEM_CONTRACT_TEST_PASS")
	quit()


func _enemy_allows_empty_gems(enemy: UnitState) -> bool:
	return enemy.has_tag("unit:test_fixture") or enemy.has_tag("unit:allow_empty_gems")


func _unit_has_gem(unit: UnitState) -> bool:
	for slot in unit.slots:
		if slot != null and not str(slot.gem_uid).is_empty():
			return true
	return false
