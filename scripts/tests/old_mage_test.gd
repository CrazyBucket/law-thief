extends SceneTree

const OldMageBehavior = preload("res://scripts/rules/behaviors/behavior_old_mage.gd")
const GemTransfer = preload("res://scripts/rules/gem_transfer.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== Old Mage Test ===")
	_test_initial_cast_destroy_refill_loop()
	_test_editor_spawn_initializes_spell_loadout()
	_test_manual_pool_insert_recovers_spell_loop()
	_test_editor_gem_insert_recovers_with_other_empty_slot()
	_test_exhausted_refill_target_uses_remaining_spell()
	_test_pool_field_stays_connected_across_seeds()
	_test_ten_turn_pressure_keeps_casting()
	_test_blue_spell_can_use_planned_movement()
	_test_blue_control_spell_table()
	_test_ice_consumes_wet()
	_test_blue_light_reflects_to_two_targets()
	_test_red_spell_table()
	_test_blue_conductive_requires_and_hits_active_attacker()
	_test_blue_explosion_centers_on_planned_endpoint()
	_test_impact_charge_keeps_locked_row()
	_test_non_pool_decoy_skips_turn()
	_test_low_hp_blackens_a_slot_each_turn_and_locks_move_to_two()
	_test_low_hp_preview_slot_stays_locked_after_extract()
	print("OLD_MAGE_TEST_PASS")
	quit()


func _new_state() -> GameState:
	return _new_controller().state


func _new_controller() -> BattleController:
	var controller := BattleController.new()
	controller.start_encounter("boss_chapter_1", 7, "", false)
	return controller


func _mage(state: GameState) -> UnitState:
	for enemy in state.get_alive_enemies():
		if enemy.behavior_id == "old_mage":
			return enemy
	return null


func _test_initial_cast_destroy_refill_loop() -> void:
	var state := _new_state()
	var mage := _mage(state)
	assert(mage != null, "old mage should be present")
	assert(mage.max_hp == 90 and mage.base_attack == 8, "old mage must use the documented 90 HP / 8 base attack baseline")
	assert(mage.move_points == 2, "three loaded slots should give MV 2")
	assert(mage.slots.filter(func(slot): return not slot.gem_uid.is_empty()).size() == 3, "mage starts full")
	assert(mage.slots.any(func(slot): return slot.slot_type == Constants.SLOT_RED), "initial slots need at least one red slot")
	assert(mage.slots.any(func(slot): return slot.slot_type == Constants.SLOT_BLUE), "initial slots need at least one blue slot")
	assert(mage.slots.all(func(slot): return slot.slot_type in [Constants.SLOT_RED, Constants.SLOT_BLUE]), "initial slots must not include black")
	var initial_gem_ids: Array[String] = []
	for slot in mage.slots:
		initial_gem_ids.append(state.gems[slot.gem_uid].gem_id)
	assert(initial_gem_ids.duplicate().filter(func(gem_id): return initial_gem_ids.count(gem_id) > 1).is_empty(), "initial pool gems must not repeat")
	IntentSystem.refresh_unit_intent(state, mage)
	assert(mage.intent.type in ["mage_spell", "mage_impact_charge"], "first mage turn should cast")
	var cast_uid := str(mage.intent.plan_metadata.get("mage_gem_uid", ""))
	IntentSystem.execute_intent(state, mage)
	assert(not state.gems.has(cast_uid), "cast gem must be permanently destroyed")
	assert(mage.move_points == 3, "one empty slot should give MV 3")
	IntentSystem.refresh_unit_intent(state, mage)
	assert(mage.intent.type == "mage_refill", "after casting mage must refill instead of casting again")
	assert(mage.intent.preview_effects.any(func(effect): return effect.kind == "mage_pool_candidate"), "refill must preview all pool candidates")
	assert(mage.intent.preview_effects.any(func(effect): return effect.kind == "mage_pool_lock"), "refill must preview its locked gem")
	IntentSystem.execute_intent(state, mage)
	assert(mage.slots.filter(func(slot): return not slot.gem_uid.is_empty()).size() == 3, "refill should restore exactly one slot")
	print("  [OK] cast -> destroy -> refill loop")


