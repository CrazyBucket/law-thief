extends SceneTree


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Status System Test ===")
	_test_poison_stack_and_tick()
	_test_armor_max_value_merge()
	_test_shield_consumed_on_hit()
	_test_relic_grants_shield_not_unit_armor()
	_test_rooted_blocks_move()
	_test_lawless_payload()
	_test_exposed_expires()
	_test_default_status_values_from_config()
	_test_status_combat_multipliers_from_config()
	_test_disarm_blocks_one_action()
	_test_relic_numeric_refs_runtime()
	print("STATUS_TEST_PASS")
	quit()


func _test_poison_stack_and_tick() -> void:
	var state := _make_state()
	var unit := _make_unit(state, "u1")
	StatusRules.apply_poison(state, unit, 1, 2)
	StatusRules.apply_poison(state, unit, 2, 3)
	var poison: StatusInstance = unit.get_status(Constants.STATUS_POISON)
	assert(poison.stacks == 3, "poison stacks should merge")
	assert(poison.duration == 3, "poison duration should take max")
	StatusRules.tick_turn_end(state)
	assert(unit.hp == 1, "poison should deal 9 damage (3 stacks x 3) on turn end: got hp %d" % unit.hp)
	print("  [OK] poison stack + tick")


func _test_armor_max_value_merge() -> void:
	var state := _make_state()
	var unit := _make_unit(state, "u2")
	StatusRules.apply_armor(state, unit, 2, 2)
	StatusRules.apply_armor(state, unit, 4, 1)
	var armor: StatusInstance = unit.get_status(Constants.STATUS_ARMOR)
	assert(armor.value == 4, "armor should keep higher value")
	assert(armor.duration == 2, "armor duration should extend")
	assert(StatusRules.get_shield(unit) == 4, "shield value from status")
	print("  [OK] shield merge")


func _test_shield_consumed_on_hit() -> void:
	var state := _make_state()
	var unit := _make_unit(state, "u_shield")
	StatusRules.apply_shield(state, unit, 5, 0)
	CombatRules.apply_damage(state, unit, 3, "", "test_hit")
	assert(StatusRules.get_shield(unit) == 2, "shield should drop to 2 after blocking 3")
	assert(unit.hp == 10, "hp unchanged when fully blocked")
	CombatRules.apply_damage(state, unit, 4, "", "test_hit")
	assert(not unit.has_status(Constants.STATUS_ARMOR), "shield should be removed when depleted")
	assert(unit.hp == 8, "overflow damage should hit hp")
	print("  [OK] shield consumed on hit")


func _test_relic_grants_shield_not_unit_armor() -> void:
	var state := _make_state()
	var player := _make_unit(state, "player")
	player.team = Constants.TEAM_PLAYER
	state.player_uid = player.uid
	var registry: Node = Engine.get_main_loop().root.get_node("RelicEffectRegistry")
	registry.call("_action_add_shield", "relic_cracked_amulet", {
		"target": "player",
		"amount_ref": "relic_cracked_amulet_shield",
	}, state, {})
	assert(player.armor == 0, "relic should not modify unit.armor stat")
	assert(StatusRules.get_shield(player) == 3, "relic should grant shield status")
	print("  [OK] relic grants shield status")


func _test_rooted_blocks_move() -> void:
	var state := _make_state()
	var unit := _make_unit(state, "u3")
	assert(StatusRules.can_move(unit), "unit should move by default")
	StatusRules.apply_rooted(state, unit, 2)
	assert(not StatusRules.can_move(unit), "rooted should block movement")
	StatusRules.tick_turn_start(state)
	assert(unit.has_status(Constants.STATUS_ROOTED), "rooted should remain after one tick")
	StatusRules.tick_turn_start(state)
	assert(not unit.has_status(Constants.STATUS_ROOTED), "rooted should expire")
	print("  [OK] rooted move block + expire")


func _test_lawless_payload() -> void:
	var state := _make_state()
	var unit := _make_unit(state, "u4")
	StatusRules.apply_lawless(state, unit, "gem_123")
	assert(StatusRules.is_lawless(unit), "lawless flag via status")
	assert(StatusRules.get_lawless_gem_uid(unit) == "gem_123", "lawless payload stored")
	StatusRules.clear_lawless(unit)
	assert(not StatusRules.is_lawless(unit), "lawless cleared")
	print("  [OK] lawless payload")


func _test_exposed_expires() -> void:
	var state := _make_state()
	var unit := _make_unit(state, "u5")
	var gem := GemState.new()
	gem.uid = "heavy_gem"
	gem.gem_id = Constants.GEM_EXPLOSION
	state.gems[gem.uid] = gem
	var slot := SlotState.create(Constants.SLOT_BLUE, gem.uid, true, Constants.LOCK_ARMOR)
	unit.slots.append(slot)
	StatusRules.apply_exposed(state, unit, slot, 1)
	assert(not slot.locked, "slot should unlock")
	assert(unit.has_status(Constants.STATUS_EXPOSED), "exposed status applied")
	StatusRules.tick_turn_end(state)
	assert(not unit.has_status(Constants.STATUS_EXPOSED), "exposed should expire at turn end")
	assert(slot.locked, "slot should re-lock after exposed expires")
	print("  [OK] exposed expire + re-lock")


