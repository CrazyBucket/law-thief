extends SceneTree

const GemTransfer = preload("res://scripts/rules/gem_transfer.gd")
const GemLocation = preload("res://scripts/data/gem_location.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== Gem Transfer Test ===")
	_test_location_transitions_are_atomic()
	_test_occupied_destination_does_not_detach_source()
	_test_transfer_repairs_duplicate_references()
	print("GEM_TRANSFER_TEST_PASS")
	quit()


func _test_location_transitions_are_atomic() -> void:
	var fixture := _fixture()
	var state: GameState = fixture.state
	var player: UnitState = fixture.player
	var enemy: UnitState = fixture.enemy
	var gem: GemState = fixture.gem
	assert(GemTransfer.location_count(state, gem.uid) == 1)
	assert(GemTransfer.to_hand(state, gem, player.uid))
	assert(state.held_gem_uid == gem.uid and fixture.player_slot.gem_uid.is_empty())
	assert(gem.owner_uid == player.uid and gem.slot_index == -1)
	assert(gem.location.kind == GemLocation.HAND)
	assert(GemTransfer.location_count(state, gem.uid) == 1)
	assert(GemTransfer.to_ground(state, gem, Vector2i(4, 4), {"source_slot_type": Constants.SLOT_RED}))
	assert(state.held_gem_uid.is_empty() and state.dropped_gems.has(gem.uid))
	assert(gem.owner_uid.is_empty() and gem.slot_index == -1)
	assert(gem.location.kind == GemLocation.GROUND and gem.location.pos == Vector2i(4, 4))
	assert(GemTransfer.location_count(state, gem.uid) == 1)
	var enemy_slot := enemy.get_slot(Constants.SLOT_RED)
	assert(GemTransfer.to_unit_slot(state, gem, enemy, enemy_slot))
	assert(not state.dropped_gems.has(gem.uid) and enemy_slot.gem_uid == gem.uid)
	assert(gem.owner_uid == enemy.uid and gem.slot_index == enemy.slots.find(enemy_slot))
	assert(gem.location.kind == GemLocation.UNIT_SLOT)
	assert(GemTransfer.location_count(state, gem.uid) == 1)
	assert(EventValidator.assert_valid([], "gem_transfer.atomic"))
	assert(BattleInvariantChecker.assert_valid(state, "gem_transfer.atomic"))
	print("  [OK] slot, hand, ground, and unit transitions stay atomic")


func _test_occupied_destination_does_not_detach_source() -> void:
	var fixture := _fixture()
	var state: GameState = fixture.state
	var enemy: UnitState = fixture.enemy
	var gem: GemState = fixture.gem
	var occupied_slot := enemy.get_slot(Constants.SLOT_RED)
	var blocker := _new_gem(state, Constants.GEM_POISON)
	assert(GemTransfer.to_unit_slot(state, blocker, enemy, occupied_slot))
	assert(not GemTransfer.to_unit_slot(state, gem, enemy, occupied_slot))
	assert(fixture.player_slot.gem_uid == gem.uid, "failed transfer must leave the source untouched")
	assert(occupied_slot.gem_uid == blocker.uid)
	assert(GemTransfer.location_count(state, gem.uid) == 1)
	assert(EventValidator.assert_valid([], "gem_transfer.rejected"))
	assert(BattleInvariantChecker.assert_valid(state, "gem_transfer.rejected"))
	print("  [OK] occupied destination rejects without detaching source")


func _test_transfer_repairs_duplicate_references() -> void:
	var fixture := _fixture()
	var state: GameState = fixture.state
	var gem: GemState = fixture.gem
	var enemy: UnitState = fixture.enemy
	var duplicate_slot: SlotState = enemy.get_slot(Constants.SLOT_BLUE)
	duplicate_slot.gem_uid = gem.uid
	assert(GemTransfer.location_count(state, gem.uid) == 2, "fixture should contain a stale duplicate reference")
	assert(GemTransfer.to_ground(state, gem, Vector2i(3, 3)))
	assert(fixture.player_slot.gem_uid.is_empty() and duplicate_slot.gem_uid.is_empty())
	assert(GemTransfer.location_count(state, gem.uid) == 1)
	assert(GemTransfer.remove(state, gem.uid))
	assert(not state.gems.has(gem.uid) and GemTransfer.location_count(state, gem.uid) == 0)
	assert(EventValidator.assert_valid([], "gem_transfer.repair"))
	assert(BattleInvariantChecker.assert_valid(state, "gem_transfer.repair"))
	print("  [OK] transfer clears stale duplicate references and removal clears ownership")


func _fixture() -> Dictionary:
	var builder := ScenarioBuilder.new("fission_slime_test", 7001)
	var player := builder.player()
	builder.clear_slots(player)
	var enemy := builder.add_unit("transfer_enemy", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(5, 5))
	builder.clear_slots(enemy)
	var state := builder.finish()
	var gem := _new_gem(state, Constants.GEM_FIRE)
	var player_slot := player.get_slot(Constants.SLOT_RED)
	assert(GemTransfer.to_unit_slot(state, gem, player, player_slot))
	return {
		"state": state,
		"player": player,
		"enemy": enemy,
		"gem": gem,
		"player_slot": player_slot,
	}


func _new_gem(state: GameState, gem_id: String) -> GemState:
	var registry: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	var uid: String = registry.next_runtime_uid("transfer_gem")
	var gem: GemState = registry.create_gem_instance(uid, gem_id, {})
	state.gems[uid] = gem
	return gem
