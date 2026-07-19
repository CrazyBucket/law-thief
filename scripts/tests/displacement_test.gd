extends SceneTree
## 位移系统回归测试（新规则版）
## 覆盖：碰撞伤公式 / 不链推 / 静态实体单/双伤 / 越界保底伤 / pull / dash / 多格单位边界


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Displacement Test ===")
	_test_knockback_basic()
	_test_knockback_wall_stop_with_formula_damage()
	_test_knockback_no_chain_push()
	_test_knockback_unit_collision_both_take_damage()
	_test_entity_no_hp_single_damage()
	_test_entity_with_hp_double_damage()
	_test_wall_minimum_one_damage()
	_test_pull_basic()
	_test_pull_blocked_by_unit()
	_test_pull_gravity_no_contact_hooks()
	_test_dash_toward_basic()
	_test_dash_toward_blocked()
	_test_overlay_settles_only_at_landing()
	_test_large_unit_knockback_wall()
	_test_large_unit_pull_boundary()
	_test_invariants_after_all_moves()
	_test_iron_boots_player_only_forced_move_immune()
	print("DISPLACEMENT_TEST_PASS")
	quit()


# ─── knockback 基础 ────────────────────────────────────────────────────────────

func _test_knockback_basic() -> void:
	var state := _make_state()
	var unit := _make_unit(state, "u", Constants.TEAM_ENEMY, Vector2i(3, 3))
	var origin := Vector2i(1, 3)
	var events: Array[Dictionary] = []
	Displacement.knockback(state, unit, origin, 2, "", events)
	assert(unit.pos == Vector2i(5, 3), "knockback 2 steps right: expected (5,3) got %s" % unit.pos)
	assert(events.size() == 2, "should emit 2 move_step events, got %d" % events.size())
	assert(BattleInvariantChecker.assert_valid(state, "knockback_basic"))
	print("  [OK] knockback basic")


func _test_knockback_wall_stop_with_formula_damage() -> void:
	# 单位从 x=4 向右被打 5 格，实际只能走 3 步（到 x=7 边界），碰撞伤 = max(1,3) = 3
	var state := _make_state()
	var unit := _make_unit(state, "u", Constants.TEAM_ENEMY, Vector2i(4, 3))
	var hp_before := unit.hp
	var events: Array[Dictionary] = []
	Displacement.knockback(state, unit, Vector2i(2, 3), 5, "", events)
	assert(unit.pos.x == 7, "should stop at right wall x=7, got x=%d" % unit.pos.x)
	var steps_taken := unit.pos.x - 4  # = 3
	var expected_dmg := maxi(1, steps_taken)
	assert(unit.hp == hp_before - expected_dmg, "wall collision dmg should be max(1,3)=%d, got hp=%d" % [expected_dmg, unit.hp])
	_assert_displacement_impact(events, unit.uid, Vector2i(8, 3), "boundary")
	print("  [OK] knockback wall: damage = max(1, actual_steps)")


func _test_knockback_no_chain_push() -> void:
	# 新规则：A 撞 B，立即截停，B 不移动（不再链推）
	var state := _make_state()
	var a := _make_unit(state, "a", Constants.TEAM_ENEMY, Vector2i(2, 3))
	var b := _make_unit(state, "b", Constants.TEAM_ENEMY, Vector2i(4, 3))
	var b_start := b.pos
	var events: Array[Dictionary] = []
	Displacement.knockback(state, a, Vector2i(0, 3), 3, "", events)
	assert(a.pos == Vector2i(3, 3), "a should stop one cell before b, got %s" % a.pos)
	assert(b.pos == b_start, "b must NOT move (no chain push), got %s" % b.pos)
	assert(BattleInvariantChecker.assert_valid(state, "no_chain_push"))
	print("  [OK] no chain push: A stops before B, B stays")


