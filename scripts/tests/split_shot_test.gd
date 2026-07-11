extends SceneTree

const SplitShotRules = preload("res://scripts/rules/split_shot_rules.gd")
const AttackPipeline = preload("res://scripts/rules/attack_pipeline.gd")
const CombatConfig = preload("res://scripts/core/combat_config.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== Split Shot Test ===")
	_test_same_cell_no_wings()
	_test_forward_dir8()
	_test_standard_right()
	_test_diagonal_45()
	_test_irregular_angle()
	_test_edge_clip()
	_test_corner_aim()
	_test_spawn_shoot_water_3_3()
	_test_preview_matches_resolve_shot()
	_test_aim_empty_cell_hits_wings()
	_test_wing_damage_ignores_front_obstacle()
	_test_main_target_ignores_front_obstacle()
	_test_red_split_level_two_four_shots()
	_test_red_split_level_three_five_shots()
	_test_never_hit_self()
	if _failed:
		push_error("SPLIT_SHOT_TEST_FAIL")
		quit(1)
		return
	print("SPLIT_SHOT_TEST_PASS")
	quit(0)


func _assert_shot(origin: Vector2i, aim: Vector2i, expected_forward: Vector2i, expected_wings: Array) -> void:
	var forward := SplitShotRules.compute_forward_step(origin, aim)
	if forward != expected_forward:
		_fail("forward %s != expected %s (origin=%s aim=%s)" % [forward, expected_forward, origin, aim])
		return
	var shot: Dictionary = SplitShotRules.compute_shot(origin, aim)
	if shot.main != aim:
		_fail("main %s != aim %s" % [shot.main, aim])
		return
	var wings: Array = shot.wings
	if wings.size() != expected_wings.size():
		_fail("wings %s != expected %s" % [wings, expected_wings])
		return
	for wing in expected_wings:
		if not wing in wings:
			_fail("missing wing %s in %s" % [wing, wings])
			return
	var cells := SplitShotRules.all_hit_cells(origin, aim)
	for cell in [aim] + expected_wings:
		if not cell in cells:
			_fail("all_hit_cells missing %s (got %s)" % [cell, cells])
			return


func _test_same_cell_no_wings() -> void:
	assert(SplitShotRules.wing_cells(Vector2i(2, 2), Vector2i(2, 2)).is_empty())
	print("  [OK] same cell -> no wings")


func _test_forward_dir8() -> void:
	assert(SplitShotRules.forward_step(Vector2i(0, 0), Vector2i(3, 0)) == Vector2i(1, 0))
	assert(SplitShotRules.forward_step(Vector2i(0, 0), Vector2i(1, 1)) == Vector2i(1, 1))
	print("  [OK] DIR8 forward")


func _test_standard_right() -> void:
	_assert_shot(Vector2i(2, 3), Vector2i(4, 3), Vector2i(1, 0), [Vector2i(3, 4), Vector2i(3, 2)])
	print("  [OK] standard right attack")


func _test_diagonal_45() -> void:
	_assert_shot(Vector2i(2, 2), Vector2i(4, 4), Vector2i(1, 1), [Vector2i(3, 4), Vector2i(4, 3)])
	print("  [OK] 45deg diagonal attack")


func _test_irregular_angle() -> void:
	_assert_shot(Vector2i(1, 1), Vector2i(4, 2), Vector2i(1, 0), [Vector2i(3, 3), Vector2i(3, 1)])
	print("  [OK] irregular angle snap")


func _test_edge_clip() -> void:
	_assert_shot(Vector2i(7, 1), Vector2i(7, 3), Vector2i(0, 1), [Vector2i(6, 2)])
	print("  [OK] edge wing clipped")


func _test_corner_aim() -> void:
	_assert_shot(Vector2i(5, 6), Vector2i(7, 7), Vector2i(1, 1), [Vector2i(6, 7), Vector2i(7, 6)])
	print("  [OK] corner aim")


func _test_spawn_shoot_water_3_3() -> void:
	_assert_shot(Vector2i(0, 2), Vector2i(3, 3), Vector2i(1, 0), [Vector2i(2, 4), Vector2i(2, 2)])
	print("  [OK] spawn (0,2) -> aim (3,3)")


