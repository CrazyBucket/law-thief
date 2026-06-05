extends SceneTree

const AttackPipeline = preload("res://scripts/rules/attack_pipeline.gd")
const GemEchoRules = preload("res://scripts/rules/gem_echo_rules.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Gem Echo Test ===")
	_test_resolve_echo_skips_self()
	_test_resolve_echo_depth_guard()
	_test_blue_echo_once_per_turn()
	_test_blue_echo_level_three_empowers_first_tag()
	_test_black_echo_respects_death_chain_guard()
	if _failed:
		push_error("GEM_ECHO_TEST_FAIL")
		quit(1)
		return
	print("GEM_ECHO_TEST_PASS")
	quit(0)


func _test_resolve_echo_skips_self() -> void:
	var state := _create_state()
	var player := state.get_player()
	player.pos = Vector2i(2, 3)
	_mount_gems(state, player, Constants.SLOT_RED, ["gem_echo", Constants.GEM_FIRE])
	var result := AttackPipeline.execute_aimed(state, player, Vector2i(5, 3), [AttackPipeline.TAG_RANGED])
	_expect(result.get("ok", false), "red echo attack should succeed")
	var events: Array = result.get("events", [])
	_expect(_count_events(events, "gem_flash") >= 1, "red echo should emit gem_flash")
	_expect(_count_events(events, "fire_burst") >= 1, "red echo should not pick itself and should replay fire")
	print("  [OK] resolve echo skips self")


func _test_resolve_echo_depth_guard() -> void:
	var state := _create_state()
	var tags := GemEchoRules.resolve_echo_tags(state, {
		"tags": ["echo", "poison"],
		"tag_levels": {"echo": 2},
		"echo_depth": 1,
	}, "echo_depth_guard")
	_expect(tags.is_empty(), "echo depth guard should stop recursive picks")
	print("  [OK] resolve echo depth guard")


func _test_blue_echo_once_per_turn() -> void:
	var state := _create_state()
	var owner := _spawn_unit(state, "echo_blue_owner", Vector2i(4, 3), Constants.TEAM_ENEMY, 40)
	var source := _spawn_unit(state, "echo_blue_source", Vector2i(2, 3), Constants.TEAM_PLAYER, 40)
	_mount_gems(state, owner, Constants.SLOT_BLUE, ["gem_echo", Constants.GEM_POISON])
	var events: Array[Dictionary] = []
	state.bind_combat_events(events)
	CombatRules.apply_damage(state, owner, 4, source.uid, "ranged_attack")
	var poison_after_first := _status_stacks(source, Constants.STATUS_POISON)
	CombatRules.apply_damage(state, owner, 4, source.uid, "ranged_attack")
	state.unbind_combat_events()
	var poison_after_second := _status_stacks(source, Constants.STATUS_POISON)
	_expect(poison_after_first >= 1, "blue echo should replay poison on first trigger")
	_expect(poison_after_second == poison_after_first, "blue echo should only trigger once per turn")
	print("  [OK] blue echo once per turn")


func _test_blue_echo_level_three_empowers_first_tag() -> void:
	var state := _create_state()
	var owner := _spawn_unit(state, "echo_blue_owner_l3", Vector2i(4, 3), Constants.TEAM_ENEMY, 40)
	var source := _spawn_unit(state, "echo_blue_source_l3", Vector2i(2, 3), Constants.TEAM_PLAYER, 40)
	_mount_gems(state, owner, Constants.SLOT_BLUE, ["gem_echo", "gem_echo", "gem_echo", Constants.GEM_POISON])
	CombatRules.apply_damage(state, owner, 4, source.uid, "ranged_attack")
	_expect(_status_stacks(source, Constants.STATUS_POISON) == 2, "level 3 blue echo should empower the first echoed tag")
	print("  [OK] blue echo level 3 empowers first tag")


func _test_black_echo_respects_death_chain_guard() -> void:
	var state := _create_state()
	var victim := _spawn_unit(state, "echo_black_victim", Vector2i(4, 3), Constants.TEAM_ENEMY, 20)
	var neighbor := _spawn_unit(state, "echo_black_neighbor", Vector2i(5, 3), Constants.TEAM_ENEMY, 80)
	_mount_gems(state, victim, Constants.SLOT_BLACK, ["gem_echo", Constants.GEM_POISON])
	StatusRules.apply_slowed(state, victim, 2, "echo_black_payload")
	var events := _kill_and_collect_events(state, victim, {"death_chain_id": 1})
	_expect(_count_events(events, "poison_burst") == 0, "level 1 poison echoed from black slot should not create poison burst")
	_expect(neighbor.has_status(Constants.STATUS_SLOWED), "black echo should replay poison payload")
	var slowed := neighbor.get_status(Constants.STATUS_SLOWED)
	_expect(slowed != null and slowed.stacks == 2, "death chain guard should prevent duplicate black echo replay")
	print("  [OK] black echo death chain guard")


func _create_state() -> GameState:
	var reg: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	var state: GameState = reg.create_battle_state("fission_slime_test", 54321)
	var to_remove: Array[String] = []
	for unit in state.units.values():
		if unit.team == Constants.TEAM_ENEMY:
			to_remove.append(unit.uid)
	for uid in to_remove:
		state.unregister_unit(state.units[uid])
	var player := state.get_player()
	for slot in player.slots:
		if not slot.gem_uid.is_empty():
			state.gems.erase(slot.gem_uid)
		slot.gem_uid = ""
	return state


func _mount_gems(state: GameState, unit: UnitState, slot_type: String, gem_ids: Array[String]) -> void:
	while unit.slots_accepting(slot_type).size() < gem_ids.size():
		unit.slots.append(SlotState.create(slot_type))
	var slots := unit.slots_accepting(slot_type)
	var reg: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	for i in range(gem_ids.size()):
		var slot: SlotState = slots[i]
		var gem_uid: String = reg.next_runtime_uid("echo_gem")
		var gem := GemState.create(gem_uid, gem_ids[i], {})
		gem.owner_uid = unit.uid
		gem.slot_index = unit.slots.find(slot)
		state.gems[gem_uid] = gem
		slot.gem_uid = gem_uid


func _spawn_unit(state: GameState, uid: String, pos: Vector2i, team: String, hp: int = 30) -> UnitState:
	var unit := UnitState.new()
	unit.uid = uid
	unit.unit_def_id = "unit_patrol_guard"
	unit.team = team
	unit.pos = pos
	unit.hp = hp
	unit.max_hp = hp
	unit.speed = 5
	unit.base_attack = 6
	unit.alive = true
	unit.slots.append(SlotState.create(Constants.SLOT_RED))
	unit.slots.append(SlotState.create(Constants.SLOT_BLUE))
	unit.slots.append(SlotState.create(Constants.SLOT_BLACK))
	state.register_unit(unit)
	return unit


func _kill_and_collect_events(state: GameState, victim: UnitState, ctx: Dictionary = {}) -> Array:
	var events: Array[Dictionary] = []
	victim.hp = 0
	state.kill_unit(victim)
	GemEffects.trigger_black_death_effects(state, victim, events, ctx)
	return events


func _count_events(events: Array, event_type: String) -> int:
	var total := 0
	for ev in events:
		if str(ev.get("type", "")) == event_type:
			total += 1
	return total


func _status_stacks(unit: UnitState, status_id: String) -> int:
	var status := unit.get_status(status_id)
	if status == null:
		return 0
	return status.stacks


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
