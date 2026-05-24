extends SceneTree


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Gravity Test ===")
	_test_diagonal_pull_collision()
	_test_friendly_collision()
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
	assert(target.pos == Vector2i(1, 1), "diagonal target should stay put on collision")
	assert(target.hp < hp_before, "pulled unit should take collision damage")
	assert(puller.hp < puller_hp_before, "puller should take collision damage")
	assert(not events.is_empty(), "collision should emit events")
	print("  [OK] diagonal pull collision")


func _test_friendly_collision() -> void:
	var state := _make_state()
	var puller := _make_unit(state, "puller", Constants.TEAM_ENEMY, Vector2i(3, 3))
	var ally := _make_unit(state, "ally", Constants.TEAM_ENEMY, Vector2i(2, 2))
	var hp_before := ally.hp
	GemEffects.pull_unit_toward_with_events(state, ally, puller.pos, 2, puller.uid)
	assert(ally.hp < hp_before, "friendly unit should still take collision damage")
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
	state.units[uid] = unit
	return unit
