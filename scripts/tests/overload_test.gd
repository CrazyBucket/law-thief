extends SceneTree

const CombatConfig = preload("res://scripts/core/combat_config.gd")
const GemTransfer = preload("res://scripts/rules/gem_transfer.gd")


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
	_test_enemy_empty_slot_second_insert_creates_overload_slot(controller, state, player, guard)
	_test_pending_activation(controller, state, player, guard)
	_test_mutation_order(state, player, guard)
	_test_lawless_any_extract(controller, state, player, guard)
	_test_overload_extract_removes_slot(controller, state, player, guard)
	_test_operation_damage(controller, state, player, guard)
	_test_operation_damage_is_nonlethal(controller, state, player, guard)
	_test_echo_extract(controller, state, player, guard)
	_test_echo_extract_does_not_chain(state, player, guard)
	_test_ai_control_emits_action_events(state, player, guard)
	_test_ai_control_blocks_manual_actions(controller, state, player, guard)

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


func _test_enemy_empty_slot_second_insert_creates_overload_slot(controller: BattleController, state: GameState, player: UnitState, guard: UnitState) -> void:
	_reset_slots(state, player, guard)
	controller.select_action(Constants.ACTION_INSERT)
	var first := controller.try_insert(guard.uid, 2)
	if not first.get("ok", false):
		_fail("first insert before enemy empty overload failed: %s" % first.get("reason", ""))
		return
	var empty_enemy_slot := SlotState.create(Constants.SLOT_RED)
	guard.slots.append(empty_enemy_slot)
	state.held_gem_uid = _make_gem(state, Constants.GEM_FIRE, player.uid)
	var held_before := state.held_gem_uid
	var slot_count_before := guard.slots.size()
	var forced := controller.try_insert(guard.uid, guard.slots.find(empty_enemy_slot))
	if not forced.get("ok", false):
		_fail("second insert into enemy empty slot should overload: %s" % forced.get("reason", ""))
		return
	if not bool(forced.get("overload_forced", false)):
		_fail("second enemy insert should report overload_forced")
		return
	if guard.slots.size() != slot_count_before + 1:
		_fail("enemy empty forced insert should append an overload slot")
		return
	if not empty_enemy_slot.gem_uid.is_empty():
		_fail("original enemy empty slot should stay empty after forced overload insert")
		return
	var overload_slot := guard.get_slot_by_index(guard.slots.size() - 1)
	if overload_slot.gem_uid != held_before or overload_slot.lock_type != Constants.LOCK_OVERLOAD_SLOT:
		_fail("new enemy overload slot should hold inserted gem and carry overload lock")
		return
	print("  [OK] second insert into enemy empty slot creates overload slot")


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
	if state.overload_active_mutations[0] != Constants.OVERLOAD_LAWLESS_ANY_EXTRACT:
		_fail("first overload mutation should follow layer order")
		return
	print("  [OK] overload activates on next phase")


func _test_mutation_order(state: GameState, player: UnitState, guard: UnitState) -> void:
	_reset_slots(state, player, guard)
	_mark_overload_slot(guard, 0)
	OverloadRules.sync_active_mutations_to_overload_slots(state, true)
	if state.overload_active_mutations != [Constants.OVERLOAD_LAWLESS_ANY_EXTRACT]:
		_fail("one overload gem should only enable the first mutation")
		return
	_mark_overload_slot(guard, 1)
	OverloadRules.sync_active_mutations_to_overload_slots(state, true)
	if state.overload_active_mutations != [
		Constants.OVERLOAD_LAWLESS_ANY_EXTRACT,
		Constants.OVERLOAD_GEM_OP_DAMAGE,
	]:
		_fail("two overload gems should enable the first two mutations in order")
		return
	print("  [OK] overload mutations follow layer order")


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


func _test_overload_extract_removes_slot(controller: BattleController, state: GameState, player: UnitState, guard: UnitState) -> void:
	_force_player_phase(state)
	_reset_slots(state, player, guard)
	_mark_overload_slot(guard, 0)
	OverloadRules.sync_active_mutations_to_overload_slots(state, true)
	var slot_count_before := guard.slots.size()
	state.held_gem_uid = ""
	controller.select_action(Constants.ACTION_EXTRACT)
	var result := controller.try_extract(guard.uid, 0)
	if not result.get("ok", false):
		_fail("extract overload slot failed: %s" % result.get("reason", ""))
		return
	if guard.slots.size() != slot_count_before - 1:
		_fail("empty overload slot should be removed after extract")
		return
	if not state.overload_active_mutations.is_empty():
		_fail("overload mutations should trim when overload gem count drops")
		return
	print("  [OK] extracting overload gem removes slot and layer")


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
	if player.hp != hp_before - CombatConfig.overload_gem_op_damage_amount():
		_fail("gem operation should damage player by overload amount")
		return
	print("  [OK] gem operations can damage the player")


func _test_operation_damage_is_nonlethal(controller: BattleController, state: GameState, player: UnitState, guard: UnitState) -> void:
	_force_player_phase(state)
	_reset_slots(state, player, guard)
	_mark_overload_slot(guard, 0)
	state.overload_active_mutations = [Constants.OVERLOAD_GEM_OP_DAMAGE]
	player.hp = 2
	controller.select_action(Constants.ACTION_INSERT)
	var result := controller.try_insert(guard.uid, 2)
	if not result.get("ok", false):
		_fail("insert for nonlethal damage test failed: %s" % result.get("reason", ""))
		return
	if not player.alive:
		_fail("overload operation backlash should not defeat the player")
		return
	if player.hp != 1:
		_fail("overload operation backlash should leave player at 1 hp, got %d" % player.hp)
		return
	print("  [OK] gem operation backlash is nonlethal")