func _test_editor_spawn_initializes_spell_loadout() -> void:
	var controller := _new_controller()
	var state := controller.state
	var original := _mage(state)
	state.unregister_unit(original)
	var editor := BattleEditorCli.new()
	editor.setup(controller)
	var result := editor.run("/spawn unit_old_mage 6,2")
	assert(result.get("ok", false), "editor should spawn old mage")
	var mage: UnitState = state.get_unit_at(Vector2i(6, 2))
	assert(mage != null and mage.behavior_id == "old_mage", "editor spawn should create old mage")
	assert(mage.slots.filter(func(slot): return not slot.gem_uid.is_empty()).size() == 3, "editor-spawned old mage must start with three gems")
	IntentSystem.refresh_unit_intent(state, mage)
	assert(mage.intent.type == "mage_spell", "editor-spawned old mage must open with a spell, not staff")
	print("  [OK] editor spawn initializes spell loadout")


func _test_manual_pool_insert_recovers_spell_loop() -> void:
	var state := _new_state()
	var mage := _mage(state)
	for slot in mage.slots:
		if not slot.gem_uid.is_empty():
			GemTransfer.remove(state, slot.gem_uid)
	mage.slots[0].slot_type = Constants.SLOT_RED
	state.battle_temp_flags["old_mage:%s:phase" % mage.uid] = "refill"
	state.battle_temp_flags["old_mage:%s:refill_gem_uid" % mage.uid] = "missing_gem"
	var registry: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	var uid: String = registry.next_runtime_uid("gem")
	var gem: GemState = registry.create_gem_instance(uid, "gem_explosion", {})
	state.gems[uid] = gem
	var player := state.get_player()
	state.move_unit(player, mage.pos + Vector2i(0, 1))
	assert(GemTransfer.to_hand(state, gem, player.uid), "manual pool gem should be held")
	var insert := GemRules.insert(state, player, mage, mage.slots[0])
	assert(insert.get("ok", false), "manual pool gem should insert")
	IntentSystem.refresh_unit_intent(state, mage)
	assert(mage.intent.type == "mage_spell", "a manually inserted pool gem must cast before any refill")
	IntentSystem.execute_intent(state, mage)
	assert(not state.gems.has(uid), "a manually inserted pool gem must be consumed by the spell")
	var repaired_state := _new_state()
	var repaired_mage := _mage(repaired_state)
	IntentSystem.refresh_unit_intent(repaired_state, repaired_mage)
	IntentSystem.execute_intent(repaired_state, repaired_mage)
	var repaired_slot: SlotState = repaired_mage.slots.filter(func(slot): return slot.gem_uid.is_empty())[0]
	repaired_slot.slot_type = Constants.SLOT_RED
	var repaired_uid: String = registry.next_runtime_uid("gem")
	var repaired_gem: GemState = registry.create_gem_instance(repaired_uid, "gem_explosion", {})
	repaired_state.gems[repaired_uid] = repaired_gem
	assert(GemTransfer.to_unit_slot(repaired_state, repaired_gem, repaired_mage, repaired_slot), "external slot mutation should load")
	IntentSystem.refresh_unit_intent(repaired_state, repaired_mage)
	assert(repaired_mage.intent.type == "mage_spell", "a full refill slot must recover from stale refill phase")
	print("  [OK] manual pool insert recovers spell loop")


func _test_editor_gem_insert_recovers_with_other_empty_slot() -> void:
	var controller := _new_controller()
	var state := controller.state
	var mage := _mage(state)
	IntentSystem.refresh_unit_intent(state, mage)
	IntentSystem.execute_intent(state, mage)
	var emptied := mage.slots.filter(func(slot): return slot.gem_uid.is_empty()).size()
	for slot in mage.slots:
		if not slot.gem_uid.is_empty():
			GemTransfer.remove(state, slot.gem_uid)
			emptied += 1
			break
	assert(emptied == 2, "fixture needs two empty slots")
	var target_index := -1
	for index in range(mage.slots.size()):
		if mage.slots[index].gem_uid.is_empty():
			target_index = index
			break
	mage.slots[target_index].slot_type = Constants.SLOT_RED
	var result := controller.run_editor_action("spawn_gem", {
		"gem_id": "gem_explosion",
		"pos": mage.pos,
		"target_kind": "unit",
		"slot_index": target_index,
	})
	assert(result.get("ok", false), "editor should insert a pool gem")
	assert(mage.slots.filter(func(slot): return slot.gem_uid.is_empty()).size() == 1, "one unrelated slot should remain empty")
	assert(mage.intent.type == "mage_spell", "editor-inserted pool gem must cast even while another slot is empty")
	var inserted_uid: String = mage.slots[target_index].gem_uid
	IntentSystem.execute_intent(state, mage)
	assert(not state.gems.has(inserted_uid), "editor-inserted pool gem must be consumed")
	print("  [OK] editor gem insert recovers with another empty slot")


