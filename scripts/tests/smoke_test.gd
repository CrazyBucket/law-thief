extends SceneTree


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var controller := BattleController.new()
	controller.start_encounter("tutorial_001", 12345)
	var state := controller.state
	var rat := _find_unit_by_def(state, "unit_bomb_rat")
	var guard := _find_unit_by_def(state, "unit_patrol_guard")
	if rat == null or guard == null:
		push_error("missing units")
		quit(1)
		return
	rat.hp = 10

	_force_gem(state, rat, Constants.SLOT_RED, Constants.GEM_EXPLOSION)

	controller.select_action(Constants.ACTION_EXTRACT)
	var extract_result := controller.try_extract(rat.uid, 0)
	if not extract_result.get("ok", false):
		push_error("extract failed: %s" % extract_result.get("reason", ""))
		quit(1)
		return
	if state.player_acted:
		push_error("extract should NOT consume action (new economy)")
		quit(1)
		return
	print("  [OK] extract is free")

	controller.select_action(Constants.ACTION_MOVE)
	var moved := false
	var player := state.get_player()
	for cell in BoardUtils.reachable_cells(state, player.pos, player.move_points):
		if BoardUtils.manhattan(cell, guard.pos) == 1:
			var move_result := controller.try_move(cell)
			if move_result.get("ok", false):
				moved = true
				break
	if not moved:
		push_error("could not move adjacent to guard")
		quit(1)
		return
	print("  [OK] moved adjacent to guard")

	var black_slot := guard.get_slot(Constants.SLOT_BLACK)
	if black_slot != null and not black_slot.gem_uid.is_empty():
		state.gems.erase(black_slot.gem_uid)
		black_slot.gem_uid = ""

	controller.select_action(Constants.ACTION_INSERT)
	var insert_result := controller.try_insert(guard.uid, 2)
	if not insert_result.get("ok", false):
		push_error("insert failed: %s" % insert_result.get("reason", ""))
		quit(1)
		return
	if state.player_acted:
		push_error("insert should NOT consume action (new economy)")
		quit(1)
		return
	print("  [OK] insert is free (into BLACK slot)")

	guard.hp = 10

	controller.select_action(Constants.ACTION_ATTACK)
	var attack_result := controller.try_attack(guard.uid)
	if not attack_result.get("ok", false):
		push_error("attack failed: %s" % attack_result.get("reason", ""))
		quit(1)
		return
	if not state.player_acted:
		push_error("attack should consume action")
		quit(1)
		return
	print("  [OK] attack consumes action")

	if guard.alive or rat.alive:
		push_error("expected both enemies dead after death explosion")
		quit(1)
		return
	print("  [OK] both enemies dead in ONE turn")

	if controller.can_use_action(Constants.ACTION_ATTACK):
		push_error("should not be able to attack again")
		quit(1)
		return
	if controller.can_use_action(Constants.ACTION_TRIGGER):
		push_error("should not be able to trigger after acting")
		quit(1)
		return
	if controller.can_use_action(Constants.ACTION_EXTRACT):
		push_error("should not be able to extract after acting")
		quit(1)
		return
	print("  [OK] action economy correct after attack")

	print("SMOKE_TEST_PASS")
	quit()


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
