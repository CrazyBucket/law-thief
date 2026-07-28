extends SceneTree

const ContactResolver = preload("res://scripts/rules/contact_resolver.gd")


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Hook System Test ===")
	_test_lawless_on_player_extract()
	_test_patrol_guard_lawless_rampage()
	_test_lawless_on_enemy_extract()
	_test_pillar_turn_aura()
	_test_blue_poison_contact()
	_test_black_poison_death()
	_test_red_gem_triggers_on_attack()
	_test_water_conduction_hits_every_unit_in_water()
	_test_editor_console_spawns_and_edits_unit()
	_test_editor_console_batch_move_delete_commands()
	_test_editor_console_entities_overlays_and_export()
	_test_editor_console_relic_commands()
	_test_editor_unlimited_actions()
	_test_training_dummy_waits_and_tracks_as_spawnable()
	_test_editor_console_import_encounter_file()
	_test_editor_can_add_five_same_gems_to_red_slots()
	print("HOOK_TEST_PASS")
	quit()


func _test_lawless_on_player_extract() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	var guard := _find_unit(state, "unit_patrol_guard")
	_force_red_gem(state, guard, Constants.GEM_EXPLOSION)
	var player := state.get_player()
	var gem_uid: String = guard.slots[0].gem_uid
	var result := GemRules.extract(state, player, guard, guard.slots[0])
	assert(result.get("ok", false), "extract should succeed")
	assert(StatusRules.is_lawless(guard), "patrol guard should enter lawless")
	assert(StatusRules.get_lawless_gem_uid(guard) == gem_uid, "lawless should track stolen gem")
	print("  [OK] lawless on player extract")


func _test_patrol_guard_lawless_rampage() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	var guard := _find_unit(state, "unit_patrol_guard")
	_force_red_gem(state, guard, Constants.GEM_EXPLOSION)
	var player := state.get_player()
	player.pos = guard.pos + Vector2i(1, 0)
	GemRules.extract(state, player, guard, guard.slots[0])
	assert(StatusRules.is_lawless(guard), "patrol guard should enter lawless")
	assert(guard.get_status(Constants.STATUS_VULNERABLE) != null, "patrol guard should be vulnerable")
	guard.pos = player.pos
	IntentSystem.refresh_all_intents(state)
	assert(guard.intent.preview_text.begins_with("暴走"), "lawless patrol guard should blind rampage")
	print("  [OK] patrol guard lawless blind rampage intent")


func _test_lawless_on_enemy_extract() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	var player := state.get_player()
	var gem := GemState.new()
	gem.uid = "player_red_gem"
	gem.gem_id = Constants.GEM_EXPLOSION
	gem.owner_uid = player.uid
	gem.slot_index = 0
	state.gems[gem.uid] = gem
	player.slots[0].gem_uid = gem.uid
	var enemy := _find_unit(state, "unit_bomb_rat")
	enemy.pos = player.pos + Vector2i(1, 0)
	var intent := IntentState.new()
	intent.target_uid = player.uid
	IntentSystem._execute_extract(state, enemy, intent)
	assert(player.slots[0].gem_uid.is_empty(), "player gem should be stolen")
	assert(not StatusRules.is_lawless(player), "player should not enter lawless")
	print("  [OK] enemy extract clears slot without player lawless")


func _test_pillar_turn_aura() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("template_a", 42)
	var state := ctrl.state
	var player := state.get_player()
	player.pos = Vector2i(7, 5)
	var bug := _find_unit(state, "unit_patrol_guard")
	bug.pos = Vector2i(6, 5)
	var gem := GemState.new()
	gem.uid = "pillar_poison"
	gem.gem_id = Constants.GEM_POISON
	state.gems[gem.uid] = gem
	state.held_gem_uid = gem.uid
	var pillar := state.get_tile(Vector2i(7, 5))
	GemRules.insert_tile(state, player, pillar, pillar.slots[0])
	assert(bug.get_status("poison") == null, "poison should not exist before tick")
	StatusRules.tick_turn_end(state)
	assert(bug.get_status("poison") != null, "pillar poison aura should apply poison")
	print("  [OK] pillar turn aura via hook")


