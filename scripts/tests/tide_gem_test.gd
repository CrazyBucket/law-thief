extends SceneTree

const Builder = preload("res://scripts/testkit/scenario_builder.gd")
const StatusRegistry = preload("res://scripts/rules/status_registry.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Tide Gem Test ===")
	_test_red_flush_levels_and_shallow_water()
	_test_blue_trigger_limits_and_attack_deduplication()
	_test_black_flushes_each_nearby_unit()
	_test_shallow_water_overlay_reactions()
	_test_shallow_water_wet_refresh_boundaries()
	_test_wet_fire_and_arc_reactions()
	if _failed:
		push_error("TIDE_GEM_TEST_FAIL")
		quit(1)
		return
	print("TIDE_GEM_TEST_PASS")
	quit(0)


func _test_red_flush_levels_and_shallow_water() -> void:
	_expect(
		FileAccess.file_exists("res://assets/ui/gem_icons_generated/gem_tide.png"),
		"tide gem should load its generated icon"
	)
	for level in range(1, 4):
		var builder = Builder.new("fission_slime_test", 9600 + level, true)
		var attacker := builder.player()
		builder.move(attacker, Vector2i(1, 3)).clear_slots(attacker)
		var gems: Array = []
		for _index in range(level):
			gems.append(Constants.GEM_TIDE)
		builder.mount_gems(attacker, Constants.SLOT_RED, gems)
		var target := builder.add_unit(
			"tide_red_%d" % level,
			"unit_patrol_guard",
			Constants.TEAM_ENEMY,
			Vector2i(3, 3),
			{"hp": 100, "max_hp": 100}
		)
		builder.clear_slots(target)
		var state := builder.finish()
		_add_status(target, Constants.STATUS_BURNING, 2)
		_add_status(target, Constants.STATUS_POISON, 3)
		_add_status(target, Constants.STATUS_STORED_FLURRY, 3)
		_add_status(target, Constants.STATUS_LAWLESS, 1)
		var before_mass := _flush_mass(target)
		var before_kinds := _flush_kind_count(target)
		var result := CombatRules.ranged_attack(state, attacker, target.pos, CombatConfig.attack_range())
		_expect(bool(result.get("ok", false)), "red tide level %d should execute" % level)
		_expect(not target.has_status(Constants.STATUS_BURNING), "red tide must extinguish burning before spending flushes")
		_expect(target.has_status(Constants.STATUS_WET), "shallow water created under the target should apply wet")
		_expect(state.get_tile(target.pos).has_modifier(Constants.TILE_MOD_SHALLOW_WATER), "red tide should create shallow water")
		if level < 3:
			_expect(
				_flush_mass(target) == before_mass - level,
				"red tide level %d should remove exactly %d total layer(s)" % [level, level]
			)
		else:
			_expect(
				_flush_kind_count(target) == before_kinds - 1,
				"red tide level 3 should remove every layer of exactly one flushable status"
			)
		_expect(_valid(state, result.get("events", [])), "red tide level %d should preserve invariants" % level)
	print("  [OK] red tide levels flush without spending a flush on burning")


func _test_blue_trigger_limits_and_attack_deduplication() -> void:
	for level in range(1, 4):
		var builder = Builder.new("fission_slime_test", 9610 + level, true)
		var owner := builder.player()
		builder.move(owner, Vector2i(3, 3)).clear_slots(owner)
		var gems: Array = []
		for _index in range(level):
			gems.append(Constants.GEM_TIDE)
		builder.mount_gems(owner, Constants.SLOT_BLUE, gems)
		var source := builder.add_unit(
			"tide_blue_source_%d" % level,
			"unit_patrol_guard",
			Constants.TEAM_ENEMY,
			Vector2i(4, 3),
			{"hp": 100, "max_hp": 100}
		)
		builder.clear_slots(source)
		var state := builder.finish()
		if level < 3:
			_add_status(source, Constants.STATUS_STORED_FLURRY, 6)
		else:
			_add_status(source, Constants.STATUS_STORED_FLURRY, 2)
			_add_status(source, Constants.STATUS_POISON, 2)
			_add_status(source, Constants.STATUS_LAWLESS, 1)
		var event_ids := ["blue_a", "blue_a", "blue_b", "blue_c"]
		for event_id in event_ids:
			var damage_context := DamageContext.create(source.uid, "attack", [], {}, true)
			damage_context["attack_event_id"] = event_id
			CombatRules.apply_damage(state, owner, 1, source.uid, "attack", damage_context)
		if level == 1:
			_expect(_status_layers(source, Constants.STATUS_STORED_FLURRY) == 5, "blue level 1 should trigger once per round")
		elif level == 2:
			_expect(_status_layers(source, Constants.STATUS_STORED_FLURRY) == 4, "blue level 2 should trigger on two distinct attacks")
		else:
			_expect(_flush_kind_count(source) == 0, "blue level 3 should trigger on every distinct active attack")
		_expect(owner.has_status(Constants.STATUS_WET), "blue tide should create shallow water under its owner")
		_expect(state.get_tile(owner.pos).has_modifier(Constants.TILE_MOD_SHALLOW_WATER), "blue tide should leave shallow water under its owner")
	print("  [OK] blue tide respects per-round limits and deduplicates attack segments")


