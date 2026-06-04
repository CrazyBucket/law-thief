extends SceneTree


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
	_test_water_conduction_hits_unit_standing_in_water()
	_test_editor_console_spawns_and_edits_unit()
	_test_editor_console_batch_move_delete_commands()
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


func _test_water_conduction_hits_unit_standing_in_water() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("template_c", 42)
	var state := ctrl.state
	var player := state.get_player()
	assert(ctrl.run_editor_command("move 1,6 2,5").get("ok", false), "move player in range of water")
	assert(ctrl.run_editor_command("spawn unit_patrol_guard 4,5 --team enemy").get("ok", false), "spawn enemy in water")
	assert(ctrl.run_editor_command("spawn gem_conductive 2,5 --slot red").get("ok", false), "give player arc gem")
	var guard := state.get_unit_at(Vector2i(4, 5))
	assert(guard != null, "enemy should stand on water")
	assert(StatusRules.is_wet(guard), "standing in water should apply wet")
	var hp_before := guard.hp
	var atk := ctrl.try_attack_cell(Vector2i(4, 5))
	assert(atk.get("ok", false), "attack water should succeed")
	assert(guard.hp < hp_before, "enemy in water should take arc damage from water shock")
	print("  [OK] water conduction hits unit standing in water")


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


func _force_red_gem(state: GameState, unit: UnitState, gem_id: String) -> void:
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