func _test_echo_extract(controller: BattleController, state: GameState, player: UnitState, guard: UnitState) -> void:
	_force_player_phase(state)
	_reset_slots(state, player, guard)
	_mark_overload_slot(guard, 1)
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


func _test_echo_extract_does_not_chain(state: GameState, player: UnitState, guard: UnitState) -> void:
	var slot := guard.get_slot_by_index(0)
	var original_uid := state.held_gem_uid
	var echo_uid := slot.gem_uid
	assert(not original_uid.is_empty() and not echo_uid.is_empty(), "echo fixture should retain both gems")
	assert(state.overload_echo_gems.has(echo_uid), "fixture slot should contain a tracked echo")
	assert(GemTransfer.to_ground(state, state.gems[original_uid], player.pos), "real gem should leave hand before extracting echo")
	var result := GemRules.extract(state, player, guard, slot)
	assert(result.get("ok", false), "echo extraction should succeed")
	assert(slot.gem_uid.is_empty(), "extracting an echo must not create another echo")
	assert(state.held_gem_uid == echo_uid, "the extracted echo should be the held gem")
	print("  [OK] echo extraction cannot chain into infinite gems")


func _test_ai_control_blocks_manual_actions(controller: BattleController, state: GameState, player: UnitState, guard: UnitState) -> void:
	_force_player_phase(state)
	_reset_slots(state, player, guard)
	StatusRegistry.apply_to_unit(player, StatusInstance.create(Constants.STATUS_OVERLOAD_AI_CONTROL, 1, 1))
	if controller.can_use_action(Constants.ACTION_MOVE):
		_fail("AI control should disable manual move")
		return
	if controller.can_use_action(Constants.ACTION_ATTACK):
		_fail("AI control should disable manual attack")
		return
	state.held_gem_uid = ""
	if controller.can_use_action(Constants.ACTION_EXTRACT):
		_fail("AI control should disable manual extract")
		return
	state.held_gem_uid = _make_gem(state, Constants.GEM_FIRE, player.uid)
	if controller.can_use_action(Constants.ACTION_INSERT):
		_fail("AI control should disable manual insert")
		return
	if not controller.can_use_action(Constants.ACTION_END_TURN):
		_fail("AI control should still allow ending the turn")
		return
	for result in [
		controller.try_move(player.pos),
		controller.try_attack_cell(guard.pos),
		controller.try_extract(guard.uid, 0),
		controller.try_insert(guard.uid, 2),
	]:
		if result.get("ok", false) or str(result.get("reason", "")) != "AI 已接管本回合":
			_fail("manual action should be rejected by AI control, got %s" % JSON.stringify(result))
			return
	print("  [OK] AI control blocks manual actions")


func _test_ai_control_emits_action_events(state: GameState, player: UnitState, guard: UnitState) -> void:
	_force_player_phase(state)
	_reset_slots(state, player, guard)
	var events: Array[Dictionary] = []
	var action := OverloadRules._execute_player_ai_control(state, player, events)
	if action.is_empty():
		_fail("AI control should execute an available gem operation")
		return
	if not events.any(func(ev: Dictionary) -> bool: return str(ev.get("type", "")) == "gem_flash"):
		_fail("AI gem operation should emit a visible gem_flash event")
		return
	print("  [OK] AI control emits action events")


func _reset_slots(state: GameState, player: UnitState, guard: UnitState) -> void:
	for raw_uid in state.gems.keys().duplicate():
		var uid := str(raw_uid)
		if uid.begins_with("test_gem"):
			GemTransfer.remove(state, uid)
	if not state.held_gem_uid.is_empty():
		GemTransfer.remove(state, state.held_gem_uid)
	for unit in [player, guard]:
		unit.statuses.clear()
		for slot in unit.slots:
			if slot != null and not slot.gem_uid.is_empty():
				GemTransfer.remove(state, slot.gem_uid)
		_restore_unit_slots_from_def(unit)
	var held_uid := _make_gem(state, Constants.GEM_EXPLOSION, player.uid)
	state.held_gem_uid = held_uid
	var guard_red := guard.get_slot_by_index(0)
	var guard_blue := guard.get_slot_by_index(1)
	if guard_red != null:
		var red_uid := _make_gem(state, Constants.GEM_POISON, "")
		assert(GemTransfer.to_unit_slot(state, state.gems[red_uid], guard, guard_red))
	if guard_blue != null:
		var blue_uid := _make_gem(state, Constants.GEM_GRAVITY, "")
		assert(GemTransfer.to_unit_slot(state, state.gems[blue_uid], guard, guard_blue))
	state.overload_pending = false
	state.overload_last_action = ""
	state.overload_last_insert_turn = 0
	state.overload_active_mutations.clear()
	state.overload_echo_gems.clear()


func _restore_unit_slots_from_def(unit: UnitState) -> void:
	var registry: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	var def: Dictionary = registry.get_unit_def(unit.unit_def_id)
	unit.slots.clear()
	for slot_data in def.get("slots", []):
		var slot := SlotState.create(
			slot_data.get("slot_type", Constants.SLOT_RED),
			"",
			bool(slot_data.get("locked", false)),
			str(slot_data.get("lock_type", ""))
		)
		slot.dual_type = str(slot_data.get("dual_type", ""))
		slot.unlock_until_turn = int(slot_data.get("unlock_until_turn", -1))
		unit.slots.append(slot)


func _make_gem(state: GameState, gem_id: String, owner_uid: String) -> String:
	var registry: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	var gem_uid: String = registry.next_runtime_uid("test_gem")
	var gem: GemState = registry.create_gem_instance(gem_uid, gem_id, {})
	state.gems[gem_uid] = gem
	if not owner_uid.is_empty():
		assert(GemTransfer.to_hand(state, gem, owner_uid))
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
