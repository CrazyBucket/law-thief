extends SceneTree

const Builder = preload("res://scripts/testkit/scenario_builder.gd")
const CombatTransaction = preload("res://scripts/rules/combat_transaction.gd")
const CONTRACT_PATH := "res://tests/contracts/gem_semantics.json"

var _failed := false
var _passed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var document := _load_contract()
	for raw_case in document.get("cases", []):
		_run_case(raw_case)
	if _failed:
		push_error("GEM_SEMANTIC_CONTRACT_FAIL passed=%d" % _passed)
		quit(1)
		return
	print("GEM_SEMANTIC_CONTRACT_PASS cases=%d" % _passed)
	quit(0)


func _run_case(contract: Dictionary) -> void:
	var builder = Builder.new("fission_slime_test", 4401, true)
	var player := builder.player()
	builder.clear_slots(player)
	var player_pos := _vector_from_variant(contract.get("player_pos", Vector2i(2, 3)))
	builder.move(player, player_pos)
	var player_stats: Dictionary = contract.get("player_stats", {})
	if not player_stats.is_empty():
		builder.set_stats(player, player_stats)
	builder.mount_gems(player, Constants.SLOT_RED, contract.get("gems", []))
	var target_pos := _vector_from_variant(contract.get("target_pos", Vector2i(5, 3)))
	var target := builder.add_unit(
		"contract_target",
		"unit_patrol_guard",
		Constants.TEAM_ENEMY,
		target_pos,
		{"hp": 100, "max_hp": 100}
	)
	var tracked_units: Dictionary = {
		target.uid: target,
		player.uid: player,
		"player": player,
		"contract_target": target,
	}
	for raw_unit in contract.get("extra_units", []):
		var unit_def_id := str(raw_unit.get("unit_def_id", "unit_patrol_guard"))
		var extra := builder.add_unit(
			str(raw_unit.get("uid", "")),
			unit_def_id,
			str(raw_unit.get("team", Constants.TEAM_ENEMY)),
			_vector_from_variant(raw_unit.get("pos", Vector2i.ZERO)),
			raw_unit.get("stats", {"hp": 100, "max_hp": 100})
		)
		tracked_units[extra.uid] = extra
	for raw_entity in contract.get("entities", []):
		builder.state.add_entity(EntityState.create(
			str(raw_entity.get("uid", "")),
			str(raw_entity.get("entity_id", Constants.ENTITY_PROP)),
			_vector_from_variant(raw_entity.get("pos", Vector2i.ZERO))
		))
	var state := builder.finish()
	var setup: Dictionary = contract.get("setup", {})
	_apply_setup_statuses(state, player, player, setup.get("player_statuses", []))
	_apply_setup_statuses(state, target, player, setup.get("target_statuses", []))
	if str(setup.get("target_status", "")) == Constants.STATUS_BURNING:
		StatusRules.apply_burning(state, target, 1, player.uid)
	for raw_setup_unit in setup.get("unit_statuses", []):
		var unit_uid := str(raw_setup_unit.get("uid", ""))
		var unit: UnitState = tracked_units.get(unit_uid, null)
		if unit == null:
			continue
		_apply_setup_statuses(state, unit, player, raw_setup_unit.get("statuses", []))
	for key in (setup.get("battle_temp_flags", {}) as Dictionary).keys():
		state.battle_temp_flags[key] = setup["battle_temp_flags"][key]
	var hp_before: Dictionary = {}
	for unit_uid in tracked_units.keys():
		var unit: UnitState = tracked_units[unit_uid]
		hp_before[unit_uid] = unit.hp
	var action_tags: Array[String] = [AttackPipeline.TAG_RANGED]
	for raw_tag in contract.get("action_tags", []):
		action_tags.append(str(raw_tag))
	var aim_cell := _vector_from_variant(contract.get("aim_cell", target.pos))
	var result := AttackPipeline.execute_aimed(state, player, aim_cell, action_tags)
	var events: Array = result.get("events", [])
	for raw_step in contract.get("post_steps", []):
		_run_post_step(state, tracked_units, events, raw_step)
	var expect: Dictionary = contract.get("expect", {})
	var label := str(contract.get("id", "unnamed"))
	var failure_before_case := _failed

	_check(result.get("ok", false) == bool(expect.get("ok", true)), label, "action result expected=%s actual=%s" % [str(expect.get("ok", true)), str(result.get("ok", false))])
	if expect.has("damage"):
		_check(int(hp_before.get(target.uid, target.hp)) - target.hp == int(expect.get("damage", -1)), label, "damage expected=%d actual=%d" % [int(expect.get("damage", -1)), int(hp_before.get(target.uid, target.hp)) - target.hp])
	if expect.has("target_status"):
		_check(target.has_status(str(expect["target_status"])), label, "target missing status %s" % expect["target_status"])
	if expect.has("target_pos"):
		_check(target.pos == _vector_from_variant(expect.get("target_pos", target.pos)), label, "target pos expected=%s actual=%s" % [str(expect.get("target_pos", "")), str(target.pos)])
	if expect.has("unit_damages"):
		for unit_uid in (expect["unit_damages"] as Dictionary).keys():
			var unit: UnitState = tracked_units.get(str(unit_uid), null)
			_check(unit != null, label, "missing tracked unit %s" % unit_uid)
			if unit == null:
				continue
			var actual_damage := int(hp_before.get(unit.uid, unit.hp)) - unit.hp
			var expected_damage := int(expect["unit_damages"][unit_uid])
			_check(actual_damage == expected_damage, label, "unit %s damage expected=%d actual=%d" % [unit_uid, expected_damage, actual_damage])
	if expect.has("unit_positions"):
		for unit_uid in (expect["unit_positions"] as Dictionary).keys():
			var unit: UnitState = tracked_units.get(str(unit_uid), null)
			_check(unit != null, label, "missing tracked unit %s" % unit_uid)
			if unit == null:
				continue
			var expected_pos := _vector_from_variant(expect["unit_positions"][unit_uid])
			_check(unit.pos == expected_pos, label, "unit %s pos expected=%s actual=%s" % [unit_uid, str(expected_pos), str(unit.pos)])
	if expect.has("unit_statuses"):
		for unit_uid in (expect["unit_statuses"] as Dictionary).keys():
			var unit: UnitState = tracked_units.get(str(unit_uid), null)
			_check(unit != null, label, "missing tracked unit %s" % unit_uid)
			if unit == null:
				continue
			_check_status_expectations(unit, expect["unit_statuses"][unit_uid], label, unit_uid)
	if expect.has("fire_cells"):
		_check(_count_tiles(state, Constants.TILE_MOD_FIRE) == int(expect["fire_cells"]), label, "fire cell count expected=%d actual=%d" % [int(expect["fire_cells"]), _count_tiles(state, Constants.TILE_MOD_FIRE)])
	if expect.has("poison_fog_cells"):
		_check(_count_tiles(state, Constants.TILE_MOD_POISON_FOG) == int(expect["poison_fog_cells"]), label, "poison fog count expected=%d actual=%d" % [int(expect["poison_fog_cells"]), _count_tiles(state, Constants.TILE_MOD_POISON_FOG)])
	if expect.has("toxic_smoke_cells"):
		_check(_count_tiles(state, Constants.TILE_MOD_TOXIC_SMOKE) == int(expect["toxic_smoke_cells"]), label, "toxic smoke count expected=%d actual=%d" % [int(expect["toxic_smoke_cells"]), _count_tiles(state, Constants.TILE_MOD_TOXIC_SMOKE)])
	if expect.has("tile_modifier_durations"):
		for raw_duration in expect.get("tile_modifier_durations", []):
			var pos := _vector_from_variant(raw_duration.get("pos", Vector2i.ZERO))
			var tile := state.get_tile(pos)
			var modifier := str(raw_duration.get("modifier", ""))
			var actual_duration := -1
			if tile != null and tile.has_modifier(modifier):
				actual_duration = int(tile.get_modifier(modifier).get("duration", -1))
			_check(actual_duration == int(raw_duration.get("duration", -1)), label, "modifier %s at %s duration expected=%d actual=%d" % [modifier, str(pos), int(raw_duration.get("duration", -1)), actual_duration])
	if expect.has("event_counts"):
		for event_type in (expect["event_counts"] as Dictionary).keys():
			_check(_count_events(events, str(event_type)) == int(expect["event_counts"][event_type]), label, "event %s count expected=%d actual=%d" % [event_type, int(expect["event_counts"][event_type]), _count_events(events, str(event_type))])
	if expect.has("event_min_counts"):
		for event_type in (expect["event_min_counts"] as Dictionary).keys():
			_check(_count_events(events, str(event_type)) >= int(expect["event_min_counts"][event_type]), label, "event %s count expected>=%d actual=%d" % [event_type, int(expect["event_min_counts"][event_type]), _count_events(events, str(event_type))])
	if expect.has("event_matches"):
		for raw_match in expect.get("event_matches", []):
			_check(_has_event_match(events, raw_match), label, "missing event match %s" % JSON.stringify(raw_match))
	if expect.has("combo_event"):
		_check(_has_combo(events, str(expect["combo_event"])), label, "missing combo event %s" % expect["combo_event"])
	_check(BattleInvariantChecker.check_all(state).is_empty(), label, "battle invariant violation")
	_check(EventValidator.validate_events(events).is_empty(), label, "event invariant violation")
	if _failed == failure_before_case:
		_passed += 1
		print("  CONTRACT_PASS ", label)