func _test_preview_matches_resolve_shot() -> void:
	var state := _create_test_state()
	var player := state.get_player()
	_mount_split_red(state, player)
	player.pos = Vector2i(1, 2)
	var aim := Vector2i(3, 3)
	if not BoardUtils.can_unit_attack_cell(player, state, aim, CombatConfig.attack_range()):
		_fail("test setup: aim out of attack range")
		return
	var expected: Array = SplitShotRules.resolve_shot(player, aim).cells
	var preview: Array = _preview_split_cells(state, player, aim)
	if expected.size() != preview.size():
		_fail("preview size %d != %d" % [preview.size(), expected.size()])
		return
	for cell in expected:
		if not cell in preview:
			_fail("preview missing %s (got %s)" % [cell, preview])
			return
	print("  [OK] preview == resolve_shot")


func _fail(msg: String) -> void:
	_failed = true
	push_error(msg)


func _create_test_state() -> GameState:
	var reg: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	return reg.create_battle_state("fission_slime_test", 42)


func _preview_split_cells(state: GameState, player: UnitState, target_pos: Vector2i) -> Array:
	if target_pos == player.pos:
		return []
	if not BoardUtils.can_unit_attack_cell(player, state, target_pos, CombatConfig.attack_range()):
		return []
	var shot := SplitShotRules.resolve_shot(player, target_pos)
	var cells: Array = []
	for cell in shot.cells:
		if BoardUtils.in_bounds(state, cell) and not cell in cells:
			cells.append(cell)
	return cells


func _test_never_hit_self() -> void:
	var origin := Vector2i(3, 6)
	var aim := Vector2i(3, 7)
	var forbidden: Array = [origin]
	for cell in SplitShotRules.all_hit_cells(origin, aim, forbidden):
		if SplitShotRules.is_blocked_cell(cell, origin, forbidden):
			_fail("hit cell %s must not be attacker footprint" % cell)
			return
	var player_origin := Vector2i(2, 6)
	var cells := SplitShotRules.all_hit_cells(player_origin, aim, [player_origin])
	if player_origin in cells:
		_fail("wing must not land on origin %s, got %s" % [player_origin, cells])
		return
	print("  [OK] never hit self")


func _test_aim_empty_cell_hits_wings() -> void:
	var state := _create_test_state()
	var player := state.get_player()
	_mount_split_red(state, player)
	player.pos = Vector2i(0, 2)
	var aim := Vector2i(2, 3)
	if state.get_unit_at(aim) != null:
		_fail("aim cell should be empty")
		return
	var guard := _spawn_guard(state, Vector2i(1, 3))
	var hp_before := guard.hp
	var result := AttackPipeline.execute_aimed(
		state, player, aim, [AttackPipeline.TAG_RANGED, AttackPipeline.TAG_SPLIT_SHOT], {}, CombatConfig.attack_range()
	)
	if not result.get("ok", false):
		_fail("split aim on empty should succeed")
		return
	if guard.hp >= hp_before:
		_fail("wing unit should take damage (%d -> %d)" % [hp_before, guard.hp])
		return
	print("  [OK] split aim empty cell damages wings")


func _test_wing_damage_ignores_front_obstacle() -> void:
	var state := _create_test_state()
	var player := state.get_player()
	_mount_split_red(state, player)
	player.pos = Vector2i(0, 2)
	var prop := EntityState.create("block_prop", Constants.ENTITY_PROP, Vector2i(1, 2))
	state.add_entity(prop)
	var aim := Vector2i(2, 3)
	var guard := _spawn_guard(state, Vector2i(1, 3))
	var hp_before := guard.hp
	var result := AttackPipeline.execute_aimed(
		state, player, aim, [AttackPipeline.TAG_RANGED, AttackPipeline.TAG_SPLIT_SHOT], {}, CombatConfig.attack_range()
	)
	if not result.get("ok", false):
		_fail("split with front obstacle should succeed")
		return
	if guard.hp >= hp_before:
		_fail("wing should take damage despite obstacle in front (%d -> %d)" % [hp_before, guard.hp])
		return
	print("  [OK] wing damage ignores front obstacle")


