extends SceneTree
## 红槽宝石攻击触发测试：验证玩家装备红槽宝石后，攻击命中时附带效果正确触发


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Red Gem Attack Trigger Test ===")
	_test_attack_without_red_gem()
	_test_explosion_triggers_on_attack_hit()
	_test_poison_triggers_on_attack_hit()
	_test_poison_fogs_target_not_attacker()
	_test_explosion_on_empty_cell()
	_test_explosion_splash_damages_neighbor()
	_test_fire_gem_burns_target_not_attacker()
	_test_light_beam_hits_line_targets()
	_test_counter_red_triggers_followup()
	_test_gravity_red_range_extends_attack()
	_test_gravity_red_pulls_attack_target()
	_test_gravity_red_collision_when_adjacent()
	print("SKILL_TEST_PASS")
	quit()


func _test_attack_without_red_gem() -> void:
	print("--- Test: Attack without red gem produces no bonus events ---")
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	var player := state.get_player()
	var guard: UnitState = null
	for unit in state.units.values():
		if unit.unit_def_id == "unit_patrol_guard":
			guard = unit
			break
	assert(guard != null, "guard should exist")
	assert(player.get_slot(Constants.SLOT_RED).gem_uid.is_empty(), "red slot should be empty")
	var result := ctrl.try_attack_cell(guard.pos)
	assert(result.get("ok", false), "attack should succeed")
	var events: Array = result.get("attack_events", [])
	var has_explode := events.any(func(e): return e.get("type", "") == "explode")
	assert(not has_explode, "no explosion without red gem")
	print("  [OK] no bonus effect without red gem")


func _test_explosion_triggers_on_attack_hit() -> void:
	print("--- Test: Explosion red gem triggers on attack hit ---")
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	var player := state.get_player()
	var gem := GemState.new()
	gem.uid = "test_explosion_red"
	gem.gem_id = Constants.GEM_EXPLOSION
	state.gems[gem.uid] = gem
	player.get_slot(Constants.SLOT_RED).gem_uid = gem.uid
	var guard: UnitState = null
	for unit in state.units.values():
		if unit.unit_def_id == "unit_patrol_guard":
			guard = unit
			break
	assert(guard != null, "guard should exist")
	var hp_before := guard.hp
	var result := ctrl.try_attack_cell(guard.pos)
	assert(result.get("ok", false), "attack should succeed: %s" % result.get("reason", ""))
	assert(guard.hp < hp_before, "guard should take damage")
	assert(state.player_acted, "attack should consume action")
	var events: Array = result.get("attack_events", [])
	assert(not events.is_empty(), "should return animation events")
	var has_explode := events.any(func(e): return e.get("type", "") == "explode")
	assert(has_explode, "explosion gem should produce explode event on hit")
	print("  [OK] explosion gem triggered on attack hit, dealt %d total damage" % (hp_before - guard.hp))


func _test_poison_triggers_on_attack_hit() -> void:
	print("--- Test: Poison red gem triggers on attack hit ---")
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	var player := state.get_player()
	var gem := GemState.new()
	gem.uid = "test_poison_red"
	gem.gem_id = Constants.GEM_POISON
	state.gems[gem.uid] = gem
	player.get_slot(Constants.SLOT_RED).gem_uid = gem.uid
	var guard: UnitState = null
	for unit in state.units.values():
		if unit.unit_def_id == "unit_patrol_guard":
			guard = unit
			break
	assert(guard != null, "guard should exist")
	var result := ctrl.try_attack_cell(guard.pos)
	assert(result.get("ok", false), "attack should succeed")
	var events: Array = result.get("attack_events", [])
	var has_poison := events.any(func(e): return e.get("type", "") == "poison_burst")
	assert(has_poison, "poison gem should produce poison_burst event on hit")
	print("  [OK] poison gem triggered on attack hit")


