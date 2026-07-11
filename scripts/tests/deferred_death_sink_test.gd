extends SceneTree

const EventValidator = preload("res://scripts/debug/event_validator.gd")
const ScenarioBuilder = preload("res://scripts/testkit/scenario_builder.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_deferred_death_sink_keeps_events()
	_test_lethal_gem_tags_reach_immediate_and_deferred_black_light()
	_test_wall_collision_preserves_lethal_damage_tags()
	_test_forced_pass_through_spike_uses_collision_value_and_context()
	_test_forced_landing_spike_triggers_once()
	print("DEFERRED_DEATH_SINK_TEST_PASS")
	quit()


func _test_deferred_death_sink_keeps_events() -> void:
	var reg: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	var state: GameState = reg.create_battle_state("fission_slime_test", 42)
	var victim := UnitState.new()
	victim.uid = "victim"
	victim.unit_def_id = "unit_patrol_guard"
	victim.team = Constants.TEAM_ENEMY
	victim.pos = Vector2i(3, 3)
	victim.hp = 1
	victim.max_hp = 20
	victim.alive = true
	for slot_type in [Constants.SLOT_RED, Constants.SLOT_BLUE, Constants.SLOT_BLACK]:
		var slot := SlotState.new()
		slot.slot_type = slot_type
		victim.slots.append(slot)
	state.register_unit(victim)
	var gem := GemState.new()
	gem.uid = "explosion_gem"
	gem.gem_id = Constants.GEM_EXPLOSION
	state.gems[gem.uid] = gem
	victim.get_slot(Constants.SLOT_BLACK).gem_uid = gem.uid
	var events: Array[Dictionary] = []
	CombatRules.begin_deferred_death_hooks(events)
	CombatRules.apply_damage(state, victim, 10, "player", "test")
	CombatRules.end_deferred_death_hooks(state)
	var types: Array[String] = []
	for ev in events:
		types.append(str(ev.get("type", "")))
	print("DEFERRED_DEATH_SINK types=%s" % ", ".join(types))
	assert(types.has("explode"), "expected explode in deferred sink")


func _test_lethal_gem_tags_reach_immediate_and_deferred_black_light() -> void:
	_clear_run_relics()
	for use_deferred_pipeline in [false, true]:
		var builder := ScenarioBuilder.new("fission_slime_test", 3600 + int(use_deferred_pipeline), true)
		var attacker := builder.player()
		builder.clear_slots(attacker)
		builder.move(attacker, Vector2i(2, 3))
		builder.set_stats(attacker, {"base_attack": 20})
		builder.mount_gems(attacker, Constants.SLOT_RED, [Constants.GEM_FIRE, Constants.GEM_POISON])
		var victim := builder.add_unit(
			"lethal_context_victim_%s" % str(use_deferred_pipeline),
			"unit_patrol_guard",
			Constants.TEAM_ENEMY,
			Vector2i(3, 3),
			{"hp": 1, "max_hp": 20}
		)
		builder.clear_slots(victim)
		builder.mount_gems(victim, Constants.SLOT_BLACK, [Constants.GEM_LIGHT])
		var exposed_target := builder.add_unit(
			"lethal_context_exposed_%s" % str(use_deferred_pipeline),
			"unit_patrol_guard",
			Constants.TEAM_ENEMY,
			Vector2i(5, 3),
			{"hp": 100, "max_hp": 100}
		)
		builder.clear_slots(exposed_target)
		var state := builder.finish()
		StatusRules.apply_light_exposed(state, exposed_target, 1, victim.uid)
		var events: Array[Dictionary] = []
		if use_deferred_pipeline:
			var result := CombatRules.melee_attack(state, attacker, victim)
			assert(result.get("ok", false), "deferred tagged attack should execute")
			events = result.get("events", [])
		else:
			var gem_ctx := GemTagResolver.build_context(
				state,
				attacker,
				Constants.SLOT_RED,
				GemEffects.TIMING_ACTIVE
			)
			var tx := CombatTransaction.begin(state, events)
			tx.damage_unit(victim, 20, attacker.uid, "melee_attack", {
				"gem_tag_context": gem_ctx,
			})
			tx.finish("deferred_death_sink.immediate_context")
		assert(not victim.alive, "tagged lethal damage should defeat the black-light owner")
		var black_light_events := events.filter(func(event: Dictionary) -> bool:
			return str(event.get("type", "")) == "light_beam" \
				and str(event.get("source_uid", "")) == victim.uid
		)
		assert(black_light_events.size() == 1, "black light should observe one exposed target")
		assert(
			black_light_events[0].get("damage_tags", []) == ["fire", "poison"],
			"black light should receive the lethal attack's canonical gem tags"
		)
		var lethal_damage_events := events.filter(func(event: Dictionary) -> bool:
			return str(event.get("type", "")) == "damage" \
				and str(event.get("uid", "")) == victim.uid \
				and bool(event.get("lethal", false))
		)
		assert(lethal_damage_events.size() == 1, "lethal victim damage event should be present")
		assert(lethal_damage_events[0].get("damage_tags", []) == ["fire", "poison"])
		assert(EventValidator.assert_valid(events, "lethal_damage_context"))
		assert(BattleInvariantChecker.assert_valid(state, "lethal_damage_context"))


func _test_wall_collision_preserves_lethal_damage_tags() -> void:
	var builder := ScenarioBuilder.new("fission_slime_test", 3610, true)
	var player := builder.player()
	builder.move(player, Vector2i(0, 0))
	var victim := builder.add_unit(
		"collision_context_victim",
		"unit_patrol_guard",
		Constants.TEAM_ENEMY,
		Vector2i(7, 3),
		{"hp": 1, "max_hp": 20}
	)
	builder.clear_slots(victim)
	builder.mount_gems(victim, Constants.SLOT_BLACK, [Constants.GEM_LIGHT])
	var exposed_target := builder.add_unit(
		"collision_context_exposed",
		"unit_patrol_guard",
		Constants.TEAM_ENEMY,
		Vector2i(5, 3),
		{"hp": 100, "max_hp": 100}
	)
	builder.clear_slots(exposed_target)
	var state := builder.finish()
	StatusRules.apply_light_exposed(state, exposed_target, 1, victim.uid)
	var events: Array[Dictionary] = []
	Displacement.knockback(
		state,
		victim,
		Vector2i(6, 3),
		1,
		player.uid,
		events,
		-1,
		false,
		DamageContext.create(player.uid, "gravity_collision", ["gravity"])
	)
	assert(not victim.alive, "minimum wall collision damage should defeat the 1 HP victim")
	var lethal_events := events.filter(func(event: Dictionary) -> bool:
		return str(event.get("type", "")) == "damage" \
			and str(event.get("uid", "")) == victim.uid \
			and bool(event.get("lethal", false))
	)
	assert(lethal_events.size() == 1, "wall collision should emit one lethal damage event")
	assert(lethal_events[0].get("damage_tags", []) == ["gravity"])
	var black_light_events := events.filter(func(event: Dictionary) -> bool:
		return str(event.get("type", "")) == "light_beam" \
			and str(event.get("source_uid", "")) == victim.uid
	)
	assert(black_light_events.size() == 1, "black light should run after collision death")
	assert(black_light_events[0].get("damage_tags", []) == ["gravity"])
	assert(EventValidator.assert_valid(events, "wall_collision_lethal_context"))
	assert(BattleInvariantChecker.assert_valid(state, "wall_collision_lethal_context"))


func _test_forced_pass_through_spike_uses_collision_value_and_context() -> void:
	var builder := ScenarioBuilder.new("fission_slime_test", 3611, true)
	var player := builder.player()
	builder.move(player, Vector2i(0, 0))
	var target := builder.add_unit(
		"pass_through_spike_target",
		"unit_patrol_guard",
		Constants.TEAM_ENEMY,
		Vector2i(2, 3),
		{"hp": 30, "max_hp": 30}
	)
	builder.state.add_entity(EntityState.create(
		"pass_through_spike",
		Constants.ENTITY_SPIKE,
		Vector2i(3, 3)
	))
	var state := builder.finish()
	var events: Array[Dictionary] = []
	Displacement.knockback(
		state,
		target,
		Vector2i(0, 3),
		2,
		player.uid,
		events,
		0,
		false,
		DamageContext.create(player.uid, "gravity_collision", ["gravity"])
	)
	assert(target.pos == Vector2i(4, 3), "target should pass through the spike and land at (4,3)")
	assert(
		target.hp == 30 - CombatConfig.spike_collision_damage(),
		"forced pass-through spike should use collision damage, hp=%d" % target.hp
	)
	assert(StatusRules.is_vulnerable(target), "forced pass-through spike should apply vulnerable")
	var spike_events := events.filter(func(event: Dictionary) -> bool:
		return str(event.get("type", "")) == "damage" \
			and str(event.get("reason", "")) == "spike_collision"
	)
	assert(spike_events.size() == 1, "pass-through spike should deal damage exactly once")
	assert(spike_events[0].get("damage_tags", []) == ["gravity"])
	assert(EventValidator.assert_valid(events, "forced_pass_through_spike_context"))
	assert(BattleInvariantChecker.assert_valid(state, "forced_pass_through_spike_context"))


func _test_forced_landing_spike_triggers_once() -> void:
	var builder := ScenarioBuilder.new("fission_slime_test", 3612, true)
	var player := builder.player()
	builder.move(player, Vector2i(0, 0))
	var target := builder.add_unit(
		"landing_spike_target",
		"unit_patrol_guard",
		Constants.TEAM_ENEMY,
		Vector2i(2, 3),
		{"hp": 30, "max_hp": 30}
	)
	builder.state.add_entity(EntityState.create(
		"landing_spike",
		Constants.ENTITY_SPIKE,
		Vector2i(3, 3)
	))
	var state := builder.finish()
	var events: Array[Dictionary] = []
	Displacement.knockback(
		state,
		target,
		Vector2i(0, 3),
		1,
		player.uid,
		events,
		0,
		false,
		DamageContext.create(player.uid, "gravity_collision", ["gravity"])
	)
	assert(target.pos == Vector2i(3, 3), "target should land on the spike")
	assert(
		target.hp == 30 - CombatConfig.spike_collision_damage(),
		"forced landing spike should deal collision damage exactly once, hp=%d" % target.hp
	)
	var vulnerable: StatusInstance = target.get_status(Constants.STATUS_VULNERABLE)
	assert(vulnerable != null and vulnerable.stacks == 1, "forced landing spike should add one vulnerable stack")
	var spike_events := events.filter(func(event: Dictionary) -> bool:
		return str(event.get("type", "")) == "damage" \
			and str(event.get("reason", "")) == "spike_collision"
	)
	assert(spike_events.size() == 1, "forced landing spike should emit one damage event")
	assert(spike_events[0].get("damage_tags", []) == ["gravity"])
	assert(EventValidator.assert_valid(events, "forced_landing_spike_once"))
	assert(BattleInvariantChecker.assert_valid(state, "forced_landing_spike_once"))


func _clear_run_relics() -> void:
	var run_service: Node = Engine.get_main_loop().root.get_node_or_null("RunService")
	if run_service == null:
		return
	var run: RunState = run_service.get_run()
	if run != null:
		run.owned_relics.clear()
