extends SceneTree

const _Generator = preload("res://scripts/services/procedural_encounter_generator.gd")
const _ExportButton = preload("res://scripts/ui/generated_encounter_export_button.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	_test_determinism_and_diversity()
	_test_generation_contracts()
	_test_enemy_pool_coverage()
	_test_runtime_blueprint_and_export()
	print("PROCEDURAL_ENCOUNTER_GENERATOR_TEST_PASS")
	quit()


func _test_determinism_and_diversity() -> void:
	var first := _Generator.generate(271828, 2, "chapter_2:4_3")
	var second := _Generator.generate(271828, 2, "chapter_2:4_3")
	assert(first == second, "same seed, chapter, room, and generator version must reproduce the encounter")

	var signatures: Dictionary = {}
	for seed_value in range(1, 41):
		var encounter := _Generator.generate(seed_value, 2, "diversity_room")
		var generation: Dictionary = encounter.get("generation", {})
		var signature := "%s|%s|%s|%s|%s" % [
			generation.get("layout", ""),
			generation.get("theme", ""),
			str(encounter.get("player_spawn", Vector2i.ZERO)),
			str(encounter.get("enemies", [])),
			str(encounter.get("entities", [])),
		]
		signatures[signature] = true
	assert(signatures.size() >= 30, "forty seeds should produce meaningfully varied battlefields")


func _test_generation_contracts() -> void:
	for seed_value in range(1, 121):
		var chapter := 1 + seed_value % 3
		var encounter := _Generator.generate(seed_value, chapter, "contract_%d" % seed_value)
		var errors := _Generator.validate(encounter)
		assert(errors.is_empty(), "generated encounter %d must satisfy topology and budget rules: %s" % [seed_value, errors])
		var generation: Dictionary = encounter.get("generation", {})
		assert(int(generation.get("version", 0)) == _Generator.GENERATOR_VERSION)
		assert(int(generation.get("threat", 999)) <= int(generation.get("threat_budget", 0)))
		assert((encounter.get("enemies", []) as Array).size() >= 3)


func _test_enemy_pool_coverage() -> void:
	var seen: Dictionary = {}
	var mother_encounters := 0
	var worm_encounters := 0
	for seed_value in range(1, 401):
		var encounter := _Generator.generate(seed_value, 3, "coverage_%d" % seed_value)
		var encounter_defs: Dictionary = {}
		for enemy in encounter.get("enemies", []):
			var def_id := str(enemy.get("def_id", ""))
			seen[def_id] = true
			encounter_defs[def_id] = true
		if encounter_defs.has("unit_broodmother"):
			mother_encounters += 1
		if encounter_defs.has("unit_law_worm"):
			worm_encounters += 1
			assert(encounter_defs.has("unit_broodmother"), "a law worm must never be generated without its broodmother")
	for expected_id in [
		"unit_bomb_rat", "unit_patrol_guard", "unit_stone_bow_guard",
		"unit_fission_slime", "unit_law_worm", "unit_broodmother",
	]:
		assert(seen.has(expected_id), "chapter 3 procedural samples must include %s" % expected_id)
	assert(mother_encounters > worm_encounters, "broodmothers should be the usual initial law-worm-family encounter")
	assert(not seen.has("unit_overload_enforcer") and not seen.has("unit_law_beast"), "special enemies stay in elite, boss, and overload encounters")


func _test_runtime_blueprint_and_export() -> void:
	var registry: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	var state: GameState = registry.create_battle_state(_Generator.ENCOUNTER_ID, 424242, "chapter_1:2_4")
	assert(state != null, "procedural encounter must materialize through DataRegistry")
	assert(BattleInvariantChecker.check_all(state).is_empty(), "materialized generated battle must satisfy battle invariants")
	assert(state.content_warnings.is_empty(), "generated enemies should receive legal initial gems")
	var blueprint := state.generated_encounter_blueprint
	assert(not blueprint.is_empty(), "generated battle must retain its immutable initial blueprint")
	assert((blueprint.get("enemies", []) as Array).size() == state.get_alive_enemies().size())
	assert(int((blueprint.get("generation", {}) as Dictionary).get("seed", 0)) == state.run_seed)

	var controller := BattleController.new()
	controller.start_encounter(_Generator.ENCOUNTER_ID, 424242, "chapter_1:2_4")
	var initial_enemy_count := controller.state.get_alive_enemies().size()
	var enemy: UnitState = controller.state.get_alive_enemies()[0]
	var remove_result := controller.run_editor_command("remove unit %d,%d" % [enemy.pos.x, enemy.pos.y])
	assert(remove_result.get("ok", false), "editor mutation should remove an enemy before export")
	assert(controller.state.get_alive_enemies().size() == initial_enemy_count - 1)

	var export_button := _ExportButton.new()
	export_button.setup(controller)
	assert(export_button.visible, "normal generated battles must expose a visible in-battle export button in debug builds")
	export_button.pressed.emit()
	var export_path := export_button.last_export_path()
	assert(FileAccess.file_exists(export_path), "generated export should write a JSON file")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(export_path))
	assert(parsed is Dictionary, "generated export should be valid JSON")
	assert(((parsed as Dictionary).get("enemies", []) as Array).size() == initial_enemy_count, "export must preserve enemies removed during play")
	assert(int(((parsed as Dictionary).get("generation", {}) as Dictionary).get("version", 0)) == _Generator.GENERATOR_VERSION)
	DirAccess.remove_absolute(export_path)
	export_button.free()
