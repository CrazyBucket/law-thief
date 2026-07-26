extends SceneTree

const BombRatRules = preload("res://scripts/rules/bomb_rat_rules.gd")
const PresentationPlanner = preload("res://scripts/ui/battle_presentation_planner.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== Bomb Rat Test ===")
	_test_spawn_black_gem_and_hp()
	_test_chase_when_far()
	_test_suicide_when_adjacent()
	_test_chase_suicide_presentation_order()
	_test_plunder_after_black_lost()
	_test_lawless_waits_then_steals_nearest_unit_gem()
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
	_force_gem(state, rat, Constants.SLOT_BLACK, Constants.GEM_EXPLOSION)
	state.move_unit(rat, player.pos + Vector2i(1, 0))
	IntentSystem.refresh_unit_intent(state, rat)
	assert(rat.intent.type == "black_suicide", "adjacent rat should suicide, got %s" % rat.intent.type)
	var hp_before := player.hp
	IntentSystem.execute_intent(state, rat)
	assert(not rat.alive, "rat should die after suicide")
	assert(player.hp < hp_before, "player should suffer black death explosion")
	print("  [OK] black suicide kills rat and hits player")


func _test_chase_suicide_presentation_order() -> void:
	var controller := BattleController.new()
	controller.start_encounter("bomb_rat_test", 42)
	var state := controller.state
	var rat := _find_rat(state)
	var player := state.get_player()
	_force_gem(state, rat, Constants.SLOT_BLACK, Constants.GEM_IMPACT)
	IntentSystem.refresh_unit_intent(state, rat)
	assert(rat.intent.type == "black_suicide" and not rat.intent.path.is_empty())
	var events := IntentSystem.execute_intent(state, rat)
	var plan := PresentationPlanner.build(events)
	assert(plan.violations.is_empty())
	assert(plan.beats.size() >= 2)
	var approach: Dictionary = plan.beats[0]
	var death_reaction: Dictionary = plan.beats[1]
	assert(approach.kind == "move" and approach.mode == PresentationPlanner.MODE_SERIAL)
	assert(approach.visuals.all(func(event): return event.uid == rat.uid and not bool(event.get("forced", false))))
	assert(death_reaction.kind == "move")
	assert(death_reaction.visuals.all(func(event): return event.uid == player.uid and bool(event.get("forced", false))))
	print("  [OK] chase movement finishes before black-impact displacement")


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
	state.move_unit(rat, player.pos + Vector2i(1, 0))
	rat.get_slot(Constants.SLOT_BLACK).gem_uid = ""
	BombRatRules.sync_plunder_state(state, rat)
	IntentSystem.refresh_unit_intent(state, rat)
	assert(rat.intent.type == "bomb_rat_plunder_wait", "should wait first, got %s" % rat.intent.type)
	IntentSystem.execute_intent(state, rat)
	IntentSystem.refresh_unit_intent(state, rat)
	assert(rat.intent.type == "bomb_rat_plunder_steal",
		"after wait should steal, got %s" % rat.intent.type)
	var hp_before := player.hp
	IntentSystem.execute_intent(state, rat)
	assert(player.hp < hp_before, "plunder steal should damage nearest unit")
	assert(rat.get_slot(Constants.SLOT_BLACK).gem_uid == gem_uid, "stolen gem should embed in black")
	assert(player.get_slot(Constants.SLOT_RED).gem_uid.is_empty(), "target gem should be stolen")
	IntentSystem.refresh_unit_intent(state, rat)
	assert(rat.intent.type != "bomb_rat_plunder_wait", "rat with stolen black gem should leave plunder loop")
	print("  [OK] plunder wait -> steal -> gem embedded")


func _test_lawless_waits_then_steals_nearest_unit_gem() -> void:
	var controller := BattleController.new()
	controller.start_encounter("bomb_rat_test", 42)
	var state := controller.state
	var rat := _find_rat(state)
	var player := state.get_player()
	var reg: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	state.move_unit(rat, Vector2i(3, 3))
	state.move_unit(player, Vector2i(6, 3))
	var guard := UnitState.from_def(
		"near_guard",
		"unit_patrol_guard",
		Constants.TEAM_ENEMY,
		rat.pos + Vector2i(0, 1),
		reg.get_unit_def("unit_patrol_guard")
	)
	state.register_unit(guard)
	_force_gem(state, player, Constants.SLOT_RED, Constants.GEM_POISON)
	var guard_gem_uid := _force_gem(state, guard, Constants.SLOT_RED, Constants.GEM_GRAVITY)
	rat.get_slot(Constants.SLOT_BLACK).gem_uid = ""
	StatusRules.apply_lawless(state, rat, "stolen_missing")
	IntentSystem.refresh_unit_intent(state, rat)
	assert(rat.intent.type == "bomb_rat_plunder_wait", "lawless rat should wait first, got %s" % rat.intent.type)
	IntentSystem.execute_intent(state, rat)
	IntentSystem.refresh_unit_intent(state, rat)
	assert(rat.intent.target_uid == guard.uid, "lawless rat should target nearest gem-carrying unit, got %s" % rat.intent.target_uid)
	assert(rat.intent.type == "bomb_rat_plunder_steal", "adjacent nearest gem carrier should be stolen from")
	IntentSystem.execute_intent(state, rat)
	assert(rat.get_slot(Constants.SLOT_BLACK).gem_uid == guard_gem_uid, "rat should steal nearest unit gem into black")
	assert(guard.get_slot(Constants.SLOT_RED).gem_uid.is_empty(), "nearest unit gem should be removed")
	assert(not StatusRules.is_lawless(rat), "rat should leave lawless after stealing a gem")
	print("  [OK] lawless rat waits then steals nearest unit gem")


func _force_gem(state: GameState, unit: UnitState, slot_type: String, gem_id: String) -> String:
	var reg: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	var slot := unit.get_slot(slot_type)
	if slot == null:
		return ""
	if not slot.gem_uid.is_empty():
		state.gems.erase(slot.gem_uid)
	var gem_uid: String = reg.next_runtime_uid("test_gem")
	var gem: GemState = reg.create_gem_instance(gem_uid, gem_id, {})
	state.gems[gem_uid] = gem
	slot.gem_uid = gem_uid
	gem.owner_uid = unit.uid
	gem.slot_index = unit.slots.find(slot)
	return gem_uid


func _find_rat(state: GameState) -> UnitState:
	for unit in state.units.values():
		if unit.unit_def_id == "unit_bomb_rat":
			return unit
	return null