func _test_knockback_unit_collision_both_take_damage() -> void:
	# A 向右被打，走 1 步后碰到 B；实际步数 = 1，双方各受 max(1,1)=1 点伤
	var state := _make_state()
	var a := _make_unit(state, "a", Constants.TEAM_ENEMY, Vector2i(2, 3))
	var b := _make_unit(state, "b", Constants.TEAM_ENEMY, Vector2i(4, 3))
	var a_hp_before := a.hp
	var b_hp_before := b.hp
	var events: Array[Dictionary] = []
	Displacement.knockback(state, a, Vector2i(0, 3), 5, "", events)
	var actual_steps := a.pos.x - 2  # 从起点到停下时走了几格
	var expected_dmg := maxi(1, actual_steps)
	assert(a.hp == a_hp_before - expected_dmg, "A should take collision dmg=%d" % expected_dmg)
	assert(b.hp == b_hp_before - expected_dmg, "B should take same collision dmg=%d" % expected_dmg)
	_assert_damage_event_identity(events, a.uid, "unit_collision")
	_assert_damage_event_identity(events, b.uid, "unit_collision")
	print("  [OK] unit collision: A and B both take max(1, actual_steps) damage")


# ─── 静态实体碰撞 ──────────────────────────────────────────────────────────────

func _test_entity_no_hp_single_damage() -> void:
	# 无血量实体（石柱 max_hp == -1）：只有碰撞者受伤，实体不受伤
	var state := _make_state()
	var unit := _make_unit(state, "u", Constants.TEAM_ENEMY, Vector2i(2, 3))
	var rock := EntityState.create("rock0", Constants.ENTITY_ROCK, Vector2i(4, 3))
	state.add_entity(rock)
	var hp_before := unit.hp
	var events: Array[Dictionary] = []
	Displacement.knockback(state, unit, Vector2i(0, 3), 5, "", events)
	# 实际走了 1 步（2→3），伤害 = max(1,1) = 1
	assert(unit.pos == Vector2i(3, 3), "unit should stop before rock, got %s" % unit.pos)
	assert(unit.hp < hp_before, "unit should take collision damage")
	assert(rock.hp == -1, "indestructible rock hp should remain -1, got %d" % rock.hp)
	assert(rock.alive, "rock should still be alive")
	_assert_displacement_impact(events, unit.uid, rock.pos, "entity")
	print("  [OK] entity no-hp: only unit takes damage, rock unchanged")


func _test_entity_with_hp_double_damage() -> void:
	# 有血量实体（油桶 max_hp > 0）：碰撞者和油桶同伤
	var state := _make_state()
	var unit := _make_unit(state, "u", Constants.TEAM_ENEMY, Vector2i(2, 3))
	var barrel := EntityState.create("barrel0", Constants.ENTITY_BARREL, Vector2i(4, 3))
	state.add_entity(barrel)
	var unit_hp_before := unit.hp
	var barrel_hp_before := barrel.hp
	var events: Array[Dictionary] = []
	Displacement.knockback(state, unit, Vector2i(0, 3), 5, "", events)
	assert(unit.pos == Vector2i(3, 3), "unit should stop before barrel, got %s" % unit.pos)
	assert(unit.hp < unit_hp_before, "unit should take collision damage")
	assert(barrel.hp < barrel_hp_before, "barrel should take collision damage too")
	print("  [OK] entity with hp: both unit and barrel take damage")


func _test_wall_minimum_one_damage() -> void:
	# 单位紧贴墙壁被原地截停（0 步实际移动），碰撞伤 = max(1,0) = 1
	var state := _make_state()
	var unit := _make_unit(state, "u", Constants.TEAM_ENEMY, Vector2i(7, 3))
	var hp_before := unit.hp
	var events: Array[Dictionary] = []
	# 从 x=7 向右打，next=(8,3) 越界，实际步数 = 0，但保底 1 伤
	Displacement.knockback(state, unit, Vector2i(5, 3), 3, "", events)
	assert(unit.pos == Vector2i(7, 3), "unit should stay at wall, got %s" % unit.pos)
	assert(unit.hp == hp_before - 1, "should take minimum 1 collision damage even at 0 steps, hp=%d" % unit.hp)
	_assert_displacement_impact(events, unit.uid, Vector2i(8, 3), "boundary")
	print("  [OK] wall collision minimum 1 damage")


