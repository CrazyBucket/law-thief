extends SceneTree

const CombatRules = preload("res://scripts/rules/combat_rules.gd")
const CombatConfig = preload("res://scripts/core/combat_config.gd")
const GemEffectsScript = preload("res://scripts/rules/gem_effects.gd")
const GemRules = preload("res://scripts/rules/gem_rules.gd")
const GemTransfer = preload("res://scripts/rules/gem_transfer.gd")
const SlimeSprites = preload("res://scripts/ui/slime_sprites.gd")
const ColoredSlimeRules = preload("res://scripts/rules/colored_slime_rules.gd")
const RunPlayerGemService = preload("res://scripts/services/run_player_gem_service.gd")
const BattleSettlementService = preload("res://scripts/battle/battle_settlement_service.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	print("=== Fission Slime Test ===")
	_test_spawn()
	_test_split_black_gem_mounted()
	_test_black_split_can_extract()
	_test_blue_only_on_single_target()
	_test_clone_hp_ratio()
	_test_colored_children_are_distinct_units()
	_test_split_clones_retain_slots_and_partition_gems()
	_test_player_split_merge_preserves_gems_across_battles()
	_test_split_gem_rewards_once_after_both_clones_die()
	_test_black_split_level_ratios()
	_test_slam_pushes_adjacent_target()
	_test_split_redirect_skips_without_neighbor()
	_test_split_surround_uses_footprint_ring()
	_test_split_blue_level_two_splits_to_all_neighbors()
	_test_split_blue_level_three_temp_clone_once_per_turn()
	_test_clone_footprint_1x1()
	_test_locked_clone_death_does_not_resplit()
	_test_clone_uses_melee_ai()
	_test_red_gravity_overrides_default_ai()
	_test_attack_range_uses_nearest_footprint_cell()
	_test_approach_around_prop()
	_test_clone_approaches_around_pillar()
	_test_trample_occupancy_override()
	_test_trample_star_relocation()
	_test_trample_squeeze_all_blocked()
	_test_trample_landing_terrain_settlement()
	print("FISSION_SLIME_TEST_PASS")
	quit()


func _test_spawn() -> void:
	var controller := BattleController.new()
	controller.start_encounter("fission_slime_test", 42)
	var slime := _find_slime(controller.state)
	assert(slime != null)
	assert(slime.footprint_size == Vector2i(2, 2))
	assert(slime.max_hp >= 22 and slime.max_hp <= 28)
	assert(slime.move_points == 2 and slime.base_attack == 4)
	print("  [OK] spawn hp=%d footprint 2x2" % slime.max_hp)


func _test_split_black_gem_mounted() -> void:
	var controller := BattleController.new()
	controller.start_encounter("fission_slime_test", 42)
	var slime := _find_slime(controller.state)
	var blue := slime.get_slot(Constants.SLOT_BLUE)
	var black := slime.get_slot(Constants.SLOT_BLACK)
	assert(blue != null and black != null)
	assert(blue.gem_uid.is_empty(), "blue slot should start empty")
	var black_gem: GemState = controller.state.gems.get(black.gem_uid, null)
	assert(black_gem != null and black_gem.gem_id == Constants.GEM_SPLIT)
	assert(not black.locked and black.lock_type.is_empty(), "black split should be a normal slot before death")
	print("  [OK] only black split gem mounted")


func _test_black_split_can_extract() -> void:
	var controller := BattleController.new()
	controller.start_encounter("fission_slime_test", 42)
	var state := controller.state
	var slime := _find_slime(state)
	var player := state.get_player()
	var black := slime.get_slot(Constants.SLOT_BLACK)
	state.move_unit(player, Vector2i(2, 3))
	state.held_gem_uid = ""
	var check := GemRules.can_extract(state, player, slime, black)
	assert(check.get("ok", false), "black split gem should be stealable, got %s" % check.get("reason", ""))
	controller.selected_action = Constants.ACTION_EXTRACT
	var targets: Array = controller.get_highlights().get("targets", [])
	var slime_targeted := false
	for cell in slime.occupied_cells():
		if cell in targets:
			slime_targeted = true
			break
	assert(slime_targeted, "slime with black split should be extract target in range")
	var result := controller.try_extract(slime.uid, slime.slots.find(black))
	assert(result.get("ok", false), "extract black split should succeed")
	assert(not state.held_gem_uid.is_empty(), "player should hold stolen split gem")
	if not black.gem_uid.is_empty():
		var echo_gem: GemState = state.gems.get(black.gem_uid, null)
		assert(echo_gem != null and echo_gem.gem_id == Constants.GEM_SPLIT, "overload echo should preserve the extracted gem identity")
	print("  [OK] black split gem can extract")


func _test_blue_only_on_single_target() -> void:
	var controller := BattleController.new()
	controller.start_encounter("fission_slime_test", 42)
	var state := controller.state
	var slime := _find_slime(state)
	var dummy := _spawn_dummy(state, Vector2i(3, 3))
	var melee_remaining := GemEffectsScript.intercept_damage_for_split(
		state, slime, dummy.uid, "melee_attack", 10
	)
	assert(melee_remaining == 10, "without blue split, single target should not redirect, got %d" % melee_remaining)
	_mount_gem(state, slime, Constants.SLOT_BLUE, Constants.GEM_SPLIT)
	melee_remaining = GemEffectsScript.intercept_damage_for_split(
		state, slime, dummy.uid, "melee_attack", 10
	)
	assert(melee_remaining == 5, "with blue split, single target should redirect 50%%, got %d" % melee_remaining)
	var boom_remaining := GemEffectsScript.intercept_damage_for_split(
		state, slime, dummy.uid, "explosion", 10
	)
	assert(boom_remaining == 10, "aoe should not redirect for fission slime")
	print("  [OK] blue split only affects single target")


func _test_clone_hp_ratio() -> void:
	var controller := BattleController.new()
	controller.start_encounter("fission_slime_test", 42)
	var state := controller.state
	var slime := _find_slime(state)
	slime.max_hp = 20
	slime.hp = 20
	var events: Array[Dictionary] = []
	state.kill_unit(slime)
	GemEffectsScript.on_unit_death(state, slime, events)
	var clone_hp := 0
	for unit in state.units.values():
		if unit.has_tag(Constants.TAG_UNIT_SPLIT_CLONE):
			clone_hp = unit.max_hp
			assert(unit.footprint_size == Vector2i(1, 1))
			break
	assert(clone_hp == 10, "fission slime override should raise level 1 clone hp to 50%% of 20, got %d" % clone_hp)
	print("  [OK] fission slime level 1 override raises clone hp to 50%%")


func _test_colored_children_are_distinct_units() -> void:
	var controller := BattleController.new()
	controller.start_encounter("fission_slime_test", 424242)
	var state := controller.state
	var slime := _find_slime(state)
	var events: Array[Dictionary] = []
	state.kill_unit(slime)
	GemEffectsScript.on_unit_death(state, slime, events)
	var children: Array[UnitState] = []
	for unit in state.units.values():
		if unit.alive and unit.split_origin_uid == slime.uid:
			children.append(unit)
	assert(children.size() == 2, "fission slime death should create two small slimes")
	assert(children[0].unit_def_id != children[1].unit_def_id, "one split should use two different slime colors")
	for child in children:
		assert(child.unit_def_id in ColoredSlimeRules.CHILD_UNIT_IDS, "split child must use a colored small-slime definition")
		assert(child.has_tag(Constants.TAG_UNIT_SMALL_SLIME), "small slime must have its own monster tag")
		assert(child.unit_def_id != "unit_fission_slime", "small slime must not remain a resized fission-slime clone")
		assert(child.behavior_id == "generic_melee" and child.footprint_size == Vector2i.ONE)
	for child_id in ColoredSlimeRules.CHILD_UNIT_IDS:
		var variant := SlimeSprites.variant_for_unit(child_id)
		assert(SlimeSprites.new(variant).portrait_texture() != null, "colored slime sheet must load: %s" % child_id)
	print("  [OK] split creates two distinct colored small-slime monsters and all six sheets load")


func _test_split_clones_retain_slots_and_partition_gems() -> void:
	var controller := BattleController.new()
	controller.start_encounter("fission_slime_test", 42)
	var state := controller.state
	var slime := _find_slime(state)
	_mount_gem(state, slime, Constants.SLOT_RED, Constants.GEM_FIRE)
	_mount_gem(state, slime, Constants.SLOT_BLUE, Constants.GEM_POISON)
	var source_gem_uids: Array[String] = []
	for slot in slime.slots:
		if not slot.gem_uid.is_empty():
			source_gem_uids.append(slot.gem_uid)
	var source_slot_count := slime.slots.size()
	var presentation_state := state.clone()
	var events: Array[Dictionary] = []
	state.bind_combat_events(events)
	CombatRules.apply_damage(state, slime, slime.hp, state.player_uid, "ranged_attack")
	state.unbind_combat_events()
	var clones: Array[UnitState] = []
	for unit in state.units.values():
		if unit.has_tag(Constants.TAG_UNIT_SPLIT_CLONE) and not unit.has_tag(Constants.TAG_UNIT_SPLIT_BLUE_TEMP_CLONE):
			clones.append(unit)
	clones.sort_custom(func(a: UnitState, b: UnitState) -> bool: return a.uid < b.uid)
	assert(clones.size() == 2, "death split should create two clones")
	var inherited_slot_count := 0
	var inherited_gem_count := 0
	var disabled_split_count := 0
	var split_clone: UnitState = null
	for clone in clones:
		inherited_slot_count += clone.slots.size()
		assert(clone.slots.size() == source_slot_count, "each split clone should retain the complete source slot layout")
		assert(clone.get_slot(Constants.SLOT_BLACK) != null, "each split clone should retain its black slot")
		for slot in clone.slots:
			if not slot.gem_uid.is_empty():
				inherited_gem_count += 1
				assert(state.gems.has(slot.gem_uid), "every inherited gem should exist in state")
			if slot.lock_type == Constants.LOCK_SPLIT_DISABLED:
				disabled_split_count += 1
				split_clone = clone
				var split_gem: GemState = state.gems.get(slot.gem_uid, null)
				assert(split_gem != null and split_gem.gem_id == Constants.GEM_SPLIT, "only an inherited split gem should be disabled")
	assert(inherited_slot_count == source_slot_count * 2, "split clones should duplicate slot layout, not gem instances")
	assert(inherited_gem_count == source_gem_uids.size(), "split clones should partition source gems exactly once")
	assert(disabled_split_count == 1, "the actual inherited split gem should be disabled once")
	assert(split_clone != null, "one clone should inherit the disabled split gem")
	assert(state.dropped_gems.is_empty(), "inherited enemy gems should not also drop")
	for source_gem_uid in source_gem_uids:
		assert(state.gems.has(source_gem_uid), "split should preserve the original gem identity")
		assert(GemTransfer.location_count(state, source_gem_uid) == 1, "each inherited gem should have one location")
	var player := state.get_player()
	var moved_in_range := false
	for neighbor in BoardUtils.neighbors4(split_clone.pos):
		if BoardUtils.unit_footprint_passable(state, player, neighbor, player.uid):
			state.move_unit(player, neighbor)
			moved_in_range = true
			break
	assert(moved_in_range, "test setup should place player beside split clone")
	state.held_gem_uid = ""
	controller.select_action(Constants.ACTION_EXTRACT)
	var targets: Array = controller.get_highlights().get("targets", [])
	assert(split_clone.pos in targets, "disabled split gem should keep clone visible as an extract target")
	var clone_black := split_clone.get_slot(Constants.SLOT_BLACK)
	var black_check := controller.check_slot_action(split_clone.uid, split_clone.slots.find(clone_black))
	assert(not black_check.get("ok", false), "disabled split gem should remain non-operable")
	var presenter := BattleEventPlayer.new()
	presenter.set("_controller", controller)
	presenter.set("_display_state", presentation_state)
	var matching_events := events.filter(
		func(ev: Dictionary) -> bool:
			return str(ev.get("type", "")) == "split_spawn" and str(ev.get("uid", "")) == split_clone.uid
	)
	assert(not matching_events.is_empty(), "split clone should emit a presentation event")
	var split_event: Dictionary = matching_events[0]
	presenter._apply_event_state(split_event)
	var display_clone: UnitState = presentation_state.units.get(str(split_event.get("uid", "")), null)
	assert(display_clone != null, "split presentation should register clone")
	var display_black := display_clone.get_slot(Constants.SLOT_BLACK)
	assert(display_black != null and presentation_state.gems.has(display_black.gem_uid), "split presentation should copy locked black gem")
	print("  [OK] split clones retain all slots while partitioning gem instances")


func _test_player_split_merge_preserves_gems_across_battles() -> void:
	var run_service: Node = Engine.get_main_loop().root.get_node("RunService")
	run_service.start_run(817, 818)
	var run: RunState = run_service.get_run()
	_embed_run_gem(run_service, run, Constants.GEM_FIRE, 0)
	_embed_run_gem(run_service, run, Constants.GEM_POISON, 1)
	_embed_run_gem(run_service, run, Constants.GEM_SPLIT, 2)
	_embed_run_gem(run_service, run, Constants.GEM_SPLIT, 2, true)
	var overload_slot_index := run.player_slot_gems.size() - 1
	assert(
		str((run.player_slot_gems[overload_slot_index] as Dictionary).get("lock_type", ""))
			== Constants.LOCK_OVERLOAD_SLOT,
		"fixture must create a real persistent overload slot"
	)
	var controller := BattleController.new()
	controller.start_encounter("fission_slime_test", 42)
	var state := controller.state
	var player := state.get_player()
	_assert_player_overload_slot(player, overload_slot_index, "first battle player")
	OverloadRules.sync_active_mutations_to_overload_slots(state, true)
	assert(state.overload_active_mutations.size() == 1, "real overload slot should activate one mutation")
	var expected_gem_ids: Array[String] = []
	for slot in player.slots:
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		expected_gem_ids.append(gem.gem_id if gem != null else "")
	var expected_max_hp := player.max_hp
	var origin_uid := player.uid
	var killer := _find_slime(state)
	CombatRules.apply_true_damage(state, player, player.hp, killer.uid, "test_split_merge")
	controller._check_battle_end()
	assert(state.get_player().has_tag(Constants.TAG_UNIT_SPLIT_CLONE), "a surviving split clone should take control")
	var first_generation := state.get_alive_split_clones(origin_uid)
	assert(first_generation.size() == 2, "two split gems must still create exactly two clones")
	var locked_split_count := 0
	var active_split_clone: UnitState = null
	var locked_split_clone: UnitState = null
	for clone in first_generation:
		var split_slots := clone.slots.filter(
			func(slot: SlotState) -> bool:
				var gem: GemState = state.gems.get(slot.gem_uid, null)
				return gem != null and gem.gem_id == Constants.GEM_SPLIT
		)
		assert(split_slots.size() == 1, "each first-generation clone should retain one black split slot")
		if split_slots[0].lock_type == Constants.LOCK_SPLIT_DISABLED:
			locked_split_count += 1
			locked_split_clone = clone
		else:
			active_split_clone = clone
	assert(locked_split_count == 1, "only the split gem that triggered this death should lock")
	assert(active_split_clone != null, "the second split gem should remain active on the other clone")
	CombatRules.apply_true_damage(
		state,
		active_split_clone,
		active_split_clone.hp,
		killer.uid,
		"test_recursive_split"
	)
	controller._check_battle_end()
	var descendants := state.get_alive_split_clones(origin_uid)
	assert(descendants.size() == 3, "the unlocked clone should split into two while its sibling survives")
	for descendant in descendants:
		assert(descendant.split_origin_uid == origin_uid, "recursive clones must retain the root merge origin")
	var disabled_overload_split_found := false
	for descendant in descendants:
		for slot: SlotState in descendant.slots:
			if slot.is_overload_slot() and slot.is_split_disabled():
				disabled_overload_split_found = true
	assert(
		disabled_overload_split_found,
		"an overload split slot must retain its overload identity while the triggering gem is disabled"
	)
	assert(OverloadRules.overload_gem_count(state) == 1, "recursive split must keep the overload gem counted")
	OverloadRules.sync_active_mutations_to_overload_slots(state, false)
	assert(state.overload_active_mutations.size() == 1, "recursive split must not discard the overload layer")
	assert(locked_split_clone != null, "fixture should retain the clone carrying the first locked split gem")
	var corpse_gem_uid := ""
	for slot: SlotState in locked_split_clone.slots:
		if not slot.gem_uid.is_empty():
			corpse_gem_uid = slot.gem_uid
			break
	assert(not corpse_gem_uid.is_empty(), "locked split clone should carry a gem before death")
	CombatRules.apply_true_damage(
		state,
		locked_split_clone,
		locked_split_clone.hp,
		killer.uid,
		"test_split_corpse"
	)
	controller._check_battle_end()
	assert(not locked_split_clone.alive, "defeated split clone should remain as a corpse")
	assert(state.get_corpse_at(locked_split_clone.pos) == locked_split_clone, "split corpse should remain discoverable")
	assert(
		GemTransfer.location_count(state, corpse_gem_uid) == 1
			and state.gems[corpse_gem_uid].owner_uid == locked_split_clone.uid,
		"split corpse should retain its gem until victory merge"
	)
	for enemy: UnitState in state.get_alive_enemies().duplicate():
		state.kill_unit(enemy)
	controller._check_battle_end()
	assert(state.get_player().uid == origin_uid, "victory should merge split clones back into the original player")
	assert(state.get_player().max_hp == expected_max_hp, "first merge should restore the original max hp")
	_assert_player_gem_ids(state.get_player(), state, expected_gem_ids, "merged player")
	_assert_player_overload_slot(state.get_player(), overload_slot_index, "merged player")
	assert(BattleInvariantChecker.assert_valid(state, "fission_slime.player_split_merge"))
	run_service.capture_player_battle_state(state)
	var second_controller := BattleController.new()
	second_controller.start_encounter("fission_slime_test", 43)
	var next_state := second_controller.state
	assert(next_state.get_player().max_hp == expected_max_hp, "next battle should restore max hp")
	_assert_player_gem_ids(next_state.get_player(), next_state, expected_gem_ids, "next battle player")
	_assert_player_overload_slot(next_state.get_player(), overload_slot_index, "next battle player")
	var second_origin_uid := next_state.player_uid
	var second_player := next_state.get_player()
	var second_killer := _find_slime(next_state)
	CombatRules.apply_true_damage(
		next_state,
		second_player,
		second_player.hp,
		second_killer.uid,
		"test_second_battle_split_merge"
	)
	second_controller._check_battle_end()
	assert(
		next_state.get_player().has_tag(Constants.TAG_UNIT_SPLIT_CLONE),
		"the restored player should split again in the second battle"
	)
	for enemy: UnitState in next_state.get_alive_enemies().duplicate():
		next_state.kill_unit(enemy)
	second_controller._check_battle_end()
	assert(next_state.get_player().uid == second_origin_uid, "second victory should merge into its battle origin")
	assert(next_state.get_player().max_hp == expected_max_hp, "second merge should preserve max hp")
	_assert_player_gem_ids(next_state.get_player(), next_state, expected_gem_ids, "second merged player")
	_assert_player_overload_slot(next_state.get_player(), overload_slot_index, "second merged player")
	assert(BattleInvariantChecker.assert_valid(next_state, "fission_slime.player_split_persist"))
	run_service.capture_player_battle_state(next_state)
	var third_controller := BattleController.new()
	third_controller.start_encounter("fission_slime_test", 44)
	assert(third_controller.state.get_player().max_hp == expected_max_hp, "post-merge battle should retain max hp")
	_assert_player_gem_ids(
		third_controller.state.get_player(),
		third_controller.state,
		expected_gem_ids,
		"post-merge player"
	)
	_assert_player_overload_slot(
		third_controller.state.get_player(),
		overload_slot_index,
		"post-merge player"
	)
	run_service.end_run()
	print("  [OK] player split merge preserves max hp and gems across repeated battles")


func _assert_player_gem_ids(player: UnitState, state: GameState, expected: Array[String], label: String) -> void:
	assert(player.slots.size() == expected.size(), "%s should preserve slot count" % label)
	for i in range(expected.size()):
		var gem: GemState = state.gems.get(player.slots[i].gem_uid, null)
		assert(gem != null and gem.gem_id == expected[i], "%s slot %d should preserve its gem" % [label, i])


func _assert_player_overload_slot(player: UnitState, slot_index: int, label: String) -> void:
	var slot := player.get_slot_by_index(slot_index)
	assert(slot != null, "%s should preserve the overload slot" % label)
	assert(
		slot.lock_type == Constants.LOCK_OVERLOAD_SLOT,
		"%s should preserve the overload slot marker" % label
	)


func _embed_run_gem(
	run_service: Node,
	run: RunState,
	gem_id: String,
	slot_index: int,
	force_overload: bool = false
) -> void:
	var acquired: Dictionary = run_service.acquire_gem(gem_id)
	assert(acquired.get("ok", false), "fixture should acquire %s" % gem_id)
	var embedded := RunPlayerGemService.embed_carried_gem(run, slot_index, force_overload)
	assert(embedded.get("ok", false), "fixture should embed %s" % gem_id)
	assert(
		bool(embedded.get("overload_forced", false)) == force_overload,
		"fixture overload result should match the requested path"
	)


func _test_split_gem_rewards_once_after_both_clones_die() -> void:
	var controller := BattleController.new()
	controller.start_encounter("fission_slime_test", 4242)
	var state := controller.state
	var slime := _find_slime(state)
	var events: Array[Dictionary] = []
	state.bind_combat_events(events)
	CombatRules.apply_true_damage(state, slime, slime.hp, state.player_uid, "test")
	var clones: Array[UnitState] = []
	for unit: UnitState in state.units.values():
		if unit.alive and unit.has_tag(Constants.TAG_UNIT_SPLIT_CLONE):
			clones.append(unit)
	assert(clones.size() == 2, "fission death should create two reward-bearing clones")
	for clone in clones:
		CombatRules.apply_true_damage(state, clone, clone.hp, state.player_uid, "test")
	state.unbind_combat_events()
	var split_offer_count := 0
	for offer: Dictionary in BattleSettlementService.dropped_gem_offer(state):
		var gem: GemState = state.gems.get(str(offer.get("gem_uid", "")), null)
		if gem != null and gem.gem_id == Constants.GEM_SPLIT:
			split_offer_count += 1
	assert(split_offer_count == 1, "both split clone corpses should settle only one original split gem reward")
	assert(state.dropped_gems.is_empty(), "split gem should remain on its corpse instead of becoming a ground drop")
	assert(EventValidator.assert_valid(events, "fission_slime.split_reward_once"))
	assert(BattleInvariantChecker.assert_valid(state, "fission_slime.split_reward_once"))
	print("  [OK] both clone deaths retain one split gem reward on a corpse")


func _test_black_split_level_ratios() -> void:
	assert(_clone_hp_for_black_split_level(2) == 10, "level 2 split clone hp should be 50%% of 20")
	assert(_clone_hp_for_black_split_level(3) == 16, "level 3 split clone hp should be 80%% of 20")
	print("  [OK] black split level 2/3 hp ratios")


func _clone_hp_for_black_split_level(level: int) -> int:
	var controller := BattleController.new()
	controller.start_encounter("fission_slime_test", 42)
	var state := controller.state
	var slime := _find_slime(state)
	slime.max_hp = 20
	slime.hp = 20
	while slime.slots_accepting(Constants.SLOT_BLACK).size() < level:
		slime.slots.append(SlotState.create(Constants.SLOT_BLACK))
	var black_slots := slime.slots_accepting(Constants.SLOT_BLACK)
	for i in range(level):
		_mount_gem_on_slot(state, slime, black_slots[i], Constants.GEM_SPLIT)
	var events: Array[Dictionary] = []
	state.kill_unit(slime)
	GemEffectsScript.on_unit_death(state, slime, events)
	var clones: Array[UnitState] = []
	for unit in state.units.values():
		if unit.has_tag(Constants.TAG_UNIT_SPLIT_CLONE):
			clones.append(unit)
	assert(clones.size() == 2, "multiple black split gems must still create exactly two clones")
	return clones[0].max_hp
	return -1


func _test_slam_pushes_adjacent_target() -> void:
	var controller := BattleController.new()
	controller.start_encounter("fission_slime_test", 42)
	var state := controller.state
	var slime := _find_slime(state)
	var player := state.get_player()
	state.move_unit(player, Vector2i(3, 3))
	assert(BoardUtils.are_units_adjacent(slime, player), "player should be adjacent to slime footprint")
	IntentSystem.refresh_unit_intent(state, slime)
	assert(slime.intent.type == "slam_attack", "expected slam, got %s" % slime.intent.type)
	var pos_before := player.pos
	var hp_before := player.hp
	var events := IntentSystem.execute_intent(state, slime)
	assert(player.hp < hp_before or player.pos != pos_before, "slam should damage or push player")
	assert(not events.is_empty(), "slam should emit events")
	print("  [OK] slam attack hits and displaces")


func _test_red_gravity_overrides_default_ai() -> void:
	var controller := BattleController.new()
	controller.start_encounter("fission_slime_test", 42)
	var state := controller.state
	var slime := _find_slime(state)
	var player := state.get_player()
	assert(slime != null and player != null, "slime/player should exist")
	state.move_unit(slime, Vector2i(4, 2))
	state.move_unit(player, Vector2i(0, 2))
	_mount_gem(state, slime, Constants.SLOT_RED, Constants.GEM_GRAVITY)
	assert(
		BoardUtils.distance_between_units(slime, player) == CombatConfig.enemy_gravity_pull_range(),
		"setup should place player exactly at gravity pull range"
	)
	assert(not BoardUtils.are_units_adjacent(slime, player), "setup should stay outside slam range")
	IntentSystem.refresh_unit_intent(state, slime)
	assert(slime.intent.type == "pull", "gravity red should override slime default AI, got %s" % slime.intent.type)
	var start_pos := player.pos
	var events := IntentSystem.execute_intent(state, slime)
	assert(not events.is_empty(), "gravity pull should execute")
	assert(player.pos != start_pos, "gravity pull should move the player")
	print("  [OK] gravity red overrides slime default AI")


func _test_split_redirect_skips_without_neighbor() -> void:
	var controller := BattleController.new()
	controller.start_encounter("fission_slime_test", 42)
	var state := controller.state
	var slime := _find_slime(state)
	var remaining := GemEffectsScript.intercept_damage_for_split(
		state, slime, "player_1", "melee_attack", 10
	)
	assert(remaining == 10, "no neighbor should take full damage, got %d" % remaining)
	print("  [OK] split blue skips redirect without neighbor")


func _test_split_surround_uses_footprint_ring() -> void:
	var controller := BattleController.new()
	controller.start_encounter("fission_slime_test", 42)
	var state := controller.state
	var slime := _find_slime(state)
	state.move_unit(slime, Vector2i(2, 2))
	var dummy := _spawn_dummy(state, Vector2i(4, 4))
	_mount_gem(state, slime, Constants.SLOT_BLUE, Constants.GEM_SPLIT)
	assert(
		not BoardUtils.chebyshev(slime.pos, dummy.pos) <= 1,
		"anchor chebyshev should miss far corner"
	)
	var registry: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	var split_level: Dictionary = registry.get_gem_effect_level_def("split", Constants.SLOT_BLUE, 1)
	assert(BoardUtils.is_within_surround(slime, dummy, int(split_level.get("redirect_radius", 0))))
	var remaining := GemEffectsScript.intercept_damage_for_split(
		state, slime, dummy.uid, "melee_attack", 10
	)
	assert(remaining == 5, "footprint surround should allow redirect, got %d" % remaining)
	print("  [OK] split surround uses footprint ring")


func _test_split_blue_level_two_splits_to_all_neighbors() -> void:
	var controller := BattleController.new()
	controller.start_encounter("fission_slime_test", 42)
	var state := controller.state
	var slime := _find_slime(state)
	state.move_unit(slime, Vector2i(2, 2))
	var dummy_a := _spawn_dummy(state, Vector2i(1, 1))
	var dummy_b := _spawn_dummy(state, Vector2i(4, 4))
	_mount_gem(state, slime, Constants.SLOT_BLUE, Constants.GEM_SPLIT)
	slime.slots.append(SlotState.create(Constants.SLOT_BLUE))
	_mount_gem_on_slot(state, slime, slime.slots[slime.slots.size() - 1], Constants.GEM_SPLIT)
	var hp_a := dummy_a.hp
	var hp_b := dummy_b.hp
	var remaining := GemEffectsScript.intercept_damage_for_split(
		state, slime, "player_1", "melee_attack", 12
	)
	assert(remaining == 4, "level 2 split should leave owner one share, got %d" % remaining)
	assert(dummy_a.hp == hp_a - 4 and dummy_b.hp == hp_b - 4, "level 2 split should damage both neighbors")
	print("  [OK] split blue level 2 shares damage with all neighbors")


func _test_split_blue_level_three_temp_clone_once_per_turn() -> void:
	var controller := BattleController.new()
	controller.start_encounter("fission_slime_test", 42)
	var state := controller.state
	var slime := _find_slime(state)
	state.move_unit(slime, Vector2i(2, 2))
	_spawn_dummy(state, Vector2i(1, 1))
	_spawn_dummy(state, Vector2i(4, 4))
	while slime.slots_accepting(Constants.SLOT_BLUE).size() < 3:
		slime.slots.append(SlotState.create(Constants.SLOT_BLUE))
	var blue_slots := slime.slots_accepting(Constants.SLOT_BLUE)
	for i in range(3):
		_mount_gem_on_slot(state, slime, blue_slots[i], Constants.GEM_SPLIT)
	CombatRules.apply_damage(state, slime, 12, "player_1", "melee_attack")
	var count_after_first := _count_split_blue_temp_clones(state, slime.uid)
	var temp_clone := _find_split_blue_temp_clone(state, slime.uid)
	assert(temp_clone != null, "level 3 split blue should expose its temp clone")
	assert(temp_clone.hp == 1 and temp_clone.max_hp == 1, "temp clone hp should come from level data")
	assert(temp_clone.base_attack == 2 and temp_clone.speed == 3, "temp clone stats should use the level 3 30%% ratio")
	assert(temp_clone.slots.is_empty(), "blue temp clone should not inherit black split slots")
	assert(temp_clone not in state.get_alive_split_clones(slime.uid), "blue temp clone should stay outside black split control lifecycle")
	CombatRules.apply_damage(state, slime, 1, "player_1", "melee_attack")
	var count_after_second := _count_split_blue_temp_clones(state, slime.uid)
	assert(count_after_first == 1, "level 3 split blue should spawn one temp clone")
	assert(count_after_second == 1, "level 3 split blue should trigger once per turn")
	state.turn_index += 1
	GemEffectsScript.tick_turn_start(state)
	assert(_count_split_blue_temp_clones(state, slime.uid) == 0, "temp split clone should expire next turn")
	print("  [OK] split blue level 3 temp clone once per turn")


func _count_split_blue_temp_clones(state: GameState, origin_uid: String) -> int:
	var count := 0
	for unit in state.units.values():
		if unit.split_origin_uid == origin_uid and unit.has_tag(Constants.TAG_UNIT_SPLIT_BLUE_TEMP_CLONE):
			count += 1
	return count


func _find_split_blue_temp_clone(state: GameState, origin_uid: String) -> UnitState:
	for unit in state.units.values():
		if unit.split_origin_uid == origin_uid and unit.has_tag(Constants.TAG_UNIT_SPLIT_BLUE_TEMP_CLONE):
			return unit
	return null


func _test_clone_footprint_1x1() -> void:
	var controller := BattleController.new()
	controller.start_encounter("fission_slime_test", 42)
	var state := controller.state
	var slime := _find_slime(state)
	var events: Array[Dictionary] = []
	state.kill_unit(slime)
	GemEffectsScript.on_unit_death(state, slime, events)
	for unit in state.units.values():
		if unit.has_tag(Constants.TAG_UNIT_SPLIT_CLONE):
			assert(unit.footprint_size == Vector2i(1, 1), "clone should be 1x1")
			print("  [OK] split clones are 1x1")
			return
	assert(false, "expected split clone")


func _test_locked_clone_death_does_not_resplit() -> void:
	var controller := BattleController.new()
	controller.start_encounter("fission_slime_test", 42)
	var state := controller.state
	var slime := _find_slime(state)
	var events: Array[Dictionary] = []
	state.kill_unit(slime)
	GemEffectsScript.on_unit_death(state, slime, events)
	var clone: UnitState = null
	for unit in state.units.values():
		if not unit.has_tag(Constants.TAG_UNIT_SPLIT_CLONE):
			continue
		for slot in unit.slots:
			if slot.lock_type == Constants.LOCK_SPLIT_DISABLED:
				clone = unit
				break
	assert(clone != null, "expected a clone carrying the locked split gem")
	var before_count := 0
	for unit in state.units.values():
		if unit.has_tag(Constants.TAG_UNIT_SPLIT_CLONE):
			before_count += 1
	state.kill_unit(clone)
	GemEffectsScript.on_unit_death(state, clone, events)
	var after_count := 0
	for unit in state.units.values():
		if unit.has_tag(Constants.TAG_UNIT_SPLIT_CLONE) and unit.alive:
			after_count += 1
	assert(after_count == before_count - 1, "a clone whose split gem is locked must not resplit")
	print("  [OK] locked clone death does not resplit")


func _test_clone_uses_melee_ai() -> void:
	var controller := BattleController.new()
	controller.start_encounter("fission_slime_test", 42)
	var state := controller.state
	var slime := _find_slime(state)
	var player := state.get_player()
	var events: Array[Dictionary] = []
	state.kill_unit(slime)
	GemEffectsScript.on_unit_death(state, slime, events)
	var clone: UnitState = null
	for unit in state.units.values():
		if unit.has_tag(Constants.TAG_UNIT_SPLIT_CLONE):
			clone = unit
			break
	assert(clone != null)
	assert(clone.behavior_id == "generic_melee")
	state.move_unit(player, clone.pos + Vector2i(1, 0))
	if not BoardUtils.are_units_adjacent(clone, player):
		state.move_unit(player, clone.pos + Vector2i(0, 1))
	IntentSystem.refresh_unit_intent(state, clone)
	assert(clone.intent.type != "wait", "clone should act, got %s" % clone.intent.type)
	print("  [OK] clone uses generic melee ai")


func _test_attack_range_uses_nearest_footprint_cell() -> void:
	var controller := BattleController.new()
	controller.start_encounter("fission_slime_test", 42)
	var state := controller.state
	var slime := _find_slime(state)
	var player := state.get_player()
	state.move_unit(slime, Vector2i(3, 2))
	state.move_unit(player, Vector2i(0, 2))
	assert(BoardUtils.distance_between_units(player, slime) == 3)
	var far_cell := Vector2i(4, 3)
	assert(BoardUtils.manhattan(player.pos, far_cell) == 5)
	assert(BoardUtils.can_unit_attack_cell(player, state, far_cell, CombatConfig.attack_range()))
	var result := controller.try_attack_cell(far_cell)
	assert(result.get("ok", false), "should attack slime via nearest footprint cell")
	print("  [OK] attack range uses nearest footprint cell")


func _test_approach_around_prop() -> void:
	var controller := BattleController.new()
	controller.start_encounter("template_c", 42)
	var state := controller.state
	var slime := _find_slime(state)
	var player := state.get_player()
	assert(slime.pos == Vector2i(3, 3))
	assert(state.get_entity_at(Vector2i(2, 3)) != null, "prop should block west side")
	state.move_unit(player, Vector2i(1, 6))
	IntentSystem.refresh_unit_intent(state, slime)
	assert(slime.intent.type != "wait", "slime should move toward player around prop, got %s" % slime.intent.type)
	assert(not slime.intent.path.is_empty(), "slime should have approach path")
	print("  [OK] approach path around blocking prop")


func _test_clone_approaches_around_pillar() -> void:
	var controller := BattleController.new()
	controller.start_encounter("fission_slime_test", 42)
	var state := controller.state
	var slime := _find_slime(state)
	var player := state.get_player()
	slime.max_hp = 10
	slime.hp = 10
	var events: Array[Dictionary] = []
	state.kill_unit(slime)
	GemEffectsScript.on_unit_death(state, slime, events)
	var clone: UnitState = null
	for unit in state.units.values():
		if unit.has_tag(Constants.TAG_UNIT_SPLIT_CLONE):
			clone = unit
			break
	assert(clone != null, "expected split clone")
	var pillar := EntityState.create("prop_block", Constants.ENTITY_PROP, clone.pos + Vector2i(0, -1))
	state.add_entity(pillar)
	state.move_unit(player, clone.pos + Vector2i(-2, 0))
	IntentSystem.refresh_unit_intent(state, clone)
	assert(clone.intent.type != "wait", "clone should approach player around pillar, got %s" % clone.intent.type)
	if clone.intent.type == "move":
		var end_pos: Vector2i = clone.intent.path.back() if not clone.intent.path.is_empty() else clone.pos
		var before := BoardUtils.path_distance_to_cell(state, clone.pos, player.pos, clone.uid, {}, clone)
		var after := BoardUtils.path_distance_to_cell(state, end_pos, player.pos, clone.uid, {}, clone)
		assert(after < before, "move should reduce path distance (%d -> %d)" % [before, after])
	print("  [OK] clone approaches via path distance")


## 践踏：玩家站在大史莱姆占格上时，执行践踏后玩家被震飞，史莱姆仍然占据原格
func _test_trample_occupancy_override() -> void:
	var state := _make_bare_state()
	# 大史莱姆 2x2，锚点 (2,2)，占格 (2,2)(3,2)(2,3)(3,3)
	var slime := _make_slime(state, Vector2i(2, 2))
	# 玩家站在史莱姆某个占格上
	var player := _make_player(state, Vector2i(3, 3))
	assert(slime.occupied_cells().has(player.pos), "precondition: player on slime footprint")
	var hp_before := player.hp
	var events: Array[Dictionary] = []
	events.append_array(FissionSlimeRules.execute_trample(state, slime, _trample_intent(slime, player)))
	# 玩家应该被震飞（pos 已变）
	assert(player.pos != Vector2i(3, 3), "player should be relocated after trample, got %s" % player.pos)
	# 玩家受到伤害
	assert(
		hp_before - player.hp == FissionSlimeRules.trample_total_damage(slime),
		"player should take the configured trample skill + collision damage"
	)
	# 史莱姆仍然占据原位
	assert(slime.pos == Vector2i(2, 2), "slime should remain at anchor, got %s" % slime.pos)
	print("  [OK] trample: player relocated, slime stays, player takes damage")


## 践踏：星状落点搜索——玩家优先落在距离 1 的合法空格
func _test_trample_star_relocation() -> void:
	var state := _make_bare_state()
	var slime := _make_slime(state, Vector2i(2, 2))
	# 玩家站在 (3,3) 被踩
	var player := _make_player(state, Vector2i(3, 3))
	var events: Array[Dictionary] = []
	events.append_array(FissionSlimeRules.execute_trample(state, slime, _trample_intent(slime, player)))
	# 距离 (3,3) 最近的合法空格应在距离 ≤ 2 以内
	var dist := BoardUtils.manhattan(Vector2i(3, 3), player.pos)
	assert(dist <= 2, "player should land within ring 2 of origin (3,3), got dist=%d pos=%s" % [dist, player.pos])
	print("  [OK] trample star relocation: player lands within ring 2")


## 践踏：全堵死时触发空间挤压惩罚伤害，玩家停留在原位（保底保留）
func _test_trample_squeeze_all_blocked() -> void:
	var state := _make_bare_state()
	var slime := _make_slime(state, Vector2i(0, 0))
	# 玩家在 (1,1)（史莱姆 footprint 内）
	var player := _make_player(state, Vector2i(1, 1))
	player.hp = 5
	player.max_hp = 5
	# 堵住配置搜索半径内的所有棋盘内候选格。
	var max_distance := CombatConfig.star_relocation_max_distance()
	var blocked_index := 0
	for x in range(
		maxi(0, player.pos.x - max_distance),
		mini(state.board_size.x - 1, player.pos.x + max_distance) + 1
	):
		for y in range(
			maxi(0, player.pos.y - max_distance),
			mini(state.board_size.y - 1, player.pos.y + max_distance) + 1
		):
			var cell := Vector2i(x, y)
			if cell == player.pos or slime.occupied_cells().has(cell):
				continue
			blocked_index += 1
			state.add_entity(EntityState.create(
				"squeeze_block_%d" % blocked_index,
				Constants.ENTITY_ROCK,
				cell
			))
	var events: Array[Dictionary] = []
	events.append_array(FissionSlimeRules.execute_trample(state, slime, _trample_intent(slime, player)))
	var squeeze_events := events.filter(func(event: Dictionary) -> bool:
		return str(event.get("type", "")) == "damage" \
			and str(event.get("reason", "")) == "space_squeeze"
	)
	assert(squeeze_events.size() == 1, "fully blocked trample should emit space_squeeze damage")
	assert(not player.alive, "trample plus squeeze should defeat the 5 HP fixture target")
	assert(EventValidator.assert_valid(events, "fission_slime.squeeze_all_blocked"))
	assert(BattleInvariantChecker.assert_valid(state, "fission_slime.squeeze_all_blocked"))
	print("  [OK] trample squeeze: all blocked, player takes squeeze penalty")


## 践踏：落点有地刺时，结算地刺伤害（落点地形二次结算）
func _test_trample_landing_terrain_settlement() -> void:
	var state := _make_bare_state()
	var slime := _make_slime(state, Vector2i(2, 2))
	var player := _make_player(state, Vector2i(3, 3))
	# 把距离 (3,3) 最近的合法落点（优先上方 (3,2)）改成地刺
	# 先模拟找到落点，然后在那里放地刺
	var reloc := BoardUtils.find_star_relocation_cell(state, Vector2i(3, 3), player.uid)
	var landing: Vector2i = reloc.get("pos", Vector2i(3, 2))
	state.add_entity(EntityState.create("spike_land", Constants.ENTITY_SPIKE, landing))
	var hp_before := player.hp
	var events: Array[Dictionary] = []
	events.append_array(FissionSlimeRules.execute_trample(state, slime, _trample_intent(slime, player)))
	# 践踏伤害 + 地刺伤害，总血量应低于只受践踏伤害
	assert(player.hp < hp_before - FissionSlimeRules.trample_total_damage(slime), "landing spike should add extra damage on top of trample")
	print("  [OK] trample landing terrain: spike damage applied after relocation")


func _trample_intent(slime: UnitState, target: UnitState) -> IntentState:
	var intent := IntentState.new()
	intent.type = "trample"
	intent.source_uid = slime.uid
	intent.target_uid = target.uid
	intent.path = []
	intent.target_pos = slime.pos
	intent.base_damage = FissionSlimeRules.trample_damage(slime)
	intent.damage = FissionSlimeRules.trample_total_damage(slime)
	return intent


func _make_bare_state() -> GameState:
	var state := GameState.new()
	state.board_size = Constants.BOARD_SIZE
	state.units = {}
	return state


func _make_slime(state: GameState, pos: Vector2i) -> UnitState:
	var reg: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	var uid: String = reg.next_runtime_uid("slime")
	var unit := UnitState.from_def(uid, "unit_fission_slime", Constants.TEAM_ENEMY, pos, reg.get_unit_def("unit_fission_slime"))
	state.register_unit(unit)
	return unit


func _make_player(state: GameState, pos: Vector2i) -> UnitState:
	var unit := UnitState.new()
	unit.uid = "player"
	unit.team = Constants.TEAM_PLAYER
	unit.pos = pos
	unit.hp = 20
	unit.max_hp = 20
	unit.alive = true
	unit.footprint_size = Vector2i(1, 1)
	state.register_unit(unit)
	state.player_uid = unit.uid
	return unit


func _spawn_dummy(state: GameState, pos: Vector2i) -> UnitState:
	var reg: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	var uid: String = reg.next_runtime_uid("dummy")
	var unit := UnitState.from_def(uid, "unit_patrol_guard", Constants.TEAM_ENEMY, pos, reg.get_unit_def("unit_patrol_guard"))
	state.register_unit(unit)
	return unit


func _mount_gem(state: GameState, unit: UnitState, slot_type: String, gem_id: String) -> void:
	var reg: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	var slot := unit.get_slot(slot_type)
	assert(slot != null, "slot should exist")
	_mount_gem_on_slot(state, unit, slot, gem_id)


func _mount_gem_on_slot(state: GameState, unit: UnitState, slot: SlotState, gem_id: String) -> void:
	var reg: Node = Engine.get_main_loop().root.get_node("DataRegistry")
	if not slot.gem_uid.is_empty():
		state.gems.erase(slot.gem_uid)
	var gem_uid: String = reg.next_runtime_uid("gem")
	var gem: GemState = reg.create_gem_instance(gem_uid, gem_id, {})
	gem.owner_uid = unit.uid
	gem.slot_index = unit.slots.find(slot)
	state.gems[gem_uid] = gem
	slot.gem_uid = gem_uid


func _find_slime(state: GameState) -> UnitState:
	for unit in state.units.values():
		if unit.unit_def_id == "unit_fission_slime":
			return unit
	return null
