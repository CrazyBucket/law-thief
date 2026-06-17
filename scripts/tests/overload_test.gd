extends SceneTree


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var controller := BattleController.new()
	controller.start_encounter("tutorial_001", 24680)
	var state := controller.state
	var player := state.get_player()
	var guard := _find_unit_by_def(state, "unit_patrol_guard")
	if player == null or guard == null:
		_fail("missing player or guard")
		return
	state.move_unit(player, guard.pos + Vector2i(0, -1))
	state.rebuild_occupancy()

	_test_pending_cancel(controller, state, player, guard)
	_test_forced_insert_appends_slot(controller, state, player, guard)
	_test_pending_activation(controller, state, player, guard)
	_test_lawless_any_extract(controller, state, player, guard)
	_test_operation_damage(controller, state, player, guard)
	_test_echo_extract(controller, state, player, guard)

	print("OVERLOAD_TEST_PASS")
	quit(0)


func _test_pending_cancel(controller: BattleController, state: GameState, player: UnitState, guard: UnitState) -> void:
	_reset_slots(state, player, guard)
	controller.select_action(Constants.ACTION_INSERT)
	var first := controller.try_insert(guard.uid, 2)
	if not first.get("ok", false):
		_fail("first insert failed: %s" % first.get("reason", ""))
		return
	state.held_gem_uid = _make_gem(state, Constants.GEM_FIRE, player.uid)
	var second := controller.try_insert(guard.uid, 1)
	if not second.get("ok", false):
		_fail("second insert failed: %s" % second.get("reason", ""))
		return
	if not state.overload_pending:
		_fail("expected overload pending after two consecutive inserts")
		return
	controller.select_action("")
	if state.overload_pending:
		_fail("selecting no action should cancel pending overload")
		return
	print("  [OK] overload pending can be cancelled")


func _test_forced_insert_appends_slot(controller: BattleController, state: GameState, player: UnitState, guard: UnitState) -> void:
	_reset_slots(state, player, guard)
	controller.select_action(Constants.ACTION_INSERT)
	var first := controller.try_insert(guard.uid, 2)
	if not first.get("ok", false):
		_fail("first insert for forced overload failed: %s" % first.get("reason", ""))
		return
	state.held_gem_uid = _make_gem(state, Constants.GEM_FIRE, player.uid)
	var held_before := state.held_gem_uid
	var slot_count_before := guard.slots.size()
	var original_red_uid := guard.get_slot_by_index(0).gem_uid
	var forced := controller.try_insert(guard.uid, 0)
	if not forced.get("ok", false):
		_fail("forced overload insert failed: %s" % forced.get("reason", ""))
		return
	if not bool(forced.get("overload_forced", false)):
		_fail("forced overload insert should report overload_forced")
		return
	if state.held_gem_uid != "":
		_fail("forced overload insert should consume held gem")
		return
	if guard.slots.size() != slot_count_before + 1:
		_fail("forced overload insert should add one extra slot")
		return
	if guard.get_slot_by_index(0).gem_uid != original_red_uid:
		_fail("forced overload insert should keep original slot occupant")
		return
	if guard.get_slot_by_index(guard.slots.size() - 1).gem_uid != held_before:
		_fail("forced overload insert should place held gem in new slot")
		return
	print("  [OK] forced overload insert appends slot")


func _test_pending_activation(controller: BattleController, state: GameState, player: UnitState, guard: UnitState) -> void:
	_reset_slots(state, player, guard)
	controller.select_action(Constants.ACTION_INSERT)
	var first := controller.try_insert(guard.uid, 2)
	state.held_gem_uid = _make_gem(state, Constants.GEM_FIRE, player.uid)
	var second := controller.try_insert(guard.uid, 1)
	if not first.get("ok", false) or not second.get("ok", false):
		_fail("insert chain failed before activation")
		return
	var before_count := state.overload_active_mutations.size()
	controller.begin_enemy_phase()
	if state.overload_pending:
		_fail("pending overload should be flushed when enemy phase begins")
		return
	if state.overload_active_mutations.size() <= before_count:
		_fail("expected one active overload mutation")
		return
	print("  [OK] overload activates on next phase")


