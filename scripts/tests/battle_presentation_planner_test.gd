extends SceneTree

const Planner = preload("res://scripts/ui/battle_presentation_planner.gd")
const Validator = preload("res://scripts/debug/event_validator.gd")


func _initialize() -> void:
	print("=== Battle Presentation Planner Test ===")
	_test_split_is_one_parallel_volley()
	_test_blast_damage_is_an_impact()
	_test_arc_hop_is_parallel_and_impacts_after_visuals()
	_test_unknown_event_requires_a_policy()
	print("BATTLE_PRESENTATION_PLANNER_TEST_PASS")
	quit()


func _test_split_is_one_parallel_volley() -> void:
	var events := [
		{"type": "projectile", "from": Vector2i(1, 1), "to": Vector2i(5, 1)},
		{"type": "projectile", "from": Vector2i(1, 1), "to": Vector2i(4, 0)},
		{"type": "projectile", "from": Vector2i(1, 1), "to": Vector2i(4, 2)},
		_damage("a", Vector2i(5, 1), 7),
		_damage("b", Vector2i(4, 0), 7),
		_damage("c", Vector2i(4, 2), 7),
	]
	var result := Planner.build(events)
	assert(result.violations.is_empty())
	assert(result.beats.size() == 1)
	var beat: Dictionary = result.beats[0]
	assert(beat.kind == "projectile")
	assert(beat.mode == Planner.MODE_PARALLEL)
	assert(beat.visuals.size() == 3)
	assert(beat.impacts.size() == 3)


func _test_blast_damage_is_an_impact() -> void:
	var result := Planner.build([
		{"type": "explode", "pos": Vector2i(4, 4)},
		_damage("blast_target", Vector2i(4, 4), 12),
		{"type": "move_step", "uid": "blast_target", "from": Vector2i(4, 4), "to": Vector2i(5, 4)},
		{"type": "displacement_impact", "uid": "blast_target", "from": Vector2i(5, 4), "contact": Vector2i(6, 4)},
	])
	assert(result.violations.is_empty())
	assert(result.beats.size() == 1)
	assert(result.beats[0].kind == "blast")
	assert(result.beats[0].visuals.size() == 1)
	assert(result.beats[0].impacts.size() == 1)
	assert(result.beats[0].impact_motions.size() == 2, "blast movement and collision must share the impact frame")
	assert(result.beats[0].aftermath.is_empty(), "blast knockback is impact motion, not post-explosion aftermath")


func _test_arc_hop_is_parallel_and_impacts_after_visuals() -> void:
	var result := Planner.build([
		{"type": "arc", "from": Vector2i(3, 3), "pos": Vector2i(3, 3), "target_pos": Vector2i(5, 2)},
		{"type": "arc", "from": Vector2i(3, 3), "pos": Vector2i(3, 3), "target_pos": Vector2i(5, 4)},
		_damage("upper", Vector2i(5, 2), 2),
		_damage("lower", Vector2i(5, 4), 2),
	])
	assert(result.violations.is_empty())
	assert(result.beats.size() == 1)
	assert(result.beats[0].kind == "electrical")
	assert(result.beats[0].mode == Planner.MODE_PARALLEL)
	assert(result.beats[0].visuals.size() == 2)
	assert(result.beats[0].impacts.size() == 2)


func _test_unknown_event_requires_a_policy() -> void:
	var result := Planner.build([{"type": "future_animation", "pos": Vector2i.ZERO}])
	assert(result.violations.size() == 1)
	var schema_violations := Validator.validate_events([{"type": "future_animation", "pos": Vector2i.ZERO}])
	assert(schema_violations.size() == 1)


func _damage(uid: String, pos: Vector2i, amount: int) -> Dictionary:
	return {
		"type": "damage",
		"uid": uid,
		"victim_uid": uid,
		"pos": pos,
		"damage": amount,
		"is_crit": false,
	}
