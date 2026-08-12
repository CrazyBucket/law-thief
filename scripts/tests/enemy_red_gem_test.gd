extends SceneTree
## 敌人红槽宝石：射程、AI 接入、伤害事件

const CombatConfig = preload("res://scripts/core/combat_config.gd")
const Builder = preload("res://scripts/testkit/scenario_builder.gd")
const EventValidator = preload("res://scripts/debug/event_validator.gd")
const BattleInvariantChecker = preload("res://scripts/debug/battle_invariant_checker.gd")


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Enemy Red Gem Test ===")
	_test_arc_requires_adjacent_for_ai()
	_test_arc_execute_rejects_ranged()
	_test_arc_lethal_hit_still_bounces()
	_test_fire_gem_ai_and_execute()
	_test_ice_gem_ai_and_execute()
	_test_explosion_attack_does_not_suicide()
	_test_enemy_red_damage_includes_attacker_uid()
	_test_pull_execute_respects_range()
	_test_pull_range_scales_with_gravity_level()
	_test_pull_keeps_normal_attack_through_scenery()
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
	assert(guard.intent.type == "arc_attack", "arc AI should plan an attack after moving, got %s" % guard.intent.type)
	var attack_anchor: Vector2i = guard.intent.path[-1] if not guard.intent.path.is_empty() else guard.pos
	assert(BoardUtils.distance_between_unit_at_and_unit(guard, attack_anchor, player) == 1, "arc AI must end adjacent before attacking")
	print("  [OK] arc AI moves adjacent before attacking")


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


func _test_arc_lethal_hit_still_bounces() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("template_c", 43)
	var state := ctrl.state
	var guard := _find_guard(state)
	var player := state.get_player()
	_embed_red_gem(state, guard, Constants.GEM_CONDUCTIVE)
	state.move_unit(guard, player.pos + Vector2i(1, 0))
	player.hp = guard.base_attack
	var ally := UnitState.new()
	ally.uid = "enemy_arc_ally"
	ally.unit_def_id = player.unit_def_id
	ally.team = Constants.TEAM_PLAYER
	var ally_pos := Vector2i(-1, -1)
	for candidate in BoardUtils.neighbors4(player.pos):
		if BoardUtils.in_bounds(state, candidate) and state.get_unit_at(candidate) == null:
			ally_pos = candidate
			break
	assert(ally_pos != Vector2i(-1, -1), "enemy arc test requires an empty cell beside the player")
	ally.pos = ally_pos
	ally.hp = 20
	ally.max_hp = 20
	ally.alive = true
	state.register_unit(ally)
	guard.intent = IntentState.new()
	guard.intent.type = "arc_attack"
	guard.intent.target_uid = player.uid
	var events := IntentSystem.execute_intent(state, guard)
	assert(not player.alive, "enemy arc primary hit should defeat the fragile player")
	assert(ally.hp < ally.max_hp, "enemy arc should bounce from the defeated player's attack anchor")
	assert(events.any(func(event): return str(event.get("type", "")) == "arc" and event.get("from", Vector2i.ZERO) == player.pos), "enemy arc should emit from the defeated anchor")
	print("  [OK] enemy lethal arc keeps its hit anchor")


func _test_fire_gem_ai_and_execute() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("template_c", 42)
	var state := ctrl.state
	var guard := _find_guard(state)
	var player := state.get_player()
	_embed_red_gem(state, guard, Constants.GEM_FIRE)
	state.move_unit(guard, player.pos + Vector2i(1, 0))
	IntentSystem.refresh_unit_intent(state, guard)
	assert(guard.intent.type == "fire_attack", "fire gem should produce fire_attack intent")
	var hp_before := player.hp
	var events := IntentSystem.execute_intent(state, guard)
	assert(not events.is_empty(), "fire attack should produce events")
	assert(player.hp < hp_before, "fire attack should deal damage")
	assert(player.has_status(Constants.STATUS_BURNING), "fire attack should apply burning")
	var dmg_ev := _first_damage_event(events, player.uid)
	assert(dmg_ev.get("attacker_uid", "") == guard.uid, "fire damage should include attacker_uid")
	print("  [OK] fire gem AI + execute")


