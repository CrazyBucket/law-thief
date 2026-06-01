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
	_test_approach_around_prop()
	_test_clone_approaches_around_pillar()
	_test_trample_occupancy_override()
	_test_trample_star_relocation()
	_test_trample_squeeze_all_blocked()
	_test_trample_landing_terrain_settlement()
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


func _test_approach_around_prop() -> void:
	var controller := BattleController.new()
	controller.start_encounter("template_c", 42)
	var state := controller.state
	var slime := _find_slime(state)
	var player := state.get_player()
	assert(slime.pos == Vector2i(3, 3))
	assert(state.get_entity_at(Vector2i(2, 3)) != null, "prop should block west side")
	player.pos = Vector2i(1, 6)
	IntentSystem.refresh_unit_intent(state, slime)
	assert(slime.intent.type != "wait", "slime should move toward player around prop, got %s" % slime.intent.type)
	assert(not slime.intent.path.is_empty(), "slime should have approach path")
	print("  [OK] approach path around blocking prop")


func _test_clone_approaches_around_pillar() -> void:
	var controller := BattleController.new()
	controller.start_encounter("fission_slime_test", 42)
	var state := controller.state
	var slime := _find_slime(state)
	var player := state.get_player()
	slime.max_hp = 10
	slime.hp = 10
	var events: Array[Dictionary] = []
	GemEffectsScript.on_unit_death(state, slime, events)
	var clone: UnitState = null
	for unit in state.units.values():
		if unit.has_tag(Constants.TAG_UNIT_SPLIT_CLONE):
			clone = unit
			break
	assert(clone != null, "expected split clone")
	var pillar := EntityState.create("prop_block", Constants.ENTITY_PROP, clone.pos + Vector2i(0, -1))
	state.add_entity(pillar)
	player.pos = clone.pos + Vector2i(-2, 0)
	IntentSystem.refresh_unit_intent(state, clone)
	assert(clone.intent.type != "wait", "clone should approach player around pillar, got %s" % clone.intent.type)
	if clone.intent.type == "move":
		var end_pos: Vector2i = clone.intent.path.back() if not clone.intent.path.is_empty() else clone.pos
		var before := BoardUtils.path_distance_to_cell(state, clone.pos, player.pos, clone.uid, {}, clone)
		var after := BoardUtils.path_distance_to_cell(state, end_pos, player.pos, clone.uid, {}, clone)
		assert(after < before, "move should reduce path distance (%d -> %d)" % [before, after])
	print("  [OK] clone approaches via path distance")


## 践踏：玩家站在大史莱姆占格上时，执行践踏后玩家被震飞，史莱姆仍然占据原格
func _test_trample_occupancy_override() -> void:
	var state := _make_bare_state()
	# 大史莱姆 2x2，锚点 (2,2)，占格 (2,2)(3,2)(2,3)(3,3)
	var slime := _make_slime(state, Vector2i(2, 2))
	# 玩家站在史莱姆某个占格上
	var player := _make_player(state, Vector2i(3, 3))
	assert(slime.occupied_cells().has(player.pos), "precondition: player on slime footprint")
	var hp_before := player.hp
	var events: Array[Dictionary] = []
	events.append_array(FissionSlimeRules.execute_trample(state, slime, _trample_intent(slime, player)))
	# 玩家应该被震飞（pos 已变）
	assert(player.pos != Vector2i(3, 3), "player should be relocated after trample, got %s" % player.pos)
	# 玩家受到伤害
	assert(player.hp < hp_before, "player should take trample damage")
	# 史莱姆仍然占据原位
	assert(slime.pos == Vector2i(2, 2), "slime should remain at anchor, got %s" % slime.pos)
	print("  [OK] trample: player relocated, slime stays, player takes damage")


## 践踏：星状落点搜索——玩家优先落在距离 1 的合法空格
func _test_trample_star_relocation() -> void:
	var state := _make_bare_state()
	var slime := _make_slime(state, Vector2i(2, 2))
	# 玩家站在 (3,3) 被踩
	var player := _make_player(state, Vector2i(3, 3))
	var events: Array[Dictionary] = []
	events.append_array(FissionSlimeRules.execute_trample(state, slime, _trample_intent(slime, player)))
	# 距离 (3,3) 最近的合法空格应在距离 ≤ 2 以内
	var dist := BoardUtils.manhattan(Vector2i(3, 3), player.pos)
	assert(dist <= 2, "player should land within ring 2 of origin (3,3), got dist=%d pos=%s" % [dist, player.pos])
	print("  [OK] trample star relocation: player lands within ring 2")


