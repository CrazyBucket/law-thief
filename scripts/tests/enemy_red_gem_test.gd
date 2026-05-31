extends SceneTree
## 敌人红槽宝石：射程、AI 接入、伤害事件


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Enemy Red Gem Test ===")
	_test_arc_requires_adjacent_for_ai()
	_test_arc_execute_rejects_ranged()
	_test_fire_gem_ai_and_execute()
	_test_ice_gem_ai_and_execute()
	_test_enemy_red_damage_includes_attacker_uid()
	_test_pull_execute_respects_range()
	_test_custom_intent_keeps_move_events()
	print("ENEMY_RED_GEM_TEST_PASS")
	quit()


func _test_arc_requires_adjacent_for_ai() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("template_c", 42)
	var state := ctrl.state
	var guard := _find_guard(state)
	assert(guard != null, "guard should exist")
	_embed_red_gem(state, guard, Constants.GEM_CONDUCTIVE)
	var player := state.get_player()
	var far_pos := guard.pos + Vector2i(3, 0)
	while not BoardUtils.in_bounds(state, far_pos):
		far_pos += Vector2i(1, 0)
	player.pos = far_pos
	state.rebuild_occupancy()
	IntentSystem.refresh_unit_intent(state, guard)
	assert(guard.intent.type != "arc_attack", "arc should not fire at range, got %s" % guard.intent.type)
	print("  [OK] arc AI requires adjacent")


func _test_arc_execute_rejects_ranged() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("template_c", 42)
	var state := ctrl.state
	var guard := _find_guard(state)
	var player := state.get_player()
	_embed_red_gem(state, guard, Constants.GEM_CONDUCTIVE)
	player.pos = guard.pos + Vector2i(2, 0)
	state.rebuild_occupancy()
	guard.intent = IntentState.new()
	guard.intent.type = "arc_attack"
	guard.intent.target_uid = player.uid
	guard.intent.path = []
	var events := IntentSystem.execute_intent(state, guard)
	assert(events.is_empty(), "arc execute should fail out of melee range")
	print("  [OK] arc execute rejects ranged target")


func _test_fire_gem_ai_and_execute() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("template_c", 42)
	var state := ctrl.state
	var guard := _find_guard(state)
	var player := state.get_player()
	_embed_red_gem(state, guard, Constants.GEM_FIRE)
	IntentSystem.refresh_unit_intent(state, guard)
	assert(guard.intent.type == "fire_attack", "fire gem should produce fire_attack intent")
	var hp_before := player.hp
	var events := IntentSystem.execute_intent(state, guard)
	assert(not events.is_empty(), "fire attack should produce events")
	assert(player.hp < hp_before, "fire attack should deal damage")
	assert(player.has_status(Constants.STATUS_BURNING), "fire attack should apply burning")
	var dmg_ev: Dictionary = events[0]
	assert(dmg_ev.get("attacker_uid", "") == guard.uid, "fire damage should include attacker_uid")
	print("  [OK] fire gem AI + execute")


func _test_ice_gem_ai_and_execute() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("template_c", 42)
	var state := ctrl.state
	var guard := _find_guard(state)
	var player := state.get_player()
	_embed_red_gem(state, guard, Constants.GEM_ICE)
	IntentSystem.refresh_unit_intent(state, guard)
	assert(guard.intent.type == "ice_attack", "ice gem should produce ice_attack intent")
	var hp_before := player.hp
	var events := IntentSystem.execute_intent(state, guard)
	assert(not events.is_empty(), "ice attack should produce events")
	assert(player.hp < hp_before, "ice attack should deal damage")
	var dmg_ev: Dictionary = events[0]
	assert(dmg_ev.get("attacker_uid", "") == guard.uid, "ice damage should include attacker_uid")
	print("  [OK] ice gem AI + execute")


func _test_enemy_red_damage_includes_attacker_uid() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("template_c", 42)
	var state := ctrl.state
	var guard := _find_guard(state)
	var player := state.get_player()
	_embed_red_gem(state, guard, Constants.GEM_POISON)
	guard.intent = IntentState.new()
	guard.intent.type = "poison_attack"
	guard.intent.target_uid = player.uid
	var events := IntentSystem.execute_intent(state, guard)
	assert(not events.is_empty(), "poison attack should produce events")
	assert(events[0].get("attacker_uid", "") == guard.uid, "poison damage should include attacker_uid")
	print("  [OK] poison damage includes attacker_uid")


func _test_pull_execute_respects_range() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("template_c", 42)
	var state := ctrl.state
	var guard := _find_guard(state)
	var player := state.get_player()
	_embed_red_gem(state, guard, Constants.GEM_GRAVITY)
	player.pos = guard.pos + Vector2i(Constants.ENEMY_GRAVITY_PULL_RANGE + 1, 0)
	state.rebuild_occupancy()
	guard.intent = IntentState.new()
	guard.intent.type = "pull"
	guard.intent.target_uid = player.uid
	var events := IntentSystem.execute_intent(state, guard)
	assert(events.is_empty(), "pull should fail beyond gravity range")
	print("  [OK] pull execute respects range")


func _test_custom_intent_keeps_move_events() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("bomb_rat_test", 42)
	var state := ctrl.state
	var rat := _find_unit_by_def(state, "unit_bomb_rat")
	assert(rat != null, "bomb rat should exist")
	var player := state.get_player()
	var step := BoardUtils.step_toward(rat.pos, player.pos)
	if step == rat.pos:
		print("  [SKIP] custom intent move batch — rat already adjacent")
		return
	rat.intent = IntentState.new()
	rat.intent.type = "bomb_rat_plunder_steal"
	rat.intent.target_uid = player.uid
	rat.intent.path = [step]
	rat.intent.damage = CombatRules.attack_damage(state, rat)
	var events := IntentSystem.execute_intent(state, rat)
	var has_move := false
	for ev in events:
		if ev.get("type", "") == "move_step":
			has_move = true
			break
	assert(has_move, "custom intent should preserve move_step events")
	print("  [OK] custom intent keeps move events")


func _find_guard(state: GameState) -> UnitState:
	return _find_unit_by_def(state, "unit_patrol_guard")


func _find_unit_by_def(state: GameState, def_id: String) -> UnitState:
	for unit in state.units.values():
		if unit.unit_def_id == def_id:
			return unit
	return null


func _embed_red_gem(state: GameState, unit: UnitState, gem_id: String) -> void:
	var gem := GemState.new()
	gem.uid = "test_%s_%s" % [gem_id, unit.uid]
	gem.gem_id = gem_id
	state.gems[gem.uid] = gem
	var red := unit.get_slot(Constants.SLOT_RED)
	assert(red != null, "unit should have red slot")
	red.gem_uid = gem.uid
	gem.owner_uid = unit.uid
	gem.slot_index = unit.slots.find(red)
	IntentSystem.refresh_unit_intent(state, unit)
