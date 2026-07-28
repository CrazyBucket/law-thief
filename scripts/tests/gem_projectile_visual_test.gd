extends SceneTree

const AttackPipeline = preload("res://scripts/rules/attack_pipeline.gd")
const ScenarioBuilder = preload("res://scripts/testkit/scenario_builder.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Gem Projectile Visual Test ===")
	_test_plain_ranged_attack_stays_generic()
	_test_fire_level_uses_resolved_tag_level()
	_test_visual_element_priority_is_deterministic()
	if _failed:
		push_error("GEM_PROJECTILE_VISUAL_TEST_FAIL")
		quit(1)
		return
	print("GEM_PROJECTILE_VISUAL_TEST_PASS")
	quit(0)


func _test_plain_ranged_attack_stays_generic() -> void:
	var result := _attack_with([])
	var projectile := _first_projectile(result)
	_expect(not projectile.has("element"), "ordinary ranged attacks should retain the generic projectile")
	_expect(not projectile.has("gem_level"), "ordinary ranged attacks should not create a visual gem level")


func _test_fire_level_uses_resolved_tag_level() -> void:
	var result := _attack_with([Constants.GEM_FIRE, Constants.GEM_FIRE, Constants.GEM_FIRE])
	var projectile := _first_projectile(result)
	_expect(str(projectile.get("element", "")) == "fire", "fire gems should select the fire projectile animation")
	_expect(int(projectile.get("gem_level", 0)) == 3, "three fire gems should select the level-three projectile scale")


func _test_visual_element_priority_is_deterministic() -> void:
	var result := _attack_with([Constants.GEM_FIRE, Constants.GEM_POISON])
	var projectile := _first_projectile(result)
	_expect(str(projectile.get("element", "")) == "fire", "mixed elemental shots should use the documented fire-first visual priority")
	_expect(int(projectile.get("gem_level", 0)) == 1, "the selected element should use its own resolved level")


func _attack_with(gems: Array) -> Dictionary:
	var builder := ScenarioBuilder.new("fission_slime_test", 9127, true)
	var player := builder.player()
	builder.clear_slots(player)
	builder.move(player, Vector2i(2, 3))
	if not gems.is_empty():
		builder.mount_gems(player, Constants.SLOT_RED, gems)
	var target := builder.add_unit("projectile_visual_target", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(5, 3), {"hp": 100, "max_hp": 100})
	var state := builder.finish()
	var result := AttackPipeline.execute_aimed(state, player, target.pos, [AttackPipeline.TAG_RANGED])
	_expect(result.get("ok", false), "ranged attack should resolve for projectile visual metadata")
	return result


func _first_projectile(result: Dictionary) -> Dictionary:
	for event: Dictionary in result.get("events", []):
		if str(event.get("type", "")) == "projectile":
			return event
	_expect(false, "ranged attack should emit a projectile event")
	return {}


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