# ─── pull ─────────────────────────────────────────────────────────────────────

func _test_pull_basic() -> void:
	var state := _make_state()
	var anchor := Vector2i(5, 5)
	var unit := _make_unit(state, "u", Constants.TEAM_PLAYER, Vector2i(2, 5))
	var events: Array[Dictionary] = []
	Displacement.pull_toward(state, unit, anchor, 2, "", events, 0)
	assert(unit.pos == Vector2i(4, 5), "pull 2 steps toward (5,5): expected (4,5) got %s" % unit.pos)
	assert(BattleInvariantChecker.assert_valid(state, "pull_basic"))
	print("  [OK] pull basic")


func _test_pull_blocked_by_unit() -> void:
	# 新规则：pull 撞 blocker 立即停，B 不移动
	var state := _make_state()
	var anchor := Vector2i(5, 3)
	var unit := _make_unit(state, "u", Constants.TEAM_PLAYER, Vector2i(2, 3))
	var blocker := _make_unit(state, "blocker", Constants.TEAM_ENEMY, Vector2i(4, 3))
	var events: Array[Dictionary] = []
	Displacement.pull_toward(state, unit, anchor, 3, "", events)
	assert(unit.pos == Vector2i(3, 3), "should stop before blocker, got %s" % unit.pos)
	assert(unit.hp < unit.max_hp, "pull collision should damage mover")
	assert(blocker.hp < blocker.max_hp, "pull collision should damage blocker")
	assert(BattleInvariantChecker.assert_valid(state, "pull_blocked"))
	print("  [OK] pull blocked by unit (no chain push, both take damage)")


func _test_pull_gravity_no_contact_hooks() -> void:
	var state := _make_state()
	var anchor := Vector2i(5, 3)
	var unit := _make_unit(state, "u", Constants.TEAM_PLAYER, Vector2i(2, 3))
	var blocker := _make_unit(state, "blocker", Constants.TEAM_ENEMY, Vector2i(4, 3))
	var events := GemEffects.pull_unit_toward_with_events(state, unit, anchor, 3, blocker.uid)
	assert(unit.pos == Vector2i(3, 3), "gravity pull should stop before blocker, got %s" % unit.pos)
	assert(unit.hp < unit.max_hp, "gravity collision should damage mover")
	assert(blocker.hp < blocker.max_hp, "gravity collision should damage blocker")
	assert(BattleInvariantChecker.assert_valid(state, "gravity_pull"))
	print("  [OK] gravity pull (via GemEffects) collision damage + no contact hooks")


# ─── dash ─────────────────────────────────────────────────────────────────────

func _test_dash_toward_basic() -> void:
	var state := _make_state()
	var unit := _make_unit(state, "u", Constants.TEAM_PLAYER, Vector2i(1, 1))
	var target := Vector2i(5, 1)
	var events: Array[Dictionary] = []
	Displacement.dash_toward(state, unit, target, 3, unit.uid, events)
	assert(unit.pos == Vector2i(4, 1), "dash 3 steps toward (5,1): expected (4,1) got %s" % unit.pos)
	assert(BattleInvariantChecker.assert_valid(state, "dash_basic"))
	print("  [OK] dash_toward basic")