func _test_black_flushes_each_nearby_unit() -> void:
	var builder = Builder.new("fission_slime_test", 9620, true)
	var killer := builder.player()
	builder.move(killer, Vector2i(2, 3)).clear_slots(killer)
	var owner := builder.add_unit("tide_black_owner", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(3, 3), {"hp": 1, "max_hp": 1})
	var near := builder.add_unit("tide_black_near", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(4, 3), {"hp": 100, "max_hp": 100})
	var far := builder.add_unit("tide_black_far", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(6, 6), {"hp": 100, "max_hp": 100})
	builder.clear_slots(owner).clear_slots(near).clear_slots(far)
	builder.mount_gems(owner, Constants.SLOT_BLACK, [Constants.GEM_TIDE, Constants.GEM_TIDE, Constants.GEM_TIDE])
	for unit in [killer, near, far]:
		_add_status(unit, Constants.STATUS_POISON, 2)
		_add_status(unit, Constants.STATUS_STORED_FLURRY, 2)
	var state := builder.finish()
	var events: Array[Dictionary] = []
	state.bind_combat_events(events)
	CombatRules.apply_damage(state, owner, 1, killer.uid, "test_death")
	state.unbind_combat_events()
	_expect(_flush_kind_count(killer) == 1 and _flush_kind_count(near) == 1, "black level 3 should remove exactly one status kind from each nearby unit")
	_expect(_flush_kind_count(far) == 2, "black tide must not affect units outside the surrounding 3x3")
	_expect(state.get_tile(killer.pos).has_modifier(Constants.TILE_MOD_SHALLOW_WATER), "black tide should create water under each nearby unit")
	_expect(state.get_tile(near.pos).has_modifier(Constants.TILE_MOD_SHALLOW_WATER), "black tide should create water under same-team nearby units too")
	_expect(not state.get_tile(far.pos).has_modifier(Constants.TILE_MOD_SHALLOW_WATER), "black tide should not create water under distant units")
	_expect(_valid(state, events), "black tide should preserve battle and event invariants")
	print("  [OK] black tide resolves one capped flush package per nearby unit")


func _test_shallow_water_overlay_reactions() -> void:
	var state := GameState.new()
	var cell := Vector2i(2, 2)
	TileRules.create_fire(state, cell, 2)
	TileRules.create_shallow_water(state, cell, 2)
	_expect(state.get_tile(cell).has_modifier(Constants.TILE_MOD_SHALLOW_WATER), "flush should remove fire and then create shallow water")
	_expect(not state.get_tile(cell).has_modifier(Constants.TILE_MOD_FIRE), "flush should clear fire")
	TileRules.create_fire(state, cell, 2)
	_expect(not state.get_tile(cell).has_modifier(Constants.TILE_MOD_SHALLOW_WATER), "incoming fire should consume shallow water")
	_expect(not state.get_tile(cell).has_modifier(Constants.TILE_MOD_FIRE), "fire and shallow water should leave no overlay")

	TileRules.create_shallow_water(state, cell, 2)
	TileRules.create_poison_fog(state, cell, 2)
	_expect(state.get_tile(cell).has_modifier(Constants.TILE_MOD_POISON_PUDDLE), "poison fog should contaminate shallow water")
	_expect(not state.get_tile(cell).has_modifier(Constants.TILE_MOD_SHALLOW_WATER), "contaminated shallow water should become poison puddle")

	var smoke_cell := Vector2i(3, 2)
	TileRules.create_poison_fog(state, smoke_cell, 2)
	TileRules.create_fire(state, smoke_cell, 2)
	TileRules.create_shallow_water(state, smoke_cell, 2)
	_expect(state.get_tile(smoke_cell).has_modifier(Constants.TILE_MOD_POISON_FOG), "washing toxic smoke should downgrade it to poison fog")
	_expect(not state.get_tile(smoke_cell).has_modifier(Constants.TILE_MOD_SHALLOW_WATER), "toxic-smoke downgrade should not create shallow water")
	print("  [OK] shallow water rewrites fire, poison fog, and toxic smoke")