func _test_exhausted_refill_target_uses_remaining_spell() -> void:
	var state := _new_state()
	var mage := _mage(state)
	IntentSystem.refresh_unit_intent(state, mage)
	IntentSystem.execute_intent(state, mage)
	for slot in mage.slots:
		if not slot.gem_uid.is_empty():
			slot.slot_type = Constants.SLOT_RED
	var external_pool_uids: Array[String] = []
	for gem_uid in state.gems.keys():
		var gem: GemState = state.gems.get(str(gem_uid), null)
		if gem != null and gem.gem_id in OldMageBehavior.POOL_IDS and gem.location.owner_uid != mage.uid:
			external_pool_uids.append(gem.uid)
	for gem_uid in external_pool_uids:
		GemTransfer.remove(state, gem_uid)
	IntentSystem.refresh_unit_intent(state, mage)
	assert(mage.intent.type in ["mage_spell", "mage_impact_charge"], "no refill target must release a remaining loaded spell")
	print("  [OK] exhausted refill target uses remaining spell")


func _test_non_pool_decoy_skips_turn() -> void:
	var state := _new_state()
	var mage := _mage(state)
	IntentSystem.refresh_unit_intent(state, mage)
	IntentSystem.execute_intent(state, mage)
	var empty_index := -1
	for index in range(mage.slots.size()):
		if mage.slots[index].gem_uid.is_empty():
			empty_index = index
			break
	assert(empty_index >= 0, "cast should create one empty slot")
	var registry: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	var uid: String = registry.next_runtime_uid("gem")
	var decoy: GemState = registry.create_gem_instance(uid, "gem_echo", {})
	state.gems[uid] = decoy
	var player := state.get_player()
	state.move_unit(player, mage.pos + Vector2i(0, 1))
	assert(GemTransfer.to_hand(state, decoy, player.uid), "test decoy should be held by player")
	var check := GemRules.can_insert(state, player, mage, mage.slots[empty_index])
	assert(check.get("ok", false) and not check.get("requires_overload", true), "decoy insert must bypass overload")
	assert(GemTransfer.to_unit_slot(state, decoy, mage, mage.slots[empty_index]), "test decoy should insert")
	IntentSystem.refresh_unit_intent(state, mage)
	assert(mage.intent.type == "mage_destroy_decoy", "non-pool gem must telegraph a skipped turn")
	IntentSystem.execute_intent(state, mage)
	assert(not state.gems.has(uid), "decoy must be destroyed")
	assert(mage.slots[empty_index].gem_uid.is_empty(), "destroyed decoy leaves refill slot empty")
	IntentSystem.refresh_unit_intent(state, mage)
	assert(mage.intent.type == "mage_refill", "destroying a decoy must resume refill before another spell")
	print("  [OK] non-pool decoy destroys and skips")