func _test_main_target_ignores_front_obstacle() -> void:
	var state := _create_test_state()
	var player := state.get_player()
	_mount_split_red(state, player)
	player.pos = Vector2i(0, 2)
	var prop := EntityState.create("block_prop", Constants.ENTITY_PROP, Vector2i(2, 2))
	state.add_entity(prop)
	var guard := _spawn_guard(state, Vector2i(3, 2))
	var hp_before := guard.hp
	var result := AttackPipeline.execute_aimed(
		state, player, guard.pos, [AttackPipeline.TAG_RANGED, AttackPipeline.TAG_SPLIT_SHOT], {}, CombatConfig.attack_range()
	)
	if not result.get("ok", false):
		_fail("split main target through obstacle should succeed")
		return
	if guard.hp >= hp_before:
		_fail("main target should take damage through obstacle (%d -> %d)" % [hp_before, guard.hp])
		return
	print("  [OK] split main target ignores front obstacle")


func _test_red_split_level_two_four_shots() -> void:
	var state := _create_test_state()
	var player := state.get_player()
	player.pos = Vector2i(2, 3)
	player.base_attack = 10
	_mount_split_red_level(state, player, 2)
	var targets := [
		_spawn_guard(state, Vector2i(4, 3)),
		_spawn_guard(state, Vector2i(3, 4)),
		_spawn_guard(state, Vector2i(3, 2)),
		_spawn_guard(state, Vector2i(3, 3)),
	]
	var result := AttackPipeline.execute_aimed(state, player, Vector2i(4, 3), [AttackPipeline.TAG_RANGED], {}, CombatConfig.attack_range())
	if not result.get("ok", false):
		_fail("level 2 split attack should succeed")
		return
	var events: Array = result.get("events", [])
	if events.size() < 4:
		_fail("level 2 split should emit four projectile visuals")
		return
	for i in range(4):
		if str(events[i].get("type", "")) != "projectile":
			_fail("all split projectile visuals must be contiguous before impact events")
			return
	for target in targets:
		if target.hp != target.max_hp - 5:
			_fail("level 2 split target %s should take 5, hp=%d" % [target.uid, target.hp])
			return
	print("  [OK] red split level 2 fires four 50%% shots")


func _test_red_split_level_three_five_shots() -> void:
	var state := _create_test_state()
	var player := state.get_player()
	player.pos = Vector2i(2, 3)
	player.base_attack = 10
	_mount_split_red_level(state, player, 3)
	var targets := [
		_spawn_guard(state, Vector2i(4, 3)),
		_spawn_guard(state, Vector2i(3, 4)),
		_spawn_guard(state, Vector2i(3, 2)),
		_spawn_guard(state, Vector2i(3, 3)),
		_spawn_guard(state, Vector2i(5, 3)),
	]
	var result := AttackPipeline.execute_aimed(state, player, Vector2i(4, 3), [AttackPipeline.TAG_RANGED], {}, CombatConfig.attack_range())
	if not result.get("ok", false):
		_fail("level 3 split attack should succeed")
		return
	for target in targets:
		if target.hp != target.max_hp - 3:
			_fail("level 3 split target %s should take 3, hp=%d" % [target.uid, target.hp])
			return
	print("  [OK] red split level 3 fires five 30%% shots")


func _spawn_guard(state: GameState, pos: Vector2i) -> UnitState:
	var guard := UnitState.new()
	guard.uid = "test_guard_%d_%d" % [pos.x, pos.y]
	guard.unit_def_id = "unit_patrol_guard"
	guard.team = Constants.TEAM_ENEMY
	guard.pos = pos
	guard.hp = 20
	guard.max_hp = 20
	guard.speed = 5
	guard.base_attack = 4
	guard.alive = true
	state.register_unit(guard)
	return guard


func _mount_split_red(state: GameState, player: UnitState) -> void:
	_mount_split_red_level(state, player, 1)


func _mount_split_red_level(state: GameState, player: UnitState, level: int) -> void:
	var reg: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	while player.slots_accepting(Constants.SLOT_RED).size() < level:
		player.slots.append(SlotState.create(Constants.SLOT_RED))
	var red_slots := player.slots_accepting(Constants.SLOT_RED)
	for i in range(level):
		var slot: SlotState = red_slots[i]
		var gem_uid: String = str(reg.call("_next_uid", "gem"))
		var gem := GemState.create(gem_uid, Constants.GEM_SPLIT, {})
		gem.owner_uid = player.uid
		state.gems[gem_uid] = gem
		slot.gem_uid = gem_uid