func _test_poison_fogs_target_not_attacker() -> void:
	print("--- Test: Poison red gem fogs target area, not attacker ---")
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	var player := state.get_player()
	var gem := GemState.new()
	gem.uid = "test_poison_fog"
	gem.gem_id = Constants.GEM_POISON
	state.gems[gem.uid] = gem
	player.get_slot(Constants.SLOT_RED).gem_uid = gem.uid
	var guard: UnitState = null
	for unit in state.units.values():
		if unit.unit_def_id == "unit_patrol_guard":
			guard = unit
			break
	assert(guard != null, "guard should exist")
	var result := ctrl.try_attack_cell(guard.pos)
	assert(result.get("ok", false), "attack should succeed")
	var player_tile := state.get_tile(player.pos)
	var guard_tile := state.get_tile(guard.pos)
	assert(
		not player_tile.has_modifier(Constants.TILE_MOD_POISON_FOG),
		"player tile should not have poison fog"
	)
	assert(
		guard_tile.has_modifier(Constants.TILE_MOD_POISON_FOG),
		"target tile should have poison fog"
	)
	assert(guard.has_status(Constants.STATUS_POISON), "target should be poisoned")
	print("  [OK] poison fog on target only")


func _test_explosion_on_empty_cell() -> void:
	print("--- Test: Explosion red gem triggers on empty cell ---")
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	var player := state.get_player()
	var gem := GemState.new()
	gem.uid = "test_explosion_empty"
	gem.gem_id = Constants.GEM_EXPLOSION
	state.gems[gem.uid] = gem
	player.get_slot(Constants.SLOT_RED).gem_uid = gem.uid
	var empty := player.pos + Vector2i(2, 0)
	if state.get_unit_at(empty) != null:
		empty = player.pos + Vector2i(0, 2)
	var result := ctrl.try_attack_cell(empty)
	assert(result.get("ok", false), "attack empty should succeed")
	var events: Array = result.get("attack_events", [])
	var explode_ev: Dictionary = {}
	for ev in events:
		if ev.get("type", "") == "explode":
			explode_ev = ev
			break
	assert(not explode_ev.is_empty(), "should emit explode on empty cell")
	assert(explode_ev.get("pattern", "") == "cross", "should be cross pattern")
	var cells: Array = explode_ev.get("cells", [])
	assert(cells.size() == 5, "cross should cover 5 cells, got %d" % cells.size())
	print("  [OK] explosion on empty cell")


func _test_explosion_splash_damages_neighbor() -> void:
	print("--- Test: Explosion red gem splash damages adjacent unit ---")
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	var player := state.get_player()
	var gem := GemState.new()
	gem.uid = "test_explosion_splash"
	gem.gem_id = Constants.GEM_EXPLOSION
	state.gems[gem.uid] = gem
	player.get_slot(Constants.SLOT_RED).gem_uid = gem.uid
	var guards: Array[UnitState] = []
	for unit in state.units.values():
		if unit.unit_def_id == "unit_patrol_guard" and unit.alive:
			guards.append(unit)
	assert(not guards.is_empty(), "need at least 1 guard")
	var primary := guards[0]
	var neighbor := guards[1] if guards.size() >= 2 else _spawn_test_guard(state, primary.pos + Vector2i(1, 0), "splash_guard")
	neighbor.pos = primary.pos + Vector2i(1, 0)
	assert(BoardUtils.chebyshev(primary.pos, neighbor.pos) == 1, "neighbor setup")
	var primary_hp := primary.hp
	var neighbor_hp := neighbor.hp
	var result := ctrl.try_attack_cell(primary.pos)
	assert(result.get("ok", false), "attack should succeed")
	assert(primary.hp < primary_hp, "primary target should take hit damage")
	assert(neighbor.hp < neighbor_hp, "neighbor should take explosion splash (%d -> %d)" % [neighbor_hp, neighbor.hp])
	print("  [OK] explosion splash damages neighbor (%d -> %d)" % [neighbor_hp, neighbor.hp])


