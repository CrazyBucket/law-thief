extends SceneTree

const GemRules = preload("res://scripts/rules/gem_rules.gd")
const BattleSettlementService = preload("res://scripts/battle/battle_settlement_service.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== Gem Insert Overload Test ===")
	_test_enemy_occupied_insert_creates_overload_slot()
	_test_second_insert_overloads_without_replacing()
	_test_forced_insert_keeps_held_visual_state_consistent()
	_test_self_occupied_insert_creates_overload_slot()
	_test_split_locked_slot_can_overload_insert()
	_test_enemy_gems_stay_on_corpse()
	_test_corpse_gem_can_be_extracted()
	_test_corpse_gem_can_be_embedded_at_settlement()
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
	controller.select_action(Constants.ACTION_INSERT)
	var insert_result := controller.try_insert(player.uid, player.slots.find(player_red))
	assert(insert_result.get("ok", false) and bool(insert_result.get("overload_armed", false)), "first occupied insert should only arm overload")
	assert(state.held_gem_uid == held_explosion_uid, "first occupied insert must keep the gem in hand")
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
	assert(player.slots.size() >= 2, "forced overload insert should create an extra slot")
	assert(player.slots[player.slots.size() - 1].gem_uid == held_explosion_uid, "second insert should place the armed gem into the new slot")
	print("  [OK] second insert creates real overload slot")


func _test_enemy_occupied_insert_creates_overload_slot() -> void:
	var controller := BattleController.new()
	controller.start_encounter("tutorial_001", 12346)
	var state := controller.state
	var player := state.get_player()
	var rat := _find_unit_by_def(state, "unit_bomb_rat")
	if player == null or rat == null:
		push_error("missing units for enemy occupied overload test")
		quit(1)
		return
	_force_gem(state, rat, Constants.SLOT_BLACK, Constants.GEM_GRAVITY)
	state.held_gem_uid = _make_gem(state, Constants.GEM_FIRE, player.uid)
	var held_uid := state.held_gem_uid
	var black_slot := rat.get_slot(Constants.SLOT_BLACK)
	var black_uid := black_slot.gem_uid
	var slot_count_before := rat.slots.size()
	controller.select_action(Constants.ACTION_INSERT)
	var result := controller.try_insert(rat.uid, rat.slots.find(black_slot))
	assert(result.get("ok", false) and bool(result.get("overload_armed", false)), "first occupied enemy insert should only arm overload")
	assert(state.held_gem_uid == held_uid and rat.slots.size() == slot_count_before, "arming overload must not move the gem or add a slot")
	result = controller.try_insert(rat.uid, rat.slots.find(black_slot))
	assert(result.get("ok", false) and bool(result.get("overload_forced", false)), "second occupied enemy insert should force overload")
	assert(state.overload_pending, "occupied enemy insert should set overload pending")
	assert(black_slot.gem_uid == black_uid, "occupied enemy slot should stay unchanged")
	assert(rat.slots.size() == slot_count_before + 1, "occupied enemy insert should append a slot")
	assert(rat.slots[rat.slots.size() - 1].gem_uid == held_uid, "new overload slot should hold inserted gem")
	print("  [OK] occupied enemy insert creates overload slot")


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
	assert(result.get("ok", false) and bool(result.get("overload_armed", false)), "first self occupied insert should only arm overload")
	assert(state.held_gem_uid == held_uid and player.slots.size() == before_count, "first self insert must not mutate ownership")
	result = controller.try_insert(player.uid, player.slots.find(red_slot))
	assert(result.get("ok", false) and bool(result.get("overload_forced", false)), "second self occupied insert should force overload")
	assert(state.overload_pending, "self overload insert should set overload pending")
	assert(red_slot.gem_uid == red_uid, "self overload insert should not replace occupied slot")
	assert(player.slots.size() == before_count + 1, "self overload insert should append a slot")
	assert(player.slots[player.slots.size() - 1].gem_uid == held_uid, "self overload slot should hold inserted gem")
	print("  [OK] self occupied insert creates overload slot")


func _test_split_locked_slot_can_overload_insert() -> void:
	var controller := BattleController.new()
	controller.start_encounter("tutorial_001", 11224)
	var state := controller.state
	var player := state.get_player()
	assert(player != null, "locked overload fixture should have player")
	_force_gem(state, player, Constants.SLOT_BLACK, Constants.GEM_SPLIT)
	var locked_slot := player.get_slot(Constants.SLOT_BLACK)
	locked_slot.locked = true
	locked_slot.lock_type = Constants.LOCK_SPLIT_DISABLED
	state.held_gem_uid = _make_gem(state, Constants.GEM_FIRE, player.uid)
	var held_uid := state.held_gem_uid
	var original_uid := locked_slot.gem_uid
	var original_count := player.slots.size()
	controller.select_action(Constants.ACTION_INSERT)
	var result := controller.try_insert(player.uid, player.slots.find(locked_slot))
	assert(result.get("ok", false) and bool(result.get("overload_armed", false)), "locked split slot should arm overload")
	result = controller.try_insert(player.uid, player.slots.find(locked_slot))
	assert(result.get("ok", false) and bool(result.get("overload_forced", false)), "locked split slot should accept forced overload")
	assert(locked_slot.lock_type == Constants.LOCK_SPLIT_DISABLED and locked_slot.gem_uid == original_uid, "overload must not rewrite the locked split slot")
	assert(player.slots.size() == original_count + 1, "locked split overload should append one slot")
	var overload_slot: SlotState = player.slots[-1]
	assert(overload_slot.is_overload_slot() and not overload_slot.is_split_disabled(), "new slot should be overload-only and operable")
	assert(overload_slot.slot_type == Constants.SLOT_BLACK and overload_slot.gem_uid == held_uid, "new overload slot should inherit black color and hold the gem")
	print("  [OK] split-locked slot can be used as an overload anchor")