func _test_blue_poison_contact() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	var player := state.get_player()
	var guard := _find_unit(state, "unit_patrol_guard")
	var gem := GemState.new()
	gem.uid = "blue_poison_contact"
	gem.gem_id = Constants.GEM_POISON
	state.gems[gem.uid] = gem
	player.slots[1].gem_uid = gem.uid
	assert(guard.get_status("poison") == null, "poison should not exist before contact")
	ContactResolver.on_attack_contact(state, player, guard)
	assert(guard.get_status("poison") != null, "blue poison contact should apply poison")
	assert(guard.get_status("poison").stacks == 1, "contact should apply exactly 1 stack")
	print("  [OK] blue poison contact via hook")


func _test_black_poison_death() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	var guard := _find_unit(state, "unit_patrol_guard")
	_force_slot_gems(state, guard, Constants.SLOT_BLACK, [Constants.GEM_POISON, Constants.GEM_POISON])
	var fog_before := _count_poison_fog_tiles(state)
	CombatRules.apply_damage(state, guard, guard.hp, "", "test_kill")
	assert(not guard.alive, "guard should die")
	assert(_count_poison_fog_tiles(state) > fog_before, "black poison level 2 death should create fog")
	print("  [OK] black poison death hook")


func _test_red_gem_triggers_on_attack() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	var player := state.get_player()
	var guard := _find_unit(state, "unit_patrol_guard")
	var gem := GemState.new()
	gem.uid = "attack_red_gem"
	gem.gem_id = Constants.GEM_EXPLOSION
	state.gems[gem.uid] = gem
	player.slots[0].gem_uid = gem.uid
	var hp_before := guard.hp
	var result := ctrl.try_attack_cell(guard.pos)
	assert(result.get("ok", false), "attack should succeed")
	assert(guard.hp < hp_before, "red gem should trigger on attack hit")
	var events: Array = result.get("attack_events", [])
	assert(not events.is_empty(), "attack should return events")
	print("  [OK] red gem explosion triggers on attack hit")


func _test_water_conduction_hits_every_unit_in_water() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("template_c", 42)
	var state := ctrl.state
	var player := state.get_player()
	assert(ctrl.run_editor_command("move 1,6 3,5").get("ok", false), "move player into water")
	assert(ctrl.run_editor_command("spawn unit_patrol_guard 4,5 --team enemy").get("ok", false), "spawn enemy in water")
	assert(ctrl.run_editor_command("spawn gem_conductive 3,5 --slot red").get("ok", false), "give player arc gem")
	var guard := state.get_unit_at(Vector2i(4, 5))
	assert(guard != null, "enemy should stand on water")
	assert(StatusRules.is_wet(player) and StatusRules.is_wet(guard), "both units standing in water should be wet")
	var player_hp_before := player.hp
	var guard_hp_before := guard.hp
	var atk := ctrl.try_attack_cell(Vector2i(4, 5))
	assert(atk.get("ok", false), "attack water should succeed")
	assert(guard.hp < guard_hp_before, "enemy in water should take arc damage from water shock")
	assert(player.hp < player_hp_before, "the source standing in water should also take arc damage")
	print("  [OK] water conduction hits every unit in water, including its source")


func _test_editor_console_spawns_and_edits_unit() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001", 42)
	var spawn_result := ctrl.run_editor_command("spawn unit_bomb_rat 0,0 --team enemy")
	assert(spawn_result.get("ok", false), "editor console should spawn unit")
	var spawned := ctrl.state.get_unit_at(Vector2i(0, 0))
	assert(spawned != null, "spawned unit should exist at target cell")
	assert(spawned.unit_def_id == "unit_bomb_rat", "spawned unit def should match")
	var edit_result := ctrl.run_editor_command("set stat 0,0 hp 9")
	assert(edit_result.get("ok", false), "editor console should edit unit hp")
	assert(spawned.hp == 9, "spawned unit hp should update")
	print("  [OK] editor console spawns unit and edits stats")


