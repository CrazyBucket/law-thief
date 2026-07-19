extends SceneTree

const Builder = preload("res://scripts/testkit/scenario_builder.gd")
const _GemTransfer = preload("res://scripts/rules/gem_transfer.gd")
const _PresentationPlanner = preload("res://scripts/ui/battle_presentation_planner.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Flurry And Ruffled Crow Test ===")
	_test_red_flurry_scales_by_count()
	_test_flurry_triggers_split_wings_per_segment()
	_test_split_elemental_tags_stay_single_volley()
	_test_blue_stored_flurry_triggers_once_and_is_consumed()
	_test_remaining_segments_stop_on_death()
	_test_ruffled_crow_normal_and_disorder_attacks()
	if _failed:
		push_error("FLURRY_AND_RUFFLED_CROW_TEST_FAIL")
		quit(1)
		return
	print("FLURRY_AND_RUFFLED_CROW_TEST_PASS")
	quit(0)


func _test_red_flurry_scales_by_count() -> void:
	var builder = Builder.new("fission_slime_test", 9101, true)
	var attacker := builder.player()
	builder.clear_slots(attacker)
	builder.mount_gems(attacker, Constants.SLOT_RED, [
		Constants.GEM_FLURRY,
		Constants.GEM_FLURRY,
		Constants.GEM_FLURRY,
		Constants.GEM_FLURRY,
	])
	var target := builder.add_unit("flurry_target", "unit_patrol_guard", Constants.TEAM_ENEMY, attacker.pos + Vector2i(1, 0), {"hp": 100, "max_hp": 100})
	var state := builder.finish()
	var result := AttackPipeline.execute(state, attacker, target, [AttackPipeline.TAG_MELEE])
	var damage_events := _events_of_type(result.get("events", []), "damage")
	_expect(result.get("ok", false), "red flurry attack should execute")
	_expect(damage_events.size() == 5, "four red gems should turn one hit into five")
	_expect(damage_events.all(func(event): return int(event.get("damage", 0)) == 2), "five segments should each deal 20% of base damage")
	_expect(target.hp == 90, "five segments should preserve 100% total damage at X=4")
	_expect(_valid(state, result.get("events", [])), "red flurry should preserve invariants")
	print("  [OK] red flurry count, decay, and per-segment events")


func _test_flurry_triggers_split_wings_per_segment() -> void:
	var builder = Builder.new("fission_slime_test", 9106, true)
	var attacker := builder.player()
	builder.clear_slots(attacker)
	builder.mount_gems(attacker, Constants.SLOT_RED, [Constants.GEM_FLURRY, Constants.GEM_SPLIT])
	var main_target := builder.add_unit("flurry_split_main", "unit_patrol_guard", Constants.TEAM_ENEMY, attacker.pos + Vector2i(1, 0), {"hp": 100, "max_hp": 100})
	var wing_a := builder.add_unit("flurry_split_wing_a", "unit_patrol_guard", Constants.TEAM_ENEMY, attacker.pos + Vector2i(0, 1), {"hp": 100, "max_hp": 100})
	var wing_b := builder.add_unit("flurry_split_wing_b", "unit_patrol_guard", Constants.TEAM_ENEMY, attacker.pos + Vector2i(0, -1), {"hp": 100, "max_hp": 100})
	var state := builder.finish()
	var result := AttackPipeline.execute(state, attacker, main_target, [AttackPipeline.TAG_RANGED])
	var damage_events := _events_of_type(result.get("events", []), "damage")
	var projectile_events := _events_of_type(result.get("events", []), "projectile")
	var events: Array = result.get("events", [])
	_expect(result.get("ok", false), "flurry plus split attack should execute")
	_expect(damage_events.size() == 6, "two flurry segments should each resolve the main split shot and both wings")
	_expect(projectile_events.size() == 6, "each flurry segment should emit its own three split projectiles")
	_expect(events.slice(0, 3).all(func(event): return str(event.get("type", "")) == "projectile"), "the first split segment should begin with one three-shot volley")
	var second_volley_start := -1
	for index in range(3, events.size() - 2):
		if events.slice(index, index + 3).all(func(event): return str(event.get("type", "")) == "projectile"):
			second_volley_start = index
			break
	_expect(second_volley_start > 3, "the second three-shot volley should wait until the first segment resolves")
	var plan := _PresentationPlanner.build(events)
	var projectile_beats: Array = plan.get("beats", []).filter(func(beat): return str(beat.get("kind", "")) == "projectile")
	_expect(plan.get("violations", []).is_empty(), "flurry plus split events should have valid presentation policies")
	_expect(projectile_beats.size() == 2 and projectile_beats.all(func(beat): return beat.get("visuals", []).size() == 3), "presentation should play two separate three-shot volleys")
	_expect(damage_events.all(func(event): return int(event.get("damage", 0)) == 2), "flurry decay should apply before every split projectile deals damage")
	_expect(main_target.hp == 96 and wing_a.hp == 96 and wing_b.hp == 96, "every split target should be hit once by each flurry segment")
	for target_uid in [main_target.uid, wing_a.uid, wing_b.uid]:
		var target_events := damage_events.filter(func(event): return str(event.get("uid", "")) == target_uid)
		_expect(target_events.map(func(event): return int(event.get("segment_index", -1))) == [0, 1], "split hits should retain their originating flurry segment indices")
	_expect(_valid(state, result.get("events", [])), "flurry plus split should preserve invariants")
	print("  [OK] flurry segments each trigger split wings")