func _test_enemy_gems_stay_on_corpse() -> void:
	var controller := BattleController.new()
	controller.start_encounter("tutorial_001", 24601)
	var state := controller.state
	var rat := _find_unit_by_def(state, "unit_bomb_rat")
	if rat == null:
		push_error("missing rat for death drop test")
		quit(1)
		return
	_force_gem(state, rat, Constants.SLOT_RED, Constants.GEM_EXPLOSION)
	var gem_uid := rat.get_slot(Constants.SLOT_RED).gem_uid
	var death_pos := rat.pos
	CombatRules.apply_true_damage(state, rat, rat.hp, state.player_uid, "test")
	assert(state.dropped_gems.is_empty(), "enemy gem should not be detached into a ground drop")
	assert(state.gems.has(gem_uid), "corpse gem should remain in state.gems")
	assert(rat.get_slot(Constants.SLOT_RED).gem_uid == gem_uid, "dead enemy slot should retain its gem")
	assert(state.get_corpse_at(death_pos) == rat, "dead gem carrier should remain as a corpse")
	var offered := BattleSettlementService.dropped_gem_offer(state).any(
		func(entry: Dictionary) -> bool: return str(entry.get("gem_uid", "")) == gem_uid
	)
	assert(offered, "corpse gem should remain available to battle settlement")
	print("  [OK] enemy gems remain on the corpse")


func _test_corpse_gem_can_be_extracted() -> void:
	var controller := BattleController.new()
	controller.start_encounter("tutorial_001", 24602)
	var state := controller.state
	var player := state.get_player()
	var rat := _find_unit_by_def(state, "unit_bomb_rat")
	assert(player != null and rat != null, "corpse extract fixture should have player and rat")
	_force_gem(state, rat, Constants.SLOT_RED, Constants.GEM_EXPLOSION)
	var gem_uid := rat.get_slot(Constants.SLOT_RED).gem_uid
	var slot_index := rat.slots.find(rat.get_slot(Constants.SLOT_RED))
	var death_pos := rat.pos
	CombatRules.apply_true_damage(state, rat, rat.hp, state.player_uid, "test")
	var moved_in_range := false
	for neighbor in BoardUtils.neighbors4(death_pos):
		if BoardUtils.unit_footprint_passable(state, player, neighbor, player.uid):
			state.move_unit(player, neighbor)
			moved_in_range = true
			break
	assert(moved_in_range, "test should place player beside the corpse gem")
	controller.select_action(Constants.ACTION_EXTRACT)
	assert(controller.check_slot_action(rat.uid, slot_index).get("ok", false), "adjacent corpse gem should be extractable")
	var targets: Array = controller.get_highlights().get("targets", [])
	assert(death_pos in targets, "extract highlights should include the corpse cell")
	var result := controller.try_extract(rat.uid, slot_index)
	assert(result.get("ok", false), "corpse gem extract should succeed")
	assert(state.held_gem_uid == gem_uid, "extracted corpse gem should be held")
	assert(rat.get_slot_by_index(slot_index).gem_uid.is_empty(), "extracted gem should leave the corpse")
	assert(BattleInvariantChecker.assert_valid(state, "gem_insert_replace.corpse_extract"))
	print("  [OK] corpse gem can be extracted in combat")


func _test_corpse_gem_can_be_embedded_at_settlement() -> void:
	var controller := BattleController.new()
	controller.start_encounter("tutorial_001", 24603)
	var state := controller.state
	var player := state.get_player()
	var rat := _find_unit_by_def(state, "unit_bomb_rat")
	assert(player != null and rat != null, "corpse settlement fixture should have player and rat")
	_force_gem(state, rat, Constants.SLOT_RED, Constants.GEM_EXPLOSION)
	var gem_uid := rat.get_slot(Constants.SLOT_RED).gem_uid
	var player_red := player.get_slot(Constants.SLOT_RED)
	assert(player_red != null and player_red.gem_uid.is_empty(), "settlement fixture needs an empty red slot")
	CombatRules.apply_true_damage(state, rat, rat.hp, state.player_uid, "test")
	var result := BattleSettlementService.embed_dropped_gem(
		state,
		gem_uid,
		player.slots.find(player_red)
	)
	assert(result.get("ok", false), "corpse gem should be embeddable from settlement")
	assert(player_red.gem_uid == gem_uid, "settlement should move the corpse gem into the player slot")
	assert(rat.get_slot(Constants.SLOT_RED).gem_uid.is_empty(), "settled gem should leave the corpse")
	assert(BattleInvariantChecker.assert_valid(state, "gem_insert_replace.corpse_settlement"))
	print("  [OK] corpse gem remains available at settlement")


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
