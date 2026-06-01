extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Explosion Test ===")
	_test_cross_splash_damages_neighbor()
	_test_multicell_target_no_splash_self()
	_test_radius_explosion_dedupes_multicell()
	_test_aim_cell_shifts_cross_center()
	print("EXPLOSION_TEST_PASS")
	quit()


func _test_cross_splash_damages_neighbor() -> void:
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	var player := state.get_player()
	_equip_red_explosion(state, player)
	var guards := _guards(state)
	assert(guards.size() >= 1)
	var primary := guards[0]
	var neighbor := _spawn_guard(state, primary.pos + Vector2i(1, 0))
	state.rebuild_occupancy()
	var neighbor_hp := neighbor.hp
	var result := ctrl.try_attack_cell(primary.pos)
	assert(result.get("ok", false))
	assert(neighbor.hp < neighbor_hp, "orthogonal neighbor should take cross splash")
	print("  [OK] cross splash hits neighbor")


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
	var events := GemEffects.explode_at(state, slime.pos, Constants.EXPLOSION_DAMAGE, player.uid)
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


func _equip_red_explosion(state: GameState, unit: UnitState) -> void:
	var gem := GemState.new()
	gem.uid = "test_explosion_%s" % unit.uid
	gem.gem_id = Constants.GEM_EXPLOSION
	state.gems[gem.uid] = gem
	unit.get_slot(Constants.SLOT_RED).gem_uid = gem.uid


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
