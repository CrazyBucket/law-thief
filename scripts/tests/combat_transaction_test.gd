extends SceneTree


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Combat Transaction Test ===")
	_test_damage_unit_event_shape()
	_test_true_damage_unit_lethal_event_shape()
	_test_damage_unit_preserves_existing_event_sink()
	_test_begin_from_state_reuses_existing_event_sink()
	_test_bound_move_sink_captures_spike_damage()
	_test_damage_context_tags_are_normalized()
	_test_event_validator_requires_damage_identity()
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
	assert(events.size() == 2, "lethal true damage should emit damage and die events")
	var ev := events[0]
	assert(ev.get("type", "") == "damage", "lethal damage should be presented before final death")
	assert(ev.get("uid", "") == victim.uid, "true damage event should include uid")
	assert(ev.get("victim_uid", "") == victim.uid, "true damage event should include victim_uid")
	assert(ev.get("lethal", false), "lethal true damage should mark lethal=true")
	assert(int(ev.get("remaining_hp", -1)) == 0, "lethal event should record remaining_hp=0")
	assert(ev.get("reason", "") == "true_tx_test", "true damage event should include reason")
	assert(events[1].get("type", "") == "die", "death should have an explicit terminal presentation event")
	assert(events[1].get("uid", "") == victim.uid, "die event should identify the victim")
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


func _test_begin_from_state_reuses_existing_event_sink() -> void:
	var state := _make_state()
	var attacker := _make_unit(state, "attacker", Constants.TEAM_PLAYER, Vector2i(1, 1), 10)
	var victim := _make_unit(state, "victim", Constants.TEAM_ENEMY, Vector2i(2, 1), 10)
	var events: Array[Dictionary] = []
	state.bind_combat_events(events)
	var tx := CombatTransaction.begin_from_state(state)
	tx.damage_unit(victim, 2, attacker.uid, "sink_reuse_test")
	tx.finish("combat_transaction_test.sink_reuse")
	assert(state.has_combat_event_sink(), "begin_from_state should not unbind an existing event sink")
	state.unbind_combat_events()
	assert(events.size() == 1, "begin_from_state should append damage to the existing sink")
	assert(events[0].get("uid", "") == victim.uid, "sink damage event should include uid")
	_assert_events_valid(events, "begin_from_state_reuses_existing_event_sink")
	print("  [OK] begin_from_state reuses existing event sink")


func _test_bound_move_sink_captures_spike_damage() -> void:
	var state := _make_state()
	var unit := _make_unit(state, "walker", Constants.TEAM_PLAYER, Vector2i(1, 1), 20)
	state.add_entity(EntityState.create("spike_test", Constants.ENTITY_SPIKE, Vector2i(2, 1)))
	var events: Array[Dictionary] = []
	var tx := CombatTransaction.begin(state, events).bind_event_sink()
	tx.move_unit(unit, Vector2i(2, 1), {"reason": "test_move"})
	TileRules.on_unit_moved_through(state, unit, unit.pos)
	tx.finish("combat_transaction_test.bound_move_spike")
	assert(not state.has_combat_event_sink(), "bound movement transaction should restore event sink")
	var damage_events := events.filter(func(ev): return ev.get("type", "") == "damage")
	assert(damage_events.size() == 1, "spike damage should be captured in movement events")
	var damage_ev: Dictionary = damage_events[0]
	assert(damage_ev.get("uid", "") == unit.uid, "spike damage event should include uid")
	assert(damage_ev.get("victim_uid", "") == unit.uid, "spike damage event should include victim_uid")
	assert(damage_ev.get("reason", "") == "spike_enter", "spike damage should keep reason")
	_assert_events_valid(events, "bound_move_sink_captures_spike_damage")
	print("  [OK] bound move sink captures spike damage")


func _test_damage_context_tags_are_normalized() -> void:
	var state := _make_state()
	var attacker := _make_unit(state, "tag_attacker", Constants.TEAM_PLAYER, Vector2i(1, 1), 10)
	var victim := _make_unit(state, "tag_victim", Constants.TEAM_ENEMY, Vector2i(2, 1), 10)
	var events: Array[Dictionary] = []
	var tx := CombatTransaction.begin(state, events)
	tx.damage_unit(victim, 3, attacker.uid, "tag_test", {
		"damage_tags": ["poison", "fire", "poison", "not_a_gem_tag"],
	})
	assert(events.size() == 1, "tagged damage should emit one event")
	assert(events[0].get("damage_tags", []) == ["fire", "poison"], "damage tags should be known, unique, and canonical")
	_assert_events_valid(events, "damage_context_tags")
	tx.finish("combat_transaction_test.damage_context_tags")
	print("  [OK] damage context tags are normalized")


func _test_event_validator_requires_damage_identity() -> void:
	var violations := EventValidator.validate_events([
		{"type": "damage", "pos": Vector2i(1, 1), "damage": 1, "is_crit": false},
	])
	assert(not violations.is_empty(), "damage without uid should violate event contract")
	assert(
		violations.any(func(v: String) -> bool: return v.find("uid") >= 0),
		"damage identity violation should mention uid: %s" % str(violations)
	)
	var duplicate_tag_violations := EventValidator.validate_events([{
		"type": "damage",
		"uid": "victim",
		"victim_uid": "victim",
		"pos": Vector2i(1, 1),
		"damage": 1,
		"is_crit": false,
		"damage_tags": ["fire", "fire"],
	}])
	assert(duplicate_tag_violations.any(
		func(v: String) -> bool: return v.find("duplicate damage tag") >= 0
	), "event validator should reject duplicate damage tags")
	print("  [OK] event validator requires damage identity")


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
