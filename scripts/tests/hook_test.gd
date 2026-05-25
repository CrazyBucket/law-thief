extends SceneTree


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Hook System Test ===")
	_test_lawless_on_player_extract()
	_test_lawless_reclaim_from_hand()
	_test_lawless_on_enemy_extract()
	_test_altar_insert_triggers()
	_test_pillar_turn_aura()
	_test_blue_poison_move_trail()
	_test_black_poison_death()
	_test_player_skill_via_hook()
	_test_chaos_trigger_uses_overridden_profile()
	_test_editor_console_spawns_and_edits_unit()
	_test_editor_console_replaces_tile_and_spawns_gem()
	_test_editor_console_batch_move_delete_commands()
	_test_editor_console_exports_encounter()
	print("HOOK_TEST_PASS")
	quit()


func _test_lawless_on_player_extract() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	var bomber := _find_unit(state, "unit_bomber")
	var player := state.get_player()
	var gem_uid: String = bomber.slots[0].gem_uid
	var result := GemRules.extract(state, player, bomber, bomber.slots[0])
	assert(result.get("ok", false), "extract should succeed")
	assert(StatusRules.is_lawless(bomber), "bomber should enter lawless")
	assert(StatusRules.get_lawless_gem_uid(bomber) == gem_uid, "lawless should track stolen gem")
	print("  [OK] lawless on player extract")


func _test_lawless_reclaim_from_hand() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	var bomber := _find_unit(state, "unit_bomber")
	var player := state.get_player()
	player.pos = bomber.pos + Vector2i(1, 0)
	var gem_uid: String = bomber.slots[0].gem_uid
	GemRules.extract(state, player, bomber, bomber.slots[0])
	assert(StatusRules.is_lawless(bomber), "bomber should enter lawless")
	assert(state.held_gem_uid == gem_uid, "stolen gem should be in player hand")
	bomber.pos = player.pos
	var intent := IntentSystem._lawless_intent(state, bomber)
	assert(intent.type == "lawless_extract", "adjacent bomber should try to reclaim gem")
	var events := IntentSystem.execute_intent(state, bomber)
	assert(not StatusRules.is_lawless(bomber), "lawless should clear after reclaim")
	assert(bomber.slots[0].gem_uid == gem_uid, "gem should return to bomber red slot")
	assert(state.held_gem_uid.is_empty(), "player hand should be empty after reclaim")
	assert(not events.is_empty(), "reclaim should emit animation events")
	print("  [OK] lawless reclaim gem from player hand")


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
	var thief := _find_unit(state, "unit_bomber")
	thief.pos = player.pos + Vector2i(1, 0)
	var intent := IntentState.new()
	intent.target_uid = player.uid
	IntentSystem._execute_extract(state, thief, intent)
	assert(player.slots[0].gem_uid.is_empty(), "player gem should be stolen")
	assert(not StatusRules.is_lawless(player), "player should not enter lawless")
	print("  [OK] enemy extract clears slot without player lawless")


func _test_altar_insert_triggers() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("template_a", 42)
	var state := ctrl.state
	var player := state.get_player()
	player.pos = Vector2i(2, 4)
	var bomber := _find_unit(state, "unit_bomber")
	var hp_before := bomber.hp
	var gem := GemState.new()
	gem.uid = "altar_gem"
	gem.gem_id = Constants.GEM_EXPLOSION
	state.gems[gem.uid] = gem
	state.held_gem_uid = gem.uid
	var altar := state.get_tile(Vector2i(2, 3))
	var result := GemRules.insert_tile(state, player, altar, altar.slots[0])
	assert(result.get("ok", false), "altar insert should succeed")
	assert(bomber.hp < hp_before, "altar explosion should damage enemies")
	print("  [OK] altar insert triggers active hook")


func _test_pillar_turn_aura() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("template_a", 42)
	var state := ctrl.state
	var player := state.get_player()
	player.pos = Vector2i(7, 5)
	var bug := _find_unit(state, "unit_poison_bug")
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