func _test_pool_field_stays_connected_across_seeds() -> void:
	for seed in range(1, 13):
		var controller := BattleController.new()
		controller.start_encounter("boss_chapter_1", seed, "", false)
		var state: GameState = controller.state
		var mage := _mage(state)
		var remaining: Array[Vector2i] = []
		for drop in state.dropped_gems.values():
			if drop is Dictionary and bool((drop as Dictionary).get("old_mage_pool", false)):
				remaining.append((drop as Dictionary).get("pos", Vector2i(-1, -1)))
		assert(remaining.size() == 8, "pool field must spawn eight gems for seed %d" % seed)
		var connected: Array[Vector2i] = []
		while not remaining.is_empty():
			var found := -1
			for index in range(remaining.size()):
				var within_chain := false
				if connected.is_empty():
					within_chain = BoardUtils.path_distance_to_cell(state, mage.pos, remaining[index], mage.uid, {}, mage) <= 3
				else:
					for linked in connected:
						if BoardUtils.path_distance_to_cell(state, linked, remaining[index], mage.uid, {}, mage) <= 3:
							within_chain = true
							break
				if within_chain:
					found = index
					break
			assert(found >= 0, "pool field must remain refill-connected for seed %d" % seed)
			connected.append(remaining[found])
			remaining.remove_at(found)
	print("  [OK] pool field stays refill-connected across seeds")


func _test_ten_turn_pressure_keeps_casting() -> void:
	var controller := _new_controller()
	var state := controller.state
	var mage := _mage(state)
	var player := state.get_player()
	player.hp = 200
	player.max_hp = 200
	var casts := 0
	var damage := 0
	var used_dodge := false
	for _turn in range(10):
		var hp_before := player.hp
		controller.begin_enemy_phase()
		for enemy in controller.get_sorted_enemies():
			if enemy.uid == mage.uid:
				IntentSystem.refresh_unit_intent(state, enemy)
				if enemy.intent.type in ["mage_spell", "mage_impact_charge"]:
					casts += 1
					if not used_dodge and _dodge_one_locked_mage_spell(state, player, enemy.intent):
						used_dodge = true
			controller.execute_single_enemy(enemy)
		controller.finish_enemy_phase()
		damage += hp_before - player.hp
	assert(casts >= 4, "baseline ten-turn loop should produce at least four casts, got %d" % casts)
	assert(used_dodge, "baseline should include one legal response to a telegraphed spell")
	assert(damage >= 25 and damage <= 35, "baseline ten-turn damage should stay near 30, got %d" % damage)
	print("  [OK] ten-turn loop casts %d times for %d damage" % [casts, damage])


func _dodge_one_locked_mage_spell(state: GameState, player: UnitState, intent: IntentState) -> bool:
	if player.pos not in intent.affected_cells:
		return false
	for direction: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var candidate: Vector2i = player.pos + direction
		if not BoardUtils.in_bounds(state, candidate) or candidate in intent.affected_cells:
			continue
		if not BoardUtils.is_passable(state, candidate, player.uid):
			continue
		state.move_unit(player, candidate)
		return true
	return false


func _test_blue_spell_can_use_planned_movement() -> void:
	var state := _new_state()
	var mage := _mage(state)
	state.move_unit(mage, Vector2i(1, 4))
	var registry: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	for slot in mage.slots:
		if not slot.gem_uid.is_empty():
			GemTransfer.remove(state, slot.gem_uid)
		slot.slot_type = Constants.SLOT_BLUE
		var uid: String = registry.next_runtime_uid("gem")
		var gem: GemState = registry.create_gem_instance(uid, "gem_fire", {})
		state.gems[uid] = gem
		assert(GemTransfer.to_unit_slot(state, gem, mage, slot), "test fire gem should load")
	IntentSystem.refresh_unit_intent(state, mage)
	assert(mage.intent.type == "mage_spell", "blue fire should be executable after planned movement")
	assert(not mage.intent.path.is_empty(), "blue spell should preview its approach path")
	IntentSystem.execute_intent(state, mage)
	assert(state.get_player().has_status(Constants.STATUS_BURNING), "blue fire should apply burning after moving adjacent")
	print("  [OK] blue spell uses planned movement")