func _test_dash_toward_blocked() -> void:
	var state := _make_state()
	var unit := _make_unit(state, "u", Constants.TEAM_PLAYER, Vector2i(1, 4))
	_make_unit(state, "blocker", Constants.TEAM_ENEMY, Vector2i(4, 4))
	var target := Vector2i(6, 4)
	var events: Array[Dictionary] = []
	Displacement.dash_toward(state, unit, target, 5, unit.uid, events, 0)
	assert(unit.pos == Vector2i(3, 4), "dash should stop one step before blocker, got %s" % unit.pos)
	assert(unit.hp == unit.max_hp, "dash collision_damage=0 should not deal damage")
	_assert_displacement_impact(events, unit.uid, Vector2i(4, 4), "unit")
	assert(BattleInvariantChecker.assert_valid(state, "dash_blocked"))
	print("  [OK] dash_toward blocked (no collision damage)")


# ─── 地块覆盖层不重复 ─────────────────────────────────────────────────────────

func _test_overlay_settles_only_at_landing() -> void:
	var state := _make_state()
	var unit := _make_unit(state, "u", Constants.TEAM_ENEMY, Vector2i(2, 3))
	state.get_tile(Vector2i(3, 3)).add_modifier(Constants.TILE_MOD_POISON_FOG, 3)
	var events: Array[Dictionary] = []
	Displacement.knockback(state, unit, Vector2i(0, 3), 2, "", events, 0)
	assert(unit.pos == Vector2i(4, 3), "unit should land at (4,3): got %s" % unit.pos)
	var poison: StatusInstance = unit.get_status(Constants.STATUS_POISON)
	assert(poison == null, "an intermediate poison_fog cell must not apply landing status")
	assert(BattleInvariantChecker.assert_valid(state, "overlay_landing_only"))
	print("  [OK] overlay status settles only on the final footprint")


# ─── 多格单位 ─────────────────────────────────────────────────────────────────

func _test_large_unit_knockback_wall() -> void:
	var state := _make_state()
	var unit := _make_large_unit(state, "big", Constants.TEAM_ENEMY, Vector2i(5, 3), Vector2i(2, 1))
	var origin := Vector2i(3, 3)
	var events: Array[Dictionary] = []
	Displacement.knockback(state, unit, origin, 3, "", events)
	# 2x1 unit：锚在 6 时 footprint (6,3)(7,3) 恰好合法，锚在 7 时 (8,3) 越界
	assert(unit.pos.x <= 6, "2x1 unit should stop before going out of bounds: %s" % unit.pos)
	assert(BattleInvariantChecker.assert_valid(state, "large_knockback_wall"))
	print("  [OK] large unit knockback wall boundary")


func _test_large_unit_pull_boundary() -> void:
	var state := _make_state()
	var unit := _make_large_unit(state, "big2", Constants.TEAM_PLAYER, Vector2i(1, 1), Vector2i(2, 2))
	var anchor := Vector2i(7, 1)
	var events: Array[Dictionary] = []
	Displacement.pull_toward(state, unit, anchor, 10, "", events, 0)
	# 2x2：锚最多到 x=6（footprint (6,1)(7,1)(6,2)(7,2) 都在边界内）
	assert(unit.pos.x <= 6, "2x2 unit anchor should be at most x=6: %s" % unit.pos)
	assert(BattleInvariantChecker.assert_valid(state, "large_pull_boundary"))
	print("  [OK] large unit pull boundary")


# ─── 全局不变量 ────────────────────────────────────────────────────────────────

func _test_invariants_after_all_moves() -> void:
	var state := _make_state()
	var u1 := _make_unit(state, "u1", Constants.TEAM_PLAYER, Vector2i(0, 0))
	var u2 := _make_unit(state, "u2", Constants.TEAM_ENEMY, Vector2i(3, 3))
	var u3 := _make_unit(state, "u3", Constants.TEAM_ENEMY, Vector2i(6, 6))
	var ev: Array[Dictionary] = []
	Displacement.knockback(state, u1, Vector2i(0, 2), 1, "", ev, 0)
	Displacement.pull_toward(state, u2, Vector2i(0, 0), 2, "", ev, 0)
	Displacement.dash_toward(state, u3, Vector2i(3, 3), 2, u3.uid, ev)
	GemEffects.pull_unit_toward_with_events(state, u2, u1.pos, 1, u1.uid)
	assert(BattleInvariantChecker.assert_valid(state, "multi_move_invariants"))
	print("  [OK] invariants valid after multiple displacement operations")


