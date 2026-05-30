extends SceneTree

const FissionSlimeRules = preload("res://scripts/rules/fission_slime_rules.gd")
const GemEffectsScript = preload("res://scripts/rules/gem_effects.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== Fission Slime Test ===")
	_test_spawn()
	_test_split_gems_mounted()
	_test_blue_only_on_single_target()
	_test_clone_hp_ratio()
	_test_slam_pushes_adjacent_target()
	_test_split_redirect_skips_without_neighbor()
	_test_split_surround_uses_footprint_ring()
	_test_clone_footprint_1x1()
	_test_clone_death_no_resplit()
	_test_clone_uses_melee_ai()
	_test_attack_range_uses_nearest_footprint_cell()
	print("FISSION_SLIME_TEST_PASS")
	quit()


func _test_spawn() -> void:
	var controller := BattleController.new()
	controller.start_encounter("fission_slime_test", 42)
	var slime := _find_slime(controller.state)
	assert(slime != null)
	assert(slime.footprint_size == Vector2i(2, 2))
	assert(slime.max_hp >= 22 and slime.max_hp <= 28)
	assert(slime.move_points == 2 and slime.base_attack == 4)
	print("  [OK] spawn hp=%d footprint 2x2" % slime.max_hp)


func _test_split_gems_mounted() -> void:
	var controller := BattleController.new()
	controller.start_encounter("fission_slime_test", 42)
	var slime := _find_slime(controller.state)
	var blue := slime.get_slot(Constants.SLOT_BLUE)
	var black := slime.get_slot(Constants.SLOT_BLACK)
	assert(blue != null and black != null)
	var blue_gem: GemState = controller.state.gems.get(blue.gem_uid, null)
	var black_gem: GemState = controller.state.gems.get(black.gem_uid, null)
	assert(blue_gem != null and blue_gem.gem_id == Constants.GEM_SPLIT)
	assert(black_gem != null and black_gem.gem_id == Constants.GEM_SPLIT)
	print("  [OK] blue/black split gems mounted")


func _test_blue_only_on_single_target() -> void:
	var controller := BattleController.new()
	controller.start_encounter("fission_slime_test", 42)
	var state := controller.state
	var slime := _find_slime(state)
	var dummy := _spawn_dummy(state, Vector2i(3, 3))
	var melee_remaining := GemEffectsScript.intercept_damage_for_split(
		state, slime, dummy.uid, "melee_attack", 10
	)
	assert(melee_remaining == 5, "single target should redirect 50%%, got %d" % melee_remaining)
	var boom_remaining := GemEffectsScript.intercept_damage_for_split(
		state, slime, dummy.uid, "explosion", 10
	)
	assert(boom_remaining == 10, "aoe should not redirect for fission slime")
	print("  [OK] split blue on single target only")


func _test_clone_hp_ratio() -> void:
	var controller := BattleController.new()
	controller.start_encounter("fission_slime_test", 42)
	var state := controller.state
	var slime := _find_slime(state)
	slime.max_hp = 20
	slime.hp = 20
	var events: Array[Dictionary] = []
	GemEffectsScript.on_unit_death(state, slime, events)
	var clone_hp := 0
	for unit in state.units.values():
		if unit.has_tag(Constants.TAG_UNIT_SPLIT_CLONE):
			clone_hp = unit.max_hp
			assert(unit.footprint_size == Vector2i(1, 1))
			break
	assert(clone_hp == 10, "clone hp should be 50%% of 20 = 10, got %d" % clone_hp)
	print("  [OK] death clones inherit 50%% hp")


func _test_slam_pushes_adjacent_target() -> void:
	var controller := BattleController.new()
	controller.start_encounter("fission_slime_test", 42)
	var state := controller.state
	var slime := _find_slime(state)
	var player := state.get_player()
	player.pos = Vector2i(3, 3)
	assert(BoardUtils.are_units_adjacent(slime, player), "player should be adjacent to slime footprint")
	IntentSystem.refresh_unit_intent(state, slime)
	assert(slime.intent.type == "slam_attack", "expected slam, got %s" % slime.intent.type)
	var pos_before := player.pos
	var hp_before := player.hp
	var events := IntentSystem.execute_intent(state, slime)
	assert(player.hp < hp_before or player.pos != pos_before, "slam should damage or push player")
	assert(not events.is_empty(), "slam should emit events")
	print("  [OK] slam attack hits and displaces")


func _test_split_redirect_skips_without_neighbor() -> void:
	var controller := BattleController.new()
	controller.start_encounter("fission_slime_test", 42)
	var state := controller.state
	var slime := _find_slime(state)
	var remaining := GemEffectsScript.intercept_damage_for_split(
		state, slime, "player_1", "melee_attack", 10
	)
	assert(remaining == 10, "no neighbor should take full damage, got %d" % remaining)
	print("  [OK] split blue skips redirect without neighbor")


