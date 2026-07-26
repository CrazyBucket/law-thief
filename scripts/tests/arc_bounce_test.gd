extends SceneTree

const GemEffects = preload("res://scripts/rules/gem_effects.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Arc Bounce Test ===")
	_test_arc_hits_all_enemies_in_range()
	_test_arc_uses_defeated_victim_as_anchor()
	_test_arc_skips_same_team()
	_test_arc_uses_base_attack_and_flat_relic_bonus()
	_test_arc_level_two_adds_one_hop()
	_test_arc_level_three_adds_range_and_hop()
	_test_arc_extra_gems_add_hops_after_level_three()
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
	GemEffects.apply_arc_bounce_from_anchor(state, victim, attacker, events)
	if events.size() < 4 \
			or str(events[0].get("type", "")) != "arc" \
			or str(events[1].get("type", "")) != "arc" \
			or str(events[2].get("type", "")) != "damage" \
			or str(events[3].get("type", "")) != "damage":
		_fail("same-hop arc events must be visuals first, then impact damage: %s" % [events])
		return
	for index in range(2):
		if events[index].get("from", Vector2i.ZERO) != victim.pos:
			_fail("arc visual must preserve its source anchor")
			return
		if not events[index].has("target_pos"):
			_fail("arc visual must preserve its target position")
			return
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
	if near_a.hp != near_a.max_hp - 2 or near_b.hp != near_b.max_hp - 2:
		_fail("red arc bounces should deal 20%% of the attacker's 10 base attack")
		return
	if far.hp < far.max_hp:
		_fail("out-of-range enemy should not take arc damage")
		return
	print("  [OK] arc hits all in-range enemies once")


func _test_arc_uses_defeated_victim_as_anchor() -> void:
	var state := _battle_state()
	var attacker := state.get_player()
	var victim := _spawn_enemy(state, Vector2i(5, 3), "defeated_victim")
	var chained := _spawn_enemy(state, Vector2i(6, 3), "after_lethal")
	victim.alive = false
	victim.hp = 0
	var events: Array[Dictionary] = []
	GemEffects.apply_arc_bounce_from_anchor(state, victim, attacker, events)
	if chained.hp != chained.max_hp - 2:
		_fail("a lethal primary hit should still launch arc from the defeated victim")
		return
	if not events.any(func(event): return str(event.get("type", "")) == "arc" and event.get("from", Vector2i.ZERO) == victim.pos):
		_fail("lethal-hit arc should preserve the defeated victim position as its anchor")
		return
	print("  [OK] defeated victim remains a valid arc anchor")


func _test_arc_skips_same_team() -> void:
	var state := _battle_state()
	var attacker := state.get_player()
	var victim := _spawn_enemy(state, Vector2i(5, 3), "victim")
	var ally := state.get_player()
	ally.pos = Vector2i(6, 3)
	var events: Array[Dictionary] = []
	GemEffects.apply_arc_bounce_from_anchor(state, victim, attacker, events)
	var arc_hits := 0
	for ev in events:
		if str(ev.get("type", "")) == "arc":
			arc_hits += 1
	if arc_hits != 0:
		_fail("arc should not hit same team, got %d" % arc_hits)
		return
	print("  [OK] arc skips allies")


func _test_arc_uses_base_attack_and_flat_relic_bonus() -> void:
	var baseline_state := _battle_state()
	var baseline_attacker := baseline_state.get_player()
	var baseline_anchor := _spawn_enemy(baseline_state, Vector2i(5, 3), "base_attack_anchor")
	var baseline_target := _spawn_enemy(baseline_state, Vector2i(6, 3), "base_attack_target")
	var baseline_events: Array[Dictionary] = []
	GemEffects.apply_arc_bounce_from_anchor(baseline_state, baseline_anchor, baseline_attacker, baseline_events)
	if baseline_target.hp != baseline_target.max_hp - 2:
		_fail("arc should use the attacker's base attack before any flurry or split reduction")
		return
	var adventure_service: Node = Engine.get_main_loop().root.get_node("AdventureService")
	var run_service: Node = Engine.get_main_loop().root.get_node("RunService")
	adventure_service.start_new_run(20260726)
	var run: RunState = run_service.get_run()
	run.owned_relics.clear()
	run.owned_relics.append("relic_silver_cable")
	var boosted_state := _battle_state()
	var boosted_attacker := boosted_state.get_player()
	var boosted_anchor := _spawn_enemy(boosted_state, Vector2i(5, 3), "silver_cable_anchor")
	var boosted_target := _spawn_enemy(boosted_state, Vector2i(6, 3), "silver_cable_target")
	var boosted_events: Array[Dictionary] = []
	GemEffects.apply_arc_bounce_from_anchor(boosted_state, boosted_anchor, boosted_attacker, boosted_events)
	run_service.end_run()
	if boosted_target.hp != boosted_target.max_hp - 3:
		_fail("silver cable should add one arc damage after the base-attack calculation")
		return
	print("  [OK] arc uses base attack and silver cable adds flat damage")


