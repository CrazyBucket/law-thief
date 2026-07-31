extends SceneTree

const Builder = preload("res://scripts/testkit/scenario_builder.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var builder = Builder.new("fission_slime_test", 7102, true)
	var source := builder.player()
	builder.clear_slots(source)
	builder.move(source, Vector2i(2, 3))
	var owner := builder.add_unit(
		"blue_echo_light_poison_owner",
		"unit_patrol_guard",
		Constants.TEAM_ENEMY,
		Vector2i(4, 3),
		{"hp": 40, "max_hp": 40, "base_attack": 6}
	)
	builder.mount_gems(
		owner,
		Constants.SLOT_BLUE,
		[Constants.GEM_ECHO, Constants.GEM_ECHO, Constants.GEM_LIGHT, Constants.GEM_POISON]
	)
	var state := builder.finish()
	var events: Array[Dictionary] = []
	state.bind_combat_events(events)
	CombatRules.apply_damage(state, owner, 4, source.uid, "ranged_attack")
	state.unbind_combat_events()

	var poison: StatusInstance = source.get_status(Constants.STATUS_POISON)
	assert(poison != null and poison.stacks == 3, "blue echo and both dyed light beams should apply three poison stacks")
	assert(_count_events(events, "light_beam") == 2, "blue light and echoed light should each reflect one dyed beam")
	assert(EventValidator.assert_valid(events, "blue_light_poison_scope"))
	assert(BattleInvariantChecker.assert_valid(state, "blue_light_poison_scope"))
	print("LIGHT_COLORED_SCOPE_TEST_PASS")
	quit(0)


func _count_events(events: Array[Dictionary], event_type: String) -> int:
	var total := 0
	for event in events:
		if str(event.get("type", "")) == event_type:
			total += 1
	return total
