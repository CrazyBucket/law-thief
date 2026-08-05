extends SceneTree

const CombatConfig = preload("res://scripts/core/combat_config.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Explosion Test ===")
	_test_cross_splash_damages_friendly_unit()
	_test_multicell_target_no_splash_self()
	_test_radius_explosion_dedupes_multicell()
	_test_aim_cell_shifts_cross_center()
	_test_red_explosion_level_4_clamps_to_level_3()
	_test_active_trigger_level_2_uses_square()
	_test_active_trigger_level_4_clamps_to_level_3()
	print("EXPLOSION_TEST_PASS")
	quit()


func _test_cross_splash_damages_friendly_unit() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001", 43)
	var state := ctrl.state
	var player := state.get_player()
	_equip_red_explosion(state, player)
	var primary := _guards(state)[0]
	var ally := _spawn_guard(state, primary.pos + Vector2i(1, 0))
	ally.team = Constants.TEAM_PLAYER
	state.rebuild_occupancy()
	var hp_before := ally.hp
	var result := ctrl.try_attack_cell(primary.pos)
	assert(result.get("ok", false))
	assert(hp_before - ally.hp == 6, "explosion splash should damage friendly units")
	print("  [OK] explosion splash is friendly fire")


func _test_multicell_target_no_splash_self() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("fission_slime_test", 42)
	var state := ctrl.state
	var player := state.get_player()
	var slime := _find_slime(state)
	_equip_red_explosion(state, player)
	player.pos = slime.pos + Vector2i(-2, 0)
	state.rebuild_occupancy()
	var aim := slime.pos + Vector2i(1, 0)
	assert(slime.pos in slime.occupied_cells())
	assert(aim in slime.occupied_cells())
	var hp_before := slime.hp
	var result := ctrl.try_attack_cell(aim)
	assert(result.get("ok", false), "attack footprint cell should succeed")
	var direct_events := 0
	for ev in result.get("attack_events", []):
		if ev.get("type", "") != "damage" or ev.get("pos", Vector2i.ZERO) != slime.pos:
			continue
		direct_events += 1
	assert(direct_events == 1, "primary multi-cell target should only take one direct damage event")
	assert(slime.hp < hp_before)
	print("  [OK] multi-cell primary not splashed twice")


func _test_radius_explosion_dedupes_multicell() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("fission_slime_test", 42)
	var state := ctrl.state
	var slime := _find_slime(state)
	var player := state.get_player()
	player.pos = slime.pos + Vector2i(2, 0)
	var hp_before := slime.hp
	var events := GemEffects.explode_at(state, slime.pos, CombatConfig.explosion_damage(), player.uid)
	var slime_hits := 0
	for ev in events:
		if ev.get("type", "") == "damage" and ev.get("pos", Vector2i.ZERO) == slime.pos:
			slime_hits += 1
	assert(slime_hits == 1, "radius explosion should damage each unit once, got %d" % slime_hits)
	assert(slime.hp < hp_before)
	print("  [OK] radius explosion dedupes multi-cell unit")


func _test_aim_cell_shifts_cross_center() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("fission_slime_test", 42)
	var state := ctrl.state
	var player := state.get_player()
	var slime := _find_slime(state)
	_equip_red_explosion(state, player)
	player.pos = slime.pos + Vector2i(-2, 0)
	state.rebuild_occupancy()
	var guard := _spawn_guard(state, slime.pos + Vector2i(2, 0))
	var aim := slime.pos + Vector2i(1, 0)
	var guard_hp := guard.hp
	var result := ctrl.try_attack_cell(aim)
	assert(result.get("ok", false))
	assert(guard.hp < guard_hp, "guard at edge of cross from aim cell should be splashed")
	print("  [OK] cross centers on aim cell")


func _test_red_explosion_level_4_clamps_to_level_3() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001", 2027)
	var state := ctrl.state
	var player := state.get_player()
	_equip_red_explosions(state, player, 4)
	var guards := _guards(state)
	assert(guards.size() >= 1)
	var primary := guards[0]
	var soak := _spawn_guard(state, primary.pos + Vector2i(1, 1))
	soak.hp = 100
	soak.max_hp = 100
	state.rebuild_occupancy()
	var hp_before := soak.hp
	var result := ctrl.try_attack_cell(primary.pos)
	assert(result.get("ok", false))
	assert(soak.hp < hp_before, "diagonal unit should take square explosion damage")
	var dealt := hp_before - soak.hp
	assert(dealt == player.base_attack, "four gems should clamp to level 3 100%% base_attack splash, got %d" % dealt)
	var explode_ev := _first_explode_event(result.get("attack_events", []))
	assert(explode_ev.get("pattern", "") == "square", "four gems should clamp to authored level 3 pattern")
	print("  [OK] red explosion count above max clamps to level 3")


