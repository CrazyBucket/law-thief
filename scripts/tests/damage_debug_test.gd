extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Damage Debug Test ===")
	_test_bomber_adjacent_explosion()
	_test_bomber_diagonal_explosion()
	_test_armor_blocks_explosion()
	_test_melee_attack()
	print("DAMAGE_DEBUG_PASS")
	quit()


func _test_bomber_adjacent_explosion() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	var bomber := _find(state, "unit_bomber")
	var player := state.get_player()
	bomber.pos = player.pos + Vector2i(1, 0)
	IntentSystem.refresh_all_intents(state)
	assert(bomber.intent.type == "charge_explode", "expected charge_explode, got %s" % bomber.intent.type)
	var hp_before := player.hp
	var events := IntentSystem.execute_intent(state, bomber)
	assert(player.hp < hp_before, "player should take explosion damage, hp %d -> %d" % [hp_before, player.hp])
	assert(not events.is_empty(), "should emit animation events")
	print("  [OK] bomber adjacent explosion deals damage (%d -> %d)" % [hp_before, player.hp])


func _test_armor_blocks_explosion() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	var bomber := _find(state, "unit_bomber")
	var player := state.get_player()
	bomber.pos = player.pos + Vector2i(1, 1)
	var gem := GemState.new()
	gem.uid = "blue_armor"
	gem.gem_id = Constants.GEM_HEAVY_ARMOR
	state.gems[gem.uid] = gem
	player.slots[1].gem_uid = gem.uid
	var hp_before := player.hp
	GemEffects.explode_at(state, player.pos, Constants.EXPLOSION_DAMAGE, bomber.uid)
	assert(player.hp == hp_before, "2 armor should fully block 2 explosion damage")
	var blocked := false
	for line in state.combat_log:
		if "护甲吸收" in line:
			blocked = true
	assert(blocked, "armor block should be logged")
	print("  [OK] heavy armor blocks explosion with log")


func _test_bomber_diagonal_explosion() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	var bomber := _find(state, "unit_bomber")
	var player := state.get_player()
	bomber.pos = player.pos + Vector2i(1, 1)
	assert(BoardUtils.manhattan(bomber.pos, player.pos) == 2, "setup diagonal adjacency")
	assert(BoardUtils.chebyshev(bomber.pos, player.pos) == 1, "player should be in blast radius")
	var hp_before := player.hp
	var events := GemEffects.on_red_action(state, bomber, _make_explode_intent(state, player.uid))
	assert(player.hp < hp_before, "diagonal self-destruct should still damage player")
	assert(not events.is_empty(), "should emit explosion events")
	print("  [OK] diagonal bomber explosion (%d -> %d)" % [hp_before, player.hp])


func _test_melee_attack() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	var guard := _find(state, "unit_training_guard")
	var player := state.get_player()
	guard.pos = player.pos + Vector2i(1, 0)
	IntentSystem.refresh_all_intents(state)
	var hp_before := player.hp
	IntentSystem.execute_intent(state, guard)
	assert(player.hp < hp_before, "melee should deal damage")
	print("  [OK] melee attack deals damage (%d -> %d)" % [hp_before, player.hp])


func _find(state: GameState, def_id: String) -> UnitState:
	for unit in state.units.values():
		if unit.unit_def_id == def_id:
			return unit
	return null


func _make_explode_intent(state: GameState, target_uid: String) -> IntentState:
	var intent := IntentState.new()
	intent.type = "charge_explode"
	intent.target_uid = target_uid
	intent.source_uid = target_uid
	return intent