func _test_red_spell_table() -> void:
	var cases := [
		{"gem": "gem_explosion", "damage": 12, "status": ""},
		{"gem": "gem_conductive", "damage": 6, "status": ""},
		{"gem": "gem_fire", "damage": 4, "status": ""},
		{"gem": "gem_ice", "damage": 4, "status": Constants.STATUS_SLOWED},
		{"gem": "gem_poison", "damage": 2, "status": Constants.STATUS_POISON},
		{"gem": "gem_light", "damage": 9, "status": Constants.STATUS_LIGHT_EXPOSED},
	]
	for spec in cases:
		var state := _new_state()
		var mage := _mage(state)
		_load_spell_gems(state, mage, str(spec["gem"]), Constants.SLOT_RED)
		var player := state.get_player()
		var hp_before := player.hp
		IntentSystem.refresh_unit_intent(state, mage)
		assert(mage.intent.type == "mage_spell", "%s should create a red spell intent" % spec["gem"])
		IntentSystem.execute_intent(state, mage)
		assert(player.hp == hp_before - int(spec["damage"]), "%s should deal its documented direct damage" % spec["gem"])
		if not str(spec["status"]).is_empty():
			assert(player.has_status(str(spec["status"])), "%s should apply its documented status" % spec["gem"])
		if str(spec["gem"]) == "gem_fire":
			assert(state.get_tile(player.pos).has_modifier(Constants.TILE_MOD_FIRE), "red fire should leave two-turn floor fire")
		if str(spec["gem"]) == "gem_poison":
			assert(state.get_tile(player.pos).has_modifier(Constants.TILE_MOD_POISON_FOG), "red poison should leave two-turn poison fog")
	print("  [OK] red spell table damages and statuses")


func _test_blue_control_spell_table() -> void:
	for spec in [
		{"gem": "gem_ice", "status": Constants.STATUS_SLOWED},
		{"gem": "gem_poison", "status": Constants.STATUS_POISON},
	]:
		var state := _new_state()
		var mage := _mage(state)
		state.move_unit(mage, Vector2i(1, 4))
		_load_spell_gems(state, mage, str(spec["gem"]), Constants.SLOT_BLUE)
		IntentSystem.refresh_unit_intent(state, mage)
		assert(mage.intent.type == "mage_spell", "%s should be executable after planned movement" % spec["gem"])
		IntentSystem.execute_intent(state, mage)
		assert(state.get_player().has_status(str(spec["status"])), "%s should apply its blue-slot control" % spec["gem"])
	var impact_state := _new_state()
	var impact_mage := _mage(impact_state)
	_load_spell_gems(impact_state, impact_mage, "gem_impact", Constants.SLOT_BLUE)
	var source := impact_state.get_player()
	impact_state.battle_temp_flags["last_active_attacker:%s" % impact_mage.uid] = source.uid
	var distance_before := BoardUtils.manhattan(impact_mage.pos, source.pos)
	IntentSystem.refresh_unit_intent(impact_state, impact_mage)
	assert(impact_mage.intent.type == "mage_spell", "blue impact needs a recent active attacker")
	assert(not impact_mage.intent.plan_metadata.get("mage_retreat_path", []).is_empty(), "blue impact must preview its retreat route")
	IntentSystem.execute_intent(impact_state, impact_mage)
	assert(BoardUtils.manhattan(impact_mage.pos, source.pos) >= distance_before, "blue impact must end no closer to its attack source")
	print("  [OK] blue control spell table")


func _test_ice_consumes_wet() -> void:
	var red_state := _new_state()
	var red_mage := _mage(red_state)
	_load_spell_gems(red_state, red_mage, "gem_ice", Constants.SLOT_RED)
	var red_player := red_state.get_player()
	StatusRules.apply_wet(red_state, red_player, 2, red_mage.uid)
	IntentSystem.refresh_unit_intent(red_state, red_mage)
	IntentSystem.execute_intent(red_state, red_mage)
	assert(red_player.has_status(Constants.STATUS_FROZEN), "red boss ice should freeze a wet player")
	assert(not red_player.has_status(Constants.STATUS_WET), "red boss ice should consume wet")

	var blue_state := _new_state()
	var blue_mage := _mage(blue_state)
	blue_state.move_unit(blue_mage, Vector2i(1, 4))
	_load_spell_gems(blue_state, blue_mage, "gem_ice", Constants.SLOT_BLUE)
	var blue_player := blue_state.get_player()
	StatusRules.apply_wet(blue_state, blue_player, 2, blue_mage.uid)
	IntentSystem.refresh_unit_intent(blue_state, blue_mage)
	IntentSystem.execute_intent(blue_state, blue_mage)
	assert(blue_player.has_status(Constants.STATUS_FROZEN), "blue boss ice should freeze a wet player")
	assert(not blue_player.has_status(Constants.STATUS_WET), "blue boss ice should consume wet")
	print("  [OK] boss ice consumes wet when it freezes")