func _test_shallow_water_wet_refresh_boundaries() -> void:
	var builder = Builder.new("fission_slime_test", 9630, true)
	var unit := builder.player()
	builder.move(unit, Vector2i(2, 2)).clear_slots(unit)
	var state := builder.finish()
	StatusRules.apply_burning(state, unit, 2)
	TileRules.create_shallow_water(state, unit.pos, 2)
	_expect(unit.has_status(Constants.STATUS_WET), "creating shallow water under a unit should apply wet")
	_expect(not unit.has_status(Constants.STATUS_BURNING), "water created under a burning unit should extinguish it without consuming the water")
	unit.remove_status(Constants.STATUS_WET)
	StatusRules.tick_unit_turn_end(state, unit)
	_expect(not unit.has_status(Constants.STATUS_WET), "remaining on shallow water must not immediately restore consumed wet at round end")
	StatusRules.tick_unit_turn_start(state, unit)
	_expect(unit.has_status(Constants.STATUS_WET), "turn start on shallow water should restore wet")

	var first := unit.pos
	var second := Vector2i(3, 2)
	TileRules.create_shallow_water(state, second, 2)
	unit.remove_status(Constants.STATUS_WET)
	state.move_unit(unit, second)
	TileRules.finish_voluntary_move(state, unit, first)
	_expect(not unit.has_status(Constants.STATUS_WET), "moving directly between shallow-water cells should not count as leaving and re-entering")
	state.move_unit(unit, Vector2i(4, 2))
	TileRules.finish_voluntary_move(state, unit, second)
	var dry := unit.pos
	state.move_unit(unit, second)
	TileRules.finish_voluntary_move(state, unit, dry)
	_expect(unit.has_status(Constants.STATUS_WET), "leaving and re-entering shallow water should restore wet")
	print("  [OK] shallow water wet refresh follows creation, re-entry, and turn start only")


func _test_wet_fire_and_arc_reactions() -> void:
	var builder = Builder.new("fission_slime_test", 9640, true)
	var attacker := builder.player()
	builder.move(attacker, Vector2i(1, 3)).clear_slots(attacker)
	builder.mount_gems(attacker, Constants.SLOT_RED, [Constants.GEM_CONDUCTIVE])
	var target := builder.add_unit("wet_arc_target", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(3, 3), {"hp": 100, "max_hp": 100})
	var neighbor := builder.add_unit("wet_arc_neighbor", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i(6, 3), {"hp": 100, "max_hp": 100})
	builder.clear_slots(target).clear_slots(neighbor)
	var state := builder.finish()
	StatusRules.apply_wet(state, attacker, 2)
	StatusRules.apply_wet(state, target, 2)
	StatusRules.apply_wet(state, neighbor, 2)
	var attacker_hp := attacker.hp
	var neighbor_hp := neighbor.hp
	var result := CombatRules.ranged_attack(state, attacker, target.pos, CombatConfig.attack_range())
	_expect(attacker.hp < attacker_hp, "a wet arc attacker inside the reaction range must be conducted into")
	_expect(neighbor.hp < neighbor_hp, "wet arc should conduct one range farther than the normal level-one arc")
	_expect(not attacker.has_status(Constants.STATUS_WET) and not target.has_status(Constants.STATUS_WET) and not neighbor.has_status(Constants.STATUS_WET), "each wet arc reaction recipient should consume wet")
	_expect(_valid(state, result.get("events", [])), "wet arc conduction should preserve invariants")

	StatusRules.apply_wet(state, neighbor, 2)
	StatusRules.apply_burning(state, neighbor, 1, attacker.uid)
	_expect(not neighbor.has_status(Constants.STATUS_WET) and not neighbor.has_status(Constants.STATUS_BURNING), "wet should consume itself to cancel one incoming burning layer")
	print("  [OK] wet reacts with fire and conducts arc back into wet attackers")


func _add_status(unit: UnitState, status_id: String, stacks: int) -> void:
	StatusRegistry.apply_to_unit(unit, StatusInstance.create(status_id, stacks, 2, "tide_test"))


func _status_layers(unit: UnitState, status_id: String) -> int:
	var status := unit.get_status(status_id)
	if status == null:
		return 0
	return status.value if StatusRegistry.flush_measure(status_id) == "value" else status.stacks


func _flush_mass(unit: UnitState) -> int:
	var total := 0
	for status: StatusInstance in unit.statuses:
		if StatusRegistry.is_flushable(status.status_id):
			total += status.value if StatusRegistry.flush_measure(status.status_id) == "value" else status.stacks
	return total


func _flush_kind_count(unit: UnitState) -> int:
	return unit.statuses.filter(func(status: StatusInstance) -> bool:
		return StatusRegistry.is_flushable(status.status_id)
	).size()


func _valid(state: GameState, events: Array) -> bool:
	return BattleInvariantChecker.check_all(state).is_empty() and EventValidator.validate_events(events).is_empty()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