# ─── 辅助 ─────────────────────────────────────────────────────────────────────

func _test_iron_boots_player_only_forced_move_immune() -> void:
	var state := _make_state()
	var player := _make_unit(state, "player", Constants.TEAM_PLAYER, Vector2i(2, 3))
	state.player_uid = player.uid
	var enemy := _make_unit(state, "enemy", Constants.TEAM_ENEMY, Vector2i(2, 5))
	var adventure_svc: Node = Engine.get_main_loop().root.get_node("AdventureService")
	adventure_svc.start_new_run(20260711)
	var run_svc: Node = Engine.get_main_loop().root.get_node("RunService")
	var run: RunState = run_svc.get_run()
	assert(run != null, "iron boots test requires an active run")
	run.owned_relics = ["relic_iron_boots"]
	var player_events: Array[Dictionary] = []
	Displacement.knockback(state, player, Vector2i(0, 3), 2, "", player_events)
	assert(player.pos == Vector2i(2, 3), "player with iron boots should ignore knockback")
	assert(player_events.is_empty(), "immune knockback should emit no move_step")
	var enemy_start := enemy.pos
	var enemy_events: Array[Dictionary] = []
	Displacement.knockback(state, enemy, Vector2i(0, 5), 2, "", enemy_events)
	assert(enemy.pos == Vector2i(4, 5), "enemy should still be knocked back, got %s" % enemy.pos)
	assert(enemy.pos != enemy_start, "enemy should move under knockback")
	assert(enemy_events.size() == 2, "enemy knockback should emit 2 move_step events")
	print("  [OK] iron boots forced move immune (player only)")


func _make_state() -> GameState:
	var state := GameState.new()
	state.board_size = Constants.BOARD_SIZE
	state.units = {}
	return state


func _make_unit(state: GameState, uid: String, team: String, pos: Vector2i) -> UnitState:
	var unit := UnitState.new()
	unit.uid = uid
	unit.team = team
	unit.pos = pos
	unit.hp = 10
	unit.max_hp = 10
	unit.alive = true
	unit.footprint_size = Vector2i(1, 1)
	state.register_unit(unit)
	return unit


func _make_large_unit(state: GameState, uid: String, team: String, pos: Vector2i, fp: Vector2i) -> UnitState:
	var unit := _make_unit(state, uid, team, pos)
	state._remove_unit_from_occupancy(unit)
	unit.footprint_size = fp
	state._add_unit_to_occupancy(unit)
	return unit


func _assert_damage_event_identity(events: Array, uid: String, reason: String) -> void:
	for ev in events:
		if str(ev.get("type", "")) != "damage":
			continue
		if str(ev.get("uid", "")) != uid:
			continue
		assert(str(ev.get("victim_uid", "")) == uid, "damage event should mirror victim_uid for %s" % uid)
		assert(str(ev.get("reason", "")) == reason, "damage event reason should be %s" % reason)
		assert(ev.has("remaining_hp"), "damage event should include remaining_hp")
		assert(ev.has("lethal"), "damage event should include lethal")
		return
	assert(false, "missing damage event for %s reason=%s events=%s" % [uid, reason, str(events)])


func _assert_displacement_impact(
	events: Array,
	uid: String,
	contact: Vector2i,
	blocker_kind: String
) -> void:
	for ev in events:
		if str(ev.get("type", "")) != "displacement_impact":
			continue
		if str(ev.get("uid", "")) != uid:
			continue
		assert(ev.get("contact", Vector2i.ZERO) == contact)
		assert(str(ev.get("blocker_kind", "")) == blocker_kind)
		assert(EventValidator.validate_events([ev]).is_empty())
		return
	assert(false, "missing displacement impact uid=%s contact=%s events=%s" % [uid, contact, str(events)])
