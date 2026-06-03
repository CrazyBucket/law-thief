extends SceneTree

const BombRatRules = preload("res://scripts/rules/bomb_rat_rules.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== Bomb Rat Test ===")
	_test_spawn_black_gem_and_hp()
	_test_chase_when_far()
	_test_suicide_when_adjacent()
	_test_plunder_after_black_lost()
	print("BOMB_RAT_TEST_PASS")
	quit()


func _test_spawn_black_gem_and_hp() -> void:
	var controller := BattleController.new()
	controller.start_encounter("bomb_rat_test", 42)
	var rat := _find_rat(controller.state)
	assert(rat != null, "bomb rat should exist")
	assert(rat.max_hp >= 10 and rat.max_hp <= 15, "hp should be 10+roll, got %d" % rat.max_hp)
	var black := rat.get_slot(Constants.SLOT_BLACK)
	assert(black != null and not black.gem_uid.is_empty(), "black slot should have gem")
	var red := rat.get_slot(Constants.SLOT_RED)
	assert(red != null and red.gem_uid.is_empty(), "red slot should stay empty")
	var blue := rat.get_slot(Constants.SLOT_BLUE)
	assert(blue != null and blue.gem_uid.is_empty(), "blue slot should stay empty")
	print("  [OK] spawn hp=%d black gem mounted" % rat.max_hp)


func _test_chase_when_far() -> void:
	var controller := BattleController.new()
	controller.start_encounter("bomb_rat_test", 42)
	var state := controller.state
	var rat := _find_rat(state)
	rat.pos = Vector2i(7, 7)
	IntentSystem.refresh_unit_intent(state, rat)
	assert(rat.intent.type == "move", "far rat should move, got %s" % rat.intent.type)
	print("  [OK] chase intent: %s" % rat.intent.preview_text)


func _test_suicide_when_adjacent() -> void:
	var controller := BattleController.new()
	controller.start_encounter("bomb_rat_test", 42)
	var state := controller.state
	var rat := _find_rat(state)
	var player := state.get_player()
	rat.pos = player.pos + Vector2i(1, 0)
	IntentSystem.refresh_unit_intent(state, rat)
	assert(rat.intent.type == "black_suicide", "adjacent rat should suicide, got %s" % rat.intent.type)
	var hp_before := player.hp
	IntentSystem.execute_intent(state, rat)
	assert(not rat.alive, "rat should die after suicide")
	var took_effect := player.hp < hp_before or player.has_status(Constants.STATUS_POISON) or player.has_status(Constants.STATUS_SLOWED) or player.has_status(Constants.STATUS_PARALYZED) or player.has_status(Constants.STATUS_SLUGGISH)
	assert(took_effect, "player should suffer black death effect")
	print("  [OK] black suicide kills rat and hits player")


func _test_plunder_after_black_lost() -> void:
	var controller := BattleController.new()
	controller.start_encounter("bomb_rat_test", 42)
	var state := controller.state
	var rat := _find_rat(state)
	var player := state.get_player()
	var reg: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	var gem_uid: String = reg.next_runtime_uid("gem")
	var gem: GemState = reg.create_gem_instance(gem_uid, Constants.GEM_POISON, {})
	state.gems[gem_uid] = gem
	player.get_slot(Constants.SLOT_RED).gem_uid = gem_uid
	gem.owner_uid = player.uid
	gem.slot_index = 0
	rat.pos = player.pos + Vector2i(1, 0)
	rat.get_slot(Constants.SLOT_BLACK).gem_uid = ""
	BombRatRules.sync_plunder_state(state, rat)
	IntentSystem.refresh_unit_intent(state, rat)
	assert(rat.intent.type == "bomb_rat_plunder_wait", "should wait first, got %s" % rat.intent.type)
	IntentSystem.execute_intent(state, rat)
	IntentSystem.refresh_unit_intent(state, rat)
	assert(rat.intent.type == "bomb_rat_plunder_steal",
		"after wait should steal, got %s" % rat.intent.type)
	IntentSystem.execute_intent(state, rat)
	assert(not rat.get_slot(Constants.SLOT_BLACK).gem_uid.is_empty(), "stolen gem should embed in black")
	print("  [OK] plunder wait -> steal -> gem embedded")


func _find_rat(state: GameState) -> UnitState:
	for unit in state.units.values():
		if unit.unit_def_id == "unit_bomb_rat":
			return unit
	return null