func _test_split_elemental_tags_stay_single_volley() -> void:
	for spec in [
		{"gem_id": Constants.GEM_EXPLOSION, "effect_event": "explode", "label": "explosion"},
		{"gem_id": Constants.GEM_POISON, "effect_event": "poison_burst", "label": "poison"},
	]:
		var builder = Builder.new("fission_slime_test", 9107 + int(str(spec.label).hash() & 255), true)
		var attacker := builder.player()
		builder.clear_slots(attacker)
		builder.mount_gems(attacker, Constants.SLOT_RED, [Constants.GEM_SPLIT, str(spec.gem_id)])
		var target := builder.add_unit("split_%s_main" % spec.label, "unit_patrol_guard", Constants.TEAM_ENEMY, attacker.pos + Vector2i(1, 0), {"hp": 100, "max_hp": 100})
		builder.add_unit("split_%s_wing_a" % spec.label, "unit_patrol_guard", Constants.TEAM_ENEMY, attacker.pos + Vector2i(0, 1), {"hp": 100, "max_hp": 100})
		builder.add_unit("split_%s_wing_b" % spec.label, "unit_patrol_guard", Constants.TEAM_ENEMY, attacker.pos + Vector2i(0, -1), {"hp": 100, "max_hp": 100})
		var state := builder.finish()
		var result := AttackPipeline.execute(state, attacker, target, [AttackPipeline.TAG_RANGED])
		var events: Array = result.get("events", [])
		var plan := _PresentationPlanner.build(events)
		var projectile_beats: Array = plan.get("beats", []).filter(func(beat): return str(beat.get("kind", "")) == "projectile")
		_expect(result.get("ok", false), "split plus %s attack should execute" % spec.label)
		_expect(_events_of_type(events, "projectile").size() == 3, "split plus %s should emit exactly three projectiles" % spec.label)
		_expect(events.slice(0, 3).all(func(event): return str(event.get("type", "")) == "projectile"), "split plus %s should place all three projectiles in one leading volley" % spec.label)
		_expect(projectile_beats.size() == 1 and projectile_beats[0].get("visuals", []).size() == 3, "split plus %s should animate as one simultaneous three-shot volley" % spec.label)
		_expect(not _events_of_type(events, str(spec.effect_event)).is_empty(), "split plus %s should retain its elemental hit effects" % spec.label)
		_expect(_valid(state, events) and plan.get("violations", []).is_empty(), "split plus %s presentation should preserve invariants" % spec.label)
	print("  [OK] split plus explosion/poison stay single three-shot volleys")


func _test_blue_stored_flurry_triggers_once_and_is_consumed() -> void:
	var builder = Builder.new("fission_slime_test", 9102, true)
	var attacker := builder.player()
	builder.clear_slots(attacker)
	builder.mount_gems(attacker, Constants.SLOT_RED, [Constants.GEM_FLURRY, Constants.GEM_FLURRY])
	var target := builder.add_unit("stored_target", "unit_patrol_guard", Constants.TEAM_ENEMY, attacker.pos + Vector2i(1, 0), {"hp": 100, "max_hp": 100})
	builder.clear_slots(target)
	builder.mount_gems(target, Constants.SLOT_BLUE, [Constants.GEM_FLURRY, Constants.GEM_FLURRY, Constants.GEM_FLURRY])
	var state := builder.finish()
	var first := AttackPipeline.execute(state, attacker, target, [AttackPipeline.TAG_MELEE])
	_expect(_events_of_type(first.get("events", []), "damage").size() == 3, "X=2 should produce three damage segments")
	_expect(FlurryRules.stored(target) == 3, "three blue gems should grant three stored flurry once for the whole attack")
	var second := AttackPipeline.execute(state, target, attacker, [AttackPipeline.TAG_MELEE])
	_expect(_events_of_type(second.get("events", []), "damage").size() == 4, "stored flurry 3 should turn the next attack into four segments")
	_expect(FlurryRules.stored(target) == 0, "stored flurry should clear after the active attack")
	_expect(_valid(state, first.get("events", [])) and EventValidator.validate_events(second.get("events", [])).is_empty(), "stored flurry should preserve invariants")
	print("  [OK] blue stored flurry is attack-scoped and consumed")


