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
