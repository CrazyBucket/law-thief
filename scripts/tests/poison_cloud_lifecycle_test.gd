extends SceneTree

const ScenarioBuilder := preload("res://scripts/testkit/scenario_builder.gd")
const PoisonCloudLifecycleClass := preload("res://scripts/map/poison_cloud_lifecycle.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var builder := ScenarioBuilder.new("fission_slime_test", 7301, true)
	var state := builder.finish()
	var cell := Vector2i(3, 3)
	var lifecycle := PoisonCloudLifecycleClass.new()
	state.get_tile(cell).add_modifier(Constants.TILE_MOD_POISON_FOG, 2)
	lifecycle.sync(state, 0.08)
	var appearing := _alpha(lifecycle, cell)
	_require(appearing > 0.0 and appearing < 1.0, "new poison fog must fade in instead of popping to full opacity")
	for index in range(8):
		lifecycle.sync(state, 0.08)
	_require(is_equal_approx(_alpha(lifecycle, cell), 1.0), "poison fog must reach full opacity after its fade-in")
	var presentation_clone := state.clone()
	lifecycle.prepare_state_change(state, presentation_clone)
	_require(is_equal_approx(_alpha(lifecycle, cell), 1.0), "same-encounter presentation state swaps must preserve existing poison fog opacity")
	state.get_tile(cell).remove_modifier(Constants.TILE_MOD_POISON_FOG)
	lifecycle.sync(state, 0.08)
	var disappearing := _alpha(lifecycle, cell)
	_require(disappearing > 0.0 and disappearing < 1.0, "removed poison fog must keep a fading visual tail")
	for index in range(10):
		lifecycle.sync(state, 0.08)
	_require(lifecycle.visuals_for_cell(cell).is_empty(), "poison fog visual tail must clean itself after fading out")
	var other_encounter := presentation_clone.clone()
	other_encounter.encounter_id = "%s_next" % presentation_clone.encounter_id
	lifecycle.sync(presentation_clone, 1.0)
	lifecycle.prepare_state_change(presentation_clone, other_encounter)
	_require(lifecycle.visuals_for_cell(cell).is_empty(), "switching encounters must reset retained poison fog visuals")
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("POISON_CLOUD_LIFECYCLE_TEST_PASS")
	quit()


func _alpha(lifecycle: RefCounted, cell: Vector2i) -> float:
	var visual: Dictionary = lifecycle.visuals_for_cell(cell).get(Constants.TILE_MOD_POISON_FOG, {})
	return float(visual.get("alpha", 0.0))


func _require(condition: bool, message: String) -> void:
	if condition:
		return
	failures.append(message)
