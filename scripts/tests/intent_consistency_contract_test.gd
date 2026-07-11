extends SceneTree

const EventValidator = preload("res://scripts/debug/event_validator.gd")
const AIProfiles = preload("res://scripts/rules/ai_profiles.gd")
const IntentPreviewRules = preload("res://scripts/rules/intent_preview_rules.gd")
const ScenarioBuilder = preload("res://scripts/testkit/scenario_builder.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== Intent Consistency Contract Test ===")
	_clear_run_relics()
	_test_patrol_guard_charge_preview_matches_execution()
	_test_stone_bow_shot_preview_matches_execution()
	_test_move_preview_matches_executed_path()
	_test_explosion_preview_matches_blast_delivery()
	_test_light_level_preview_matches_execution()
	_test_light_split_preview_tracks_each_beam()
	_test_split_preview_uses_resolved_shot_count()
	_test_split_preview_counts_large_target_per_projectile()
	_test_trample_preview_composes_configured_damage()
	_test_player_query_uses_structured_lethal_prediction()
	_test_counter_and_echo_intents_dispatch()
	_test_disarm_blocks_custom_damage_intents()
	print("INTENT_CONSISTENCY_CONTRACT_TEST_PASS")
	quit()


func _test_patrol_guard_charge_preview_matches_execution() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("patrol_guard_test", 42)
	var state := ctrl.state
	var guard := _find_unit_by_def(state, "unit_patrol_guard")
	var player := state.get_player()
	assert(guard != null and player != null, "guard/player should exist")
	var red := guard.get_slot(Constants.SLOT_RED)
	if red != null and not red.gem_uid.is_empty():
		state.gems.erase(red.gem_uid)
		red.gem_uid = ""
	guard.pos = Vector2i(6, 2)
	player.pos = Vector2i(3, 2)
	state.rebuild_occupancy()
	IntentSystem.refresh_unit_intent(state, guard)
	assert(guard.intent.type == "melee_attack", "charge setup should preview melee attack")
	assert(guard.intent.damage == 8, "charge preview should show 8 damage")
	var hp_before := player.hp
	var events := IntentSystem.execute_intent(state, guard)
	_assert_valid_events(events, "patrol_charge")
	var dealt := hp_before - player.hp
	assert(dealt == guard.intent.damage, "charge execution should match preview damage")
	_assert_valid_state(state, "patrol_charge")
	print("  [OK] patrol guard charge preview matches execution")


func _test_stone_bow_shot_preview_matches_execution() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("stone_bow_test", 42)
	var state := ctrl.state
	var bow := _find_unit_by_def(state, "unit_stone_bow_guard")
	var player := state.get_player()
	assert(bow != null and player != null, "bow/player should exist")
	_embed_red_gem(state, bow, Constants.GEM_EXPLOSION)
	bow.pos = Vector2i(5, 2)
	player.pos = Vector2i(1, 2)
	state.rebuild_occupancy()
	IntentSystem.refresh_unit_intent(state, bow)
	assert(bow.intent.type == "ranged_attack", "bow should preview ranged attack")
	assert(bow.intent.damage == CombatConfig.explosion_cross_damage(), "bow should preview configured explosion damage")
	assert(player.pos in bow.intent.affected_cells, "bow should preview the explosion blast cells")
	var hp_before := player.hp
	var events := IntentSystem.execute_intent(state, bow)
	_assert_valid_events(events, "stone_bow")
	var dealt := hp_before - player.hp
	assert(dealt == bow.intent.damage, "stone bow execution should match preview damage")
	_assert_valid_state(state, "stone_bow")
	print("  [OK] stone bow preview matches execution")


func _test_move_preview_matches_executed_path() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("stone_bow_test", 42)
	var state := ctrl.state
	var bow := _find_unit_by_def(state, "unit_stone_bow_guard")
	var player := state.get_player()
	assert(bow != null and player != null, "move preview bow/player should exist")
	bow.pos = Vector2i(5, 2)
	player.pos = Vector2i(1, 2)
	var prop := EntityState.create("block_prop", Constants.ENTITY_PROP, Vector2i(3, 2))
	state.add_entity(prop)
	state.rebuild_occupancy()
	IntentSystem.refresh_unit_intent(state, bow)
	assert(not bow.intent.path.is_empty(), "blocked bow should preview a movement path")
	var expected_end: Vector2i = bow.intent.path[bow.intent.path.size() - 1]
	var events := IntentSystem.execute_intent(state, bow)
	_assert_valid_events(events, "move_preview")
	var move_steps := events.filter(func(ev): return ev.get("type", "") == "move_step")
	assert(move_steps.size() == bow.intent.path.size(), "executed move steps should match preview path length")
	assert(bow.pos == expected_end, "executed move should end at preview destination")
	_assert_valid_state(state, "move_preview")
	print("  [OK] move preview matches executed path")


