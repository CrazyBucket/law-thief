extends SceneTree


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Status System Test ===")
	_test_poison_stack_and_tick()
	_test_armor_max_value_merge()
	_test_rooted_blocks_move()
	_test_lawless_payload()
	_test_exposed_expires()
	print("STATUS_TEST_PASS")
	quit()


func _test_poison_stack_and_tick() -> void:
	var state := _make_state()
	var unit := _make_unit(state, "u1")
	StatusRules.apply_poison(state, unit, 1, 2)
	StatusRules.apply_poison(state, unit, 2, 3)
	var poison: StatusInstance = unit.get_status(Constants.STATUS_POISON)
	assert(poison.stacks == 3, "poison stacks should merge")
	assert(poison.duration == 3, "poison duration should take max")
	StatusRules.tick_turn_start(state)
	assert(unit.hp == 7, "poison should deal 3 damage on turn start")
	print("  [OK] poison stack + tick")


func _test_armor_max_value_merge() -> void:
	var state := _make_state()
	var unit := _make_unit(state, "u2")
	StatusRules.apply_armor(state, unit, 2, 2)
	StatusRules.apply_armor(state, unit, 4, 1)
	var armor: StatusInstance = unit.get_status(Constants.STATUS_ARMOR)
	assert(armor.value == 4, "armor should keep higher value")
	assert(armor.duration == 2, "armor duration should extend")
	assert(StatusRules.get_armor_bonus(unit) == 4, "armor bonus from status")
	print("  [OK] armor merge")


func _test_rooted_blocks_move() -> void:
	var state := _make_state()
	var unit := _make_unit(state, "u3")
	assert(StatusRules.can_move(unit), "unit should move by default")
	StatusRules.apply_rooted(state, unit, 2)
	assert(not StatusRules.can_move(unit), "rooted should block movement")
	StatusRules.tick_turn_start(state)
	assert(unit.has_status(Constants.STATUS_ROOTED), "rooted should remain after one tick")
	StatusRules.tick_turn_start(state)
	assert(not unit.has_status(Constants.STATUS_ROOTED), "rooted should expire")
	print("  [OK] rooted move block + expire")


func _test_lawless_payload() -> void:
	var state := _make_state()
	var unit := _make_unit(state, "u4")
	StatusRules.apply_lawless(state, unit, "gem_123")
	assert(StatusRules.is_lawless(unit), "lawless flag via status")
	assert(StatusRules.get_lawless_gem_uid(unit) == "gem_123", "lawless payload stored")
	StatusRules.clear_lawless(unit)
	assert(not StatusRules.is_lawless(unit), "lawless cleared")
	print("  [OK] lawless payload")


func _test_exposed_expires() -> void:
	var state := _make_state()
	var unit := _make_unit(state, "u5")
	var gem := GemState.new()
	gem.uid = "heavy_gem"
	gem.gem_id = Constants.GEM_HEAVY_ARMOR
	state.gems[gem.uid] = gem
	var slot := SlotState.create(Constants.SLOT_BLUE, gem.uid, true, Constants.LOCK_ARMOR)
	unit.slots.append(slot)
	StatusRules.apply_exposed(state, unit, slot, 1)
	assert(not slot.locked, "slot should unlock")
	assert(unit.has_status(Constants.STATUS_EXPOSED), "exposed status applied")
	StatusRules.tick_turn_end(state)
	assert(not unit.has_status(Constants.STATUS_EXPOSED), "exposed should expire at turn end")
	assert(slot.locked, "slot should re-lock after exposed expires")
	print("  [OK] exposed expire + re-lock")


func _make_state() -> GameState:
	var state := GameState.new()
	state.player_uid = "player"
	state.units = {}
	return state


func _make_unit(state: GameState, uid: String) -> UnitState:
	var unit := UnitState.new()
	unit.uid = uid
	unit.team = Constants.TEAM_ENEMY
	unit.hp = 10
	unit.max_hp = 10
	unit.alive = true
	state.units[uid] = unit
	return unit
