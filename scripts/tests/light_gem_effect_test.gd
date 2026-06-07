extends SceneTree


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_width_levels()
	_test_element_styles()
	_test_fx_overrides()
	_test_eight_direction_aim()
	_test_path_dye()
	print("LIGHT_GEM_EFFECT_TEST_PASS")
	quit(0)


func _test_width_levels() -> void:
	var level_1 := GemEffects.light_beam_width_for_level(1)
	var level_2 := GemEffects.light_beam_width_for_level(2)
	var level_3 := GemEffects.light_beam_width_for_level(3)
	assert(level_1 < level_2 and level_2 < level_3, "light beam must become thicker at every level")


func _test_element_styles() -> void:
	var expected := {
		"fire": Color(1.0, 0.24, 0.12),
		"poison": Color(0.05, 0.95, 0.18),
		"arc": Color(1.0, 0.92, 0.22),
		"ice": Color(0.55, 0.9, 1.0),
		"explosion": Color(1.0, 0.58, 0.18),
	}
	for element in expected:
		var ctx := _context_with_tag(element)
		var event := GemEffects.build_light_beam_event(Vector2i.ZERO, Vector2i.ONE, ctx)
		assert(str(event.get("element", "")) == element, "beam should carry its element shader style")
		assert(event.get("color", Color.TRANSPARENT).is_equal_approx(expected[element]), "beam color should match element")


func _test_fx_overrides() -> void:
	var event := GemEffects.build_light_beam_event(
		Vector2i.ZERO,
		Vector2i.ONE,
		{},
		1.75,
		{"power": 1.8, "noise": 0.7}
	)
	assert(is_equal_approx(float(event.get("width", 0.0)), 1.75), "beam width should be a continuous parameter")
	assert(is_equal_approx(float(event.get("power", 0.0)), 1.8), "beam power override should survive event construction")
	assert(is_equal_approx(float(event.get("noise", 0.0)), 0.7), "beam noise override should survive event construction")


func _test_eight_direction_aim() -> void:
	var attacker := UnitState.new()
	attacker.pos = Vector2i(3, 3)
	for target in [Vector2i(3, 7), Vector2i(7, 3), Vector2i(7, 7), Vector2i(0, 0)]:
		assert(GemEffects.is_valid_light_aim(attacker, target), "cardinal and diagonal light aims must be valid")
	for target in [Vector2i(5, 7), Vector2i(7, 4), Vector2i(3, 3)]:
		assert(not GemEffects.is_valid_light_aim(attacker, target), "off-axis light aims must be rejected")


func _test_path_dye() -> void:
	var state := _mini_state()
	TileRules.create_fire(state, Vector2i(2, 2))
	var fire_ctx := GemEffects.light_context_with_path_dye(
		state,
		[Vector2i(1, 1), Vector2i(2, 2), Vector2i(3, 3)],
		{}
	)
	assert(GemEffects.light_element_for_context(fire_ctx) == "fire", "fire on the beam path must dye the beam")
	assert(GemEffects.light_color_for_context(fire_ctx).is_equal_approx(Color(1.0, 0.24, 0.12)), "fire dye must change beam color")

	TileRules.create_poison_fog(state, Vector2i(4, 4))
	var poison_ctx := GemEffects.light_context_with_path_dye(
		state,
		[Vector2i(2, 2), Vector2i(3, 3), Vector2i(4, 4)],
		{}
	)
	assert(GemEffects.light_element_for_context(poison_ctx) == "poison", "last overlay on the beam path must control dye")
	assert(GemTagResolver.has_tag(poison_ctx, "poison"), "path dye must also apply its element status")
	var transitions := GemEffects.light_dye_transitions(
		state,
		[Vector2i(1, 1), Vector2i(2, 2), Vector2i(3, 3), Vector2i(4, 4)]
	)
	assert(transitions.size() == 2, "beam must change color only when it reaches a dye overlay")
	assert(transitions[0].get("cell") == Vector2i(2, 2), "fire dye must begin where the beam crosses fire")
	assert(transitions[1].get("cell") == Vector2i(4, 4), "poison dye must begin where the beam crosses poison")


func _mini_state() -> GameState:
	var state := GameState.new()
	state.board_size = Vector2i(8, 8)
	for y in range(state.board_size.y):
		for x in range(state.board_size.x):
			var pos := Vector2i(x, y)
			state.tiles[state.tile_key(pos)] = TileState.create(pos, Constants.TILE_FLOOR)
	return state


func _context_with_tag(tag: String) -> Dictionary:
	return {
		"tag_levels": {tag: 1},
		"tag_counts": {tag: 1},
		"tags": [tag],
	}
