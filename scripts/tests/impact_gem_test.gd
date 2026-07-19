extends SceneTree

const Builder = preload("res://scripts/testkit/scenario_builder.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Impact Gem Test ===")
	_test_red_levels_dash_damage_and_knockback()
	_test_red_forced_knockback_ignores_active_move_block()
	_test_red_accepts_direction_and_finds_first_target()
	_test_red_preview_is_cardinal()
	_test_red_suppresses_split()
	_test_red_flurry_repeats_complete_impacts()
	_test_blue_launches_after_surviving_active_damage()
	_test_blue_ignores_self_collision_damage_and_skips_lethal_hits()
	_test_black_levels_and_gravity_merge()
	_test_enemy_impact_intent_executes_shared_pipeline()
	if _failed:
		push_error("IMPACT_GEM_TEST_FAIL")
		quit(1)
		return
	print("IMPACT_GEM_TEST_PASS")
	quit(0)


func _test_red_levels_dash_damage_and_knockback() -> void:
	for level in range(1, 4):
		var builder = Builder.new("fission_slime_test", 9300 + level, true)
		var attacker := builder.player()
		builder.move(attacker, Vector2i(1, 3)).clear_slots(attacker)
		var gems: Array = []
		for _index in range(level):
			gems.append(Constants.GEM_IMPACT)
		builder.mount_gems(attacker, Constants.SLOT_RED, gems)
		var target := builder.add_unit("impact_red_%d" % level, "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(4, 3), {"hp": 100, "max_hp": 100})
		builder.clear_slots(target)
		var state := builder.finish()
		var result := CombatRules.ranged_attack(state, attacker, target.pos, CombatConfig.attack_range())
		var events: Array = result.get("events", [])
		var damage_events := _events_of_type(events, "damage").filter(func(event): return str(event.get("uid", "")) == target.uid)
		_expect(result.get("ok", false), "red impact level %d should execute" % level)
		_expect(GemEffects.red_attack_range(state, attacker) == CombatConfig.attack_range() + level, "red impact level %d should add exactly %d range" % [level, level])
		_expect(attacker.pos == Vector2i(3, 3), "red impact should dash to contact before hitting")
		_expect(target.pos == Vector2i(4 + level, 3), "red impact level %d should knock back dash distance plus offset" % level)
		_expect(damage_events.size() == 1 and int(damage_events[0].get("damage", 0)) == CombatRules.attack_damage(state, attacker) + 2, "red impact should add actual dash distance to damage")
		var damage_index := events.find(damage_events[0]) if not damage_events.is_empty() else -1
		_expect(not events.is_empty() and str(events[0].get("type", "")) == "impact_charge", "impact should declare its dedicated charge presentation")
		_expect(damage_index >= 3 and events.slice(1, damage_index).all(func(event): return str(event.get("type", "")) == "move_step"), "dash movement should animate before impact damage")
		_expect(_events_of_type(events, "projectile").is_empty(), "impact must replace the ranged projectile presentation")
		_expect(_valid(state, events), "red impact level %d should preserve battle invariants" % level)
	print("  [OK] red impact levels dash, add distance damage, and knock back")


func _test_red_forced_knockback_ignores_active_move_block() -> void:
	var builder = Builder.new("fission_slime_test", 9305, true)
	var attacker := builder.player()
	builder.move(attacker, Vector2i(1, 3)).clear_slots(attacker)
	builder.mount_gems(attacker, Constants.SLOT_RED, [Constants.GEM_IMPACT])
	var target := builder.add_unit("impact_rooted_target", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(4, 3), {"hp": 100, "max_hp": 100})
	builder.clear_slots(target)
	var state := builder.finish()
	StatusRules.apply_rooted(state, target, 1, attacker.uid)
	var result := CombatRules.ranged_attack(state, attacker, target.pos, CombatConfig.attack_range())
	_expect(result.get("ok", false) and target.pos == Vector2i(5, 3), "active movement blocks must not grant forced-displacement immunity")
	_expect(_events_of_type(result.get("events", []), "move_step").any(func(event): return str(event.get("uid", "")) == target.uid), "impact should emit the target knockback motion")
	print("  [OK] red impact uses forced-movement immunity instead of active movement permission")


func _test_red_accepts_direction_and_finds_first_target() -> void:
	var builder = Builder.new("fission_slime_test", 9309, true)
	var attacker := builder.player()
	builder.move(attacker, Vector2i(1, 3)).clear_slots(attacker)
	builder.mount_gems(attacker, Constants.SLOT_RED, [Constants.GEM_IMPACT])
	var state := builder.finish()
	var result := CombatRules.ranged_attack(state, attacker, Vector2i(4, 3), CombatConfig.attack_range())
	_expect(result.get("ok", false), "red impact should accept an empty cardinal cell as a direction choice")
	_expect(attacker.pos == Vector2i(5, 3), "an empty impact direction should charge to its full resolved range")
	_expect(_events_of_type(result.get("events", []), "impact_charge").size() == 1, "an empty direction should still use the impact presentation")
	_expect(_events_of_type(result.get("events", []), "projectile").is_empty(), "directional impact must not fall back to a ranged projectile")

	builder = Builder.new("fission_slime_test", 9319, true)
	attacker = builder.player()
	builder.move(attacker, Vector2i(1, 3)).clear_slots(attacker)
	builder.mount_gems(attacker, Constants.SLOT_RED, [Constants.GEM_IMPACT])
	var target := builder.add_unit("impact_direction_target", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(4, 3), {"hp": 100, "max_hp": 100})
	builder.clear_slots(target)
	state = builder.finish()
	var ctrl := BattleController.new()
	ctrl.state = state
	ctrl.select_action(Constants.ACTION_ATTACK)
	result = ctrl.try_attack_cell(Vector2i(5, 3))
	_expect(result.get("ok", false), "the player should be able to click beyond a target to choose the impact direction")
	_expect(attacker.pos == Vector2i(3, 3) and target.pos == Vector2i(5, 3) and target.hp < 100, "a two-cell directional charge should move the first target by max(0, 2 - 1) = 1 cell")
	var diagonal := builder.add_unit("impact_diagonal", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(5, 1), {"hp": 100, "max_hp": 100})
	builder.clear_slots(diagonal).finish()
	result = CombatRules.ranged_attack(state, attacker, diagonal.pos, CombatConfig.attack_range())
	_expect(not result.get("ok", true), "red impact should reject diagonal targets")
	print("  [OK] red impact accepts directions and resolves the first target")


func _test_red_preview_is_cardinal() -> void:
	var builder = Builder.new("fission_slime_test", 9308, true)
	var attacker := builder.player()
	builder.move(attacker, Vector2i(3, 3)).clear_slots(attacker)
	builder.mount_gems(attacker, Constants.SLOT_RED, [Constants.GEM_IMPACT])
	var state := builder.finish()
	var ctrl := BattleController.new()
	ctrl.state = state
	ctrl.select_action(Constants.ACTION_ATTACK)
	var preview: Array = ctrl.get_highlights().get("attack_range", [])
	_expect(Vector2i(3, 0) in preview and Vector2i(0, 3) in preview, "impact preview should expose its four cardinal lanes")
	_expect(Vector2i(4, 4) not in preview, "impact preview must not expose diagonal cells")
	var hovered := ctrl.get_highlights(Vector2i(4, 3))
	var routes: Array = hovered.get("routes", [])
	_expect(routes.size() == 1 and str(routes[0].get("kind", "")) == "impact", "impact hover should expose a dedicated arrow route")
	_expect(routes.size() == 1 and routes[0].get("path", []).front() == attacker.pos and routes[0].get("path", []).back() == Vector2i(7, 3), "impact arrow should show the complete resolved charge lane")
	print("  [OK] red impact preview uses four cardinal lanes and an arrow")


func _test_red_suppresses_split() -> void:
	var builder = Builder.new("fission_slime_test", 9307, true)
	var attacker := builder.player()
	builder.move(attacker, Vector2i(1, 3)).clear_slots(attacker)
	builder.mount_gems(attacker, Constants.SLOT_RED, [Constants.GEM_IMPACT, Constants.GEM_SPLIT])
	var target := builder.add_unit("impact_split_target", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(4, 3), {"hp": 100, "max_hp": 100})
	var wing := builder.add_unit("impact_split_wing", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(3, 2), {"hp": 100, "max_hp": 100})
	builder.clear_slots(target).clear_slots(wing)
	var state := builder.finish()
	var result := CombatRules.ranged_attack(state, attacker, target.pos, CombatConfig.attack_range())
	var events: Array = result.get("events", [])
	_expect(target.hp == 88, "impact should keep full impact damage when split is suppressed")
	_expect(wing.hp == 100, "impact should not generate split wing hits")
	_expect(_events_of_type(events, "projectile").is_empty(), "impact plus split must not emit split projectiles")
	print("  [OK] red impact suppresses split")


func _test_red_flurry_repeats_complete_impacts() -> void:
	var builder = Builder.new("fission_slime_test", 9306, true)
	var attacker := builder.player()
	builder.move(attacker, Vector2i(0, 3)).clear_slots(attacker)
	builder.mount_gems(attacker, Constants.SLOT_RED, [Constants.GEM_IMPACT, Constants.GEM_IMPACT, Constants.GEM_FLURRY])
	var target := builder.add_unit("impact_flurry_target", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(3, 3), {"hp": 100, "max_hp": 100})
	builder.clear_slots(target)
	var state := builder.finish()
	var result := CombatRules.ranged_attack(state, attacker, target.pos, CombatConfig.attack_range())
	var events: Array = result.get("events", [])
	var charges := _events_of_type(events, "impact_charge")
	var damages := _events_of_type(events, "damage").filter(func(event): return str(event.get("uid", "")) == target.uid)
	_expect(charges.size() == 2, "flurry should replay one impact charge per damage segment")
	_expect(damages.size() == 2 and damages.all(func(event): return int(event.get("damage", 0)) == 4), "impact flurry should apply damage at both impact frames")
	_expect(attacker.pos == Vector2i(4, 3) and target.pos == Vector2i(7, 3), "each impact segment should chase and knock the displaced target")
	_expect(damages.size() == 2 and damages[0].get("pos") == Vector2i(3, 3) and damages[1].get("pos") == Vector2i(5, 3), "each segment damage should follow the target's current position")
	var first_damage_index := events.find(damages[0]) if damages.size() == 2 else -1
	var second_charge_index := events.find(charges[1]) if charges.size() == 2 else -1
	var displaced_between := events.slice(first_damage_index + 1, second_charge_index).any(func(event): return str(event.get("type", "")) == "move_step" and str(event.get("uid", "")) == target.uid)
	_expect(first_damage_index >= 0 and second_charge_index > first_damage_index and displaced_between, "first damage and knockback must finish before the second impact begins")
	_expect(_valid(state, events), "impact flurry should preserve battle invariants and event shape")
	print("  [OK] red flurry replays complete impact, damage, and knockback beats")


func _test_blue_launches_after_surviving_active_damage() -> void:
	for level in range(1, 4):
		var builder = Builder.new("fission_slime_test", 9310 + level, true)
		var attacker := builder.player()
		builder.move(attacker, Vector2i(1, 3)).clear_slots(attacker)
		var target := builder.add_unit("impact_blue_%d" % level, "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(2, 3), {"hp": 100, "max_hp": 100})
		builder.clear_slots(target)
		var gems: Array = []
		for _index in range(level):
			gems.append(Constants.GEM_IMPACT)
		builder.mount_gems(target, Constants.SLOT_BLUE, gems)
		var state := builder.finish()
		var result := AttackPipeline.execute(state, attacker, target, [AttackPipeline.TAG_MELEE])
		_expect(target.pos == Vector2i(3 + level, 3), "blue impact level %d should launch %d cells" % [level, level + 1])
		_expect(_valid(state, result.get("events", [])), "blue impact level %d should preserve battle invariants" % level)
	print("  [OK] blue impact launches only after survived active damage")


func _test_blue_ignores_self_collision_damage_and_skips_lethal_hits() -> void:
	var builder = Builder.new("fission_slime_test", 9321, true)
	var attacker := builder.player()
	builder.move(attacker, Vector2i(1, 3)).clear_slots(attacker)
	var target := builder.add_unit("impact_blue_collision", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(2, 3), {"hp": 100, "max_hp": 100})
	var blocker := builder.add_unit("impact_blue_blocker", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(5, 3), {"hp": 100, "max_hp": 100})
	builder.clear_slots(target).clear_slots(blocker)
	builder.mount_gems(target, Constants.SLOT_BLUE, [Constants.GEM_IMPACT, Constants.GEM_IMPACT])
	var state := builder.finish()
	var direct_damage := CombatRules.attack_damage(state, attacker)
	var result := AttackPipeline.execute(state, attacker, target, [AttackPipeline.TAG_MELEE])
	_expect(target.pos == Vector2i(4, 3), "blue impact should stop before a blocking unit")
	_expect(target.hp == 100 - direct_damage, "blue impact carrier should not take its own collision damage")
	_expect(blocker.hp < 100, "the blocking unit should still take normal collision damage")
	_expect(_valid(state, result.get("events", [])), "blue collision immunity should preserve invariants")

	builder = Builder.new("fission_slime_test", 9322, true)
	attacker = builder.player()
	builder.move(attacker, Vector2i(1, 3)).clear_slots(attacker)
	target = builder.add_unit("impact_blue_lethal", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(2, 3), {"hp": 1, "max_hp": 1})
	builder.clear_slots(target).mount_gems(target, Constants.SLOT_BLUE, [Constants.GEM_IMPACT])
	state = builder.finish()
	result = AttackPipeline.execute(state, attacker, target, [AttackPipeline.TAG_MELEE])
	_expect(not target.alive and target.pos == Vector2i(2, 3), "lethal active damage should not launch the dead carrier")
	_expect(_valid(state, result.get("events", [])), "lethal blue impact case should preserve invariants")
	print("  [OK] blue impact collision immunity and lethal-hit gate")


func _test_black_levels_and_gravity_merge() -> void:
	for level in range(1, 4):
		var builder = Builder.new("fission_slime_test", 9330 + level, true)
		var attacker := builder.player()
		builder.move(attacker, Vector2i(7, 7)).clear_slots(attacker)
		var owner := builder.add_unit("impact_black_owner_%d" % level, "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(1, 3), {"hp": 1, "max_hp": 1})
		var target := builder.add_unit("impact_black_target_%d" % level, "unit_patrol_guard", Constants.TEAM_PLAYER, Vector2i(2, 3), {"hp": 100, "max_hp": 100})
		builder.clear_slots(owner).clear_slots(target)
		var gems: Array = []
		for _index in range(level):
			gems.append(Constants.GEM_IMPACT)
		builder.mount_gems(owner, Constants.SLOT_BLACK, gems)
		var state := builder.finish()
		var events: Array[Dictionary] = []
		state.bind_combat_events(events)
		CombatRules.apply_damage(state, owner, 1, attacker.uid, "test_death")
		state.unbind_combat_events()
		_expect(target.pos == Vector2i(3 + level, 3), "black impact level %d should knock touching target %d cells" % [level, level + 1])
		_expect(_valid(state, events), "black impact level %d should preserve battle invariants" % level)

	var builder = Builder.new("fission_slime_test", 9340, true)
	var attacker := builder.player()
	builder.move(attacker, Vector2i(7, 7)).clear_slots(attacker)
	var owner := builder.add_unit("impact_gravity_owner", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(2, 3), {"hp": 1, "max_hp": 1})
	var touching := builder.add_unit("impact_gravity_touching", "unit_patrol_guard", Constants.TEAM_PLAYER, Vector2i(3, 3), {"hp": 100, "max_hp": 100})
	var gravity_only := builder.add_unit("impact_gravity_only", "unit_patrol_guard", Constants.TEAM_PLAYER, Vector2i(3, 2), {"hp": 100, "max_hp": 100})
	builder.clear_slots(owner).clear_slots(touching).clear_slots(gravity_only)
	builder.mount_gems(owner, Constants.SLOT_BLACK, [Constants.GEM_IMPACT, Constants.GEM_GRAVITY])
	var state := builder.finish()
	var events: Array[Dictionary] = []
	state.bind_combat_events(events)
	CombatRules.apply_damage(state, owner, 1, attacker.uid, "test_death")
	state.unbind_combat_events()
	var touching_moves := _events_of_type(events, "move_step").filter(func(event): return str(event.get("uid", "")) == touching.uid)
	_expect(touching.pos == Vector2i(4, 3), "impact 2 outward and gravity 1 inward should merge to one outward cell")
	_expect(touching_moves.size() == 1, "merged black death displacement should execute exactly once")
	_expect(gravity_only.pos == Vector2i(2, 2), "diagonal non-contact units should retain the gravity pull")
	_expect(_valid(state, events), "black impact and gravity merge should preserve invariants")
	print("  [OK] black impact levels and gravity merge")


func _test_enemy_impact_intent_executes_shared_pipeline() -> void:
	var builder = Builder.new("fission_slime_test", 9350, true)
	var player := builder.player()
	builder.move(player, Vector2i(5, 3)).clear_slots(player)
	var enemy := builder.add_unit("impact_enemy", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(1, 3), {"base_attack": 6})
	builder.clear_slots(enemy).mount_gems(enemy, Constants.SLOT_RED, [Constants.GEM_IMPACT])
	var state := builder.finish()
	var meta := GemEffects.get_enemy_red_intent_meta(Constants.GEM_IMPACT, enemy.base_attack)
	_expect(str(meta.get("type", "")) == "impact_attack", "impact gem should register an enemy impact intent")
	enemy.intent = IntentState.new()
	enemy.intent.source_uid = enemy.uid
	enemy.intent.type = "impact_attack"
	enemy.intent.target_uid = player.uid
	var events := IntentSystem.execute_intent(state, enemy)
	_expect(enemy.pos == Vector2i(4, 3), "enemy impact intent should dash into contact")
	_expect(not _events_of_type(events, "damage").is_empty(), "enemy impact intent should deal damage through the shared attack pipeline")
	_expect(_valid(state, events), "enemy impact intent should preserve invariants")
	print("  [OK] enemy impact intent uses the shared pipeline")


func _events_of_type(events: Array, event_type: String) -> Array:
	return events.filter(func(event): return str(event.get("type", "")) == event_type)


func _valid(state: GameState, events: Array) -> bool:
	return BattleInvariantChecker.check_all(state).is_empty() and EventValidator.validate_events(events).is_empty()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