func _test_active_trigger_level_2_uses_square() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001", 2026)
	var state := ctrl.state
	var player := state.get_player()
	_equip_red_explosions(state, player, 2)
	var guards := _guards(state)
	assert(guards.size() >= 1)
	var primary := guards[0]
	var diagonal := _spawn_guard(state, primary.pos + Vector2i(1, 1))
	state.rebuild_occupancy()
	var diagonal_hp := diagonal.hp
	var events: Array[Dictionary] = []
	var red_slot: SlotState = player.slots_accepting(Constants.SLOT_RED)[0]
	var ok := GemEffects.trigger_gem(state, player.uid, red_slot, events, "", primary.pos)
	assert(ok, "active trigger should succeed")
	var explode_ev := _first_explode_event(events)
	assert(explode_ev.get("pattern", "") == "square", "active level 2 explosion should use square pattern")
	assert(diagonal.hp < diagonal_hp, "active level 2 square explosion should hit diagonal unit")
	print("  [OK] active red explosion level 2 square")


func _test_active_trigger_level_4_clamps_to_level_3() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001", 2028)
	var state := ctrl.state
	var player := state.get_player()
	_equip_red_explosions(state, player, 4)
	var guards := _guards(state)
	assert(guards.size() >= 1)
	var primary := guards[0]
	var soak := _spawn_guard(state, primary.pos + Vector2i(1, 1))
	soak.hp = 100
	soak.max_hp = 100
	state.rebuild_occupancy()
	var hp_before := soak.hp
	var events: Array[Dictionary] = []
	var red_slot: SlotState = player.slots_accepting(Constants.SLOT_RED)[0]
	var ok := GemEffects.trigger_gem(state, player.uid, red_slot, events, "", primary.pos)
	assert(ok, "active trigger should succeed")
	assert(hp_before - soak.hp == player.base_attack, "active trigger should clamp to level 3 100% base_attack splash")
	print("  [OK] active explosion count above max clamps to level 3")


func _equip_red_explosion(state: GameState, unit: UnitState) -> void:
	_equip_red_explosions(state, unit, 1)


func _equip_red_explosions(state: GameState, unit: UnitState, count: int) -> void:
	while unit.slots_accepting(Constants.SLOT_RED).size() < count:
		unit.slots.append(SlotState.create(Constants.SLOT_RED))
	var red_slots := unit.slots_accepting(Constants.SLOT_RED)
	for i in range(count):
		var slot: SlotState = red_slots[i]
		if not slot.gem_uid.is_empty():
			state.gems.erase(slot.gem_uid)
		var gem := GemState.new()
		gem.uid = "test_explosion_%s_%d" % [unit.uid, i]
		gem.gem_id = Constants.GEM_EXPLOSION
		gem.owner_uid = unit.uid
		gem.slot_index = unit.slots.find(slot)
		state.gems[gem.uid] = gem
		slot.gem_uid = gem.uid


func _first_explode_event(events: Array) -> Dictionary:
	for ev in events:
		if str(ev.get("type", "")) == "explode":
			return ev
	return {}


func _guards(state: GameState) -> Array[UnitState]:
	var out: Array[UnitState] = []
	for unit in state.units.values():
		if unit.unit_def_id == "unit_patrol_guard" and unit.alive:
			out.append(unit)
	return out


func _find_slime(state: GameState) -> UnitState:
	for unit in state.units.values():
		if unit.unit_def_id == "unit_fission_slime":
			return unit
	return null


func _spawn_guard(state: GameState, pos: Vector2i) -> UnitState:
	var guard := UnitState.new()
	guard.uid = "test_guard_%d_%d" % [pos.x, pos.y]
	guard.unit_def_id = "unit_patrol_guard"
	guard.team = Constants.TEAM_ENEMY
	guard.pos = pos
	guard.hp = 20
	guard.max_hp = 20
	guard.speed = 5
	guard.base_attack = 4
	guard.alive = true
	state.register_unit(guard)
	return guard
