extends SceneTree

const AttackPipeline = preload("res://scripts/rules/attack_pipeline.gd")
const CombatConfig = preload("res://scripts/core/combat_config.gd")
const ScenarioBuilder = preload("res://scripts/testkit/scenario_builder.gd")
const _GemTransfer = preload("res://scripts/rules/gem_transfer.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Chaos Launcher Test ===")
	var adventure_service: Node = root.get_node("AdventureService")
	var run_service: Node = root.get_node("RunService")
	adventure_service.start_new_run(20260614)
	adventure_service.pending_room_type = "NORMAL_COMBAT"
	_test_chaos_on_empty_aim_with_explosion()
	run_service.end_run()
	if _failed:
		push_error("CHAOS_LAUNCHER_TEST_FAIL")
		quit(1)
		return
	print("CHAOS_LAUNCHER_TEST_PASS")
	quit(0)


func _test_chaos_on_empty_aim_with_explosion() -> void:
	var state := _battle_state()
	var player := state.get_player()
	_mount_red_gem(state, player, Constants.GEM_EXPLOSION)
	_ensure_chaos_launcher_relic()
	var guard := _spawn_enemy(state, Vector2i(5, 5), "guard")
	state.move_unit(player, Vector2i(2, 5))
	var aim := Vector2i(4, 5)
	var result := AttackPipeline.execute_aimed(
		state,
		player,
		aim,
		[AttackPipeline.TAG_RANGED],
		{},
		CombatConfig.attack_range()
	)
	if not result.get("ok", false):
		_fail("aimed attack failed: %s" % result.get("reason", ""))
		return
	var has_chaos_proc := false
	for line in state.combat_log:
		if "[Relic] relic_chaos_launcher" in str(line):
			has_chaos_proc = true
			break
	if not has_chaos_proc:
		for ev in result.get("events", []):
			var t := str(ev.get("type", ""))
			if t == "poison_burst" or t == "fire_burst":
				has_chaos_proc = true
				break
	if not has_chaos_proc:
		_fail("chaos launcher should proc on empty-cell aimed attack")
		return
	if guard.hp >= guard.max_hp:
		_fail("cross explosion should still damage adjacent guard")
		return
	print("  [OK] chaos procs on empty aim; explosion still damages neighbor")


func _battle_state() -> GameState:
	var builder := ScenarioBuilder.new("template_a", 11, true)
	builder.clear_slots(builder.player())
	return builder.finish()


func _mount_red_gem(state: GameState, player: UnitState, gem_id: String) -> void:
	var reg: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	var slot := player.get_slot(Constants.SLOT_RED)
	if slot == null:
		_fail("player missing red slot")
		return
	var gem_uid: String = str(reg.call("_next_uid", "gem"))
	var gem := GemState.create(gem_uid, gem_id, {})
	state.gems[gem_uid] = gem
	assert(_GemTransfer.to_unit_slot(state, gem, player, slot))


func _ensure_chaos_launcher_relic() -> void:
	var run_svc: Node = Engine.get_main_loop().root.get_node_or_null("RunService")
	if run_svc == null:
		_fail("RunService missing")
		return
	var run: RunState = run_svc.get_run()
	if run == null:
		_fail("no active run for relic test")
		return
	if "relic_chaos_launcher" not in run.owned_relics:
		run.owned_relics.append("relic_chaos_launcher")


func _spawn_enemy(state: GameState, pos: Vector2i, suffix: String) -> UnitState:
	var unit := UnitState.new()
	unit.uid = "chaos_test_%s" % suffix
	unit.unit_def_id = "unit_patrol_guard"
	unit.team = Constants.TEAM_ENEMY
	unit.pos = pos
	unit.hp = 40
	unit.max_hp = 40
	unit.alive = true
	state.register_unit(unit)
	return unit


func _fail(msg: String) -> void:
	_failed = true
	push_error(msg)
