extends SceneTree

const Builder = preload("res://scripts/testkit/scenario_builder.gd")
const CombatRules = preload("res://scripts/rules/combat_rules.gd")
const CombatTransaction = preload("res://scripts/rules/combat_transaction.gd")
const CONTRACT_PATH := "res://tests/contracts/gem_semantics.json"

var _failed := false
var _passed := 0
var _failure_count := 0


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
	var builder = Builder.new("fission_slime_test", int(contract.get("seed", 4401)), true)
	var player := builder.player()
	builder.clear_slots(player)
	var player_pos := _vector_from_variant(contract.get("player_pos", Vector2i(2, 3)))
	builder.move(player, player_pos)
	var player_stats: Dictionary = contract.get("player_stats", {})
	if not player_stats.is_empty():
		builder.set_stats(player, player_stats)
	builder.mount_gems(player, Constants.SLOT_RED, contract.get("gems", []))
	var target_pos := _vector_from_variant(contract.get("target_pos", Vector2i(5, 3)))
	var target_stats: Dictionary = contract.get("target_stats", {"hp": 100, "max_hp": 100})
	var target := builder.add_unit(
		"contract_target",
		str(contract.get("target_unit_def_id", "unit_patrol_guard")),
		Constants.TEAM_ENEMY,
		target_pos,
		target_stats
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
	for raw_mount in contract.get("mounts", []):
		var unit_uid := str(raw_mount.get("uid", ""))
		var unit: UnitState = tracked_units.get(unit_uid, null)
		_check(unit != null, str(contract.get("id", "unnamed")), "missing mount unit %s" % unit_uid)
		if unit == null:
			continue
		if bool(raw_mount.get("clear_slots", false)):
			builder.clear_slots(unit)
		builder.mount_gems(unit, str(raw_mount.get("slot", Constants.SLOT_RED)), raw_mount.get("gems", []))
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
	var slotted_gems_before: Dictionary = {}
	for unit_uid in tracked_units.keys():
		var unit: UnitState = tracked_units[unit_uid]
		hp_before[unit_uid] = unit.hp
		if not slotted_gems_before.has(unit.uid):
			var gem_uids: Array[String] = []
			for slot in unit.slots:
				if slot != null and not slot.gem_uid.is_empty():
					gem_uids.append(slot.gem_uid)
			slotted_gems_before[unit.uid] = gem_uids
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
	var failure_count_before_case := _failure_count

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
	if expect.has("unit_status_absences"):
		for unit_uid in (expect["unit_status_absences"] as Dictionary).keys():
			var unit: UnitState = tracked_units.get(str(unit_uid), null)
			_check(unit != null, label, "missing tracked unit %s" % unit_uid)
			if unit == null:
				continue
			for status_id in expect["unit_status_absences"][unit_uid]:
				_check(not unit.has_status(str(status_id)), label, "unit %s should not have status %s" % [unit_uid, status_id])
	if expect.has("unit_effective_move_points"):
		for unit_uid in (expect["unit_effective_move_points"] as Dictionary).keys():
			var unit: UnitState = tracked_units.get(str(unit_uid), null)
			_check(unit != null, label, "missing tracked unit %s" % unit_uid)
			if unit == null:
				continue
			var actual_move := StatusRules.effective_move_points(unit, unit.move_points)
			var expected_move := int(expect["unit_effective_move_points"][unit_uid])
			_check(actual_move == expected_move, label, "unit %s effective move expected=%d actual=%d" % [unit_uid, expected_move, actual_move])
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
	if expect.has("tile_modifier_absences"):
		for raw_absence in expect.get("tile_modifier_absences", []):
			var pos := _vector_from_variant(raw_absence.get("pos", Vector2i.ZERO))
			var tile := state.get_tile(pos)
			var modifier := str(raw_absence.get("modifier", ""))
			_check(not tile.has_modifier(modifier), label, "modifier %s should be absent at %s" % [modifier, str(pos)])
	if expect.has("tile_modifier_duration_counts"):
		for raw_count in expect.get("tile_modifier_duration_counts", []):
			var modifier := str(raw_count.get("modifier", ""))
			var duration := int(raw_count.get("duration", -1))
			var expected_count := int(raw_count.get("count", 0))
			var actual_count := _count_tiles_with_modifier_duration(state, modifier, duration)
			_check(actual_count == expected_count, label, "modifier %s duration %d count expected=%d actual=%d" % [modifier, duration, expected_count, actual_count])
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
	if expect.has("split_clones"):
		_check_split_clone_expectations(state, tracked_units, expect["split_clones"], slotted_gems_before, label)
	_check(BattleInvariantChecker.check_all(state).is_empty(), label, "battle invariant violation")
	_check(EventValidator.validate_events(events).is_empty(), label, "event invariant violation")
	if _failure_count == failure_count_before_case:
		_passed += 1
		print("  CONTRACT_PASS ", label)


func _count_tiles(state: GameState, modifier: String) -> int:
	var count := 0
	for tile: TileState in state.tiles.values():
		if tile.has_modifier(modifier):
			count += 1
	return count


func _count_tiles_with_modifier_duration(state: GameState, modifier: String, duration: int) -> int:
	var count := 0
	for tile: TileState in state.tiles.values():
		if tile.has_modifier(modifier) and int(tile.get_modifier(modifier).get("duration", -1)) == duration:
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


func _check_split_clone_expectations(
	state: GameState,
	tracked_units: Dictionary,
	expect: Dictionary,
	slotted_gems_before: Dictionary,
	label: String
) -> void:
	var origin_ref := str(expect.get("origin", "contract_target"))
	var origin: UnitState = tracked_units.get(origin_ref, null)
	_check(origin != null, label, "missing split origin %s" % origin_ref)
	if origin == null:
		return
	var clones: Array[UnitState] = []
	for unit in state.units.values():
		if (
			unit.alive
			and unit.split_origin_uid == origin.uid
			and unit.has_tag(Constants.TAG_UNIT_SPLIT_CLONE)
			and not unit.has_tag(Constants.TAG_UNIT_SPLIT_BLUE_TEMP_CLONE)
		):
			clones.append(unit)
	clones.sort_custom(func(a: UnitState, b: UnitState) -> bool: return a.uid < b.uid)
	_check(clones.size() == int(expect.get("count", 0)), label, "split clone count expected=%d actual=%d" % [int(expect.get("count", 0)), clones.size()])
	var total_slots := 0
	var total_gems := 0
	var disabled_split_slots := 0
	var expected_stats: Dictionary = expect.get("each_stats", {})
	for clone in clones:
		total_slots += clone.slots.size()
		for field_id in expected_stats.keys():
			_check(int(clone.get(str(field_id))) == int(expected_stats[field_id]), label, "clone %s %s expected=%d actual=%d" % [clone.uid, field_id, int(expected_stats[field_id]), int(clone.get(str(field_id)))])
		for slot in clone.slots:
			if slot == null or slot.gem_uid.is_empty():
				continue
			total_gems += 1
			_check(state.gems.has(slot.gem_uid), label, "clone %s missing inherited gem %s" % [clone.uid, slot.gem_uid])
			if slot.lock_type == Constants.LOCK_SPLIT_DISABLED:
				disabled_split_slots += 1
				var gem: GemState = state.gems.get(slot.gem_uid, null)
				_check(gem != null and gem.gem_id == Constants.GEM_SPLIT, label, "disabled clone slot should hold inherited split gem")
	if expect.has("total_slots"):
		_check(total_slots == int(expect["total_slots"]), label, "split total slots expected=%d actual=%d" % [int(expect["total_slots"]), total_slots])
	if expect.has("total_gems"):
		_check(total_gems == int(expect["total_gems"]), label, "split total gems expected=%d actual=%d" % [int(expect["total_gems"]), total_gems])
	if expect.has("disabled_split_slots"):
		_check(disabled_split_slots == int(expect["disabled_split_slots"]), label, "disabled split slots expected=%d actual=%d" % [int(expect["disabled_split_slots"]), disabled_split_slots])
	if expect.has("dropped_gems"):
		_check(state.dropped_gems.size() == int(expect["dropped_gems"]), label, "dropped gems expected=%d actual=%d" % [int(expect["dropped_gems"]), state.dropped_gems.size()])
	if bool(expect.get("source_slots_cleared", false)):
		for slot in origin.slots:
			_check(slot == null or slot.gem_uid.is_empty(), label, "split origin slot should be cleared after enemy death")
	if bool(expect.get("source_gems_removed", false)):
		for gem_uid in slotted_gems_before.get(origin.uid, []):
			_check(not state.gems.has(gem_uid), label, "split source gem should not remain after inheritance: %s" % gem_uid)


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
			Constants.STATUS_LIGHT_EXPOSED:
				StatusRules.apply_light_exposed(state, unit, int(raw_status.get("stacks", 1)), source.uid)


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
		"combat_apply_damage":
			var target: UnitState = tracked_units.get(str(raw_step.get("target", "")), null)
			var source: UnitState = tracked_units.get(str(raw_step.get("source", "")), null)
			_check(target != null, "post_step", "missing combat damage target %s" % str(raw_step.get("target", "")))
			_check(source != null, "post_step", "missing combat damage source %s" % str(raw_step.get("source", "")))
			if target == null or source == null:
				return
			CombatRules.apply_damage(
				state,
				target,
				int(raw_step.get("amount", 0)),
				source.uid,
				str(raw_step.get("reason", "attack"))
			)
		"run_blue_poison_turn_end":
			var owner: UnitState = tracked_units.get(str(raw_step.get("uid", "")), null)
			_check(owner != null, "post_step", "missing blue poison owner %s" % str(raw_step.get("uid", "")))
			if owner == null:
				return
			GemEffects.run_blue_poison_turn_end_spreads(state, owner.uid)
		"execute_attack":
			var source: UnitState = tracked_units.get(str(raw_step.get("source", "")), null)
			var target: UnitState = tracked_units.get(str(raw_step.get("target", "")), null)
			_check(source != null, "post_step", "missing attack source %s" % str(raw_step.get("source", "")))
			_check(target != null, "post_step", "missing attack target %s" % str(raw_step.get("target", "")))
			if source == null or target == null:
				return
			var repeat_result := AttackPipeline.execute_aimed(state, source, target.pos, [AttackPipeline.TAG_RANGED])
			var expected_ok := bool(raw_step.get("expect_ok", true))
			_check(bool(repeat_result.get("ok", false)) == expected_ok, "post_step", "repeat attack expected ok=%s" % expected_ok)
			events.append_array(repeat_result.get("events", []))


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
	_failure_count += 1
	push_error("CONTRACT_FAIL %s: %s" % [label, message])


func _load_contract() -> Dictionary:
	var file := FileAccess.open(CONTRACT_PATH, FileAccess.READ)
	assert(file != null, "contract file should exist")
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, "contract file should be valid JSON")
	return parsed