func _test_split_surround_uses_footprint_ring() -> void:
	var controller := BattleController.new()
	controller.start_encounter("fission_slime_test", 42)
	var state := controller.state
	var slime := _find_slime(state)
	slime.pos = Vector2i(2, 2)
	var dummy := _spawn_dummy(state, Vector2i(4, 4))
	assert(
		not BoardUtils.chebyshev(slime.pos, dummy.pos) <= 1,
		"anchor chebyshev should miss far corner"
	)
	assert(BoardUtils.is_within_surround(slime, dummy, Constants.SPLIT_SURROUND_RADIUS))
	var remaining := GemEffectsScript.intercept_damage_for_split(
		state, slime, dummy.uid, "melee_attack", 10
	)
	assert(remaining == 5, "footprint surround should allow redirect, got %d" % remaining)
	print("  [OK] split surround uses footprint ring")


func _test_clone_footprint_1x1() -> void:
	var controller := BattleController.new()
	controller.start_encounter("fission_slime_test", 42)
	var state := controller.state
	var slime := _find_slime(state)
	var events: Array[Dictionary] = []
	GemEffectsScript.on_unit_death(state, slime, events)
	for unit in state.units.values():
		if unit.has_tag(Constants.TAG_UNIT_SPLIT_CLONE):
			assert(unit.footprint_size == Vector2i(1, 1), "clone should be 1x1")
			print("  [OK] split clones are 1x1")
			return
	assert(false, "expected split clone")


func _test_clone_death_no_resplit() -> void:
	var controller := BattleController.new()
	controller.start_encounter("fission_slime_test", 42)
	var state := controller.state
	var slime := _find_slime(state)
	var events: Array[Dictionary] = []
	GemEffectsScript.on_unit_death(state, slime, events)
	var clone: UnitState = null
	for unit in state.units.values():
		if unit.has_tag(Constants.TAG_UNIT_SPLIT_CLONE):
			clone = unit
			break
	assert(clone != null, "expected a split clone")
	var before_count := 0
	for unit in state.units.values():
		if unit.has_tag(Constants.TAG_UNIT_SPLIT_CLONE):
			before_count += 1
	GemEffectsScript.on_unit_death(state, clone, events)
	var after_count := 0
	for unit in state.units.values():
		if unit.has_tag(Constants.TAG_UNIT_SPLIT_CLONE) and unit.alive:
			after_count += 1
	assert(after_count == before_count - 1, "clone death should not spawn more clones")
	print("  [OK] clone death does not resplit")


func _test_clone_uses_melee_ai() -> void:
	var controller := BattleController.new()
	controller.start_encounter("fission_slime_test", 42)
	var state := controller.state
	var slime := _find_slime(state)
	var player := state.get_player()
	var events: Array[Dictionary] = []
	GemEffectsScript.on_unit_death(state, slime, events)
	var clone: UnitState = null
	for unit in state.units.values():
		if unit.has_tag(Constants.TAG_UNIT_SPLIT_CLONE):
			clone = unit
			break
	assert(clone != null)
	assert(clone.behavior_id == "generic_melee")
	player.pos = clone.pos + Vector2i(1, 0)
	if not BoardUtils.are_units_adjacent(clone, player):
		player.pos = clone.pos + Vector2i(0, 1)
	IntentSystem.refresh_unit_intent(state, clone)
	assert(clone.intent.type != "wait", "clone should act, got %s" % clone.intent.type)
	print("  [OK] clone uses generic melee ai")


func _test_attack_range_uses_nearest_footprint_cell() -> void:
	var controller := BattleController.new()
	controller.start_encounter("fission_slime_test", 42)
	var state := controller.state
	var slime := _find_slime(state)
	var player := state.get_player()
	slime.pos = Vector2i(3, 2)
	player.pos = Vector2i(0, 2)
	assert(BoardUtils.distance_between_units(player, slime) == 3)
	var far_cell := Vector2i(4, 3)
	assert(BoardUtils.manhattan(player.pos, far_cell) == 5)
	assert(BoardUtils.can_unit_attack_cell(player, state, far_cell, Constants.ATTACK_RANGE))
	var result := controller.try_attack_cell(far_cell)
	assert(result.get("ok", false), "should attack slime via nearest footprint cell")
	print("  [OK] attack range uses nearest footprint cell")


func _spawn_dummy(state: GameState, pos: Vector2i) -> UnitState:
	var reg: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	var uid: String = reg.next_runtime_uid("dummy")
	var unit := UnitState.from_def(uid, "unit_patrol_guard", Constants.TEAM_ENEMY, pos, reg.get_unit_def("unit_patrol_guard"))
	state.register_unit(unit)
	return unit


func _find_slime(state: GameState) -> UnitState:
	for unit in state.units.values():
		if unit.unit_def_id == "unit_fission_slime":
			return unit
	return null