func _test_fire_gem_burns_target_not_attacker() -> void:
	print("--- Test: Fire red gem burns target, not attacker ---")
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	var player := state.get_player()
	var gem := GemState.new()
	gem.uid = "test_fire_red"
	gem.gem_id = Constants.GEM_FIRE
	state.gems[gem.uid] = gem
	player.get_slot(Constants.SLOT_RED).gem_uid = gem.uid
	var guard: UnitState = null
	for unit in state.units.values():
		if unit.unit_def_id == "unit_patrol_guard":
			guard = unit
			break
	assert(guard != null, "guard should exist")
	var result := ctrl.try_attack_cell(guard.pos)
	assert(result.get("ok", false), "attack should succeed")
	assert(guard.has_status(Constants.STATUS_BURNING), "guard should be burning")
	assert(not player.has_status(Constants.STATUS_BURNING), "player should not be burning")
	print("  [OK] fire gem burns target only")


func _test_light_beam_hits_line_targets() -> void:
	print("--- Test: Light red gem hits targets in a line ---")
	var state: GameState = _data_registry().create_battle_state("fission_slime_test", 24680)
	for uid in state.units.keys():
		var unit: UnitState = state.units[uid]
		if unit.team == Constants.TEAM_ENEMY:
			state.unregister_unit(unit)
	var player := state.get_player()
	var gem := GemState.new()
	gem.uid = "test_light_red"
	gem.gem_id = Constants.GEM_LIGHT
	state.gems[gem.uid] = gem
	player.get_slot(Constants.SLOT_RED).gem_uid = gem.uid
	gem.owner_uid = player.uid
	gem.slot_index = player.slots.find(player.get_slot(Constants.SLOT_RED))
	player.pos = Vector2i(1, 1)
	var first := _spawn_test_guard(state, Vector2i(3, 1), "light_guard_1")
	var second := _spawn_test_guard(state, Vector2i(4, 1), "light_guard_2")
	state.rebuild_occupancy()
	var hp_first := first.hp
	var hp_second := second.hp
	var result := AttackPipeline.execute_aimed(state, player, first.pos, [AttackPipeline.TAG_RANGED])
	assert(result.get("ok", false), "light attack should succeed")
	assert(first.hp < hp_first, "front target should take light beam damage")
	assert(second.hp < hp_second, "beam should continue and hit the second target")
	assert(result.get("events", []).any(func(e): return str(e.get("type", "")) == "light_beam"), "light attack should emit light_beam")
	print("  [OK] light red beam hits line targets")


func _test_counter_red_triggers_followup() -> void:
	print("--- Test: Counter red gem can trigger follow-up damage ---")
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	var player := state.get_player()
	var gem := GemState.new()
	gem.uid = "test_counter_red"
	gem.gem_id = Constants.GEM_COUNTER
	state.gems[gem.uid] = gem
	player.get_slot(Constants.SLOT_RED).gem_uid = gem.uid
	gem.owner_uid = player.uid
	gem.slot_index = player.slots.find(player.get_slot(Constants.SLOT_RED))
	var guard: UnitState = null
	for unit in state.units.values():
		if unit.unit_def_id == "unit_patrol_guard":
			guard = unit
			break
	assert(guard != null, "guard should exist")
	state.battle_temp_flags["damaged_by:%s:%s:%d" % [player.uid, guard.uid, state.turn_index]] = true
	var hp_before := guard.hp
	var result := ctrl.try_attack_cell(guard.pos)
	assert(result.get("ok", false), "counter attack should succeed")
	assert(hp_before - guard.hp >= CombatRules.attack_damage(state, player) * 2, "counter follow-up should add another full hit")
	print("  [OK] counter red triggers follow-up")