func _test_blue_light_reflects_to_two_targets() -> void:
	var state := _new_state()
	var mage := _mage(state)
	var source := state.get_player()
	state.move_unit(mage, Vector2i(3, 3))
	state.move_unit(source, Vector2i(3, 5))
	var ally := UnitState.new()
	ally.uid = "old_mage_light_ally"
	ally.unit_def_id = "unit_player"
	ally.team = Constants.TEAM_PLAYER
	ally.pos = Vector2i(5, 4)
	ally.hp = 30
	ally.max_hp = 30
	ally.speed = 5
	ally.base_attack = 6
	state.register_unit(ally)
	_load_spell_gems(state, mage, "gem_light", Constants.SLOT_BLUE)
	state.battle_temp_flags["last_active_attacker:%s" % mage.uid] = source.uid
	state.battle_temp_flags["last_active_attack_ranged:%s" % mage.uid] = true
	IntentSystem.refresh_unit_intent(state, mage)
	assert(mage.intent.type == "mage_spell", "blue light needs a ranged source and a second reflected path")
	var source_hp := source.hp
	var ally_hp := ally.hp
	IntentSystem.execute_intent(state, mage)
	assert(source.hp == source_hp - 5 and ally.hp == ally_hp - 5, "blue light must hit each beam target once")
	assert(source.has_status(Constants.STATUS_LIGHT_EXPOSED) and ally.has_status(Constants.STATUS_LIGHT_EXPOSED), "blue light must expose both targets")
	print("  [OK] blue light reflects to two targets")


func _load_spell_gems(state: GameState, mage: UnitState, gem_id: String, slot_type: String) -> void:
	var registry: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	for slot in mage.slots:
		if not slot.gem_uid.is_empty():
			GemTransfer.remove(state, slot.gem_uid)
		slot.slot_type = slot_type
		var uid: String = registry.next_runtime_uid("gem")
		var gem: GemState = registry.create_gem_instance(uid, gem_id, {})
		state.gems[uid] = gem
		assert(GemTransfer.to_unit_slot(state, gem, mage, slot), "test gem should load")


func _test_impact_charge_keeps_locked_row() -> void:
	var state := _new_state()
	var mage := _mage(state)
	var registry: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	for slot in mage.slots:
		if not slot.gem_uid.is_empty():
			GemTransfer.remove(state, slot.gem_uid)
		slot.slot_type = Constants.SLOT_RED
		var uid: String = registry.next_runtime_uid("gem")
		var gem: GemState = registry.create_gem_instance(uid, "gem_impact", {})
		state.gems[uid] = gem
		assert(GemTransfer.to_unit_slot(state, gem, mage, slot), "test impact gem should load")
	IntentSystem.refresh_unit_intent(state, mage)
	assert(mage.intent.type == "mage_impact_charge", "red impact must use horizontal charge")
	var locked_row := mage.intent.target_pos.y
	var player := state.get_player()
	state.move_unit(player, Vector2i(player.pos.x, locked_row - 1))
	IntentSystem.refresh_unit_intent(state, mage)
	assert(mage.intent.target_pos.y == locked_row, "impact must retain the row locked before player moved")
	var hp_before := player.hp
	IntentSystem.execute_intent(state, mage)
	assert(player.hp == hp_before, "player leaving the locked row must avoid impact damage")
	assert(mage.pos.y == locked_row, "impact charge must finish on the locked row")
	print("  [OK] impact charge keeps locked row")


