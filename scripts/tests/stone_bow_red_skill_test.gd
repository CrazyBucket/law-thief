extends SceneTree


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== Stone Bow Red Skill Test ===")
	_test_poison_skill_overrides_kiting()
	print("STONE_BOW_RED_SKILL_TEST_PASS")
	quit()


func _test_poison_skill_overrides_kiting() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("stone_bow_test", 42)
	var state := ctrl.state
	var bow := _find_unit_by_def(state, "unit_stone_bow_guard")
	var player := state.get_player()
	assert(bow != null and player != null, "stone bow/player should exist")
	_clear_slots(state, bow)
	_embed_red_gem(state, bow, Constants.GEM_POISON)
	player.pos = bow.pos + Vector2i(0, 1)
	state.rebuild_occupancy()
	IntentSystem.refresh_unit_intent(state, bow)
	assert(
		bow.intent.type == "poison_attack",
		"stone bow poison gem should override default kiting, got %s" % bow.intent.type
	)
	assert(bow.intent.path.is_empty(), "adjacent poison attack should stay in place")
	var hp_before := player.hp
	var events := IntentSystem.execute_intent(state, bow)
	assert(not events.is_empty(), "stone bow poison attack should execute")
	assert(player.hp < hp_before, "stone bow poison attack should deal damage")
	assert(player.has_status(Constants.STATUS_POISON), "stone bow poison attack should apply poison")
	print("  [OK] stone bow poison skill overrides kiting")


func _clear_slots(state: GameState, unit: UnitState) -> void:
	for slot: SlotState in unit.slots:
		if slot != null and not slot.gem_uid.is_empty():
			state.gems.erase(slot.gem_uid)
			slot.gem_uid = ""


func _embed_red_gem(state: GameState, unit: UnitState, gem_id: String) -> void:
	var red := unit.get_slot(Constants.SLOT_RED)
	assert(red != null, "stone bow should have red slot")
	var gem := GemState.new()
	gem.uid = "stone_bow_red_skill_%s" % gem_id
	gem.gem_id = gem_id
	gem.owner_uid = unit.uid
	gem.slot_index = unit.slots.find(red)
	state.gems[gem.uid] = gem
	red.gem_uid = gem.uid


func _find_unit_by_def(state: GameState, unit_def_id: String) -> UnitState:
	for unit in state.units.values():
		if unit.unit_def_id == unit_def_id:
			return unit
	return null