func _test_arc_level_two_adds_one_hop() -> void:
	var state := _battle_state()
	var attacker := state.get_player()
	var victim := _spawn_enemy(state, Vector2i(5, 3), "victim")
	var relay := _spawn_enemy(state, Vector2i(7, 3), "relay")
	var chained := _spawn_enemy(state, Vector2i(9, 3), "chained")
	var events: Array[Dictionary] = []
	GemEffects.apply_arc_bounce_from_anchor(
		state,
		victim,
		attacker,
		events,
		{"tag_levels": {"arc": 2}}
	)
	if relay.hp >= relay.max_hp or chained.hp >= chained.max_hp:
		_fail("level 2 arc should add one chained hop")
		return
	print("  [OK] arc level 2 adds one hop")


func _test_arc_level_three_adds_range_and_hop() -> void:
	var state := _battle_state()
	var attacker := state.get_player()
	var victim := _spawn_enemy(state, Vector2i(5, 3), "victim")
	var range_target := _spawn_enemy(state, Vector2i(8, 3), "range_target")
	var second_hop := _spawn_enemy(state, Vector2i(11, 3), "second_hop")
	var third_hop := _spawn_enemy(state, Vector2i(14, 3), "third_hop")
	var events: Array[Dictionary] = []
	GemEffects.apply_arc_bounce_from_anchor(
		state,
		victim,
		attacker,
		events,
		{"tag_levels": {"arc": 3}}
	)
	if range_target.hp >= range_target.max_hp or second_hop.hp >= second_hop.max_hp or third_hop.hp >= third_hop.max_hp:
		_fail("level 3 arc should reach range 3 and resolve all three hops")
		return
	print("  [OK] arc level 3 adds range and one hop")


func _test_arc_extra_gems_add_hops_after_level_three() -> void:
	var state := _battle_state()
	var attacker := state.get_player()
	var victim := _spawn_enemy(state, Vector2i(5, 3), "victim")
	var first_hop := _spawn_enemy(state, Vector2i(8, 3), "first_hop")
	var second_hop := _spawn_enemy(state, Vector2i(11, 3), "second_hop")
	var third_hop := _spawn_enemy(state, Vector2i(14, 3), "third_hop")
	var fourth_hop := _spawn_enemy(state, Vector2i(17, 3), "fourth_hop")
	var events: Array[Dictionary] = []
	GemEffects.apply_arc_bounce_from_anchor(
		state,
		victim,
		attacker,
		events,
		{"tag_levels": {"arc": 3}, "tag_counts": {"arc": 4}}
	)
	if fourth_hop.hp >= fourth_hop.max_hp:
		_fail("each conductive gem after the third should add one bounce hop")
		return
	if first_hop.hp >= first_hop.max_hp or second_hop.hp >= second_hop.max_hp or third_hop.hp >= third_hop.max_hp:
		_fail("extra arc hop must not drop prior hop damage")
		return
	print("  [OK] each conductive gem after level 3 adds one hop")


func _battle_state() -> GameState:
	var state := GameState.new()
	var player := UnitState.new()
	player.uid = "arc_test_player"
	player.team = Constants.TEAM_PLAYER
	player.pos = Vector2i(2, 3)
	player.hp = 50
	player.max_hp = 50
	player.base_attack = 10
	player.alive = true
	state.player_uid = player.uid
	state.register_unit(player)
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
