extends SceneTree

const GemRules = preload("res://scripts/rules/gem_rules.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== Gem Insert Overload Test ===")
	_test_second_insert_overloads_without_replacing()
	_test_forced_insert_keeps_held_visual_state_consistent()
	_test_self_occupied_insert_creates_overload_slot()
	_test_enemy_gems_drop_to_ground()
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
	var enemy_occupied_result := controller.try_insert(rat.uid, rat.slots.find(rat.get_slot(Constants.SLOT_BLACK)))
	assert(not enemy_occupied_result.get("ok", false), "ordinary insert into an occupied enemy slot should fail instead of replacing")
	controller.select_action(Constants.ACTION_INSERT)
	var insert_result := controller.try_insert(player.uid, player.slots.find(player_red))
	assert(insert_result.get("ok", false), "self occupied insert should overload instead of replacing")
	assert(bool(insert_result.get("overload_forced", false)), "self occupied insert should report overload_forced")
	var second_target_slot := player_red
	var second_target_original_uid := second_target_slot.gem_uid
	var forced_held_uid := _make_gem(state, Constants.GEM_POISON, player.uid)
	state.held_gem_uid = forced_held_uid

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
	assert(player.slots.size() >= 2, "forced overload insert should create an extra slot")
	assert(_unit_has_gem(player, held_explosion_uid), "first forced insert should keep held gem on player")
	assert(player.slots[player.slots.size() - 1].gem_uid == forced_held_uid, "second forced overload insert should place the held gem into the new slot")
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
	var first_result := controller.try_insert(player.uid, 1)
	assert(first_result.get("ok", false), "first insert into an empty slot should succeed before forced insert")
	var held_before_forced := _make_gem(state, Constants.GEM_FIRE, player.uid)
	state.held_gem_uid = held_before_forced
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


func _test_self_occupied_insert_creates_overload_slot() -> void:
	var controller := BattleController.new()
	controller.start_encounter("tutorial_001", 11223)
	var state := controller.state
	var player := state.get_player()
	if player == null:
		push_error("missing player for self overload test")
		quit(1)
		return
	_force_gem(state, player, Constants.SLOT_RED, Constants.GEM_EXPLOSION)
	state.held_gem_uid = _make_gem(state, Constants.GEM_FIRE, player.uid)
	var held_uid := state.held_gem_uid
	var red_slot := player.get_slot(Constants.SLOT_RED)
	var red_uid := red_slot.gem_uid
	var before_count := player.slots.size()
	controller.select_action(Constants.ACTION_INSERT)
	var result := controller.try_insert(player.uid, player.slots.find(red_slot))
	assert(result.get("ok", false), "self occupied insert should create overload slot")
	assert(bool(result.get("overload_forced", false)), "self occupied insert should report overload_forced")
	assert(state.overload_pending, "self overload insert should set overload pending")
	assert(red_slot.gem_uid == red_uid, "self overload insert should not replace occupied slot")
	assert(player.slots.size() == before_count + 1, "self overload insert should append a slot")
	assert(player.slots[player.slots.size() - 1].gem_uid == held_uid, "self overload slot should hold inserted gem")
	print("  [OK] self occupied insert creates overload slot")


func _test_enemy_gems_drop_to_ground() -> void:
	var controller := BattleController.new()
	controller.start_encounter("tutorial_001", 24601)
	var state := controller.state
	var rat := _find_unit_by_def(state, "unit_bomb_rat")
	if rat == null:
		push_error("missing rat for death drop test")
		quit(1)
		return
	_force_gem(state, rat, Constants.SLOT_RED, Constants.GEM_EXPLOSION)
	var dropped_uid := rat.get_slot(Constants.SLOT_RED).gem_uid
	var death_pos := rat.pos
	CombatRules.apply_true_damage(state, rat, rat.hp, state.player_uid, "test")
	var drop: Dictionary = state.dropped_gems.get(dropped_uid, {})
	assert(not drop.is_empty(), "enemy gem should become a ground drop")
	assert(drop.get("pos", Vector2i.ZERO) == death_pos, "ground drop should keep death position")
	assert(state.gems.has(dropped_uid), "dropped gem should remain in state.gems")
	assert(rat.get_slot(Constants.SLOT_RED).gem_uid.is_empty(), "dead enemy slot should no longer own dropped gem")
	print("  [OK] enemy gems drop onto ground")


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


func _make_gem(state: GameState, gem_id: String, owner_uid: String) -> String:
	var reg: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	var gem_uid: String = reg.next_runtime_uid("gem")
	var gem: GemState = reg.create_gem_instance(gem_uid, gem_id, {})
	state.gems[gem_uid] = gem
	gem.owner_uid = owner_uid
	gem.slot_index = -1
	return gem_uid


func _unit_has_gem(unit: UnitState, gem_uid: String) -> bool:
	for slot in unit.slots:
		if slot != null and slot.gem_uid == gem_uid:
			return true
	return false


func _find_unit_by_def(state: GameState, unit_def_id: String) -> UnitState:
	for unit in state.units.values():
		if unit.unit_def_id == unit_def_id:
			return unit
	return null
