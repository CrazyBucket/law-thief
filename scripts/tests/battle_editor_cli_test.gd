extends SceneTree


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_editor_console_spawns_and_edits_unit()
	_test_editor_console_batch_move_delete_commands()
	_test_editor_console_entities_overlays_and_export()
	_test_editor_console_relic_commands()
	_test_editor_unlimited_actions()
	_test_training_dummy_waits_and_tracks_as_spawnable()
	_test_editor_console_import_encounter_file()
	_test_editor_can_add_five_same_gems_to_red_slots()
	print("BATTLE_EDITOR_CLI_TEST_PASS")
	quit()


func _test_editor_console_spawns_and_edits_unit() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001", 42)
	var spawn_result := ctrl.run_editor_command("spawn unit_bomb_rat 0,0 --team enemy")
	assert(spawn_result.get("ok", false), "editor console should spawn unit")
	var spawned := ctrl.state.get_unit_at(Vector2i(0, 0))
	assert(spawned != null and spawned.unit_def_id == "unit_bomb_rat", "spawned unit should match the requested definition")
	var edit_result := ctrl.run_editor_command("set stat 0,0 hp 9")
	assert(edit_result.get("ok", false) and spawned.hp == 9, "editor console should edit unit hp")


func _test_editor_console_batch_move_delete_commands() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001", 42)
	assert(ctrl.run_editor_command("spawn-many unit_patrol_guard 7,0 6,0 --team enemy").get("ok", false))
	assert(ctrl.state.get_unit_at(Vector2i(7, 0)) != null and ctrl.state.get_unit_at(Vector2i(6, 0)) != null)
	assert(ctrl.run_editor_command("move 7,0 7,1").get("ok", false))
	var moved := ctrl.state.get_unit_at(Vector2i(7, 1))
	assert(moved != null and moved.unit_def_id == "unit_patrol_guard")
	assert(ctrl.run_editor_command("remove unit 7,1").get("ok", false))
	assert(ctrl.state.get_unit_at(Vector2i(7, 1)) == null)
	assert(ctrl.run_editor_command("spawn gem_explosion 6,0 --slot red --target unit").get("ok", false))
	assert(ctrl.run_editor_command("remove gem 6,0 --slot red --target unit").get("ok", false))
	var remaining := ctrl.state.get_unit_at(Vector2i(6, 0))
	assert(remaining != null and remaining.slots[0].gem_uid.is_empty())


func _test_editor_console_entities_overlays_and_export() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001", 42)
	assert(ctrl.run_editor_command("spawn entity_barrel 0,1").get("ok", false))
	assert(ctrl.run_editor_command("spawn entity_rock 0,2").get("ok", false))
	assert(ctrl.run_editor_command("spawn entity_prop 0,3").get("ok", false))
	assert(ctrl.state.get_entity_at(Vector2i(0, 2)).prop_sprite != "")
	assert(ctrl.state.get_entity_at(Vector2i(0, 3)).prop_sprite != "")
	assert(ctrl.run_editor_command("spawn fire 2,2 --duration 3").get("ok", false))
	var tile := ctrl.state.get_tile(Vector2i(2, 2))
	assert(tile.has_modifier(Constants.TILE_MOD_FIRE))
	assert(ctrl.run_editor_command("remove overlay 2,2 fire").get("ok", false))
	assert(not tile.has_modifier(Constants.TILE_MOD_FIRE))
	var export_result := ctrl.run_editor_command("export encounter cli_export_test")
	assert(export_result.get("ok", false))
	var encounter: Dictionary = export_result.get("encounter", {})
	assert(encounter.get("schema_version", 0) == 2)
	assert(encounter.get("entities", []).any(func(entry): return entry.get("entity_id", "") == Constants.ENTITY_BARREL and entry.get("pos", []) == [0, 1]))


func _test_editor_console_relic_commands() -> void:
	var run_service: Node = root.get_node("RunService")
	run_service.start_run(101, 202)
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001", 42)
	assert(ctrl.run_editor_command("relic add relic_prism").get("ok", false) and run_service.has_relic("relic_prism"))
	assert(ctrl.run_editor_command("relic remove relic_prism").get("ok", false) and not run_service.has_relic("relic_prism"))
	run_service.end_run()