func _test_ice_gem_ai_and_execute() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("template_c", 42)
	var state := ctrl.state
	var guard := _find_guard(state)
	var player := state.get_player()
	_embed_red_gem(state, guard, Constants.GEM_ICE)
	state.move_unit(guard, player.pos + Vector2i(1, 0))
	IntentSystem.refresh_unit_intent(state, guard)
	assert(guard.intent.type == "ice_attack", "ice gem should produce ice_attack intent")
	var hp_before := player.hp
	var events := IntentSystem.execute_intent(state, guard)
	assert(not events.is_empty(), "ice attack should produce events")
	assert(player.hp < hp_before, "ice attack should deal damage")
	var dmg_ev := _first_damage_event(events, player.uid)
	assert(dmg_ev.get("attacker_uid", "") == guard.uid, "ice damage should include attacker_uid")
	print("  [OK] ice gem AI + execute")


func _test_explosion_attack_does_not_suicide() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("template_c", 42)
	var state := ctrl.state
	var guard := _find_guard(state)
	var player := state.get_player()
	_clear_run_relics()
	state.battle_temp_flags.clear()
	_embed_red_gem(state, guard, Constants.GEM_EXPLOSION)
	guard.pos = player.pos + Vector2i(1, 0)
	state.rebuild_occupancy()
	IntentSystem.refresh_unit_intent(state, guard)
	assert(guard.intent.type == "explosion_attack", "explosion gem should use explosion_attack, got %s" % guard.intent.type)
	var expected_damage := guard.base_attack + roundi(float(guard.base_attack) * 0.2)
	assert(
		guard.intent.damage == expected_damage,
		"intent preview should include direct and center blast damage %d, got %d" % [expected_damage, guard.intent.damage]
	)
	var guard_hp := guard.hp
	var player_hp := player.hp
	var events := IntentSystem.execute_intent(state, guard)
	assert(guard.alive, "explosion attack should not kill the attacker")
	assert(guard.hp == guard_hp, "attacker should take no self damage")
	var dealt := player_hp - player.hp
	assert(dealt == expected_damage, "direct hit plus center blast should deal %d, got %d" % [expected_damage, dealt])
	assert(events.any(func(e): return e.get("type", "") == "explode"), "should emit explode event")
	var dmg_ev: Dictionary = {}
	for ev in events:
		if ev.get("type", "") == "damage" and ev.get("pos", Vector2i.ZERO) == player.pos:
			dmg_ev = ev
			break
	assert(int(dmg_ev.get("damage", 0)) > 0, "damage event should include the direct or center blast hit")
	print("  [OK] explosion attack cross burst without suicide")


func _test_enemy_red_damage_includes_attacker_uid() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("template_c", 42)
	var state := ctrl.state
	var guard := _find_guard(state)
	var player := state.get_player()
	_embed_red_gem(state, guard, Constants.GEM_POISON)
	state.move_unit(guard, player.pos + Vector2i(1, 0))
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
	state.move_unit(guard, Vector2i(7, 1))
	state.move_unit(player, Vector2i(1, 1))
	assert(BoardUtils.distance_between_units(guard, player) == GemEffects.gravity_pull_range(state, guard) + 1)
	guard.intent = IntentState.new()
	guard.intent.type = "pull"
	guard.intent.target_uid = player.uid
	var events := IntentSystem.execute_intent(state, guard)
	assert(events.is_empty(), "pull should fail beyond gravity range")
	print("  [OK] pull execute respects range")


func _test_pull_range_scales_with_gravity_level() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("template_c", 42)
	var state := ctrl.state
	var guard := _find_guard(state)
	var player := state.get_player()
	_embed_red_gem(state, guard, Constants.GEM_GRAVITY)
	var extra_slot := SlotState.create(Constants.SLOT_RED)
	guard.slots.append(extra_slot)
	_embed_gem_on_slot(state, guard, extra_slot, Constants.GEM_GRAVITY)
	state.move_unit(guard, Vector2i(7, 1))
	state.move_unit(player, Vector2i(1, 1))
	assert(BoardUtils.distance_between_units(guard, player) == GemEffects.gravity_pull_range(state, guard))
	guard.intent = IntentState.new()
	guard.intent.type = "pull"
	guard.intent.target_uid = player.uid
	var events := IntentSystem.execute_intent(state, guard)
	assert(not events.is_empty(), "gravity level 2 pull should execute within extended range")
	print("  [OK] pull execution range scales with gravity level")


