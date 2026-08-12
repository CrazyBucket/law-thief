extends SceneTree

const ScenarioBuilder = preload("res://scripts/testkit/scenario_builder.gd")
const FightTicketRules = preload("res://scripts/rules/fight_ticket_rules.gd")
const EventValidator = preload("res://scripts/debug/event_validator.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Fight Ticket Relic Test ===")
	root.get_node("AdventureService").start_new_run(20260813)
	root.get_node("AdventureService").pending_room_type = "NORMAL_COMBAT"
	_force_relic()
	_test_definition()
	_test_enemy_damage_marks_and_executes_one_retaliation()
	_test_invalid_damage_sources_and_shield_do_not_trigger()
	_test_true_damage_with_enemy_source_triggers()
	_test_source_death_restores_normal_intent()
	_test_non_attack_turn_preserves_retaliation()
	_test_special_enemy_uses_priority_target_entry()
	root.get_node("RunService").end_run()
	if _failed:
		push_error("FIGHT_TICKET_RELIC_TEST_FAIL")
		quit(1)
		return
	print("FIGHT_TICKET_RELIC_TEST_PASS")
	quit(0)


func _test_definition() -> void:
	var relic_def: Dictionary = root.get_node("DataRegistry").get_relic_def("relic_beast_ticket")
	_expect(str(relic_def.get("rarity", "")) == "rare", "fight ticket should be rare")
	_expect(bool(relic_def.get("unique", false)), "fight ticket should be unique")
	_expect((relic_def.get("effects", []) as Array).size() == 2, "fight ticket should own damage and death effects")
	print("  [OK] definition is rare and unique")


func _test_enemy_damage_marks_and_executes_one_retaliation() -> void:
	var fixture := _battle_fixture(41)
	var state: GameState = fixture["state"]
	var victim: UnitState = fixture["victim"]
	var source: UnitState = fixture["source"]
	var controller: BattleController = fixture["controller"]
	CombatRules.apply_damage(state, victim, 2, source.uid, "enemy_friendly_fire")
	_expect(state.relic_battle.beast_ticket_triggered, "first enemy friendly-fire life damage should trigger")
	_expect(state.relic_battle.retaliation_targets.get(victim.uid) == source.uid, "victim should remember the enemy source")
	_expect(victim.intent.target_uid == source.uid, "retaliation intent should point at the source")
	_expect(bool(victim.intent.plan_metadata.get(FightTicketRules.META_RETALIATION, false)), "retaliation intent should carry explicit metadata")
	_expect("报复" in victim.intent.preview_text, "retaliation preview should be visible to the player")
	var source_hp := source.hp
	var execution := controller.execute_single_enemy(victim)
	_expect(source.hp < source_hp, "victim should damage the source with its existing attack")
	_expect(not state.relic_battle.retaliation_targets.has(victim.uid), "active retaliation attack should consume the target")
	_expect(EventValidator.validate_events(execution.get("events", [])).is_empty(), "retaliation action events should stay valid")
	IntentSystem.refresh_unit_intent(state, victim)
	_expect(victim.intent.target_uid == state.player_uid, "victim should return to normal player targeting")
	CombatRules.apply_damage(state, victim, 1, source.uid, "second_enemy_friendly_fire")
	_expect(not state.relic_battle.retaliation_targets.has(victim.uid), "fight ticket must not trigger twice in one battle")
	_expect(BattleInvariantChecker.check_all(state).is_empty(), "retaliation should preserve battle invariants")
	print("  [OK] first friendly fire causes exactly one active retaliation")


func _test_invalid_damage_sources_and_shield_do_not_trigger() -> void:
	var fixture := _battle_fixture(42)
	var state: GameState = fixture["state"]
	var victim: UnitState = fixture["victim"]
	var source: UnitState = fixture["source"]
	StatusRules.apply_shield(state, victim, 4, 2)
	CombatRules.apply_damage(state, victim, 4, source.uid, "shield_only")
	_expect(not state.relic_battle.beast_ticket_triggered, "shield-only damage must not trigger")
	CombatRules.apply_damage(state, victim, 1, victim.uid, "self_damage")
	CombatRules.apply_damage(state, victim, 1, state.player_uid, "player_damage")
	CombatRules.apply_damage(state, victim, 1, "", "environment_damage")
	_expect(not state.relic_battle.beast_ticket_triggered, "self, player, and sourceless damage must not trigger")
	print("  [OK] invalid sources and shield absorption are ignored")


