extends SceneTree

const Builder = preload("res://scripts/testkit/scenario_builder.gd")
const GemTransfer = preload("res://scripts/rules/gem_transfer.gd")
const RollingArmadilloRules = preload("res://scripts/rules/rolling_armadillo_rules.gd")
const PresentationPlanner = preload("res://scripts/ui/battle_presentation_planner.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	_test_definition_and_normal_long_impact()
	_test_close_range_repositions_then_impacts()
	_test_lawless_roll_drops_a_collided_gem()
	_test_lawless_reposition_and_roll_are_separate_beats()
	if _failed:
		quit(1)
	print("ROLLING_ARMADILLO_TEST_PASS")
	quit()


func _test_definition_and_normal_long_impact() -> void:
	var registry: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	var unit_def: Dictionary = registry.get_unit_def("unit_rolling_armadillo")
	_expect(unit_def.get("max_hp") == 18, "rolling armadillo should have 18 HP")
	_expect(unit_def.get("move_points") == 2 and unit_def.get("base_attack") == 4, "base move and attack should match design")
	_expect(unit_def.get("spawn_gem_slots", ["unexpected"]).is_empty(), "blue and black slots should stay empty on spawn")
	var slots: Array = unit_def.get("slots", [])
	_expect(slots.size() == 3 and slots[0].get("gem_id", "") == Constants.GEM_IMPACT, "red slot should carry fixed impact")

	var builder := Builder.new("fission_slime_test", 12001, true)
	var player := builder.player()
	builder.move(player, Vector2i(6, 3))
	var beast := builder.add_unit("rolling_normal", "unit_rolling_armadillo", Constants.TEAM_ENEMY, Vector2i(3, 3))
	builder.mount_gems(beast, Constants.SLOT_RED, [Constants.GEM_IMPACT])
	var state := builder.finish()
	IntentSystem.refresh_unit_intent(state, beast)
	_expect(beast.intent.type == "impact_attack", "an aligned target at distance 3 should be impacted immediately")
	_expect(beast.intent.path.is_empty(), "a high-value impact from the current cell should not reposition first")
	var events := IntentSystem.execute_intent(state, beast)
	_expect(beast.pos == Vector2i(5, 3), "normal impact should roll until adjacent to the target")
	_expect(player.hp == player.max_hp - 6, "distance-3 impact should deal ATK plus two moved cells")
	_expect(_valid(state, events), "normal rolling impact should preserve battle and event invariants")
	print("  [OK] rolling armadillo definition and long impact")


func _test_close_range_repositions_then_impacts() -> void:
	var builder := Builder.new("fission_slime_test", 12002, true)
	var player := builder.player()
	builder.move(player, Vector2i(4, 3))
	var beast := builder.add_unit("rolling_retreat", "unit_rolling_armadillo", Constants.TEAM_ENEMY, Vector2i(3, 3))
	builder.mount_gems(beast, Constants.SLOT_RED, [Constants.GEM_IMPACT])
	var state := builder.finish()
	IntentSystem.refresh_unit_intent(state, beast)
	_expect(beast.intent.type == "impact_attack", "a close target should still produce an impact action")
	_expect(beast.intent.path == [Vector2i(2, 3), Vector2i(1, 3)], "the beast should back off to distance 3 before attacking")
	var events := IntentSystem.execute_intent(state, beast)
	_expect(beast.pos == Vector2i(3, 3), "the beast should roll back beside the target after taking distance")
	_expect(player.hp == player.max_hp - 6, "repositioned impact should use the new two-cell roll distance")
	_expect(_valid(state, events), "retreat-and-impact should preserve battle and event invariants")
	print("  [OK] rolling armadillo controls close range before impacting")


func _test_lawless_roll_drops_a_collided_gem() -> void:
	var registry: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	var builder := Builder.new("fission_slime_test", 12003, true)
	var player := builder.player()
	builder.move(player, Vector2i(4, 3))
	var beast := builder.add_unit("rolling_lawless", "unit_rolling_armadillo", Constants.TEAM_ENEMY, Vector2i(1, 3))
	builder.mount_gems(beast, Constants.SLOT_RED, [Constants.GEM_IMPACT])
	var state := builder.finish()
	var player_slot := player.get_slot(Constants.SLOT_BLUE)
	var loose_gem: GemState = registry.create_gem_instance("rolling_drop_gem", Constants.GEM_FLURRY, {})
	state.gems[loose_gem.uid] = loose_gem
	_expect(GemTransfer.to_unit_slot(state, loose_gem, player, player_slot), "fixture gem should mount on the player")
	var red_slot := beast.get_slot(Constants.SLOT_RED)
	var red_gem: GemState = state.gems.get(red_slot.gem_uid, null)
	GemTransfer.detach(state, red_gem)
	BehaviorRegistry.get_behavior(beast.behavior_id).on_gem_extracted(
		state, beast, Constants.SLOT_RED, red_gem.uid
	)
	_expect(StatusRules.is_lawless(beast), "removing fixed impact should make the beast lawless")
	_expect(beast.base_attack == 6 and beast.move_points == 3, "lawless should grant +2 ATK and +1 move")
	IntentSystem.refresh_unit_intent(state, beast)
	_expect(beast.intent.type == "rolling_uncontrolled", "an aligned lawless beast should plan an uncontrolled roll")
	var events := IntentSystem.execute_intent(state, beast)
	_expect(not _events_of_type(events, "impact_charge").is_empty(), "an uncontrolled roll should declare a dedicated impact action after any line-up movement")
	_expect(state.dropped_gems.has(loose_gem.uid), "the collided player should lose one random slotted gem")
	_expect(state.dropped_gems[loose_gem.uid].get("pos") == player.pos, "the knocked-loose gem should land on the contact tile")
	_expect(_events_of_type(events, "displacement_impact").size() == 1, "the roll should expose one unit collision")
	_expect(_events_of_type(events, "damage").size() >= 3, "collision should damage both units before the adjacent ordinary attack")
	_expect(_valid(state, events), "lawless roll and gem drop should preserve battle and event invariants")
	print("  [OK] lawless uncontrolled roll collides, attacks, and drops a gem")


func _test_lawless_reposition_and_roll_are_separate_beats() -> void:
	var builder := Builder.new("fission_slime_test", 12004, true)
	var player := builder.player()
	builder.move(player, Vector2i(5, 3))
	var beast := builder.add_unit("rolling_lawless_path", "unit_rolling_armadillo", Constants.TEAM_ENEMY, Vector2i(1, 1))
	builder.mount_gems(beast, Constants.SLOT_RED, [Constants.GEM_IMPACT])
	var state := builder.finish()
	var red_slot := beast.get_slot(Constants.SLOT_RED)
	var red_gem: GemState = state.gems.get(red_slot.gem_uid, null)
	GemTransfer.detach(state, red_gem)
	BehaviorRegistry.get_behavior(beast.behavior_id).on_gem_extracted(state, beast, Constants.SLOT_RED, red_gem.uid)
	IntentSystem.refresh_unit_intent(state, beast)
	_expect(beast.intent.type == "rolling_uncontrolled" and not beast.intent.path.is_empty(), "lawless fixture should select a line before rolling")
	var events := IntentSystem.execute_intent(state, beast)
	var charge_index := -1
	for index in range(events.size()):
		if str(events[index].get("type", "")) == "impact_charge":
			charge_index = index
			break
	_expect(charge_index > 0 and events.slice(0, charge_index).all(func(event): return str(event.get("type", "")) == "move_step"), "ordinary line-up movement must finish before the roll action starts")
	var plan := PresentationPlanner.build(events)
	var beats: Array = plan.get("beats", [])
	_expect(beats.size() >= 2 and beats[0].get("kind", "") == "move" and beats[1].get("kind", "") == "impact", "line-up movement should animate as one normal path, followed by one impact beat")
	_expect(plan.get("violations", []).is_empty(), "lawless roll events should all have declared presentation policies")
	_expect(_valid(state, events), "separated lawless movement and impact should preserve invariants")
	print("  [OK] lawless line-up movement and roll use separate animation beats")


func _events_of_type(events: Array, event_type: String) -> Array:
	return events.filter(func(event): return str(event.get("type", "")) == event_type)


func _valid(state: GameState, events: Array) -> bool:
	return BattleInvariantChecker.check_all(state).is_empty() \
		and EventValidator.validate_events(events).is_empty()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
