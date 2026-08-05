extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Gravity Test ===")
	_test_diagonal_pull_collision()
	_test_friendly_collision()
	_test_pull_into_spike_applies_vulnerable()
	if not _failures.is_empty():
		for failure in _failures:
			push_error(failure)
		quit(1)
		return
	print("GRAVITY_TEST_PASS")
	quit()


func _test_diagonal_pull_collision() -> void:
	var state := _make_state()
	var puller := _make_unit(state, "puller", Constants.TEAM_ENEMY, Vector2i(2, 2))
	var target := _make_unit(state, "target", Constants.TEAM_PLAYER, Vector2i(1, 1))
	var player := _make_unit(state, "player", Constants.TEAM_PLAYER, Vector2i(0, 0))
	state.player_uid = player.uid
	var hp_before := target.hp
	var puller_hp_before := puller.hp
	var events := GemEffects.pull_unit_toward_with_events(state, target, puller.pos, 2, puller.uid)
	_require(target.pos == Vector2i(2, 1), "diagonal pull should stop one cell before the blocker")
	_require(hp_before - target.hp == 1, "pulled unit should take one damage after one completed pull step")
	_require(puller_hp_before - puller.hp == 1, "blocking puller should take the same one-step collision damage")
	_require(not events.is_empty(), "collision should emit events")
	_require(EventValidator.validate_events(events).is_empty(), "collision events should satisfy the event contract")
	_require(BattleInvariantChecker.check_all(state).is_empty(), "diagonal pull should preserve battle invariants")
	print("  [OK] diagonal pull collision")


func _test_pull_into_spike_applies_vulnerable() -> void:
	var state := _make_state()
	var puller := _make_unit(state, "puller", Constants.TEAM_ENEMY, Vector2i(3, 3))
	var target := _make_unit(state, "target", Constants.TEAM_PLAYER, Vector2i(1, 3))
	target.hp = 20
	target.max_hp = 20
	state.add_entity(EntityState.create("spike_0", Constants.ENTITY_SPIKE, Vector2i(2, 3)))
	var hp_before := target.hp
	var events := GemEffects.pull_unit_toward_with_events(state, target, puller.pos, 1, puller.uid)
	_require(target.pos == Vector2i(2, 3), "target should land on spike")
	_require(StatusRules.is_vulnerable(target), "forced pull onto spike should apply vulnerable")
	_require(
		target.hp == hp_before - CombatConfig.spike_collision_damage(),
		"pull onto spike should deal configured collision damage exactly once"
	)
	_require(EventValidator.validate_events(events).is_empty(), "spike pull events should satisfy the event contract")
	_require(BattleInvariantChecker.check_all(state).is_empty(), "spike pull should preserve battle invariants")
	print("  [OK] gravity pull onto spike: vulnerable + damage")


func _test_friendly_collision() -> void:
	var state := _make_state()
	var puller := _make_unit(state, "puller", Constants.TEAM_ENEMY, Vector2i(3, 3))
	var ally := _make_unit(state, "ally", Constants.TEAM_ENEMY, Vector2i(2, 2))
	var hp_before := ally.hp
	var puller_hp_before := puller.hp
	var events := GemEffects.pull_unit_toward_with_events(state, ally, puller.pos, 2, puller.uid)
	_require(hp_before - ally.hp == 1, "friendly unit should take one damage after one completed pull step")
	_require(puller_hp_before - puller.hp == 1, "friendly blocker should take the same one-step collision damage")
	_require(EventValidator.validate_events(events).is_empty(), "friendly collision events should satisfy the event contract")
	_require(BattleInvariantChecker.check_all(state).is_empty(), "friendly collision should preserve battle invariants")
	print("  [OK] friendly collision damage")


func _make_state() -> GameState:
	var state := GameState.new()
	state.units = {}
	return state


func _make_unit(state: GameState, uid: String, team: String, pos: Vector2i) -> UnitState:
	var unit := UnitState.new()
	unit.uid = uid
	unit.team = team
	unit.pos = pos
	unit.hp = 6
	unit.max_hp = 6
	unit.alive = true
	state.register_unit(unit)
	return unit


func _require(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