func _test_editor_console_batch_move_delete_commands() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001", 42)
	var batch_result := ctrl.run_editor_command("spawn-many unit_patrol_guard 7,0 6,0 --team enemy")
	assert(batch_result.get("ok", false), "editor console should batch spawn units")
	assert(ctrl.state.get_unit_at(Vector2i(7, 0)) != null, "batch spawn should create first unit")
	assert(ctrl.state.get_unit_at(Vector2i(6, 0)) != null, "batch spawn should create second unit")
	var move_result := ctrl.run_editor_command("move 7,0 7,1")
	assert(move_result.get("ok", false), "editor console should move unit")
	var moved := ctrl.state.get_unit_at(Vector2i(7, 1))
	assert(moved != null and moved.unit_def_id == "unit_patrol_guard", "moved unit should arrive at destination")
	var delete_unit_result := ctrl.run_editor_command("remove unit 7,1")
	assert(delete_unit_result.get("ok", false), "editor console should delete unit")
	assert(ctrl.state.get_unit_at(Vector2i(7, 1)) == null, "deleted unit should be removed")
	var gem_spawn_result := ctrl.run_editor_command("spawn gem_explosion 6,0 --slot red --target unit")
	assert(gem_spawn_result.get("ok", false), "editor console should create gem before deletion")
	var delete_gem_result := ctrl.run_editor_command("remove gem 6,0 --slot red --target unit")
	assert(delete_gem_result.get("ok", false), "editor console should delete gem")
	var remaining := ctrl.state.get_unit_at(Vector2i(6, 0))
	assert(remaining != null and remaining.slots[0].gem_uid.is_empty(), "unit slot gem should be removed")
	print("  [OK] editor console batch/move/delete commands")


func _test_editor_console_entities_overlays_and_export() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001", 42)
	var entity_result := ctrl.run_editor_command("spawn entity_barrel 0,1")
	assert(entity_result.get("ok", false), "editor console should spawn entity")
	var barrel := ctrl.state.get_entity_at(Vector2i(0, 1))
	assert(barrel != null and barrel.entity_id == Constants.ENTITY_BARREL, "spawned entity should exist")
	var rock_result := ctrl.run_editor_command("spawn entity_rock 0,2")
	assert(rock_result.get("ok", false), "editor console should spawn rock")
	var rock := ctrl.state.get_entity_at(Vector2i(0, 2))
	assert(rock != null and not rock.prop_sprite.is_empty(), "editor-spawned rock should receive a rock sprite")
	var prop_result := ctrl.run_editor_command("spawn entity_prop 0,3")
	assert(prop_result.get("ok", false), "editor console should spawn prop")
	var prop := ctrl.state.get_entity_at(Vector2i(0, 3))
	assert(prop != null and not prop.prop_sprite.is_empty(), "editor-spawned prop should receive a prop sprite")
	var overlay_result := ctrl.run_editor_command("spawn fire 2,2 --duration 3")
	assert(overlay_result.get("ok", false), "editor console should spawn overlay")
	var tile := ctrl.state.get_tile(Vector2i(2, 2))
	assert(tile.has_modifier(Constants.TILE_MOD_FIRE), "tile should have fire modifier")
	var remove_overlay_result := ctrl.run_editor_command("remove overlay 2,2 fire")
	assert(remove_overlay_result.get("ok", false), "editor console should remove overlay")
	assert(not tile.has_modifier(Constants.TILE_MOD_FIRE), "fire modifier should be removed")
	var export_result := ctrl.run_editor_command("export encounter cli_export_test")
	assert(export_result.get("ok", false), "editor console should export encounter")
	var encounter: Dictionary = export_result.get("encounter", {})
	assert(int(encounter.get("schema_version", 0)) == 2, "export should use schema_version 2")
	var entities: Array = encounter.get("entities", [])
	assert(not entities.is_empty(), "export should include entities")
	var found_barrel := false
	for entry in entities:
		if str(entry.get("entity_id", "")) == Constants.ENTITY_BARREL:
			found_barrel = true
			assert(entry.get("pos", []) == [0, 1], "exported entity position should be JSON array")
	assert(found_barrel, "export should include spawned barrel")
	print("  [OK] editor console entity/overlay/export commands")