func _test_blue_explosion_centers_on_planned_endpoint() -> void:
	var state := _new_state()
	var mage := _mage(state)
	state.move_unit(mage, Vector2i(1, 5))
	var registry: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	for slot in mage.slots:
		if not slot.gem_uid.is_empty():
			GemTransfer.remove(state, slot.gem_uid)
		slot.slot_type = Constants.SLOT_BLUE
		var uid: String = registry.next_runtime_uid("gem")
		var gem: GemState = registry.create_gem_instance(uid, "gem_explosion", {})
		state.gems[uid] = gem
		assert(GemTransfer.to_unit_slot(state, gem, mage, slot), "test explosion gem should load")
	IntentSystem.refresh_unit_intent(state, mage)
	assert(mage.intent.type == "mage_spell", "blue explosion should be legal at its planned endpoint")
	var endpoint: Vector2i = mage.intent.path.back() if not mage.intent.path.is_empty() else mage.pos
	var events := IntentSystem.execute_intent(state, mage)
	var blast := events.filter(func(event): return str(event.get("type", "")) == "explode")
	assert(not blast.is_empty() and blast[0].get("pos", Vector2i(-1, -1)) == endpoint, "blue explosion must center on the planned endpoint")
	print("  [OK] blue explosion centers on endpoint")


func _test_blue_conductive_requires_and_hits_active_attacker() -> void:
	var state := _new_state()
	var mage := _mage(state)
	var registry: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	for slot in mage.slots:
		if not slot.gem_uid.is_empty():
			GemTransfer.remove(state, slot.gem_uid)
		slot.slot_type = Constants.SLOT_BLUE
		var uid: String = registry.next_runtime_uid("gem")
		var gem: GemState = registry.create_gem_instance(uid, "gem_conductive", {})
		state.gems[uid] = gem
		assert(GemTransfer.to_unit_slot(state, gem, mage, slot), "test conductive gem should load")
	IntentSystem.refresh_unit_intent(state, mage)
	assert(mage.intent.type != "mage_spell", "blue conductive needs an active attacker")
	var player := state.get_player()
	state.battle_temp_flags["last_active_attacker:%s" % mage.uid] = player.uid
	state.battle_temp_flags["last_active_attack_turn:%s" % mage.uid] = state.turn_index
	IntentSystem.refresh_unit_intent(state, mage)
	assert(mage.intent.type == "mage_spell", "blue conductive should become legal after an active hit")
	assert(player.pos in mage.intent.affected_cells, "conductive preview must lock the active attacker")
	var hp_before := player.hp
	IntentSystem.execute_intent(state, mage)
	assert(player.hp == hp_before - 8, "conductive primary target takes 8 damage")
	print("  [OK] blue conductive locks active attacker")


func _test_low_hp_blackens_a_slot_each_turn_and_locks_move_to_two() -> void:
	var state := _new_state()
	var mage := _mage(state)
	mage.hp = 19
	OldMageBehavior.on_turn_start(state, mage)
	var black_slots := mage.slots.filter(func(slot): return slot.slot_type == Constants.SLOT_BLACK)
	assert(black_slots.size() == 1, "first low-hp turn should blacken exactly one slot")
	assert(mage.move_points == 2, "low-hp mage movement must stay at 2")
	OldMageBehavior.on_turn_start(state, mage)
	OldMageBehavior.on_turn_start(state, mage)
	black_slots = mage.slots.filter(func(slot): return slot.slot_type == Constants.SLOT_BLACK)
	assert(black_slots.size() == 3, "each low-hp boss turn should blacken another slot")
	print("  [OK] low HP blackens one slot each turn at MV 2")


func _test_low_hp_preview_slot_stays_locked_after_extract() -> void:
	var state := _new_state()
	var mage := _mage(state)
	mage.hp = 19
	IntentSystem.refresh_unit_intent(state, mage)
	var key := "old_mage:%s:next_black_slot" % mage.uid
	var marked := int(state.battle_temp_flags.get(key, -1))
	assert(marked >= 0, "low-hp intent must premark a blackening slot")
	if not mage.slots[marked].gem_uid.is_empty():
		GemTransfer.remove(state, mage.slots[marked].gem_uid)
	IntentSystem.refresh_unit_intent(state, mage)
	assert(int(state.battle_temp_flags.get(key, -1)) == marked, "extracting the marked gem must not retarget blackening")
	OldMageBehavior.on_turn_start(state, mage)
	assert(mage.slots[marked].slot_type == Constants.SLOT_BLACK, "the premarked slot must be the slot that blackens")
	print("  [OK] low HP blackening preview stays locked")