func _test_blue_poison_move_trail() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	var player := state.get_player()
	var gem := GemState.new()
	gem.uid = "blue_poison_trail"
	gem.gem_id = Constants.GEM_POISON
	state.gems[gem.uid] = gem
	player.slots[1].gem_uid = gem.uid
	var pass_pos := player.pos + Vector2i(1, 0)
	TileRules.on_unit_moved_through(state, player, pass_pos)
	var tile := state.get_tile(pass_pos)
	assert(tile.has_modifier("poison_fog"), "blue poison should leave fog on moved-through tile")
	print("  [OK] blue poison move trail via hook")


func _test_black_poison_death() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	var guard := _find_unit(state, "unit_training_guard")
	var gem := GemState.new()
	gem.uid = "black_poison"
	gem.gem_id = Constants.GEM_POISON
	state.gems[gem.uid] = gem
	guard.slots.append(SlotState.create(Constants.SLOT_BLACK, gem.uid))
	gem.owner_uid = guard.uid
	var fog_before := _count_poison_fog_tiles(state)
	CombatRules.apply_damage(state, guard, guard.hp, "", "test_kill")
	assert(not guard.alive, "guard should die")
	assert(_count_poison_fog_tiles(state) > fog_before, "black poison death should create fog")
	print("  [OK] black poison death hook")


func _test_player_skill_via_hook() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	var player := state.get_player()
	var guard := _find_unit(state, "unit_training_guard")
	var gem := GemState.new()
	gem.uid = "skill_hook_gem"
	gem.gem_id = Constants.GEM_EXPLOSION
	state.gems[gem.uid] = gem
	player.slots[0].gem_uid = gem.uid
	var hp_before := guard.hp
	var events := GemEffects.player_use_skill(state, player, guard.pos)
	assert(not events.is_empty(), "skill should return events")
	assert(guard.hp < hp_before, "skill hook should deal damage")
	print("  [OK] player skill routed through active hook")


func _test_chaos_trigger_uses_overridden_profile() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001", 42)
	var state := ctrl.state
	var player := state.get_player()
	var chaos_gem: GemState = _data_registry().create_gem_instance("chaos_hook_gem", Constants.GEM_CHAOS, {
		"ability_profiles": {
			"unit_red_active": "poison",
			"player_skill": "gravity",
		}
	})
	state.gems[chaos_gem.uid] = chaos_gem
	player.slots[0].gem_uid = chaos_gem.uid
	var fog_before := _count_poison_fog_tiles(state)
	var triggered := GemEffects.trigger_gem(state, player.uid, player.slots[0])
	assert(triggered, "chaos trigger should execute overridden red active profile")
	assert(_count_poison_fog_tiles(state) > fog_before, "chaos trigger should create poison fog")
	print("  [OK] chaos trigger routed through overridden profile")


func _test_editor_console_spawns_and_edits_unit() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001", 42)
	var spawn_result := ctrl.run_editor_command("spawn unit_bomber 0,0 --team enemy")
	assert(spawn_result.get("ok", false), "editor console should spawn unit")
	var spawned := ctrl.state.get_unit_at(Vector2i(0, 0))
	assert(spawned != null, "spawned unit should exist at target cell")
	assert(spawned.unit_def_id == "unit_bomber", "spawned unit def should match")
	var edit_result := ctrl.run_editor_command("set stat 0,0 hp 9")
	assert(edit_result.get("ok", false), "editor console should edit unit hp")
	assert(spawned.hp == 9, "spawned unit hp should update")
	print("  [OK] editor console spawns unit and edits stats")


