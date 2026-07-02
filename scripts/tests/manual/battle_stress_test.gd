extends SceneTree
## 随机压力测试入口
## 用固定 seed 驱动多回合随机动作序列，每步后校验系统级不变量。
## 发现任何不变量违规时立刻打印上下文并以非 0 退出码终止，方便 CI 拦截。


# ─── 配置 ─────────────────────────────────────────────────────────────────────

const DEFAULT_ROUNDS := 30       # 每局最多执行回合数
const DEFAULT_SEED   := 99991    # 默认 seed，可通过命令行 --seed=<N> 覆盖
const DEFAULT_SEEDS  := [99991, 20260611, 20260616]
const DEFAULT_ENCOUNTERS := [
	"tutorial_001",
	"template_a",
	"template_c",
	"bomb_rat_test",
	"stone_bow_test",
]


# ─── 入口 ─────────────────────────────────────────────────────────────────────

func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== Battle Stress Test ===")

	var run_seed: int = DEFAULT_SEED
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--seed="):
			var raw := arg.trim_prefix("--seed=")
			if raw.is_valid_int():
				run_seed = int(raw)

	var seed_set := [run_seed]
	if run_seed == DEFAULT_SEED:
		seed_set.clear()
		for seed_value in DEFAULT_SEEDS:
			seed_set.append(seed_value)

	var failures := 0
	for encounter_id in DEFAULT_ENCOUNTERS:
		for seed_value in seed_set:
			var ok := _run_encounter_stress(encounter_id, seed_value)
			if not ok:
				failures += 1

	if failures == 0:
		print("STRESS_TEST_PASS")
		quit(0)
	else:
		print("STRESS_TEST_FAIL (%d encounter(s) failed)" % failures)
		quit(1)


# ─── 单局压力测试 ─────────────────────────────────────────────────────────────

func _run_encounter_stress(encounter_id: String, base_seed: int) -> bool:
	print("--- Stress: %s (seed=%d) ---" % [encounter_id, base_seed])
	var controller := BattleController.new()
	controller.start_encounter(encounter_id, base_seed)
	var state := controller.state

	if state == null:
		push_error("[Stress] failed to load encounter: %s" % encounter_id)
		return false

	# 初始状态校验
	if not _invariant_check(state, encounter_id, "initial"):
		return false

	var rng := RandomNumberGenerator.new()
	rng.seed = base_seed

	var round_index := 0
	while round_index < DEFAULT_ROUNDS:
		if state.phase == Constants.PHASE_ENDED:
			break

		if state.phase == Constants.PHASE_PLAYER:
			var done := _do_player_turn(controller, state, rng, encounter_id, round_index)
			if not done:
				return false
		elif state.phase == Constants.PHASE_ENEMY:
			var done := _do_enemy_turn(controller, state, encounter_id, round_index)
			if not done:
				return false
		else:
			break

		round_index += 1

	print("  [OK] %s completed %d round(s), phase=%s" % [encounter_id, round_index, state.phase])
	return true


# ─── 玩家回合 ─────────────────────────────────────────────────────────────────

func _do_player_turn(
	controller: BattleController,
	state: GameState,
	rng: RandomNumberGenerator,
	encounter_id: String,
	round_index: int
) -> bool:
	# 随机尝试移动
	if not state.player_moved:
		var player := state.get_player()
		if player != null and player.alive:
			var reachable := BoardUtils.reachable_cells(state, player.pos, player.move_points)
			if not reachable.is_empty():
				var target_pos: Vector2i = reachable[rng.randi() % reachable.size()]
				controller.select_action(Constants.ACTION_MOVE)
				controller.try_move(target_pos)
				if not _invariant_check(state, encounter_id, "round%d:player_move" % round_index):
					return false

	if not _try_random_slot_action(controller, state, encounter_id, round_index, Constants.ACTION_EXTRACT):
		return false
	if not _try_random_slot_action(controller, state, encounter_id, round_index, Constants.ACTION_INSERT):
		return false

	# 随机尝试攻击（如果有敌人相邻或在射程内）
	if not state.player_acted:
		var player := state.get_player()
		var enemies := state.get_alive_enemies()
		if player != null and player.alive and not enemies.is_empty():
			var target_enemy: UnitState = enemies[rng.randi() % enemies.size()]
			controller.select_action(Constants.ACTION_ATTACK)
			controller.try_attack(target_enemy.uid)
			if not _invariant_check(state, encounter_id, "round%d:player_attack" % round_index):
				return false

	# 结束玩家回合
	controller.select_action(Constants.ACTION_END_TURN)
	controller.begin_enemy_phase()
	if not _invariant_check(state, encounter_id, "round%d:end_player_turn" % round_index):
		return false

	return true


func _try_random_slot_action(
	controller: BattleController,
	state: GameState,
	encounter_id: String,
	round_index: int,
	action: String
) -> bool:
	if not controller.can_use_action(action):
		return true
	controller.select_action(action)
	for unit in state.units.values():
		if not unit is UnitState:
			continue
		for slot_index in range(unit.slots.size()):
			var check := controller.check_slot_action(unit.uid, slot_index)
			if not bool(check.get("ok", false)):
				continue
			var result := controller.try_extract(unit.uid, slot_index) if action == Constants.ACTION_EXTRACT else controller.try_insert(unit.uid, slot_index)
			if not bool(result.get("ok", false)):
				continue
			if not _invariant_check(state, encounter_id, "round%d:%s" % [round_index, action]):
				return false
			return true
	return true


# ─── 敌方回合 ─────────────────────────────────────────────────────────────────

func _do_enemy_turn(
	controller: BattleController,
	state: GameState,
	encounter_id: String,
	round_index: int
) -> bool:
	for enemy in controller.get_sorted_enemies():
		if not enemy.alive:
			continue
		controller.execute_single_enemy(enemy)
		if not _invariant_check(state, encounter_id, "round%d:enemy_%s" % [round_index, enemy.uid]):
			return false

	controller.finish_enemy_phase()
	if not _invariant_check(state, encounter_id, "round%d:finish_enemy" % round_index):
		return false

	return true


# ─── 不变量校验封装 ───────────────────────────────────────────────────────────

func _invariant_check(state: GameState, encounter_id: String, step: String) -> bool:
	var violations := BattleInvariantChecker.check_all(state)
	if violations.is_empty():
		return true
	push_error("[Stress:%s] invariant violation at step '%s':" % [encounter_id, step])
	for v in violations:
		push_error("  - %s" % v)
	_print_state_context(state)
	return false


func _print_state_context(state: GameState) -> void:
	print("[Stress] state context:")
	print("  phase=%s  turn=%d  result=%s" % [state.phase, state.turn_index, state.result])
	for uid in state.units:
		var u: UnitState = state.units[uid]
		print("  unit %s (%s) alive=%s pos=%s hp=%d/%d fp=%s" % [
			u.uid, u.unit_def_id, u.alive, u.pos, u.hp, u.max_hp, u.footprint_size
		])