func _test_remaining_segments_stop_on_death() -> void:
	var builder = Builder.new("fission_slime_test", 9103, true)
	var attacker := builder.player()
	builder.clear_slots(attacker)
	builder.mount_gems(attacker, Constants.SLOT_RED, [Constants.GEM_FLURRY, Constants.GEM_FLURRY, Constants.GEM_FLURRY, Constants.GEM_FLURRY])
	var target := builder.add_unit("fragile_target", "unit_patrol_guard", Constants.TEAM_ENEMY, attacker.pos + Vector2i(1, 0), {"hp": 3, "max_hp": 3})
	var state := builder.finish()
	var result := AttackPipeline.execute(state, attacker, target, [AttackPipeline.TAG_MELEE])
	_expect(_events_of_type(result.get("events", []), "damage").size() == 2, "remaining flurry segments should stop when the target dies")
	_expect(not target.alive, "the second segment should kill the target")
	_expect(_valid(state, result.get("events", [])), "death during flurry should preserve invariants")
	print("  [OK] target death terminates remaining segments")


func _test_ruffled_crow_normal_and_disorder_attacks() -> void:
	var registry: Node = root.get_node("DataRegistry")
	var unit_def: Dictionary = registry.get_unit_def("unit_ruffled_crow")
	var fixed_slot: Dictionary = unit_def.get("slots", [])[0]
	_expect(str(fixed_slot.get("gem_id", "")) == Constants.GEM_FLURRY, "ruffled crow definition should fix flurry in its red slot")
	var builder = Builder.new("fission_slime_test", 9104, true)
	var player := builder.player()
	builder.move(player, Vector2i(2, 3))
	var crow := builder.add_unit("ruffled_normal", "unit_ruffled_crow", Constants.TEAM_ENEMY, Vector2i(3, 3))
	builder.mount_gems(crow, Constants.SLOT_RED, [Constants.GEM_FLURRY])
	var state := builder.finish()
	_expect(crow != null, "ruffled crow should spawn")
	_expect(crow.max_hp == 16 and crow.base_attack == 6 and crow.move_points == 3, "ruffled crow base stats should match design")
	var red_slot := crow.get_slot(Constants.SLOT_RED)
	var red_gem: GemState = state.gems.get(red_slot.gem_uid, null)
	_expect(red_gem != null and red_gem.gem_id == Constants.GEM_FLURRY, "ruffled crow should carry one fixed red flurry gem")
	IntentSystem.refresh_unit_intent(state, crow)
	var normal_events := IntentSystem.execute_intent(state, crow)
	_expect(_events_of_type(normal_events, "damage").size() + _events_of_type(normal_events, "miss").size() == 2, "normal crow attack should resolve two independent segments")
	_expect(_events_of_type(normal_events, "damage").all(func(event): return int(event.get("damage", 0)) == 2), "normal crow segments should deal 40% damage")

	builder = Builder.new("fission_slime_test", 9105, true)
	player = builder.player()
	builder.move(player, Vector2i(2, 3))
	crow = builder.add_unit("ruffled_disorder", "unit_ruffled_crow", Constants.TEAM_ENEMY, Vector2i(3, 3))
	builder.mount_gems(crow, Constants.SLOT_RED, [Constants.GEM_FLURRY])
	state = builder.finish()
	var player_blue := player.get_slot(Constants.SLOT_BLUE)
	var blue_gem: GemState = registry.create_gem_instance("ruffled_test_blue", Constants.GEM_FLURRY, {})
	state.gems[blue_gem.uid] = blue_gem
	_GemTransfer.to_unit_slot(state, blue_gem, player, player_blue)
	red_slot = crow.get_slot(Constants.SLOT_RED)
	red_gem = state.gems.get(red_slot.gem_uid, null)
	_GemTransfer.detach(state, red_gem)
	BehaviorRegistry.get_behavior(crow.behavior_id).on_gem_extracted(state, crow, Constants.SLOT_RED, red_gem.uid)
	_expect(StatusRules.is_lawless(crow), "removing the red flurry gem should disorder the crow")
	BehaviorRegistry.get_behavior(crow.behavior_id).on_turn_start(state, crow)
	CombatRules.apply_damage(state, crow, 1, player.uid, "test_hit")
	CombatRules.apply_damage(state, crow, 1, player.uid, "test_hit")
	_expect(RuffledCrowRules.feathers(crow) == 3, "turn start and two damage instances should grant three startled feathers")
	crow.intent = IntentState.new()
	crow.intent.type = "melee_attack"
	crow.intent.target_uid = player.uid
	var disorder_events := IntentSystem.execute_intent(state, crow)
	var landed := _events_of_type(disorder_events, "damage").size()
	var missed := _events_of_type(disorder_events, "miss").size()
	_expect(landed + missed == 4, "three feathers should create four disorder attacks")
	_expect(_events_of_type(disorder_events, "damage").all(func(event): return int(event.get("damage", 0)) == 2), "each disorder attack should deal 40% damage")
	_expect(FlurryRules.stored(player) == landed, "each landed disorder attack should independently trigger the target blue slot")
	_expect(RuffledCrowRules.feathers(crow) == 1, "feathers should halve after the attack")
	_expect(_valid(state, disorder_events), "ruffled crow disorder attack should preserve invariants")
	print("  [OK] ruffled crow normal and disorder loops")


func _events_of_type(events: Array, event_type: String) -> Array:
	return events.filter(func(event): return str(event.get("type", "")) == event_type)


func _valid(state: GameState, events: Array) -> bool:
	return BattleInvariantChecker.check_all(state).is_empty() and EventValidator.validate_events(events).is_empty()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