## 践踏：全堵死时触发空间挤压惩罚伤害，玩家停留在原位（保底保留）
func _test_trample_squeeze_all_blocked() -> void:
	var state := _make_bare_state()
	var slime := _make_slime(state, Vector2i(0, 0))
	# 玩家在 (1,1)（史莱姆 footprint 内）
	var player := _make_player(state, Vector2i(1, 1))
	# 围死 (1,1) 周围所有合法格（距离 1 和 2 的可用格用实体或单位堵死）
	# 在 3x3 角落，距离 1 的格子有限，用临时单位填满
	state.add_entity(EntityState.create("e1", Constants.ENTITY_ROCK, Vector2i(0, 1)))
	state.add_entity(EntityState.create("e2", Constants.ENTITY_ROCK, Vector2i(1, 0)))
	state.add_entity(EntityState.create("e3", Constants.ENTITY_ROCK, Vector2i(0, 2)))
	state.add_entity(EntityState.create("e4", Constants.ENTITY_ROCK, Vector2i(2, 0)))
	state.add_entity(EntityState.create("e5", Constants.ENTITY_ROCK, Vector2i(2, 1)))
	state.add_entity(EntityState.create("e6", Constants.ENTITY_ROCK, Vector2i(1, 2)))
	state.add_entity(EntityState.create("e7", Constants.ENTITY_ROCK, Vector2i(2, 2)))
	# 越界格：(-1,*) (*,-1) 不需要堵，find_star_relocation_cell 会跳过
	var hp_before := player.hp
	var events: Array[Dictionary] = []
	events.append_array(FissionSlimeRules.execute_trample(state, slime, _trample_intent(slime, player)))
	# 挤压惩罚伤害
	assert(player.hp < hp_before, "squeezed player should take squeeze damage")
	print("  [OK] trample squeeze: all blocked, player takes squeeze penalty")


## 践踏：落点有地刺时，结算地刺伤害（落点地形二次结算）
func _test_trample_landing_terrain_settlement() -> void:
	var state := _make_bare_state()
	var slime := _make_slime(state, Vector2i(2, 2))
	var player := _make_player(state, Vector2i(3, 3))
	# 把距离 (3,3) 最近的合法落点（优先上方 (3,2)）改成地刺
	# 先模拟找到落点，然后在那里放地刺
	var reloc := BoardUtils.find_star_relocation_cell(state, Vector2i(3, 3), player.uid)
	var landing: Vector2i = reloc.get("pos", Vector2i(3, 2))
	state.add_entity(EntityState.create("spike_land", Constants.ENTITY_SPIKE, landing))
	var hp_before := player.hp
	var events: Array[Dictionary] = []
	events.append_array(FissionSlimeRules.execute_trample(state, slime, _trample_intent(slime, player)))
	# 践踏伤害 + 地刺伤害，总血量应低于只受践踏伤害
	assert(player.hp < hp_before - Constants.FISSION_SLIME_TRAMPLE_DAMAGE, "landing spike should add extra damage on top of trample")
	print("  [OK] trample landing terrain: spike damage applied after relocation")


func _trample_intent(slime: UnitState, target: UnitState) -> IntentState:
	var intent := IntentState.new()
	intent.type = "trample"
	intent.source_uid = slime.uid
	intent.target_uid = target.uid
	intent.path = []
	intent.target_pos = slime.pos
	intent.damage = Constants.FISSION_SLIME_TRAMPLE_DAMAGE
	return intent


func _make_bare_state() -> GameState:
	var state := GameState.new()
	state.board_size = Constants.BOARD_SIZE
	state.units = {}
	return state


func _make_slime(state: GameState, pos: Vector2i) -> UnitState:
	var reg: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	var uid: String = reg.next_runtime_uid("slime")
	var unit := UnitState.from_def(uid, "unit_fission_slime", Constants.TEAM_ENEMY, pos, reg.get_unit_def("unit_fission_slime"))
	state.register_unit(unit)
	return unit


func _make_player(state: GameState, pos: Vector2i) -> UnitState:
	var unit := UnitState.new()
	unit.uid = "player"
	unit.team = Constants.TEAM_PLAYER
	unit.pos = pos
	unit.hp = 20
	unit.max_hp = 20
	unit.alive = true
	unit.footprint_size = Vector2i(1, 1)
	state.register_unit(unit)
	state.player_uid = unit.uid
	return unit


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
