extends SceneTree

const GemEffects = preload("res://scripts/rules/gem_effects.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Arc Bounce Test ===")
	_test_arc_hits_all_enemies_in_range()
	_test_arc_skips_same_team()
	_test_arc_level_two_adds_one_hop()
	_test_arc_level_three_adds_range()
	if _failed:
		push_error("ARC_BOUNCE_TEST_FAIL")
		quit(1)
		return
	print("ARC_BOUNCE_TEST_PASS")
	quit(0)


func _test_arc_hits_all_enemies_in_range() -> void:
	var state := _battle_state()
	var attacker := state.get_player()
	var victim := _spawn_enemy(state, Vector2i(5, 3), "victim")
	var near_a := _spawn_enemy(state, Vector2i(6, 3), "near_a")
	var near_b := _spawn_enemy(state, Vector2i(5, 2), "near_b")
	var far := _spawn_enemy(state, Vector2i(9, 3), "far")
	var events: Array[Dictionary] = []
	GemEffects.apply_arc_bounce_from_victim(state, victim, attacker, 10, events)
	var arc_hits := 0
	for ev in events:
		if str(ev.get("type", "")) != "arc":
			continue
		arc_hits += 1
	if arc_hits != 2:
		_fail("expected 2 arc hits in range, got %d" % arc_hits)
		return
	if near_a.hp >= near_a.max_hp or near_b.hp >= near_b.max_hp:
		_fail("in-range enemies should take arc damage")
		return
	if far.hp < far.max_hp:
		_fail("out-of-range enemy should not take arc damage")
		return
	print("  [OK] arc hits all in-range enemies once")


func _test_arc_skips_same_team() -> void:
	var state := _battle_state()
	var attacker := state.get_player()
	var victim := _spawn_enemy(state, Vector2i(5, 3), "victim")
	var ally := state.get_player()
	ally.pos = Vector2i(6, 3)
	var events: Array[Dictionary] = []
	GemEffects.apply_arc_bounce_from_victim(state, victim, attacker, 10, events)
	var arc_hits := 0
	for ev in events:
		if str(ev.get("type", "")) == "arc":
			arc_hits += 1
	if arc_hits != 0:
		_fail("arc should not hit same team, got %d" % arc_hits)
		return
	print("  [OK] arc skips allies")


func _test_arc_level_two_adds_one_hop() -> void:
	var state := _battle_state()
	var attacker := state.get_player()
	var victim := _spawn_enemy(state, Vector2i(5, 3), "victim")
	var relay := _spawn_enemy(state, Vector2i(7, 3), "relay")
	var chained := _spawn_enemy(state, Vector2i(9, 3), "chained")
	var events: Array[Dictionary] = []
	GemEffects.apply_arc_bounce_from_victim(
		state,
		victim,
		attacker,
		10,
		events,
		{"tag_levels": {"arc": 2}}
	)
	if relay.hp >= relay.max_hp or chained.hp >= chained.max_hp:
		_fail("level 2 arc should add one chained hop")
		return
	print("  [OK] arc level 2 adds one hop")


func _test_arc_level_three_adds_range() -> void:
	var state := _battle_state()
	var attacker := state.get_player()
	var victim := _spawn_enemy(state, Vector2i(5, 3), "victim")
	var range_target := _spawn_enemy(state, Vector2i(8, 3), "range_target")
	var events: Array[Dictionary] = []
	GemEffects.apply_arc_bounce_from_victim(
		state,
		victim,
		attacker,
		10,
		events,
		{"tag_levels": {"arc": 3}}
	)
	if range_target.hp >= range_target.max_hp:
		_fail("level 3 arc should reach range 3")
		return
	print("  [OK] arc level 3 adds range")


func _battle_state() -> GameState:
	var reg: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	var state: GameState = reg.create_battle_state("fission_slime_test", 7)
	for unit in state.units.values():
		if unit.team == Constants.TEAM_ENEMY:
			state.unregister_unit(unit)
	var player := state.get_player()
	player.pos = Vector2i(2, 3)
	player.base_attack = 10
	return state


func _spawn_enemy(state: GameState, pos: Vector2i, suffix: String) -> UnitState:
	var unit := UnitState.new()
	unit.uid = "arc_test_%s" % suffix
	unit.unit_def_id = "unit_patrol_guard"
	unit.team = Constants.TEAM_ENEMY
	unit.pos = pos
	unit.hp = 50
	unit.max_hp = 50
	unit.alive = true
	state.register_unit(unit)
	return unit


func _fail(msg: String) -> void:
	_failed = true
	push_error(msg)
