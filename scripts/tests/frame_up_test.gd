extends SceneTree

const GemRules = preload("res://scripts/rules/gem_rules.gd")
const ScenarioBuilder = preload("res://scripts/testkit/scenario_builder.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Frame Up Relic Test ===")
	var adventure_service: Node = root.get_node("AdventureService")
	var run_service: Node = root.get_node("RunService")
	adventure_service.start_new_run(20260620)
	adventure_service.pending_room_type = "NORMAL_COMBAT"
	_test_enemy_to_enemy_insert_applies_weak_and_reduces_attack()
	_test_player_to_enemy_insert_does_not_apply_weak()
	run_service.end_run()
	if _failed:
		push_error("FRAME_UP_TEST_FAIL")
		quit(1)
		return
	print("FRAME_UP_TEST_PASS")
	quit(0)


func _test_enemy_to_enemy_insert_applies_weak_and_reduces_attack() -> void:
	var state := _build_state()
	var player := state.get_player()
	var source_enemy := _add_enemy(state, "frame_up_source", Vector2i(3, 2), Constants.GEM_FIRE)
	var target_enemy := _add_enemy(state, "frame_up_target", Vector2i(4, 2), "")
	target_enemy.base_attack = 8
	_force_relic("relic_frame_up")
	var extract_slot := source_enemy.get_slot(Constants.SLOT_RED)
	var insert_slot := target_enemy.get_slot(Constants.SLOT_RED)
	var extract_result := GemRules.extract(state, player, source_enemy, extract_slot)
	if not extract_result.get("ok", false):
		_fail("enemy extract failed: %s" % extract_result.get("reason", ""))
		return
	var insert_result := GemRules.insert(state, player, target_enemy, insert_slot)
	if not insert_result.get("ok", false):
		_fail("enemy insert failed: %s" % insert_result.get("reason", ""))
		return
	if not StatusRules.is_weak(target_enemy):
		_fail("frame up should apply weak when moving enemy gem to another enemy")
		return
	var reduced_attack := CombatRules.attack_damage(state, target_enemy)
	if reduced_attack != 6:
		_fail("weak should reduce normal attack from 8 to 6, got %d" % reduced_attack)
		return
	print("  [OK] enemy -> enemy insert applies weak and reduces attack to 75%")


func _test_player_to_enemy_insert_does_not_apply_weak() -> void:
	var state := _build_state()
	var player := state.get_player()
	var target_enemy := _add_enemy(state, "frame_up_target_player_source", Vector2i(4, 2), "")
	_force_relic("relic_frame_up")
	var extract_slot := player.get_slot(Constants.SLOT_RED)
	var insert_slot := target_enemy.get_slot(Constants.SLOT_RED)
	var extract_result := GemRules.extract(state, player, player, extract_slot)
	if not extract_result.get("ok", false):
		_fail("player self extract failed: %s" % extract_result.get("reason", ""))
		return
	var insert_result := GemRules.insert(state, player, target_enemy, insert_slot)
	if not insert_result.get("ok", false):
		_fail("player to enemy insert failed: %s" % insert_result.get("reason", ""))
		return
	if StatusRules.is_weak(target_enemy):
		_fail("frame up should not apply weak when source gem came from player")
		return
	print("  [OK] player -> enemy insert does not apply weak")


func _build_state() -> GameState:
	var builder := ScenarioBuilder.new("template_a", 1, true)
	var state := builder.finish()
	var player := state.get_player()
	builder.move(player, Vector2i(2, 2))
	builder.clear_slots(player)
	builder.mount_gems(player, Constants.SLOT_RED, [Constants.GEM_POISON])
	state = builder.finish()
	return state


func _add_enemy(state: GameState, uid: String, pos: Vector2i, red_gem_id: String) -> UnitState:
	var builder := ScenarioBuilder.new()
	builder.state = state
	var enemy := builder.add_unit(uid, "unit_patrol_guard", Constants.TEAM_ENEMY, pos)
	builder.clear_slots(enemy)
	if not red_gem_id.is_empty():
		builder.mount_gems(enemy, Constants.SLOT_RED, [red_gem_id])
	state.rebuild_occupancy()
	return enemy


func _force_relic(relic_id: String) -> void:
	var run_service: Node = root.get_node("RunService")
	var run: RunState = run_service.get_run()
	if run == null:
		_fail("no active run for relic test")
		return
	run.owned_relics.clear()
	run.owned_relics.append(relic_id)


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