func _test_lawless_any_extract(controller: BattleController, state: GameState, player: UnitState, guard: UnitState) -> void:
	_force_player_phase(state)
	_reset_slots(state, player, guard)
	_mark_overload_slot(guard, 0)
	state.overload_active_mutations = [Constants.OVERLOAD_LAWLESS_ANY_EXTRACT]
	state.held_gem_uid = ""
	controller.select_action(Constants.ACTION_EXTRACT)
	var result := controller.try_extract(guard.uid, 0)
	if not result.get("ok", false):
		_fail("extract failed: %s" % result.get("reason", ""))
		return
	if not StatusRules.is_lawless(guard):
		_fail("enemy should become lawless after any gem extract while overload mutation is active")
		return
	print("  [OK] any enemy gem extraction can trigger lawless")


func _test_operation_damage(controller: BattleController, state: GameState, player: UnitState, guard: UnitState) -> void:
	_force_player_phase(state)
	_reset_slots(state, player, guard)
	_mark_overload_slot(guard, 0)
	state.overload_active_mutations = [Constants.OVERLOAD_GEM_OP_DAMAGE]
	var hp_before := player.hp
	controller.select_action(Constants.ACTION_INSERT)
	var result := controller.try_insert(guard.uid, 2)
	if not result.get("ok", false):
		_fail("insert for damage test failed: %s" % result.get("reason", ""))
		return
	if player.hp != hp_before - Constants.OVERLOAD_GEM_OP_DAMAGE_AMOUNT:
		_fail("gem operation should damage player by overload amount")
		return
	print("  [OK] gem operations can damage the player")


func _test_echo_extract(controller: BattleController, state: GameState, player: UnitState, guard: UnitState) -> void:
	_force_player_phase(state)
	_reset_slots(state, player, guard)
	_mark_overload_slot(guard, 0)
	state.overload_active_mutations = [Constants.OVERLOAD_ECHO_EXTRACT]
	state.held_gem_uid = ""
	controller.select_action(Constants.ACTION_EXTRACT)
	var slot := guard.get_slot_by_index(0)
	var original_uid := slot.gem_uid
	var result := controller.try_extract(guard.uid, 0)
	if not result.get("ok", false):
		_fail("extract for echo test failed: %s" % result.get("reason", ""))
		return
	if state.held_gem_uid != original_uid:
		_fail("real gem should be held after extract")
		return
	if slot.gem_uid.is_empty() or slot.gem_uid == original_uid:
		_fail("slot should contain an echo gem after extract")
		return
	print("  [OK] extraction can leave a one-turn echo")


func _reset_slots(state: GameState, player: UnitState, guard: UnitState) -> void:
	for unit in [player, guard]:
		unit.statuses.clear()
		for slot in unit.slots:
			if slot != null and not slot.gem_uid.is_empty():
				state.gems.erase(slot.gem_uid)
			if slot != null:
				slot.gem_uid = ""
				slot.locked = false
				slot.lock_type = ""
				slot.unlock_until_turn = -1
	var held_uid := _make_gem(state, Constants.GEM_EXPLOSION, player.uid)
	state.held_gem_uid = held_uid
	var guard_red := guard.get_slot_by_index(0)
	var guard_blue := guard.get_slot_by_index(1)
	if guard_red != null:
		guard_red.gem_uid = _make_gem(state, Constants.GEM_POISON, guard.uid)
	if guard_blue != null:
		guard_blue.gem_uid = _make_gem(state, Constants.GEM_GRAVITY, guard.uid)
	state.overload_pending = false
	state.overload_last_action = ""
	state.overload_last_insert_turn = 0
	state.overload_active_mutations.clear()
	state.overload_echo_gems.clear()


func _make_gem(state: GameState, gem_id: String, owner_uid: String) -> String:
	var registry: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	var gem_uid: String = registry.next_runtime_uid("test_gem")
	var gem: GemState = registry.create_gem_instance(gem_uid, gem_id, {})
	gem.owner_uid = owner_uid
	state.gems[gem_uid] = gem
	return gem_uid


func _force_player_phase(state: GameState) -> void:
	state.phase = Constants.PHASE_PLAYER
	state.result = ""
	state.player_moved = false
	state.player_acted = false
	state.overload_pending = false
	state.overload_last_action = ""
	state.overload_last_insert_turn = 0


func _mark_overload_slot(unit: UnitState, slot_index: int) -> void:
	var slot := unit.get_slot_by_index(slot_index)
	if slot != null:
		slot.lock_type = Constants.LOCK_OVERLOAD_SLOT


func _find_unit_by_def(state: GameState, unit_def_id: String) -> UnitState:
	for unit in state.units.values():
		if unit.unit_def_id == unit_def_id:
			return unit
	return null


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