func _test_gravity_red_range_extends_attack() -> void:
	print("--- Test: Gravity red gem extends attack range ---")
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	var player := state.get_player()
	var red_slot := player.get_slot(Constants.SLOT_RED)
	var first := GemState.new()
	first.uid = "test_gravity_red_1"
	first.gem_id = Constants.GEM_GRAVITY
	state.gems[first.uid] = first
	red_slot.gem_uid = first.uid
	first.owner_uid = player.uid
	first.slot_index = player.slots.find(red_slot)
	var extra_slot := SlotState.create(Constants.SLOT_RED)
	player.slots.append(extra_slot)
	var second := GemState.new()
	second.uid = "test_gravity_red_2"
	second.gem_id = Constants.GEM_GRAVITY
	state.gems[second.uid] = second
	extra_slot.gem_uid = second.uid
	second.owner_uid = player.uid
	second.slot_index = player.slots.find(extra_slot)
	var far_aim := player.pos + Vector2i(4, 0)
	assert(BoardUtils.in_bounds(state, far_aim), "far aim should stay inside board")
	ctrl.select_action(Constants.ACTION_ATTACK)
	var highlights := ctrl.get_highlights()
	assert(far_aim in highlights.get("attack_range", []), "gravity level 2 should expose far cell in attack preview")
	var result := ctrl.try_attack_cell(far_aim)
	assert(result.get("ok", false), "gravity level 2 should extend attack range to 4")
	var events: Array = result.get("attack_events", [])
	assert(events.any(func(e): return str(e.get("type", "")) == "gem_flash"), "gravity attack should emit gem flash")
	print("  [OK] gravity red range extends attack")


func _test_gravity_red_pulls_attack_target() -> void:
	print("--- Test: Gravity red gem pulls attack target after hit ---")
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	var player := state.get_player()
	var red_slot := player.get_slot(Constants.SLOT_RED)
	var gem := GemState.new()
	gem.uid = "test_gravity_pull_gem"
	gem.gem_id = Constants.GEM_GRAVITY
	state.gems[gem.uid] = gem
	red_slot.gem_uid = gem.uid
	gem.owner_uid = player.uid
	gem.slot_index = player.slots.find(red_slot)
	var far_aim := player.pos + Vector2i(4, 0)
	var guard := _spawn_test_guard(state, far_aim, "test_gravity_pull_target")
	var start_pos := guard.pos
	ctrl.select_action(Constants.ACTION_ATTACK)
	var result := ctrl.try_attack_cell(far_aim)
	assert(result.get("ok", false), "gravity should allow extended attack")
	var events: Array = result.get("attack_events", [])
	assert(events.any(func(e): return str(e.get("type", "")) == "move_step"), "gravity should pull attack target")
	assert(guard.pos != start_pos, "attack target should move toward player after gravity hit")
	print("  [OK] gravity red pulls attack target")


func _test_gravity_red_collision_when_adjacent() -> void:
	print("--- Test: Gravity pull collides when adjacent ---")
	var ctrl := BattleController.new()
	ctrl.start_encounter("tutorial_001")
	var state := ctrl.state
	var player := state.get_player()
	var gem := GemState.new()
	gem.uid = "test_gravity_collision_gem"
	gem.gem_id = Constants.GEM_GRAVITY
	state.gems[gem.uid] = gem
	player.get_slot(Constants.SLOT_RED).gem_uid = gem.uid
	var guard := _spawn_test_guard(state, player.pos + Vector2i(1, 0), "test_gravity_collision_target")
	guard.hp = 50
	var player_hp_before := player.hp
	ctrl.select_action(Constants.ACTION_ATTACK)
	var result := ctrl.try_attack_cell(guard.pos)
	assert(result.get("ok", false), "adjacent gravity attack should succeed")
	var events: Array = result.get("attack_events", [])
	var collision_damage := events.filter(func(e: Dictionary) -> bool:
		return str(e.get("type", "")) == "damage" and str(e.get("uid", "")) == player.uid
	)
	assert(not collision_damage.is_empty(), "gravity pull into player should deal collision damage to player")
	assert(player.hp < player_hp_before, "player should take collision damage when enemy pulled in")
	print("  [OK] gravity red collision when adjacent")


func _spawn_test_guard(state: GameState, pos: Vector2i, uid: String) -> UnitState:
	var guard := UnitState.new()
	guard.uid = uid
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


func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node("DataRegistry")