func _test_explosion_preview_matches_blast_delivery() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("template_c", 42)
	var state := ctrl.state
	var guard := _find_unit_by_def(state, "unit_patrol_guard")
	var player := state.get_player()
	assert(guard != null and player != null, "explosion test guard/player should exist")
	_embed_red_gem(state, guard, Constants.GEM_EXPLOSION)
	guard.pos = player.pos + Vector2i(1, 0)
	state.rebuild_occupancy()
	IntentSystem.refresh_unit_intent(state, guard)
	assert(guard.intent.type == "explosion_attack", "explosion gem should preview explosion_attack")
	assert(player.pos in guard.intent.affected_cells, "explosion preview should include target cell")
	var hp_before := player.hp
	var events := IntentSystem.execute_intent(state, guard)
	_assert_valid_events(events, "explosion_attack")
	var dealt := hp_before - player.hp
	assert(dealt >= guard.intent.damage, "explosion execution should deal at least preview base damage")
	assert(events.any(func(ev): return ev.get("type", "") == "explode"), "explosion execution should emit explode event")
	_assert_valid_state(state, "explosion_attack")
	print("  [OK] explosion preview matches blast delivery")


func _test_light_level_preview_matches_execution() -> void:
	var builder := ScenarioBuilder.new("fission_slime_test", 3501, true)
	var player := builder.player()
	builder.clear_slots(player)
	builder.move(player, Vector2i(4, 3))
	builder.set_stats(player, {"hp": 100, "max_hp": 100})
	var enemy := builder.add_unit(
		"intent_light_enemy",
		"unit_patrol_guard",
		Constants.TEAM_ENEMY,
		Vector2i(1, 3),
		{"base_attack": 10, "move_points": 0}
	)
	builder.clear_slots(enemy)
	builder.mount_gems(enemy, Constants.SLOT_RED, [Constants.GEM_LIGHT, Constants.GEM_LIGHT])
	var state := builder.finish()
	var ai_profile := AIProfiles.get_profile(enemy.ai_profile_id)
	var light_candidates := EnemyAI.evaluate_red_skill_candidates(state, enemy, enemy.pos, ai_profile)
	assert(light_candidates.size() == 1, "light setup should expose one red-skill candidate")
	var expected_score := 7.0 * float(ai_profile.get("w_damage", 10.0)) + float(ai_profile.get("w_status", 6.0))
	assert(is_equal_approx(float(light_candidates[0].score), expected_score), "light AI score should use the configured Lv2 damage")
	IntentSystem.refresh_unit_intent(state, enemy)
	assert(enemy.intent.type == "light_beam", "two red light gems should produce a light intent")
	assert(enemy.intent.damage_components.size() == 1, "plain light should expose one structured component")
	var component: IntentDamageComponent = enemy.intent.damage_components[0]
	assert(component.source == "light", "light intent component should identify its source")
	assert(component.damage_per_hit == 7, "light Lv2 should preview floor(10 * 0.75) = 7")
	assert(component.instance_count == 1, "plain light should preview one beam")
	assert(enemy.intent.predicted_raw_damage_to(player.uid) == 7, "structured light preview should target the player for 7")
	assert("7" in enemy.intent.preview_text, "player-facing light intent should use the configured damage")
	var cloned_intent := enemy.intent.clone()
	cloned_intent.damage_components[0].target_uids.clear()
	assert(enemy.intent.predicted_raw_damage_to(player.uid) == 7, "intent clones should deep-copy structured components")
	var hp_before := player.hp
	var events := IntentSystem.execute_intent(state, enemy)
	_assert_valid_events(events, "light_level_preview")
	assert(hp_before - player.hp == enemy.intent.predicted_raw_damage_to(player.uid), "light execution should match structured preview")
	_assert_valid_state(state, "light_level_preview")
	print("  [OK] light level preview matches configured execution")