func _test_editor_console_relic_commands() -> void:
	var run_service: Node = Engine.get_main_loop().root.get_node("RunService")
	run_service.start_run(101, 202)
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001", 42)
	var add_result := ctrl.run_editor_command("relic add relic_prism")
	assert(add_result.get("ok", false), "editor console should add relic during active run")
	assert(run_service.has_relic("relic_prism"), "run should now own relic_prism")
	var remove_result := ctrl.run_editor_command("relic remove relic_prism")
	assert(remove_result.get("ok", false), "editor console should remove relic during active run")
	assert(not run_service.has_relic("relic_prism"), "run should no longer own relic_prism")
	run_service.end_run()
	print("  [OK] editor console relic commands")


func _test_editor_unlimited_actions() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001", 42)
	ctrl.editor_unlimited_actions = true
	ctrl.state.player_moved = true
	ctrl.state.player_acted = true
	assert(ctrl.can_use_action(Constants.ACTION_MOVE), "unlimited mode should allow move after moving")
	assert(ctrl.can_use_action(Constants.ACTION_ATTACK), "unlimited mode should allow attack after acting")
	var guards := []
	for unit in ctrl.state.units.values():
		if unit.unit_def_id == "unit_patrol_guard" and unit.alive:
			guards.append(unit)
	assert(not guards.is_empty(), "tutorial should have patrol guard")
	var guard: UnitState = guards[0]
	var hp_before := guard.hp
	ctrl.select_action(Constants.ACTION_ATTACK)
	var attack_result := ctrl.try_attack_cell(guard.pos)
	assert(attack_result.get("ok", false), "unlimited attack should succeed after acting")
	assert(ctrl.can_use_action(Constants.ACTION_ATTACK), "unlimited mode should allow another attack")
	var second_result := ctrl.try_attack_cell(guard.pos)
	assert(second_result.get("ok", false), "unlimited mode should allow repeated attacks")
	print("  [OK] editor unlimited actions")


func _test_training_dummy_waits_and_tracks_as_spawnable() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001", 42)
	var spawn_result := ctrl.run_editor_command("spawn unit_training_dummy 0,0 --team enemy")
	assert(spawn_result.get("ok", false), "editor console should spawn training dummy")
	var dummy := ctrl.state.get_unit_at(Vector2i(0, 0))
	assert(dummy != null and dummy.unit_def_id == "unit_training_dummy", "spawned dummy should exist")
	IntentSystem.refresh_unit_intent(ctrl.state, dummy)
	assert(dummy.intent != null and dummy.intent.type == "wait", "training dummy should always wait")
	assert(dummy.intent.preview_text == "木桩待机", "training dummy should expose wait preview")
	print("  [OK] training dummy behavior")


func _test_editor_console_import_encounter_file() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001", 42)
	var path := "user://law_thief_editor_import_test.json"
	var payload := {
		"schema_version": 2,
		"player_spawn": [1, 1],
		"floor_seed": 77,
		"enemies": [
			{"def_id": "unit_training_dummy", "pos": [2, 2]},
		],
		"entities": [
			{"entity_id": Constants.ENTITY_BARREL, "pos": [3, 3]},
		],
		"tiles": [
			{"pos": [4, 4], "tile_id": Constants.TILE_WATER, "overlays": [{"type": Constants.TILE_MOD_FIRE, "duration": 2}]},
		],
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "should be able to create import payload file")
	file.store_string(JSON.stringify(payload, "\t"))
	file = null
	var import_result := ctrl.run_editor_command("import %s" % path)
	assert(import_result.get("ok", false), "editor console should import encounter file: %s" % import_result)
	assert(ctrl.state.get_player() != null and ctrl.state.get_player().pos == Vector2i(1, 1), "player spawn should update from import")
	var dummy := ctrl.state.get_unit_at(Vector2i(2, 2))
	assert(dummy != null and dummy.unit_def_id == "unit_training_dummy", "import should spawn dummy enemy")
	var barrel := ctrl.state.get_entity_at(Vector2i(3, 3))
	assert(barrel != null and barrel.entity_id == Constants.ENTITY_BARREL, "import should spawn entity")
	assert(ctrl.state.get_tile(Vector2i(4, 4)).tile_id == Constants.TILE_WATER, "import should set tile")
	assert(ctrl.state.get_tile(Vector2i(4, 4)).has_modifier(Constants.TILE_MOD_FIRE), "import should restore tile overlays")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("  [OK] editor console import encounter file")