func _count_tiles(state: GameState, modifier: String) -> int:
	var count := 0
	for tile: TileState in state.tiles.values():
		if tile.has_modifier(modifier):
			count += 1
	return count


func _has_combo(events: Array, combo: String) -> bool:
	for event in events:
		if str(event.get("combo", "")) == combo:
			return true
	return false


func _count_events(events: Array, event_type: String) -> int:
	var count := 0
	for event in events:
		if str(event.get("type", "")) == event_type:
			count += 1
	return count


func _has_event_match(events: Array, matcher: Dictionary) -> bool:
	for raw_event in events:
		var event: Dictionary = raw_event
		var matched := true
		for key in matcher.keys():
			var expected: Variant = matcher[key]
			var actual: Variant = event.get(key, null)
			if expected is Array and actual is Vector2i:
				if _vector_from_variant(expected) != actual:
					matched = false
					break
				continue
			if expected is float or actual is float:
				if absf(float(actual) - float(expected)) > 0.001:
					matched = false
					break
				continue
			if actual != expected:
				matched = false
				break
		if matched:
			return true
	return false


func _check_status_expectations(unit: UnitState, expectations: Dictionary, label: String, unit_uid: String) -> void:
	for status_id in expectations.keys():
		var want: Dictionary = expectations[status_id]
		var status: StatusInstance = unit.get_status(str(status_id))
		_check(status != null, label, "unit %s missing status %s" % [unit_uid, status_id])
		if status == null:
			continue
		if want.has("stacks"):
			_check(status.stacks == int(want.get("stacks", 0)), label, "unit %s status %s stacks expected=%d actual=%d" % [unit_uid, status_id, int(want.get("stacks", 0)), status.stacks])
		if want.has("duration"):
			_check(status.duration == int(want.get("duration", 0)), label, "unit %s status %s duration expected=%d actual=%d" % [unit_uid, status_id, int(want.get("duration", 0)), status.duration])


