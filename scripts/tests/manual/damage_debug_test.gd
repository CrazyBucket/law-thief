extends SceneTree

const CombatConfig = preload("res://scripts/core/combat_config.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Damage Debug Test ===")
	_test_bomb_rat_adjacent_suicide()
	_test_explosion_diagonal()
	_test_armor_blocks_explosion()
	_test_melee_attack()
	_test_player_ranged_attack_penetrates_obstacle()
	_test_player_ranged_attack_keeps_empty_aim_behind_obstacle()
	print("DAMAGE_DEBUG_PASS")
	quit()


func _test_bomb_rat_adjacent_suicide() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	var rat := _find(state, "unit_bomb_rat")
	var player := state.get_player()
	_force_gem(state, rat, Constants.SLOT_BLACK, Constants.GEM_EXPLOSION)
	rat.pos = player.pos + Vector2i(1, 0)
	IntentSystem.refresh_all_intents(state)
	assert(rat.intent.type == "black_suicide", "expected black_suicide, got %s" % rat.intent.type)
	var hp_before := player.hp
	var events := IntentSystem.execute_intent(state, rat)
	assert(player.hp < hp_before, "player should take explosion damage, hp %d -> %d" % [hp_before, player.hp])
	assert(not events.is_empty(), "should emit animation events")
	print("  [OK] bomb rat adjacent suicide deals damage (%d -> %d)" % [hp_before, player.hp])


func _test_explosion_diagonal() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	var rat := _find(state, "unit_bomb_rat")
	var player := state.get_player()
	rat.pos = player.pos + Vector2i(1, 1)
	assert(BoardUtils.manhattan(rat.pos, player.pos) == 2, "setup diagonal adjacency")
	assert(BoardUtils.chebyshev(rat.pos, player.pos) == 1, "player should be in blast radius")
	var hp_before := player.hp
	GemEffects.explode_at(state, rat.pos, CombatConfig.explosion_damage(), rat.uid)
	assert(player.hp < hp_before, "diagonal explosion should still damage player")
	print("  [OK] diagonal explosion (%d -> %d)" % [hp_before, player.hp])


func _test_armor_blocks_explosion() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	var rat := _find(state, "unit_bomb_rat")
	var player := state.get_player()
	rat.pos = player.pos + Vector2i(1, 1)
	StatusRules.apply_armor(state, player, CombatConfig.explosion_damage(), 1)
	var hp_before := player.hp
	GemEffects.explode_at(state, player.pos, CombatConfig.explosion_damage(), rat.uid)
	assert(player.hp == hp_before, "armor should fully block explosion damage")
	var blocked := false
	for line in state.combat_log:
		if "护盾" in line:
			blocked = true
	assert(blocked, "shield block should be logged")
	print("  [OK] shield blocks explosion with log")


func _test_melee_attack() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	var guard := _find(state, "unit_patrol_guard")
	var player := state.get_player()
	guard.pos = player.pos + Vector2i(1, 0)
	IntentSystem.refresh_all_intents(state)
	var hp_before := player.hp
	IntentSystem.execute_intent(state, guard)
	assert(player.hp < hp_before, "melee should deal damage")
	print("  [OK] melee attack deals damage (%d -> %d)" % [hp_before, player.hp])


func _test_player_ranged_attack_penetrates_obstacle() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	var player := state.get_player()
	var guard := _find(state, "unit_patrol_guard")
	player.pos = Vector2i(3, 2)
	guard.pos = Vector2i(5, 2)
	state.rebuild_occupancy()
	var prop := EntityState.create("block_prop", Constants.ENTITY_PROP, Vector2i(4, 2))
	state.add_entity(prop)
	var hp_before := guard.hp
	var result := ctrl.try_attack_cell(guard.pos)
	assert(result.get("ok", false), "ranged attack should penetrate obstacles")
	assert(guard.hp < hp_before, "target behind obstacle should take damage")
	print("  [OK] ranged attack penetrates obstacle and damages target")


func _test_player_ranged_attack_keeps_empty_aim_behind_obstacle() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	var player := state.get_player()
	player.pos = Vector2i(3, 2)
	state.rebuild_occupancy()
	_force_gem(state, player, Constants.SLOT_RED, Constants.GEM_FIRE)
	var prop := EntityState.create("block_prop_empty_aim", Constants.ENTITY_PROP, Vector2i(4, 2))
	state.add_entity(prop)
	var aim := Vector2i(5, 2)
	assert(state.get_unit_at(aim) == null, "aim cell should stay empty for obstacle aim test")
	assert(not state.get_tile(aim).has_modifier(Constants.TILE_MOD_FIRE), "aim cell should start without fire")
	var result := ctrl.try_attack_cell(aim)
	assert(result.get("ok", false), "player should keep empty aim cell behind obstacle")
	assert(state.get_tile(aim).has_modifier(Constants.TILE_MOD_FIRE), "fire effect should land on chosen cell behind obstacle")
	assert(not state.get_tile(prop.pos).has_modifier(Constants.TILE_MOD_FIRE), "front obstacle cell should not steal the aimed ground effect")
	print("  [OK] ranged attack keeps empty aim behind obstacle")


func _force_gem(state: GameState, unit: UnitState, slot_type: String, gem_id: String) -> void:
	var reg: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	var slot := unit.get_slot(slot_type)
	if slot == null:
		return
	if not slot.gem_uid.is_empty():
		state.gems.erase(slot.gem_uid)
	var gem_uid: String = reg.next_runtime_uid("gem")
	var gem: GemState = reg.create_gem_instance(gem_uid, gem_id, {})
	state.gems[gem_uid] = gem
	slot.gem_uid = gem_uid
	gem.owner_uid = unit.uid
	gem.slot_index = unit.slots.find(slot)


func _find(state: GameState, def_id: String) -> UnitState:
	for unit in state.units.values():
		if unit.unit_def_id == def_id:
			return unit
	return null