func _test_default_status_values_from_config() -> void:
	var state := _make_state()
	var unit := _make_unit(state, "u_defaults")
	StatusRules.apply_poison(state, unit)
	StatusRules.apply_rooted(state, unit)
	StatusRules.apply_light_exposed(state, unit)
	var poison: StatusInstance = unit.get_status(Constants.STATUS_POISON)
	assert(poison != null and poison.stacks == 1 and poison.duration == 2, "poison defaults should come from status config")
	var rooted: StatusInstance = unit.get_status(Constants.STATUS_ROOTED)
	assert(rooted != null and rooted.duration == 2, "rooted default duration should come from status config")
	var exposed: StatusInstance = unit.get_status(Constants.STATUS_LIGHT_EXPOSED)
	assert(exposed != null and exposed.stacks == 1 and exposed.duration == 0, "light exposed defaults should come from status config")
	assert(StatusConfig.default_stacks("disarmed") == 1, "disarm defaults should come from status config")
	print("  [OK] status defaults from config")


func _test_status_combat_multipliers_from_config() -> void:
	var state := _make_state()
	var attacker := _make_unit(state, "u_attacker")
	var target := _make_unit(state, "u_target")
	attacker.base_attack = 8
	StatusRules.apply_weak(state, attacker)
	assert(CombatRules.attack_damage(state, attacker) == 6, "weak attack multiplier should come from status config")
	StatusRules.apply_vulnerable(state, target)
	CombatRules.apply_damage(state, target, 4, attacker.uid, "test_hit")
	assert(target.hp == 4, "vulnerable damage multiplier should come from status config")
	StatusRules.apply_slowed(state, target, 5)
	assert(StatusRules.effective_move_points(target, 2) == 1, "slowed min move points should come from status config")
	StatusRules.apply_slowed(state, target, 1, attacker.uid, 0)
	assert(StatusRules.effective_move_points(target, 2) == 0, "source-specific slow should be able to lower the movement floor")
	StatusRules.apply_slowed(state, target, 1)
	assert(StatusRules.effective_move_points(target, 2) == 0, "later default slow should preserve the strongest lower movement floor")
	print("  [OK] status combat multipliers from config")


func _test_disarm_blocks_one_action() -> void:
	var state := _make_state()
	var unit := _make_unit(state, "u_disarmed")
	StatusRules.apply_disarmed(state, unit, 1, "counter_owner")
	assert(not StatusRules.can_attack(unit), "disarmed unit should not be able to attack")
	assert(StatusRules.attack_block_reason(unit).contains("缴械"), "disarm should expose a player-facing block reason")
	assert(StatusRules.consume_disarm(unit), "ending the unit action should consume one disarm stack")
	assert(StatusRules.can_attack(unit), "unit should be able to attack after its disarm stack is consumed")
	print("  [OK] disarm blocks one action")


func _test_relic_numeric_refs_runtime() -> void:
	var state := _make_state()
	var player := _make_unit(state, "player")
	player.team = Constants.TEAM_PLAYER
	player.max_hp = 10
	player.hp = 10
	player.slots.append(SlotState.create(Constants.SLOT_RED))
	player.slots.append(SlotState.create(Constants.SLOT_BLUE))
	state.player_uid = player.uid
	var registry: Node = Engine.get_main_loop().root.get_node("RelicEffectRegistry")
	var arc_mult: float = float(registry.call("_eval_modifier_entry", "relic_silver_cable", {
		"modifier": "arc_damage_mult",
		"value_ref": "relic_silver_cable_arc_damage_mult",
	}, state, {}))
	assert(absf(arc_mult - 1.2) < 0.001, "relic modifier value refs should resolve at runtime")
	var adventure_service: Node = root.get_node("AdventureService")
	var run_service: Node = root.get_node("RunService")
	adventure_service.start_new_run(20260708)
	var run: RunState = run_service.get_run()
	run.owned_relics.clear()
	run.owned_relics.append("relic_cracked_goggles")
	var miss_chance := float(registry.query_modifier("attack_miss_chance", state))
	assert(absf(miss_chance - 0.1) < 0.001, "float additive relic modifiers should not be truncated")
	run.owned_relics.clear()
	run.owned_relics.append("relic_painkiller")
	player.hp = 10
	state.battle_temp_flags.clear()
	CombatRules.apply_damage(state, player, 5, "enemy_test", "painkiller_test")
	assert(player.hp == 9, "painkiller first damage cap should come from relic numeric refs")
	CombatRules.apply_damage(state, player, 5, "enemy_test", "painkiller_test")
	assert(player.hp == 4, "painkiller first damage cap should only apply once")
	run_service.end_run()
	var per_empty_slot: int = int(registry.call("_eval_modifier_entry", "relic_empty_shell", {
		"modifier": "extract_range_bonus",
		"per_empty_slot_ref": "relic_empty_shell_extract_per_empty_slot",
	}, state, {}))
	assert(per_empty_slot == 2, "relic per-empty-slot refs should resolve at runtime")
	registry.call("_action_apply_max_hp_reduction", "relic_empty_coffin", {
		"ratio_ref": "relic_empty_coffin_max_hp_reduction_ratio",
	}, state)
	assert(player.max_hp == 7, "relic ratio refs should resolve for max hp reduction")
	print("  [OK] relic numeric refs runtime")


func _make_state() -> GameState:
	var state := GameState.new()
	state.player_uid = "player"
	state.units = {}
	return state


func _make_unit(state: GameState, uid: String) -> UnitState:
	var unit := UnitState.new()
	unit.uid = uid
	unit.team = Constants.TEAM_ENEMY
	unit.pos = Vector2i.ZERO
	unit.hp = 10
	unit.max_hp = 10
	unit.alive = true
	state.register_unit(unit)
	return unit