func _test_true_damage_with_enemy_source_triggers() -> void:
	var fixture := _battle_fixture(43)
	var state: GameState = fixture["state"]
	var victim: UnitState = fixture["victim"]
	var source: UnitState = fixture["source"]
	CombatRules.apply_true_damage(state, victim, 2, source.uid, "burning")
	_expect(state.relic_battle.retaliation_targets.get(victim.uid) == source.uid, "enemy-sourced burning should trigger through true damage")
	print("  [OK] enemy-sourced status damage uses the same trigger boundary")


func _test_source_death_restores_normal_intent() -> void:
	var fixture := _battle_fixture(44)
	var state: GameState = fixture["state"]
	var victim: UnitState = fixture["victim"]
	var source: UnitState = fixture["source"]
	CombatRules.apply_damage(state, victim, 2, source.uid, "enemy_friendly_fire")
	CombatRules.apply_damage(state, source, source.hp, state.player_uid, "remove_retaliation_source")
	_expect(not state.relic_battle.retaliation_targets.has(victim.uid), "dead source should clear pending retaliation")
	_expect(victim.intent.target_uid == state.player_uid, "source death should immediately restore normal intent")
	print("  [OK] dead retaliation source falls back to normal AI")


func _test_non_attack_turn_preserves_retaliation() -> void:
	var fixture := _battle_fixture(45, "unit_patrol_guard", Vector2i(5, 5), Vector2i(1, 5))
	var state: GameState = fixture["state"]
	var victim: UnitState = fixture["victim"]
	var source: UnitState = fixture["source"]
	StatusRules.apply_rooted(state, victim, 2, source.uid)
	CombatRules.apply_damage(state, victim, 1, source.uid, "enemy_friendly_fire")
	_expect(not IntentSystem.is_attack_intent(victim.intent.type), "rooted distant victim should not invent an attack")
	fixture["controller"].execute_single_enemy(victim)
	_expect(state.relic_battle.retaliation_targets.get(victim.uid) == source.uid, "move, wait, or control skip should not consume retaliation")
	print("  [OK] non-attack action preserves the pending retaliation")


func _test_special_enemy_uses_priority_target_entry() -> void:
	var fixture := _battle_fixture(46, "unit_rolling_armadillo")
	var state: GameState = fixture["state"]
	var victim: UnitState = fixture["victim"]
	var source: UnitState = fixture["source"]
	CombatRules.apply_damage(state, victim, 1, source.uid, "enemy_friendly_fire")
	_expect(victim.intent != null, "special enemy should generate a retaliation intent")
	_expect(victim.intent.target_uid == source.uid, "special enemy retaliation should still point at the source")
	_expect(bool(victim.intent.plan_metadata.get(FightTicketRules.META_RETALIATION, false)), "special enemy intent should carry retaliation metadata")
	print("  [OK] special behavior inherits the priority-target entry")


func _battle_fixture(
	seed: int,
	victim_def_id: String = "unit_patrol_guard",
	victim_pos: Vector2i = Vector2i(3, 3),
	source_pos: Vector2i = Vector2i(4, 3)
) -> Dictionary:
	var builder := ScenarioBuilder.new("template_a", seed, true)
	var player := builder.player()
	builder.move(player, Vector2i(2, 3))
	builder.clear_slots(player)
	var victim := builder.add_unit("ticket_victim", victim_def_id, Constants.TEAM_ENEMY, victim_pos, {
		"hp": 30, "max_hp": 30,
	})
	var source := builder.add_unit("ticket_source", "unit_patrol_guard", Constants.TEAM_ENEMY, source_pos, {
		"hp": 30, "max_hp": 30,
	})
	builder.clear_slots(victim)
	builder.clear_slots(source)
	var state := builder.finish()
	state.phase = Constants.PHASE_PLAYER
	var controller := BattleController.new()
	controller.state = state
	controller.selected_unit_uid = state.player_uid
	controller._connect_relic_signals(state)
	IntentSystem.refresh_all_intents(state)
	return {"state": state, "victim": victim, "source": source, "controller": controller}


func _force_relic() -> void:
	var run: RunState = root.get_node("RunService").get_run()
	run.owned_relics.clear()
	run.owned_relics.append("relic_beast_ticket")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error(message)
