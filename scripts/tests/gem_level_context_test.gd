extends SceneTree

const AttackPipeline = preload("res://scripts/rules/attack_pipeline.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Gem Level Context Test ===")
	_test_poison_red_level_two_cross_fog()
	_test_fire_poison_combo_creates_toxic_smoke()
	_test_ice_red_level_three_freezes_slowed_target()
	_test_gravity_black_level_three_roots_nearby_units()
	if _failed:
		push_error("GEM_LEVEL_CONTEXT_TEST_FAIL")
		quit(1)
		return
	print("GEM_LEVEL_CONTEXT_TEST_PASS")
	quit(0)


func _test_poison_red_level_two_cross_fog() -> void:
	var state := _create_state()
	var player := state.get_player()
	player.pos = Vector2i(2, 3)
	_mount_gems(state, player, Constants.SLOT_RED, [Constants.GEM_POISON, Constants.GEM_POISON])
	var target := _spawn_guard(state, Vector2i(5, 3), "poison_cross_target")
	var result := AttackPipeline.execute_aimed(state, player, target.pos, [AttackPipeline.TAG_RANGED])
	_expect(result.get("ok", false), "poison level 2 attack should succeed")
	for cell in [target.pos, target.pos + Vector2i.LEFT, target.pos + Vector2i.RIGHT, target.pos + Vector2i.UP, target.pos + Vector2i.DOWN]:
		var tile := state.get_tile(cell)
		_expect(tile != null and tile.has_modifier(Constants.TILE_MOD_POISON_FOG), "poison level 2 should fog %s" % [cell])
	print("  [OK] poison red level 2 cross fog")


func _test_fire_poison_combo_creates_toxic_smoke() -> void:
	var state := _create_state()
	var player := state.get_player()
	player.pos = Vector2i(2, 3)
	_mount_gems(state, player, Constants.SLOT_RED, [Constants.GEM_FIRE, Constants.GEM_POISON])
	var target := _spawn_guard(state, Vector2i(5, 3), "toxic_smoke_target")
	var result := AttackPipeline.execute_aimed(state, player, target.pos, [AttackPipeline.TAG_RANGED])
	_expect(result.get("ok", false), "fire + poison attack should succeed")
	var tile := state.get_tile(target.pos)
	_expect(tile != null and tile.has_modifier(Constants.TILE_MOD_TOXIC_SMOKE), "fire + poison should create toxic smoke")
	_expect(_count_events(result.get("events", []), "toxic_smoke") > 0, "fire + poison should emit toxic smoke event")
	print("  [OK] fire + poison creates toxic smoke")


func _test_ice_red_level_three_freezes_slowed_target() -> void:
	var state := _create_state()
	var player := state.get_player()
	player.pos = Vector2i(2, 3)
	_mount_gems(state, player, Constants.SLOT_RED, [Constants.GEM_ICE, Constants.GEM_ICE, Constants.GEM_ICE])
	var target := _spawn_guard(state, Vector2i(5, 3), "ice_freeze_target")
	StatusRules.apply_slowed(state, target, 1, player.uid)
	var result := AttackPipeline.execute_aimed(state, player, target.pos, [AttackPipeline.TAG_RANGED])
	_expect(result.get("ok", false), "ice level 3 attack should succeed")
	_expect(target.has_status(Constants.STATUS_PARALYZED), "ice level 3 should freeze slowed target")
	print("  [OK] ice red level 3 freezes slowed target")


func _test_gravity_black_level_three_roots_nearby_units() -> void:
	var state := _create_state()
	var owner := _spawn_guard(state, Vector2i(4, 4), "gravity_black_owner")
	var victim := _spawn_guard(state, Vector2i(5, 4), "gravity_black_victim")
	_mount_gems(state, owner, Constants.SLOT_BLACK, [Constants.GEM_GRAVITY, Constants.GEM_GRAVITY, Constants.GEM_GRAVITY])
	var hp := owner.hp
	CombatRules.apply_damage(state, owner, hp, "", "test_kill")
	_expect(not owner.alive, "gravity black owner should die")
	_expect(victim.has_status(Constants.STATUS_ROOTED), "gravity black level 3 should root nearby units")
	print("  [OK] gravity black level 3 roots nearby units")


func _create_state() -> GameState:
	var reg: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	var state: GameState = reg.create_battle_state("fission_slime_test", 27182)
	for uid in state.units.keys():
		var unit: UnitState = state.units[uid]
		if unit.team == Constants.TEAM_ENEMY:
			state.unregister_unit(unit)
	var player := state.get_player()
	for slot in player.slots:
		slot.gem_uid = ""
	return state


func _mount_gems(state: GameState, unit: UnitState, slot_type: String, gem_ids: Array[String]) -> void:
	while unit.slots_accepting(slot_type).size() < gem_ids.size():
		unit.slots.append(SlotState.create(slot_type))
	var slots := unit.slots_accepting(slot_type)
	var reg: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	for i in range(gem_ids.size()):
		var slot: SlotState = slots[i]
		var gem_uid: String = reg.next_runtime_uid("level_gem")
		var gem := GemState.create(gem_uid, gem_ids[i], {})
		gem.owner_uid = unit.uid
		gem.slot_index = unit.slots.find(slot)
		state.gems[gem_uid] = gem
		slot.gem_uid = gem_uid


func _spawn_guard(state: GameState, pos: Vector2i, uid: String) -> UnitState:
	var guard := UnitState.new()
	guard.uid = uid
	guard.unit_def_id = "unit_patrol_guard"
	guard.team = Constants.TEAM_ENEMY
	guard.pos = pos
	guard.hp = 50
	guard.max_hp = 50
	guard.speed = 5
	guard.base_attack = 4
	guard.alive = true
	state.register_unit(guard)
	return guard


func _count_events(events: Array, event_type: String) -> int:
	var total := 0
	for ev in events:
		if str(ev.get("type", "")) == event_type:
			total += 1
	return total


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