func _test_pull_keeps_normal_attack_through_scenery() -> void:
	var builder = Builder.new("fission_slime_test", 4201, true)
	var player := builder.player()
	builder.move(player, Vector2i(1, 3)).clear_slots(player)
	var guard := builder.add_unit(
		"gravity_blocker_guard",
		"unit_patrol_guard",
		Constants.TEAM_ENEMY,
		Vector2i(6, 3),
		{"move_points": 0}
	)
	builder.clear_slots(guard).mount_gems(guard, Constants.SLOT_RED, [Constants.GEM_GRAVITY])
	var prop := EntityState.create("gravity_projectile_blocker", Constants.ENTITY_PROP, Vector2i(4, 3))
	builder.state.add_entity(prop)
	var state := builder.finish()
	assert(BoardUtils.distance_between_units(guard, player) == GemEffects.gravity_pull_range(state, guard))
	assert(BoardUtils.projectile_blocked_before_aim(state, guard.pos, player.pos), "setup needs blocking scenery")

	IntentSystem.refresh_unit_intent(state, guard)
	assert(guard.intent.type == "pull", "gravity AI should attack at its executable max range")
	assert(
		guard.intent.predicted_raw_damage_to(player.uid) == CombatRules.attack_damage(state, guard),
		"gravity intent should preview the normal attack damage"
	)
	var player_hp_before := player.hp
	var player_pos_before := player.pos
	var events := IntentSystem.execute_intent(state, guard)
	assert(player_hp_before - player.hp == CombatRules.attack_damage(state, guard), "scenery must not replace the gravity attack target")
	assert(player.pos == player_pos_before + Vector2i(1, 0), "gravity hit should pull the player one cell toward the monster")
	assert(
		events.any(func(event): return str(event.get("type", "")) == "projectile" and event.get("to", Vector2i.ZERO) == player_pos_before),
		"gravity projectile presentation should reach the locked target"
	)
	assert(EventValidator.assert_valid(events, "enemy_red_gem.gravity_scenery"))
	assert(BattleInvariantChecker.assert_valid(state, "enemy_red_gem.gravity_scenery"))
	print("  [OK] gravity keeps normal attack through scenery")


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


func _clear_run_relics() -> void:
	var run_svc: Node = Engine.get_main_loop().root.get_node_or_null("RunService")
	if run_svc == null:
		return
	var run: RunState = run_svc.get_run()
	if run != null:
		run.owned_relics.clear()


func _find_guard(state: GameState) -> UnitState:
	return _find_unit_by_def(state, "unit_patrol_guard")


func _find_unit_by_def(state: GameState, def_id: String) -> UnitState:
	for unit in state.units.values():
		if unit.unit_def_id == def_id:
			return unit
	return null


func _first_damage_event(events: Array, victim_uid: String) -> Dictionary:
	for raw_event in events:
		if raw_event is Dictionary and str(raw_event.get("type", "")) == "damage" \
				and str(raw_event.get("uid", "")) == victim_uid:
			return raw_event as Dictionary
	return {}


func _embed_red_gem(state: GameState, unit: UnitState, gem_id: String) -> void:
	var red := unit.get_slot(Constants.SLOT_RED)
	assert(red != null, "unit should have red slot")
	_embed_gem_on_slot(state, unit, red, gem_id)
	IntentSystem.refresh_unit_intent(state, unit)


func _embed_gem_on_slot(state: GameState, unit: UnitState, slot: SlotState, gem_id: String) -> void:
	if not slot.gem_uid.is_empty():
		state.gems.erase(slot.gem_uid)
	var gem := GemState.new()
	gem.uid = "test_%s_%s_%d" % [gem_id, unit.uid, unit.slots.find(slot)]
	gem.gem_id = gem_id
	state.gems[gem.uid] = gem
	slot.gem_uid = gem.uid
	gem.owner_uid = unit.uid
	gem.slot_index = unit.slots.find(slot)
