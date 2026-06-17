extends SceneTree


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Combat Transaction Test ===")
	_test_damage_unit_event_shape()
	_test_true_damage_unit_lethal_event_shape()
	_test_damage_unit_preserves_existing_event_sink()
	print("COMBAT_TRANSACTION_TEST_PASS")
	quit()


func _test_damage_unit_event_shape() -> void:
	var state := _make_state()
	var attacker := _make_unit(state, "attacker", Constants.TEAM_PLAYER, Vector2i(1, 1), 10)
	var victim := _make_unit(state, "victim", Constants.TEAM_ENEMY, Vector2i(2, 1), 10)
	var events: Array[Dictionary] = []
	var tx := CombatTransaction.begin(state, events)
	var dealt := tx.damage_unit(victim, 3, attacker.uid, "tx_test", {"is_crit": true})
	assert(dealt == 3, "damage_unit should return dealt damage")
	assert(victim.hp == 7, "victim hp should be reduced")
	assert(not state.has_combat_event_sink(), "transaction should restore temporary event sink")
	assert(events.size() == 1, "damage_unit should emit one damage event, got %d" % events.size())
	var ev := events[0]
	assert(ev.get("type", "") == "damage", "event type should be damage")
	assert(ev.get("uid", "") == victim.uid, "damage event should include uid")
	assert(ev.get("victim_uid", "") == victim.uid, "damage event should include victim_uid")
	assert(ev.get("attacker_uid", "") == attacker.uid, "damage event should include attacker_uid")
	assert(ev.get("source_uid", "") == attacker.uid, "damage event should include source_uid")
	assert(ev.get("reason", "") == "tx_test", "damage event should include reason")
	assert(ev.get("lethal", true) == false, "nonlethal damage should mark lethal=false")
	assert(int(ev.get("remaining_hp", -1)) == 7, "damage event should include remaining hp")
	assert(bool(ev.get("is_crit", false)), "opts should flow into damage event")
	_assert_events_valid(events, "damage_unit_event_shape")
	assert(BattleInvariantChecker.assert_valid(state, "damage_unit_event_shape"))
	tx.finish("combat_transaction_test.damage_unit")
	print("  [OK] damage_unit event shape")


func _test_true_damage_unit_lethal_event_shape() -> void:
	var state := _make_state()
	var attacker := _make_unit(state, "attacker", Constants.TEAM_PLAYER, Vector2i(1, 1), 10)
	var victim := _make_unit(state, "victim", Constants.TEAM_ENEMY, Vector2i(2, 1), 2)
	var events: Array[Dictionary] = []
	var tx := CombatTransaction.begin(state, events)
	var dealt := tx.true_damage_unit(victim, 5, attacker.uid, "true_tx_test")
	assert(dealt == 5, "true_damage_unit should return dealt true damage")
	assert(not victim.alive, "lethal true damage should kill victim")
	assert(victim.hp == 0, "dead victim hp should clamp to 0")
	assert(state.get_unit_at(victim.pos) == null, "dead victim should be removed from occupancy")
	assert(events.size() == 1, "true damage should emit one damage event")
	var ev := events[0]
	assert(ev.get("uid", "") == victim.uid, "true damage event should include uid")
	assert(ev.get("victim_uid", "") == victim.uid, "true damage event should include victim_uid")
	assert(ev.get("lethal", false), "lethal true damage should mark lethal=true")
	assert(int(ev.get("remaining_hp", -1)) == 0, "lethal event should record remaining_hp=0")
	assert(ev.get("reason", "") == "true_tx_test", "true damage event should include reason")
	_assert_events_valid(events, "true_damage_unit_lethal_event_shape")
	assert(BattleInvariantChecker.assert_valid(state, "true_damage_unit_lethal_event_shape"))
	tx.finish("combat_transaction_test.true_damage_unit")
	print("  [OK] true_damage_unit lethal event shape")


func _test_damage_unit_preserves_existing_event_sink() -> void:
	var state := _make_state()
	var attacker := _make_unit(state, "attacker", Constants.TEAM_PLAYER, Vector2i(1, 1), 10)
	var victim := _make_unit(state, "victim", Constants.TEAM_ENEMY, Vector2i(2, 1), 10)
	var outer_events: Array[Dictionary] = []
	var tx_events: Array[Dictionary] = []
	state.bind_combat_events(outer_events)
	var tx := CombatTransaction.begin(state, tx_events)
	tx.damage_unit(victim, 1, attacker.uid, "bound_sink_test")
	assert(state.has_combat_event_sink(), "transaction should preserve a pre-existing event sink")
	state.unbind_combat_events()
	assert(tx_events.size() == 1, "explicit transaction event should still be appended to transaction events")
	_assert_events_valid(tx_events, "damage_unit_preserves_existing_event_sink")
	tx.finish("combat_transaction_test.bound_sink")
	print("  [OK] damage_unit preserves existing sink")


func _assert_events_valid(events: Array, context: String) -> void:
	var violations := EventValidator.validate_events(events)
	assert(violations.is_empty(), "%s event violations: %s" % [context, str(violations)])


func _make_state() -> GameState:
	var state := GameState.new()
	state.board_size = Constants.BOARD_SIZE
	return state


func _make_unit(state: GameState, uid: String, team: String, pos: Vector2i, hp: int) -> UnitState:
	var unit := UnitState.new()
	unit.uid = uid
	unit.team = team
	unit.pos = pos
	unit.hp = hp
	unit.max_hp = hp
	unit.alive = true
	unit.footprint_size = Vector2i(1, 1)
	state.register_unit(unit)
	return unit
