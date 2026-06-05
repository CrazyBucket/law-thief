extends SceneTree

const AttackPipeline = preload("res://scripts/rules/attack_pipeline.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Gem Combo Test ===")
	_test_explosion_fire_combo()
	_test_explosion_poison_combo()
	_test_fire_poison_combo()
	if _failed:
		push_error("GEM_COMBO_TEST_FAIL")
		quit(1)
		return
	print("GEM_COMBO_TEST_PASS")
	quit(0)


func _test_explosion_fire_combo() -> void:
	var state := _create_state()
	var player := state.get_player()
	player.pos = Vector2i(2, 3)
	_mount_red_gems(state, player, [Constants.GEM_EXPLOSION, Constants.GEM_FIRE])
	var target := _spawn_guard(state, Vector2i(5, 3))
	var result := AttackPipeline.execute_aimed(state, player, target.pos, [AttackPipeline.TAG_RANGED])
	_expect(result.get("ok", false), "explosion + fire attack should succeed")
	var tile := state.get_tile(target.pos)
	_expect(tile != null and tile.has_modifier(Constants.TILE_MOD_FIRE), "explosion + fire should leave fire")
	_expect(_count_combo_events(result.get("events", []), "fire_burst", "explosion_fire") > 0, "explosion + fire should emit combo fire")
	print("  [OK] explosion + fire")


func _test_explosion_poison_combo() -> void:
	var state := _create_state()
	var player := state.get_player()
	player.pos = Vector2i(2, 3)
	_mount_red_gems(state, player, [Constants.GEM_EXPLOSION, Constants.GEM_POISON])
	var target := _spawn_guard(state, Vector2i(5, 3))
	var result := AttackPipeline.execute_aimed(state, player, target.pos, [AttackPipeline.TAG_RANGED])
	_expect(result.get("ok", false), "explosion + poison attack should succeed")
	var tile := state.get_tile(target.pos)
	_expect(tile != null and tile.has_modifier(Constants.TILE_MOD_POISON_FOG), "explosion + poison should leave poison fog")
	_expect(_count_combo_events(result.get("events", []), "poison_burst", "explosion_poison") > 0, "explosion + poison should emit combo poison")
	print("  [OK] explosion + poison")


func _test_fire_poison_combo() -> void:
	var state := _create_state()
	var player := state.get_player()
	player.pos = Vector2i(2, 3)
	_mount_red_gems(state, player, [Constants.GEM_FIRE, Constants.GEM_POISON])
	var target := _spawn_guard(state, Vector2i(5, 3))
	var result := AttackPipeline.execute_aimed(state, player, target.pos, [AttackPipeline.TAG_RANGED])
	_expect(result.get("ok", false), "fire + poison attack should succeed")
	var tile := state.get_tile(target.pos)
	_expect(tile != null and tile.has_modifier("toxic_smoke"), "fire + poison should leave toxic smoke")
	_expect(_count_combo_events(result.get("events", []), "toxic_smoke", "fire_poison") > 0, "fire + poison should emit toxic smoke combo")
	print("  [OK] fire + poison")


func _create_state() -> GameState:
	var reg: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	var state: GameState = reg.create_battle_state("fission_slime_test", 31415)
	for uid in state.units.keys():
		var unit: UnitState = state.units[uid]
		if unit.team == Constants.TEAM_ENEMY:
			state.unregister_unit(unit)
	var player := state.get_player()
	for slot in player.slots:
		slot.gem_uid = ""
	return state


func _mount_red_gems(state: GameState, unit: UnitState, gem_ids: Array) -> void:
	while unit.slots_accepting(Constants.SLOT_RED).size() < gem_ids.size():
		unit.slots.append(SlotState.create(Constants.SLOT_RED))
	var slots := unit.slots_accepting(Constants.SLOT_RED)
	var reg: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	for i in range(gem_ids.size()):
		var slot: SlotState = slots[i]
		var gem_uid: String = reg.next_runtime_uid("combo_gem")
		var gem := GemState.create(gem_uid, str(gem_ids[i]), {})
		gem.owner_uid = unit.uid
		gem.slot_index = unit.slots.find(slot)
		state.gems[gem_uid] = gem
		slot.gem_uid = gem_uid


func _spawn_guard(state: GameState, pos: Vector2i) -> UnitState:
	var guard := UnitState.new()
	guard.uid = "combo_guard_%d_%d" % [pos.x, pos.y]
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


func _count_combo_events(events: Array, event_type: String, combo_id: String) -> int:
	var n := 0
	for ev in events:
		if str(ev.get("type", "")) == event_type and str(ev.get("combo", "")) == combo_id:
			n += 1
	return n


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