func _test_light_split_preview_tracks_each_beam() -> void:
	var builder := ScenarioBuilder.new("fission_slime_test", 3502, true)
	var player := builder.player()
	builder.clear_slots(player)
	builder.move(player, Vector2i(4, 3))
	builder.set_stats(player, {"hp": 100, "max_hp": 100})
	var upper := builder.add_unit(
		"intent_light_upper",
		"unit_player",
		Constants.TEAM_PLAYER,
		Vector2i(3, 1),
		{"hp": 100, "max_hp": 100}
	)
	var lower := builder.add_unit(
		"intent_light_lower",
		"unit_player",
		Constants.TEAM_PLAYER,
		Vector2i(3, 5),
		{"hp": 100, "max_hp": 100}
	)
	var enemy := builder.add_unit(
		"intent_light_split_enemy",
		"unit_patrol_guard",
		Constants.TEAM_ENEMY,
		Vector2i(1, 3),
		{"base_attack": 10, "move_points": 0}
	)
	builder.clear_slots(enemy)
	builder.mount_gems(enemy, Constants.SLOT_RED, [Constants.GEM_LIGHT, Constants.GEM_SPLIT])
	var state := builder.finish()
	IntentSystem.refresh_unit_intent(state, enemy)
	assert(enemy.intent.damage_components.size() == 1, "light + split should expose one beam-volley component")
	var component: IntentDamageComponent = enemy.intent.damage_components[0]
	assert(component.source == "light", "light should own the combined damage model")
	assert(component.damage_per_hit == 3, "light + split should preview floor(floor(10 * 0.7) * 0.5) = 3")
	assert(component.instance_count == 3, "split Lv1 should expand light into three configured directions")
	for target in [player, upper, lower]:
		assert(enemy.intent.predicted_raw_damage_to(target.uid) == 3, "each occupied beam path should preview one 3-damage hit")
	assert("3" in enemy.intent.preview_text, "light volley text should expose its dynamic beam count")
	var events := IntentSystem.execute_intent(state, enemy)
	_assert_valid_events(events, "light_split_preview")
	assert(player.hp == 97 and upper.hp == 97 and lower.hp == 97, "all three previewed light paths should resolve")
	_assert_valid_state(state, "light_split_preview")
	print("  [OK] light + split preview tracks each beam")


func _test_split_preview_uses_resolved_shot_count() -> void:
	var builder := ScenarioBuilder.new("fission_slime_test", 3503, true)
	var player := builder.player()
	builder.clear_slots(player)
	builder.move(player, Vector2i(1, 3))
	builder.set_stats(player, {"base_attack": 10})
	builder.mount_gems(
		player,
		Constants.SLOT_RED,
		[Constants.GEM_SPLIT, Constants.GEM_SPLIT, Constants.GEM_SPLIT]
	)
	var hit_cells: Array[Vector2i] = [
		Vector2i(4, 3),
		Vector2i(3, 4),
		Vector2i(3, 2),
		Vector2i(3, 3),
		Vector2i(5, 3),
	]
	var targets: Array[UnitState] = []
	for index in range(hit_cells.size()):
		targets.append(builder.add_unit(
			"intent_split_target_%d" % index,
			"unit_patrol_guard",
			Constants.TEAM_ENEMY,
			hit_cells[index],
			{"hp": 100, "max_hp": 100}
		))
	var state := builder.finish()
	var intent := IntentState.new()
	intent.type = "ranged_attack"
	intent.source_uid = player.uid
	intent.target_uid = targets[0].uid
	intent.base_damage = 10
	intent.damage = 10
	IntentPreviewRules.populate_damage(state, player, intent)
	assert(intent.damage_components.size() == 1, "split attack should expose one volley component")
	var component: IntentDamageComponent = intent.damage_components[0]
	assert(component.source == "split", "split volley should identify its source")
	assert(component.damage_per_hit == 3, "split Lv3 should read the configured 30% ratio")
	assert(component.instance_count == 5, "split Lv3 ranged geometry should resolve five shots")
	assert("5" in intent.preview_text and "3" in intent.preview_text, "split text should render dynamic damage and shot count")
	for target in targets:
		assert(intent.predicted_raw_damage_to(target.uid) == 3, "each occupied split cell should predict one hit")
	var result := CombatRules.ranged_attack(state, player, targets[0].pos)
	assert(result.get("ok", false), "configured split volley should execute")
	var events: Array = result.get("events", [])
	_assert_valid_events(events, "split_preview")
	for target in targets:
		assert(target.hp == 97, "all five previewed split shots should resolve for 3 damage")
	_assert_valid_state(state, "split_preview")
	print("  [OK] split preview uses configured ratio and resolved shot count")