func _test_editor_can_add_five_same_gems_to_red_slots() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001", 42)
	var target := _find_unit(ctrl.state, "unit_patrol_guard")
	var initial_red_count := target.slots_accepting(Constants.SLOT_RED).size()
	for _i in range(5):
		var result := ctrl.run_editor_action("spawn_gem", {
			"gem_id": Constants.GEM_EXPLOSION,
			"pos": target.pos,
			"target_kind": "unit",
			"create_slot_type": Constants.SLOT_RED,
		})
		assert(result.get("ok", false), "editor should add a red slot and insert gem")
	var red_slots := target.slots_accepting(Constants.SLOT_RED)
	assert(red_slots.size() == initial_red_count + 5, "editor should append five red slots")
	var explosion_count := 0
	for slot in red_slots:
		if slot.gem_uid.is_empty():
			continue
		var gem: GemState = ctrl.state.gems.get(slot.gem_uid, null)
		if gem != null and gem.gem_id == Constants.GEM_EXPLOSION:
			explosion_count += 1
	assert(explosion_count >= 5, "editor should insert five identical gems into red slots")
	var selected_slot_index := target.slots.size() - 3
	var selected_result := ctrl.run_editor_action("spawn_gem", {
		"gem_id": Constants.GEM_CONDUCTIVE,
		"pos": target.pos,
		"target_kind": "unit",
		"slot_index": selected_slot_index,
	})
	assert(selected_result.get("ok", false), "editor should insert into explicitly selected slot")
	var selected_slot: SlotState = target.get_slot_by_index(selected_slot_index)
	var selected_gem: GemState = ctrl.state.gems.get(selected_slot.gem_uid, null)
	assert(selected_gem != null and selected_gem.gem_id == Constants.GEM_CONDUCTIVE, "selected slot should contain the replacement gem")
	print("  [OK] editor supports five identical gems in red slots")


func _force_red_gem(state: GameState, unit: UnitState, gem_id: String) -> void:
	for slot in unit.slots:
		if not slot.gem_uid.is_empty():
			state.gems.erase(slot.gem_uid)
			slot.gem_uid = ""
	_force_slot_gems(state, unit, Constants.SLOT_RED, [gem_id])


func _force_slot_gems(state: GameState, unit: UnitState, slot_type: String, gem_ids: Array[String]) -> void:
	var reg: Node = _data_registry()
	while unit.slots_accepting(slot_type).size() < gem_ids.size():
		unit.slots.append(SlotState.create(slot_type))
	var slots := unit.slots_accepting(slot_type)
	for i in range(slots.size()):
		if i >= gem_ids.size():
			break
		var slot: SlotState = slots[i]
		if not slot.gem_uid.is_empty():
			state.gems.erase(slot.gem_uid)
		var gem_uid: String = reg.next_runtime_uid("gem")
		var gem: GemState = reg.create_gem_instance(gem_uid, gem_ids[i], {})
		state.gems[gem_uid] = gem
		slot.gem_uid = gem_uid
		gem.owner_uid = unit.uid
		gem.slot_index = unit.slots.find(slot)


func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node("DataRegistry")


func _find_unit(state: GameState, def_id: String) -> UnitState:
	for unit in state.units.values():
		if unit.unit_def_id == def_id:
			return unit
	assert(false, "unit not found: %s" % def_id)
	return null


func _count_poison_fog_tiles(state: GameState) -> int:
	var count := 0
	for tile in state.tiles.values():
		if tile.has_modifier("poison_fog"):
			count += 1
	return count
