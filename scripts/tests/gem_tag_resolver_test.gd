extends SceneTree

const GemTagResolver = preload("res://scripts/rules/gem_tag_resolver.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Gem Tag Resolver Test ===")
	_test_stack_levels()
	_test_locked_slots_do_not_contribute()
	_test_combo_resolution()
	_test_dual_slot_contributes_to_accepted_color()
	if _failed:
		push_error("GEM_TAG_RESOLVER_TEST_FAIL")
		quit(1)
		return
	print("GEM_TAG_RESOLVER_TEST_PASS")
	quit(0)


func _test_stack_levels() -> void:
	var state := _create_state()
	var player := state.get_player()
	_ensure_slots(player, Constants.SLOT_RED, 3)
	var red_slots := player.slots_accepting(Constants.SLOT_RED)
	_mount_gem(state, player, red_slots[0], Constants.GEM_EXPLOSION)
	_mount_gem(state, player, red_slots[1], Constants.GEM_EXPLOSION)
	_mount_gem(state, player, red_slots[2], Constants.GEM_EXPLOSION)
	var ctx := GemTagResolver.build_context(
		state, player, Constants.SLOT_RED, GemEffects.TIMING_ACTIVE, red_slots[0]
	)
	_expect(GemTagResolver.tag_level(ctx, "explosion") == 3, "three explosion gems should resolve level 3")
	_expect(int(ctx["tag_counts"].get("explosion", 0)) == 3, "explosion count should be 3")
	_expect(str(ctx.get("primary_tag", "")) == "explosion", "primary tag should be explosion")
	print("  [OK] stack levels")


func _test_locked_slots_do_not_contribute() -> void:
	var state := _create_state()
	var player := state.get_player()
	_ensure_slots(player, Constants.SLOT_RED, 3)
	var red_slots := player.slots_accepting(Constants.SLOT_RED)
	for i in range(3):
		_mount_gem(state, player, red_slots[i], Constants.GEM_EXPLOSION)
	red_slots[2].locked = true
	red_slots[2].unlock_until_turn = -1
	var ctx := GemTagResolver.build_context(state, player, Constants.SLOT_RED, GemEffects.TIMING_ACTIVE)
	_expect(GemTagResolver.tag_level(ctx, "explosion") == 2, "locked slot should not contribute")
	print("  [OK] locked slot filtering")


func _test_combo_resolution() -> void:
	var state := _create_state()
	var player := state.get_player()
	_ensure_slots(player, Constants.SLOT_RED, 2)
	var red_slots := player.slots_accepting(Constants.SLOT_RED)
	_mount_gem(state, player, red_slots[0], Constants.GEM_EXPLOSION)
	_mount_gem(state, player, red_slots[1], Constants.GEM_FIRE)
	var ctx := GemTagResolver.build_context(state, player, Constants.SLOT_RED, GemEffects.TIMING_ACTIVE)
	_expect(GemTagResolver.has_combo(ctx, "explosion_fire"), "explosion + fire should resolve combo")
	_expect(GemTagResolver.combo_level(ctx, "explosion_fire") == 1, "combo level should use min participant level")
	print("  [OK] combo resolution")


func _test_dual_slot_contributes_to_accepted_color() -> void:
	var state := _create_state()
	var player := state.get_player()
	var blue_slot := player.get_slot(Constants.SLOT_BLUE)
	blue_slot.dual_type = Constants.SLOT_RED
	_mount_gem(state, player, blue_slot, Constants.GEM_FIRE)
	var red_ctx := GemTagResolver.build_context(state, player, Constants.SLOT_RED, GemEffects.TIMING_ACTIVE)
	var blue_ctx := GemTagResolver.build_context(state, player, Constants.SLOT_BLUE, GemEffects.TIMING_OWNER_DAMAGED)
	_expect(GemTagResolver.tag_level(red_ctx, "fire") == 1, "dual slot should contribute to accepted red group")
	_expect(GemTagResolver.tag_level(blue_ctx, "fire") == 1, "dual slot should still contribute to native blue group")
	print("  [OK] dual slot contribution")


func _create_state() -> GameState:
	var reg: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	var state: GameState = reg.create_battle_state("fission_slime_test", 9876)
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
		slot.locked = false
		slot.lock_type = ""
		slot.unlock_until_turn = -1
	return state


func _ensure_slots(unit: UnitState, slot_type: String, count: int) -> void:
	while unit.slots_accepting(slot_type).size() < count:
		unit.slots.append(SlotState.create(slot_type))


func _mount_gem(state: GameState, unit: UnitState, slot: SlotState, gem_id: String) -> void:
	var reg: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	if not slot.gem_uid.is_empty():
		state.gems.erase(slot.gem_uid)
	var gem_uid: String = reg.next_runtime_uid("gem")
	var gem: GemState = reg.create_gem_instance(gem_uid, gem_id, {})
	state.gems[gem_uid] = gem
	slot.gem_uid = gem_uid
	gem.owner_uid = unit.uid
	gem.slot_index = unit.slots.find(slot)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