func _test_split_preview_counts_large_target_per_projectile() -> void:
	var builder := ScenarioBuilder.new("fission_slime_test", 3504, true)
	var player := builder.player()
	builder.clear_slots(player)
	builder.move(player, Vector2i(1, 3))
	builder.set_stats(player, {"base_attack": 10})
	builder.mount_gems(player, Constants.SLOT_RED, [Constants.GEM_SPLIT])
	var large_target := builder.add_unit(
		"intent_split_large_target",
		"unit_fission_slime",
		Constants.TEAM_ENEMY,
		Vector2i(3, 2),
		{"hp": 100, "max_hp": 100}
	)
	builder.clear_slots(large_target)
	var state := builder.finish()
	var intent := IntentState.new()
	intent.type = "ranged_attack"
	intent.source_uid = player.uid
	intent.target_uid = large_target.uid
	intent.base_damage = 10
	intent.damage = 10
	IntentPreviewRules.populate_damage(state, player, intent)
	var component: IntentDamageComponent = intent.damage_components[0]
	assert(component.instance_count == 3, "split Lv1 should still emit three projectiles")
	assert(component.target_uids.count(large_target.uid) == 2, "a large unit should be counted once per intersecting projectile")
	assert(intent.predicted_raw_damage_to(large_target.uid) == 14, "two 70% hits should predict 14 raw damage")
	var result := CombatRules.ranged_attack(state, player, large_target.pos)
	assert(result.get("ok", false), "split attack against a large target should execute")
	var events: Array = result.get("events", [])
	_assert_valid_events(events, "split_large_target_preview")
	assert(large_target.hp == 86, "large target should receive both previewed split hits")
	_assert_valid_state(state, "split_large_target_preview")
	print("  [OK] split preview counts large targets per projectile")


func _test_trample_preview_composes_configured_damage() -> void:
	var builder := ScenarioBuilder.new("fission_slime_test", 3505, true)
	var player := builder.player()
	builder.clear_slots(player)
	builder.move(player, Vector2i(3, 3))
	builder.set_stats(player, {"hp": 100, "max_hp": 100})
	var slime := builder.add_unit(
		"intent_trample_slime",
		"unit_fission_slime",
		Constants.TEAM_ENEMY,
		Vector2i(2, 2),
		{"move_points": 0}
	)
	var state := builder.finish()
	IntentSystem.refresh_unit_intent(state, slime)
	assert(slime.intent.type == "trample", "overlapping fission slime should preview trample")
	assert(slime.intent.damage_components.size() == 2, "trample should expose skill and collision components")
	var skill: IntentDamageComponent = slime.intent.damage_components[0]
	var collision: IntentDamageComponent = slime.intent.damage_components[1]
	assert(skill.source == "trample" and skill.damage_per_hit == FissionSlimeRules.trample_damage(slime))
	assert(collision.source == "collision" and collision.damage_per_hit == FissionSlimeRules.trample_collision_damage(slime))
	assert(
		slime.intent.predicted_raw_damage_to(player.uid) == FissionSlimeRules.trample_total_damage(slime),
		"trample structured total should compose both configured components"
	)
	assert("4" in slime.intent.preview_text, "trample copy should show the configured total damage")
	var hp_before := player.hp
	var events := IntentSystem.execute_intent(state, slime)
	_assert_valid_events(events, "trample_component_preview")
	assert(
		hp_before - player.hp == slime.intent.predicted_raw_damage_to(player.uid),
		"trample execution should match its structured total"
	)
	_assert_valid_state(state, "trample_component_preview")
	print("  [OK] trample preview composes configured damage")


func _test_player_query_uses_structured_lethal_prediction() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("fission_slime_test", 3506)
	var state := ctrl.state
	for current: UnitState in state.units.values().duplicate():
		if current.team == Constants.TEAM_ENEMY:
			state.unregister_unit(current)
	var player := state.get_player()
	for slot: SlotState in player.slots:
		if not slot.gem_uid.is_empty():
			state.gems.erase(slot.gem_uid)
			slot.gem_uid = ""
	state.move_unit(player, Vector2i(2, 3))
	player.base_attack = 10
	var registry: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	var victim := UnitState.from_def(
		"query_lethal_victim",
		"unit_patrol_guard",
		Constants.TEAM_ENEMY,
		Vector2i(5, 3),
		registry.get_unit_def("unit_patrol_guard")
	)
	victim.hp = 10
	victim.max_hp = 10
	state.register_unit(victim)
	var black_slot := victim.get_slot(Constants.SLOT_BLACK)
	var black_gem: GemState = registry.create_gem_instance(
		"query_lethal_black_explosion",
		Constants.GEM_EXPLOSION,
		{}
	)
	black_gem.owner_uid = victim.uid
	black_gem.slot_index = victim.slots.find(black_slot)
	state.gems[black_gem.uid] = black_gem
	black_slot.gem_uid = black_gem.uid
	ctrl.select_action(Constants.ACTION_ATTACK)
	var death_neighbor := victim.pos + Vector2i(0, 1)
	var lethal_highlights := ctrl.get_highlights(victim.pos)
	assert(
		death_neighbor in lethal_highlights.get("effect_preview", []),
		"configured 10 damage against 10 HP should preview the black explosion area"
	)
	StatusRules.apply_shield(state, victim, 1, 0, victim.uid)
	var shielded_highlights := ctrl.get_highlights(victim.pos)
	assert(
		death_neighbor not in shielded_highlights.get("effect_preview", []),
		"one shield should prevent a false lethal/death-gem preview"
	)
	_assert_valid_state(state, "player_query_structured_lethal")
	print("  [OK] player query uses structured lethal prediction")


