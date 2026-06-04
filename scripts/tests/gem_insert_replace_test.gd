extends SceneTree

const GemRules = preload("res://scripts/rules/gem_rules.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== Gem Insert Overload Test ===")
	_test_second_insert_overloads_without_replacing()
	_test_forced_insert_keeps_held_visual_state_consistent()
	_test_slot_panels_only_show_in_operation_range()
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

	assert(bool(second_result.get("overload_forced", false)), "second insert should be a forced overload insert")
	assert(state.overload_pending, "second insert should set overload pending")
	assert(controller.get_action_hint().contains("过载预兆"), "UI hint should enter overload pending state")
	assert(state.held_gem_uid.is_empty(), "forced overload insert should consume the held gem")
	assert(second_target_slot.gem_uid == second_target_original_uid, "original occupied slot should stay unchanged")
	assert(player_red.gem_uid == held_explosion_uid, "first target slot should keep inserted gem")
	assert(player.slots.size() >= 2, "forced overload insert should create an extra slot")
	assert(player.slots[player.slots.size() - 1].gem_uid == poison_uid, "forced overload insert should place the held gem into the new slot")
	print("  [OK] second insert creates real overload slot")


func _test_forced_insert_keeps_held_visual_state_consistent() -> void:
	var controller := BattleController.new()
	controller.start_encounter("tutorial_001", 13579)
	var state := controller.state
	var player := state.get_player()
	var rat := _find_unit_by_def(state, "unit_bomb_rat")
	if player == null or rat == null:
		push_error("missing units for forced insert visual test")
		quit(1)
		return
	_force_gem(state, rat, Constants.SLOT_RED, Constants.GEM_EXPLOSION)
	_force_gem(state, player, Constants.SLOT_RED, Constants.GEM_POISON)
	controller.select_action(Constants.ACTION_EXTRACT)
	var extract_result := controller.try_extract(rat.uid, 0)
	assert(extract_result.get("ok", false), "extract should succeed before forced insert")
	controller.select_action(Constants.ACTION_INSERT)
	var first_result := controller.try_insert(player.uid, 0)
	assert(first_result.get("ok", false), "first insert should succeed before forced insert")
	var held_before_forced := state.held_gem_uid
	var slot_before_forced := player.get_slot(Constants.SLOT_RED).gem_uid
	var slot_count_before := player.slots.size()
	var forced_result := controller.try_insert(player.uid, 0)
	assert(forced_result.get("ok", false), "forced insert should still succeed")
	assert(bool(forced_result.get("overload_forced", false)), "forced insert should report overload_forced")
	assert(state.held_gem_uid.is_empty(), "held gem should be consumed after forced insert")
	assert(player.get_slot(Constants.SLOT_RED).gem_uid == slot_before_forced, "forced insert should not replace occupied slot gem")
	assert(player.slots.size() == slot_count_before + 1, "forced insert should append an overload slot")
	assert(player.slots[player.slots.size() - 1].gem_uid == held_before_forced, "new overload slot should hold the inserted gem")
	print("  [OK] forced insert creates a real overload slot")


func _test_slot_panels_only_show_in_operation_range() -> void:
	var controller := BattleController.new()
	controller.start_encounter("tutorial_001", 67890)
	var state := controller.state
	var player := state.get_player()
	var rat := _find_unit_by_def(state, "unit_bomb_rat")
	var guard := _find_unit_by_def(state, "unit_patrol_guard")
	if player == null or rat == null or guard == null:
		push_error("missing units for range test")
		quit(1)
		return
	player.pos = Vector2i(1, 2)
	rat.pos = Vector2i(2, 2)
	guard.pos = Vector2i(6, 6)
	state.rebuild_occupancy()
	assert(GemRules.is_unit_in_operation_range(state, player, rat, Constants.ACTION_EXTRACT), "extract fan should show for nearby target")
	assert(not GemRules.is_unit_in_operation_range(state, player, guard, Constants.ACTION_EXTRACT), "extract fan should hide for far target")
	_force_gem(state, player, Constants.SLOT_RED, Constants.GEM_POISON)
	state.held_gem_uid = player.get_slot(Constants.SLOT_RED).gem_uid
	assert(GemRules.is_unit_in_operation_range(state, player, rat, Constants.ACTION_INSERT), "insert fan should show for nearby target")
	assert(not GemRules.is_unit_in_operation_range(state, player, guard, Constants.ACTION_INSERT), "insert fan should hide for far target")
	print("  [OK] slot panel range filter")


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