func _test_editor_console_replaces_tile_and_spawns_gem() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001", 42)
	var tile_result := ctrl.run_editor_command("set tile 0,1 tile_altar")
	assert(tile_result.get("ok", false), "editor console should replace tile")
	var tile := ctrl.state.get_tile(Vector2i(0, 1))
	assert(tile.tile_id == Constants.TILE_ALTAR, "tile should become altar")
	assert(tile.has_slots(), "altar should create a slot")
	var gem_result := ctrl.run_editor_command("spawn gem_poison 0,1 --slot red --target tile")
	assert(gem_result.get("ok", false), "editor console should spawn gem into tile")
	var slot := tile.get_slot_by_index(0)
	assert(slot != null and not slot.gem_uid.is_empty(), "tile slot should contain gem")
	var gem: GemState = ctrl.state.gems.get(slot.gem_uid, null)
	assert(gem != null and gem.gem_id == Constants.GEM_POISON, "spawned tile gem should match")
	print("  [OK] editor console replaces tile and spawns gem")


func _test_editor_console_batch_move_delete_commands() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001", 42)
	var batch_result := ctrl.run_editor_command("spawn-many unit_grunt 0,0 1,0 --team enemy")
	assert(batch_result.get("ok", false), "editor console should batch spawn units")
	assert(ctrl.state.get_unit_at(Vector2i(0, 0)) != null, "batch spawn should create first unit")
	assert(ctrl.state.get_unit_at(Vector2i(1, 0)) != null, "batch spawn should create second unit")
	var move_result := ctrl.run_editor_command("move 0,0 0,1")
	assert(move_result.get("ok", false), "editor console should move unit")
	var moved := ctrl.state.get_unit_at(Vector2i(0, 1))
	assert(moved != null and moved.unit_def_id == "unit_grunt", "moved unit should arrive at destination")
	var delete_unit_result := ctrl.run_editor_command("remove unit 0,1")
	assert(delete_unit_result.get("ok", false), "editor console should delete unit")
	assert(ctrl.state.get_unit_at(Vector2i(0, 1)) == null, "deleted unit should be removed")
	var gem_spawn_result := ctrl.run_editor_command("spawn gem_explosion 1,0 --slot red --target unit")
	assert(gem_spawn_result.get("ok", false), "editor console should create gem before deletion")
	var delete_gem_result := ctrl.run_editor_command("remove gem 1,0 --slot red --target unit")
	assert(delete_gem_result.get("ok", false), "editor console should delete gem")
	var remaining := ctrl.state.get_unit_at(Vector2i(1, 0))
	assert(remaining != null and remaining.slots[0].gem_uid.is_empty(), "unit slot gem should be removed")
	print("  [OK] editor console batch/move/delete commands")


func _test_editor_console_exports_encounter() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001", 42)
	var spawn_result := ctrl.run_editor_command("spawn unit_grunt 0,0 --team enemy")
	assert(spawn_result.get("ok", false), "setup spawn should succeed")
	var tile_result := ctrl.run_editor_command("set tile 0,1 tile_altar")
	assert(tile_result.get("ok", false), "setup tile replacement should succeed")
	var export_result := ctrl.run_editor_command("export encounter custom_stage_001")
	assert(export_result.get("ok", false), "editor console should export encounter")
	var encounter: Dictionary = export_result.get("encounter", {})
	assert(encounter.get("player_spawn", Vector2i.ZERO) == ctrl.state.get_player().pos, "export should contain player spawn")
	var enemies: Array = encounter.get("enemies", [])
	assert(enemies.any(func(entry): return entry.get("def_id", "") == "unit_grunt" and entry.get("pos", Vector2i.ZERO) == Vector2i(0, 0)), "export should include spawned grunt")
	var tiles: Array = encounter.get("tiles", [])
	assert(tiles.any(func(entry): return entry.get("tile_id", "") == Constants.TILE_ALTAR and entry.get("pos", Vector2i.ZERO) == Vector2i(0, 1)), "export should include replaced altar")
	var lines: Array = export_result.get("lines", [])
	assert(lines.any(func(line): return "custom_stage_001" in str(line)), "export lines should include encounter id")
	print("  [OK] editor console exports encounter config")


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