func _apply_setup_statuses(state: GameState, unit: UnitState, source: UnitState, statuses: Array) -> void:
	for raw_status in statuses:
		var status_id := str(raw_status.get("status", ""))
		match status_id:
			Constants.STATUS_BURNING:
				StatusRules.apply_burning(state, unit, int(raw_status.get("stacks", 1)), source.uid)
			Constants.STATUS_POISON:
				StatusRules.apply_poison(state, unit, int(raw_status.get("stacks", 1)), int(raw_status.get("duration", 0)), source.uid)
			Constants.STATUS_SLOWED:
				StatusRules.apply_slowed(state, unit, int(raw_status.get("stacks", 1)), source.uid)
			Constants.STATUS_PARALYZED:
				StatusRules.apply_paralyzed(state, unit, int(raw_status.get("duration", 1)), source.uid)
			Constants.STATUS_WET:
				StatusRules.apply_wet(state, unit, int(raw_status.get("duration", 2)), source.uid)


func _run_post_step(state: GameState, tracked_units: Dictionary, events: Array, raw_step: Dictionary) -> void:
	match str(raw_step.get("type", "")):
		"apply_damage":
			var target: UnitState = tracked_units.get(str(raw_step.get("target", "")), null)
			var source: UnitState = tracked_units.get(str(raw_step.get("source", "")), null)
			_check(target != null, "post_step", "missing damage target %s" % str(raw_step.get("target", "")))
			_check(source != null, "post_step", "missing damage source %s" % str(raw_step.get("source", "")))
			if target == null or source == null:
				return
			var tx := CombatTransaction.begin(state, events)
			tx.damage_unit(
				target,
				int(raw_step.get("amount", 0)),
				source.uid,
				str(raw_step.get("reason", "attack")),
				{"pos": target.pos}
			)


func _vector_from_variant(raw: Variant) -> Vector2i:
	if raw is Vector2i:
		return raw
	if raw is Array and raw.size() >= 2:
		return Vector2i(int(raw[0]), int(raw[1]))
	return Vector2i.ZERO


func _check(condition: bool, label: String, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("CONTRACT_FAIL %s: %s" % [label, message])


func _load_contract() -> Dictionary:
	var file := FileAccess.open(CONTRACT_PATH, FileAccess.READ)
	assert(file != null, "contract file should exist")
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, "contract file should be valid JSON")
	return parsed
