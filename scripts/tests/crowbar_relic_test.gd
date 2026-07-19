extends SceneTree

const ShieldRules = preload("res://scripts/rules/shield_rules.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Crowbar Relic Test ===")
	var adventure_service: Node = root.get_node("AdventureService")
	var run_service: Node = root.get_node("RunService")
	adventure_service.start_new_run(20260719)
	adventure_service.pending_room_type = "NORMAL_COMBAT"
	_test_crowbar_breaks_armor_without_hp_damage()
	run_service.end_run()
	if _failed:
		push_error("CROWBAR_RELIC_TEST_FAIL")
		quit(1)
		return
	print("CROWBAR_RELIC_TEST_PASS")
	quit(0)


func _test_crowbar_breaks_armor_without_hp_damage() -> void:
	var run: RunState = root.get_node("RunService").get_run()
	if run == null:
		_fail("active run missing for crowbar test")
		return
	run.owned_relics.clear()
	run.owned_relics.append("relic_crowbar")

	var state := GameState.new()
	state.run_seed = 4404
	var player := _make_unit("player", Constants.TEAM_PLAYER, Vector2i(1, 1), 1, 20)
	var target := _make_unit("crowbar_target", Constants.TEAM_ENEMY, Vector2i(4, 1), 1, 20)
	var armor_lock := SlotState.create(Constants.SLOT_RED, "", true, Constants.LOCK_ARMOR)
	target.slots.append(armor_lock)
	state.player_uid = player.uid
	state.register_unit(player)
	state.register_unit(target)
	state.rebuild_occupancy()
	StatusRules.apply_shield(state, target, 10, 0, target.uid)
	var break_bonus := int(root.get_node("RelicEffectRegistry").query_modifier("armor_break_bonus", state))
	var removed := ShieldRules.damage(state, target, break_bonus)
	_expect(break_bonus == 4, "crowbar modifier should resolve to four armor damage")
	_expect(removed == 4, "crowbar should remove four armor")
	_expect(target.hp == 20, "crowbar should not deal extra hp damage")
	_expect(StatusRules.get_shield(target) == 6, "four crowbar damage should leave six armor")
	_expect(armor_lock.locked, "crowbar should not unlock armor-locked slots")
	_expect(BattleInvariantChecker.check_all(state).is_empty(), "crowbar should preserve battle invariants")
	print("  [OK] crowbar breaks armor without hp damage or unlocking slots")


func _make_unit(uid: String, team: String, pos: Vector2i, base_attack: int, hp: int) -> UnitState:
	var unit := UnitState.new()
	unit.uid = uid
	unit.team = team
	unit.pos = pos
	unit.base_attack = base_attack
	unit.hp = hp
	unit.max_hp = hp
	unit.alive = true
	return unit


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