func _test_editor_unlimited_actions() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001", 42)
	ctrl.editor_unlimited_actions = true
	ctrl.state.player_moved = true
	ctrl.state.player_acted = true
	assert(ctrl.can_use_action(Constants.ACTION_MOVE) and ctrl.can_use_action(Constants.ACTION_ATTACK))
	var guard := _find_unit(ctrl.state, "unit_patrol_guard")
	ctrl.select_action(Constants.ACTION_ATTACK)
	assert(ctrl.try_attack_cell(guard.pos).get("ok", false))
	assert(ctrl.can_use_action(Constants.ACTION_ATTACK))
	assert(ctrl.try_attack_cell(guard.pos).get("ok", false), "unlimited mode should allow repeated attacks")


func _test_training_dummy_waits_and_tracks_as_spawnable() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001", 42)
	assert(ctrl.run_editor_command("spawn unit_training_dummy 0,0 --team enemy").get("ok", false))
	var dummy := ctrl.state.get_unit_at(Vector2i(0, 0))
	assert(dummy != null and dummy.unit_def_id == "unit_training_dummy")
	IntentSystem.refresh_unit_intent(ctrl.state, dummy)
	assert(dummy.intent != null and dummy.intent.type == "wait" and dummy.intent.preview_text == "木桩待机")


func _test_editor_console_import_encounter_file() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001", 42)
	var path := "user://law_thief_editor_import_test.json"
	var payload := {
		"schema_version": 2,
		"player_spawn": [1, 1],
		"floor_seed": 77,
		"enemies": [{"def_id": "unit_training_dummy", "pos": [2, 2]}],
		"entities": [{"entity_id": Constants.ENTITY_BARREL, "pos": [3, 3]}],
		"tiles": [{"pos": [4, 4], "tile_id": Constants.TILE_WATER, "overlays": [{"type": Constants.TILE_MOD_FIRE, "duration": 2}]}],
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(payload, "\t"))
	file = null
	var import_result := ctrl.run_editor_command("import %s" % path)
	assert(import_result.get("ok", false), "editor console should import encounter file: %s" % import_result)
	assert(ctrl.state.get_player().pos == Vector2i(1, 1))
	assert(ctrl.state.get_unit_at(Vector2i(2, 2)).unit_def_id == "unit_training_dummy")
	assert(ctrl.state.get_entity_at(Vector2i(3, 3)).entity_id == Constants.ENTITY_BARREL)
	assert(ctrl.state.get_tile(Vector2i(4, 4)).tile_id == Constants.TILE_WATER)
	assert(ctrl.state.get_tile(Vector2i(4, 4)).has_modifier(Constants.TILE_MOD_FIRE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_editor_can_add_five_same_gems_to_red_slots() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001", 42)
	var target := _find_unit(ctrl.state, "unit_patrol_guard")
	var initial_red_count := target.slots_accepting(Constants.SLOT_RED).size()
	for _index in range(5):
		assert(ctrl.run_editor_action("spawn_gem", {
			"gem_id": Constants.GEM_EXPLOSION,
			"pos": target.pos,
			"target_kind": "unit",
			"create_slot_type": Constants.SLOT_RED,
		}).get("ok", false))
	var red_slots := target.slots_accepting(Constants.SLOT_RED)
	assert(red_slots.size() == initial_red_count + 5)
	var explosion_count := 0
	for slot: SlotState in red_slots:
		var gem: GemState = ctrl.state.gems.get(slot.gem_uid, null)
		if gem != null and gem.gem_id == Constants.GEM_EXPLOSION:
			explosion_count += 1
	assert(explosion_count >= 5)
	var selected_slot_index := target.slots.size() - 3
	assert(ctrl.run_editor_action("spawn_gem", {
		"gem_id": Constants.GEM_CONDUCTIVE,
		"pos": target.pos,
		"target_kind": "unit",
		"slot_index": selected_slot_index,
	}).get("ok", false))
	var selected_gem: GemState = ctrl.state.gems.get(target.get_slot_by_index(selected_slot_index).gem_uid, null)
	assert(selected_gem != null and selected_gem.gem_id == Constants.GEM_CONDUCTIVE)


func _find_unit(state: GameState, def_id: String) -> UnitState:
	for unit: UnitState in state.units.values():
		if unit.unit_def_id == def_id:
			return unit
	assert(false, "unit not found: %s" % def_id)
	return null
