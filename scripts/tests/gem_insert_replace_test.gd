extends SceneTree


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== Gem Insert Overload Test ===")
	_test_second_insert_overloads_without_replacing()
	print("GEM_INSERT_OVERLOAD_TEST_PASS")
	quit()


func _test_second_insert_overloads_without_replacing() -> void:
	var controller := BattleController.new()
	controller.start_encounter("tutorial_001", 12345)
	var state := controller.state
	var player := state.get_player()
	var rat := _find_unit_by_def(state, "unit_bomb_rat")
	if player == null or rat == null:
		push_error("missing units")
		quit(1)
		return

	_force_gem(state, rat, Constants.SLOT_RED, Constants.GEM_EXPLOSION)
	_force_gem(state, player, Constants.SLOT_RED, Constants.GEM_POISON)

	controller.select_action(Constants.ACTION_EXTRACT)
	var extract_result := controller.try_extract(rat.uid, 0)
	if not extract_result.get("ok", false):
		push_error("extract failed: %s" % extract_result.get("reason", ""))
		quit(1)
		return
	var held_explosion_uid := state.held_gem_uid
	var player_red := player.get_slot(Constants.SLOT_RED)
	var poison_uid := player_red.gem_uid

	controller.select_action(Constants.ACTION_INSERT)
	var insert_result := controller.try_insert(player.uid, player.slots.find(player_red))
	if not insert_result.get("ok", false):
		push_error("first insert failed: %s" % insert_result.get("reason", ""))
		quit(1)
		return
	var second_target_slot := player_red
	var second_target_original_uid := second_target_slot.gem_uid

	var second_result := controller.try_insert(player.uid, player.slots.find(second_target_slot))
	if not second_result.get("ok", false):
		push_error("second insert overload failed: %s" % second_result.get("reason", ""))
		quit(1)
		return

	assert(bool(second_result.get("overload_only", false)), "second insert should be overload-only")
	assert(state.overload_pending, "second insert should set overload pending")
	assert(state.held_gem_uid == poison_uid, "held gem should not be swapped again")
	assert(second_target_slot.gem_uid == second_target_original_uid, "occupied slot should not be replaced")
	assert(player_red.gem_uid == held_explosion_uid, "first target slot should keep inserted gem")
	print("  [OK] second insert overloads without replacement")


func _force_gem(state: GameState, unit: UnitState, slot_type: String, gem_id: String) -> void:
	var reg: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	var slot := unit.get_slot(slot_type)
	if slot == null:
		return
	if not slot.gem_uid.is_empty():
		state.gems.erase(slot.gem_uid)
	var gem_uid: String = reg.next_runtime_uid("gem")
	var gem: GemState = reg.create_gem_instance(gem_uid, gem_id, {})
	state.gems[gem_uid] = gem
	slot.gem_uid = gem_uid
	gem.owner_uid = unit.uid
	gem.slot_index = unit.slots.find(slot)


func _find_unit_by_def(state: GameState, unit_def_id: String) -> UnitState:
	for unit in state.units.values():
		if unit.unit_def_id == unit_def_id:
			return unit
	return null