func _test_counter_and_echo_intents_dispatch() -> void:
	var specs := [
		{"gem_id": Constants.GEM_COUNTER, "intent_type": "counter_attack"},
		{"gem_id": Constants.GEM_ECHO, "intent_type": "echo_attack"},
	]
	for index in range(specs.size()):
		var spec: Dictionary = specs[index]
		var builder := ScenarioBuilder.new("fission_slime_test", 3510 + index, true)
		var player := builder.player()
		builder.clear_slots(player)
		builder.move(player, Vector2i(3, 3))
		builder.set_stats(player, {"hp": 100, "max_hp": 100})
		var enemy := builder.add_unit(
			"intent_dispatch_enemy_%d" % index,
			"unit_patrol_guard",
			Constants.TEAM_ENEMY,
			Vector2i(2, 3),
			{"base_attack": 6, "move_points": 0}
		)
		builder.clear_slots(enemy)
		builder.mount_gems(enemy, Constants.SLOT_RED, [spec["gem_id"]])
		var state := builder.finish()
		IntentSystem.refresh_unit_intent(state, enemy)
		assert(enemy.intent.type == spec["intent_type"], "%s should remain an executable attack intent" % spec["intent_type"])
		var hp_before := player.hp
		var events := IntentSystem.execute_intent(state, enemy)
		_assert_valid_events(events, "intent_dispatch_%s" % spec["intent_type"])
		assert(hp_before - player.hp == 6, "%s should dispatch through enemy red execution" % spec["intent_type"])
		_assert_valid_state(state, "intent_dispatch_%s" % spec["intent_type"])
	print("  [OK] counter and echo intents dispatch")


func _test_disarm_blocks_custom_damage_intents() -> void:
	var builder := ScenarioBuilder.new("fission_slime_test", 3520, true)
	var player := builder.player()
	builder.clear_slots(player)
	builder.move(player, Vector2i(4, 2))
	var slime := builder.add_unit(
		"intent_disarmed_slime",
		"unit_fission_slime",
		Constants.TEAM_ENEMY,
		Vector2i(2, 2),
		{"move_points": 0}
	)
	var state := builder.finish()
	StatusRules.apply_disarmed(state, slime, 1, player.uid)
	IntentSystem.refresh_unit_intent(state, slime)
	assert(slime.intent.type == "wait", "disarmed custom attackers should not retain a slam intent")
	assert(slime.intent.damage_components.is_empty(), "blocked custom attacks should not expose stale damage")
	print("  [OK] disarm blocks custom damage intents")


func _assert_valid_events(events: Array, label: String) -> void:
	assert(EventValidator.assert_valid(events, label), "event stream should stay valid for %s" % label)


func _clear_run_relics() -> void:
	var run_service: Node = Engine.get_main_loop().root.get_node_or_null("RunService")
	if run_service == null:
		return
	var run: RunState = run_service.get_run()
	if run != null:
		run.owned_relics.clear()


func _assert_valid_state(state: GameState, label: String) -> void:
	assert(BattleInvariantChecker.assert_valid(state, label), "battle invariants should hold for %s" % label)


func _find_unit_by_def(state: GameState, def_id: String) -> UnitState:
	for unit in state.units.values():
		if unit.unit_def_id == def_id:
			return unit
	return null


func _embed_red_gem(state: GameState, unit: UnitState, gem_id: String) -> void:
	var red := unit.get_slot(Constants.SLOT_RED)
	assert(red != null, "unit should have red slot")
	if not red.gem_uid.is_empty():
		state.gems.erase(red.gem_uid)
	var gem := GemState.new()
	gem.uid = "intent_contract_%s_%s" % [gem_id, unit.uid]
	gem.gem_id = gem_id
	gem.owner_uid = unit.uid
	gem.slot_index = unit.slots.find(red)
	state.gems[gem.uid] = gem
	red.gem_uid = gem.uid
