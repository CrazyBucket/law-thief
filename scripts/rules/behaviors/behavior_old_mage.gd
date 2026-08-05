extends EnemyBehavior

## The Old Mage is deliberately not routed through the utility AI. Its pressure
## comes from an authored resource loop: consume one loaded gem, then spend the
## next turn reclaiming a marked pool gem. Runtime state is kept in battle flags
## because it is encounter-local and must never leak into a run save.

const _Displacement = preload("res://scripts/rules/displacement.gd")
const _FrozenStatusRules = preload("res://scripts/rules/frozen_status_rules.gd")

const POOL_IDS := [
	"gem_explosion", "gem_conductive", "gem_fire", "gem_ice",
	"gem_poison", "gem_light", "gem_impact",
]

static func _rng() -> Node:
	return Engine.get_main_loop().root.get_node("RngService")


static func compute_intent(state: GameState, unit: UnitState, cell_blockers: Dictionary = {}) -> IntentState:
	_sync_move_points(unit)
	_reconcile_loop_state(state, unit)
	if _is_final_phase(unit):
		_ensure_final_preview(state, unit)
	if _has_non_pool_loaded_gem(state, unit):
		return _decoy_intent(state, unit)
	if _is_final_phase(unit):
		return _final_intent(state, unit, cell_blockers)
	if str(state.battle_temp_flags.get(_key(unit, "phase"), "")) == "cast":
		return _cast_or_staff_intent(state, unit, cell_blockers)
	var empty_slot := _first_empty_nonblack_slot(unit)
	if empty_slot >= 0:
		return _refill_intent(state, unit, empty_slot, cell_blockers)
	return _cast_or_staff_intent(state, unit, cell_blockers)


static func on_turn_start(state: GameState, unit: UnitState) -> void:
	if unit.hp >= 20:
		_sync_move_points(unit)
		return
	state.battle_temp_flags[_key(unit, "phase")] = "final"
	# The final phase is intentionally short.  A fresh slot blackens on every
	# boss turn (until all three are black), rather than only when HP crosses 20.
	_blacken_next_slot(state, unit)
	_ensure_final_preview(state, unit)
	_sync_move_points(unit)


static func on_gem_inserted(state: GameState, unit: UnitState, gem_uid: String) -> void:
	EnemyBehavior.on_gem_inserted(state, unit, gem_uid)
	var slot_index := _slot_index_for_gem(unit, gem_uid)
	if slot_index < 0 or unit.slots[slot_index].slot_type == Constants.SLOT_BLACK:
		return
	state.battle_temp_flags.erase(_key(unit, "refill_gem_uid"))
	state.battle_temp_flags.erase(_key(unit, "refill_slot_index"))
	if _is_pool_gem(state.gems.get(gem_uid, null)):
		state.battle_temp_flags[_key(unit, "gem_loaded_turn:%s" % gem_uid)] = state.turn_index
		state.battle_temp_flags[_key(unit, "phase")] = "cast"
	else:
		state.battle_temp_flags[_key(unit, "phase")] = "decoy"


static func execute_custom_intent(
	state: GameState,
	unit: UnitState,
	intent: IntentState,
	_move_start_pos: Vector2i
) -> Dictionary:
	match intent.type:
		"mage_destroy_decoy":
			return {"handled": true, "events": _destroy_decoy(state, unit)}
		"mage_refill":
			return {"handled": true, "events": _execute_refill(state, unit, intent)}
		"mage_spell":
			return {"handled": true, "events": _execute_spell(state, unit, intent)}
		"mage_staff_attack":
			return {"handled": true, "events": _execute_staff(state, unit, intent)}
		"mage_impact_charge":
			return {"handled": true, "events": _execute_impact_charge(state, unit, intent)}
		"move":
			_clear_recent_attack_source(state, unit)
			_ensure_final_preview(state, unit)
			return {"handled": true, "events": []}
	return EnemyBehavior.execute_custom_intent(state, unit, intent, _move_start_pos)


static func _is_final_phase(unit: UnitState) -> bool:
	return unit.hp < 20


static func _sync_move_points(unit: UnitState) -> void:
	if _is_final_phase(unit):
		unit.move_points = 2
		return
	var empty := 0
	for slot in unit.slots:
		if slot.gem_uid.is_empty():
			empty += 1
	unit.move_points = 2 + int(ceil(float(empty) / 2.0))


static func _key(unit: UnitState, suffix: String) -> String:
	return "old_mage:%s:%s" % [unit.uid, suffix]


static func _is_pool_gem(gem: GemState) -> bool:
	return gem != null and gem.gem_id in POOL_IDS


static func accepts_decoy_insert(state: GameState, unit: UnitState, slot: SlotState, gem: GemState) -> bool:
	return unit != null \
		and unit.behavior_id == "old_mage" \
		and gem != null \
		and not _is_pool_gem(gem) \
		and slot != null \
		and slot.slot_type != Constants.SLOT_BLACK \
		and slot.gem_uid.is_empty() \
		and not _has_pool_loaded_gem(state, unit)


static func _first_empty_nonblack_slot(unit: UnitState) -> int:
	for index in range(unit.slots.size()):
		var slot: SlotState = unit.slots[index]
		if slot.slot_type != Constants.SLOT_BLACK and slot.gem_uid.is_empty():
			return index
	return -1


static func _has_non_pool_loaded_gem(state: GameState, unit: UnitState) -> bool:
	for slot in unit.slots:
		if slot.slot_type == Constants.SLOT_BLACK or slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem != null and not _is_pool_gem(gem):
			return true
	return false


static func _has_pool_loaded_gem(state: GameState, unit: UnitState) -> bool:
	for slot in unit.slots:
		if slot.slot_type == Constants.SLOT_BLACK or slot.gem_uid.is_empty():
			continue
		if _is_pool_gem(state.gems.get(slot.gem_uid, null)):
			return true
	return false


static func _has_untracked_pool_gem(state: GameState, unit: UnitState) -> bool:
	for slot in unit.slots:
		if slot.slot_type == Constants.SLOT_BLACK or slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if _is_pool_gem(gem) and not state.battle_temp_flags.has(_key(unit, "gem_loaded_turn:%s" % gem.uid)):
			return true
	return false


static func _mark_loaded_pool_gems(state: GameState, unit: UnitState) -> void:
	for slot in unit.slots:
		if slot.slot_type == Constants.SLOT_BLACK or slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if _is_pool_gem(gem):
			state.battle_temp_flags[_key(unit, "gem_loaded_turn:%s" % gem.uid)] = state.turn_index


static func _slot_index_for_gem(unit: UnitState, gem_uid: String) -> int:
	for index in range(unit.slots.size()):
		if unit.slots[index].gem_uid == gem_uid:
			return index
	return -1


static func _reconcile_loop_state(state: GameState, unit: UnitState) -> void:
	# The phase preserves the cast -> refill cadence. Slots only repair an
	# impossible phase, so external mutations cannot strand the Boss or erase it.
	if _has_non_pool_loaded_gem(state, unit):
		state.battle_temp_flags[_key(unit, "phase")] = "decoy"
		return
	if _is_final_phase(unit):
		return
	var phase := str(state.battle_temp_flags.get(_key(unit, "phase"), ""))
	var has_pool := _has_pool_loaded_gem(state, unit)
	var has_empty := _first_empty_nonblack_slot(unit) >= 0
	if phase == "cast" and has_pool:
		return
	if phase == "refill" and _has_untracked_pool_gem(state, unit):
		state.battle_temp_flags.erase(_key(unit, "refill_gem_uid"))
		state.battle_temp_flags.erase(_key(unit, "refill_slot_index"))
		state.battle_temp_flags[_key(unit, "phase")] = "cast"
		return
	if phase == "refill" and has_empty:
		return
	if has_pool:
		state.battle_temp_flags[_key(unit, "phase")] = "cast"
	elif has_empty:
		state.battle_temp_flags[_key(unit, "phase")] = "refill"


static func _decoy_intent(state: GameState, unit: UnitState) -> IntentState:
	var intent := IntentState.new()
	intent.source_uid = unit.uid
	intent.type = "mage_destroy_decoy"
	intent.preview_text = "摧毁异质宝石，本回合空过"
	intent.plan_metadata["mage_phase"] = "refill"
	return intent


static func _refill_intent(
	state: GameState,
	unit: UnitState,
	slot_index: int,
	cell_blockers: Dictionary
) -> IntentState:
	_prepare_refill_slot(state, unit, slot_index)
	var target := _locked_or_nearest_pool_target(state, unit, cell_blockers)
	if target.is_empty():
		if _has_pool_loaded_gem(state, unit):
			state.battle_temp_flags.erase(_key(unit, "refill_gem_uid"))
			state.battle_temp_flags.erase(_key(unit, "refill_slot_index"))
			state.battle_temp_flags[_key(unit, "phase")] = "cast"
			return _cast_or_staff_intent(state, unit, cell_blockers)
		return _staff_or_move_intent(state, unit, cell_blockers, "材料耗尽，逼近法杖射程")
	var gem_uid := str(target["gem_uid"])
	var pos: Vector2i = target["pos"]
	var path := BoardUtils.path_toward(
		state, unit.pos, pos, unit.move_points, unit.uid, {}, cell_blockers, unit
	)
	var intent := IntentState.new()
	intent.source_uid = unit.uid
	intent.type = "mage_refill"
	# A carried gem is not a valid ActionPlan "gem" target: it has no dropped
	# location. Keep its identity in metadata so the lock remains stable while
	# its carrier moves.
	if str(target.get("kind", "")) == "ground":
		intent.target_uid = gem_uid
	intent.target_pos = pos
	intent.path = path
	intent.affected_cells = [pos]
	intent.preview_text = "锁定池内宝石，补充%s槽" % _slot_label(unit.slots[slot_index].slot_type)
	intent.plan_metadata = {
		"mage_phase": "refill",
		"mage_slot_index": slot_index,
		"mage_gem_uid": gem_uid,
		"mage_target_pos": pos,
		"mage_target_kind": str(target.get("kind", "ground")),
		"mage_candidate_cells": _pool_candidate_cells(state, unit),
	}
	return intent


static func _prepare_refill_slot(state: GameState, unit: UnitState, slot_index: int) -> void:
	if _is_final_phase(unit) or slot_index < 0 or slot_index >= unit.slots.size():
		return
	var slot: SlotState = unit.slots[slot_index]
	if slot.slot_type == Constants.SLOT_BLACK:
		return
	var slot_key := _key(unit, "refill_slot_index")
	if int(state.battle_temp_flags.get(slot_key, -1)) == slot_index:
		return
	# The color is chosen when refill is telegraphed and stays visible through
	# pickup and the following cast. Blue is only offered when its spell is
	# currently executable; otherwise this refill is red.
	var color := Constants.SLOT_RED
	var player := state.get_player()
	var target := _locked_or_nearest_pool_target(state, unit, {})
	var gem: GemState = state.gems.get(str(target.get("gem_uid", "")), null)
	if player != null and gem != null and _blue_is_executable(state, unit, player, gem):
		if int(_rng().roll_int("old_mage_refill_color_%s_%d" % [unit.uid, state.turn_index], 1, 3)) == 3:
			color = Constants.SLOT_BLUE
	slot.slot_type = color
	state.battle_temp_flags[slot_key] = slot_index


static func _locked_or_nearest_pool_target(
	state: GameState,
	unit: UnitState,
	cell_blockers: Dictionary
) -> Dictionary:
	var lock_key := _key(unit, "refill_gem_uid")
	var locked_uid := str(state.battle_temp_flags.get(lock_key, ""))
	if not locked_uid.is_empty():
		var locked := _pool_target_for_gem(state, locked_uid)
		if not locked.is_empty() and str(locked.get("carrier_uid", "")) != unit.uid:
			return locked
		state.battle_temp_flags.erase(lock_key)
	var best: Dictionary = {}
	var best_distance := 99999
	for gem_uid in state.gems.keys():
		var candidate := _pool_target_for_gem(state, str(gem_uid))
		if candidate.is_empty():
			continue
		if str(candidate.get("carrier_uid", "")) == unit.uid:
			continue
		var distance := BoardUtils.path_distance_to_cell(
			state, unit.pos, candidate["pos"], unit.uid, cell_blockers, unit
		)
		if distance < 0 or distance > best_distance:
			continue
		if distance == best_distance and not best.is_empty() and not _target_precedes(candidate, best):
			continue
		best_distance = distance
		best = candidate
	if not best.is_empty():
		state.battle_temp_flags[lock_key] = str(best["gem_uid"])
	return best


static func _target_precedes(candidate: Dictionary, current: Dictionary) -> bool:
	var candidate_rank := _target_kind_rank(str(candidate.get("kind", "")))
	var current_rank := _target_kind_rank(str(current.get("kind", "")))
	if candidate_rank != current_rank:
		return candidate_rank < current_rank
	var candidate_pos: Vector2i = candidate.get("pos", Vector2i.ZERO)
	var current_pos: Vector2i = current.get("pos", Vector2i.ZERO)
	if candidate_pos.y != current_pos.y:
		return candidate_pos.y < current_pos.y
	if candidate_pos.x != current_pos.x:
		return candidate_pos.x < current_pos.x
	return str(candidate.get("gem_uid", "")) < str(current.get("gem_uid", ""))


static func _target_kind_rank(kind: String) -> int:
	# Ground gems are easier to take than a carrier; enemy-held gems are the
	# next intended contest, and player-held gems are the final tie-breaker.
	if kind == "ground":
		return 0
	if kind == "enemy_unit":
		return 1
	return 2


static func _pool_target_for_gem(state: GameState, gem_uid: String) -> Dictionary:
	var gem: GemState = state.gems.get(gem_uid, null)
	if not _is_pool_gem(gem):
		return {}
	var drop: Variant = state.dropped_gems.get(gem_uid, null)
	if drop is Dictionary:
		return {"gem_uid": gem_uid, "pos": (drop as Dictionary).get("pos", Vector2i.ZERO), "kind": "ground", "carrier_uid": ""}
	if state.held_gem_uid == gem_uid:
		var player := state.get_player()
		if player != null and player.alive:
			return {"gem_uid": gem_uid, "pos": player.pos, "kind": "player_hand", "carrier_uid": player.uid}
	for carrier: UnitState in state.units.values():
		if not carrier.alive:
			continue
		for slot in carrier.slots:
			if slot.gem_uid == gem_uid:
				var kind := "enemy_unit" if carrier.team == Constants.TEAM_ENEMY else "player_slot"
				return {"gem_uid": gem_uid, "pos": carrier.pos, "kind": kind, "carrier_uid": carrier.uid}
	return {}


static func _pool_candidate_cells(state: GameState, unit: UnitState) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for gem_uid in state.gems.keys():
		var target := _pool_target_for_gem(state, str(gem_uid))
		if target.is_empty() or str(target.get("carrier_uid", "")) == unit.uid:
			continue
		var cell: Vector2i = target.get("pos", Vector2i(-1, -1))
		if cell not in cells:
			cells.append(cell)
	return cells


static func _cast_or_staff_intent(state: GameState, unit: UnitState, cell_blockers: Dictionary) -> IntentState:
	var player := state.get_player()
	if player == null or not player.alive:
		return IntentState.wait(unit.uid)
	var chosen := _locked_or_choose_spell(state, unit, player, cell_blockers)
	if chosen.is_empty():
		return _staff_or_move_intent(state, unit, cell_blockers, "法杖攻击 (7)")
	return _spell_intent(state, unit, player, chosen)


static func _locked_or_choose_spell(
	state: GameState,
	unit: UnitState,
	player: UnitState,
	cell_blockers: Dictionary
) -> Dictionary:
	var locked_uid := str(state.battle_temp_flags.get(_key(unit, "cast_gem_uid"), ""))
	var locked_slot := int(state.battle_temp_flags.get(_key(unit, "cast_slot_index"), -1))
	if locked_slot >= 0 and locked_slot < unit.slots.size():
		var slot: SlotState = unit.slots[locked_slot]
		if slot.slot_type != Constants.SLOT_BLACK and slot.gem_uid == locked_uid and _is_pool_gem(state.gems.get(locked_uid, null)):
			return {"slot_index": locked_slot, "gem_uid": locked_uid}
	state.battle_temp_flags.erase(_key(unit, "cast_gem_uid"))
	state.battle_temp_flags.erase(_key(unit, "cast_slot_index"))
	var candidates: Array[Dictionary] = []
	for index in range(unit.slots.size()):
		var slot: SlotState = unit.slots[index]
		if slot.slot_type == Constants.SLOT_BLACK or slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if not _is_pool_gem(gem):
			continue
		var entry := {"slot_index": index, "gem_uid": gem.uid}
		if slot.slot_type == Constants.SLOT_RED:
			candidates.append(entry)
		elif slot.slot_type == Constants.SLOT_BLUE and _blue_is_executable(state, unit, player, gem, cell_blockers):
			candidates.append(entry)
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_pressure := _spell_pressure(state, unit, player, a)
		var b_pressure := _spell_pressure(state, unit, player, b)
		if a_pressure == b_pressure:
			var a_loaded := int(state.battle_temp_flags.get(_key(unit, "gem_loaded_turn:%s" % str(a["gem_uid"])), 0))
			var b_loaded := int(state.battle_temp_flags.get(_key(unit, "gem_loaded_turn:%s" % str(b["gem_uid"])), 0))
			if a_loaded != b_loaded:
				return a_loaded < b_loaded
			return int(a["slot_index"]) < int(b["slot_index"])
		return a_pressure > b_pressure
	)
	var selected: Dictionary = candidates[0]
	state.battle_temp_flags[_key(unit, "cast_gem_uid")] = str(selected["gem_uid"])
	state.battle_temp_flags[_key(unit, "cast_slot_index")] = int(selected["slot_index"])
	state.battle_temp_flags[_key(unit, "cast_target_pos")] = player.pos
	return selected


static func _spell_pressure(state: GameState, unit: UnitState, player: UnitState, entry: Dictionary) -> int:
	var slot_index := int(entry.get("slot_index", -1))
	if slot_index < 0 or slot_index >= unit.slots.size():
		return -999
	var slot: SlotState = unit.slots[slot_index]
	var gem: GemState = state.gems.get(str(entry.get("gem_uid", "")), null)
	var pressure := _spell_preview_damage(state, player, gem, slot.slot_type, player.pos)
	if gem == null:
		return pressure
	match gem.gem_id:
		"gem_fire", "gem_poison": pressure += 2
		"gem_ice": pressure += 3 if player.has_status(Constants.STATUS_WET) or player.has_status(Constants.STATUS_SLOWED) else 1
		"gem_light": pressure += 1
	return pressure


static func _blue_is_executable(
	state: GameState,
	unit: UnitState,
	player: UnitState,
	gem: GemState,
	cell_blockers: Dictionary = {}
) -> bool:
	var endpoint := _spell_move_endpoint(state, unit, player, cell_blockers)
	match gem.gem_id:
		"gem_explosion":
			return BoardUtils.manhattan(endpoint, player.pos) <= 1
		"gem_conductive":
			return _last_active_player_attacker(state, unit) != null
		"gem_fire", "gem_ice", "gem_poison":
			return _nearest_adjacent_player(state, endpoint) != null
		"gem_light":
			var ranged_source := _last_active_ranged_player_attacker(state, unit)
			return ranged_source != null and _has_second_light_path(state, endpoint, ranged_source)
		"gem_impact":
			var source := _last_active_player_attacker(state, unit)
			return source != null and _has_retreat_cell(state, unit, endpoint, source.pos)
	return true


static func _spell_intent(state: GameState, unit: UnitState, player: UnitState, chosen: Dictionary) -> IntentState:
	var slot_index := int(chosen["slot_index"])
	var gem_uid := str(chosen["gem_uid"])
	var gem: GemState = state.gems.get(gem_uid, null)
	var locked_target: Vector2i = state.battle_temp_flags.get(_key(unit, "cast_target_pos"), player.pos)
	var slot: SlotState = unit.slots[slot_index]
	var move_path := _spell_move_path(state, unit, player)
	var endpoint: Vector2i = move_path.back() if not move_path.is_empty() else unit.pos
	var cells := _spell_cells(state, unit, gem, slot.slot_type, locked_target, endpoint)
	var reactive_source := _last_active_player_attacker(state, unit)
	if slot.slot_type == Constants.SLOT_BLUE and gem != null and gem.gem_id == "gem_light":
		reactive_source = _last_active_ranged_player_attacker(state, unit)
	if slot.slot_type == Constants.SLOT_BLUE and gem != null and gem.gem_id == "gem_explosion":
		cells = _in_bounds_cells(state, BoardUtils.cells_in_radius(endpoint, 1))
	if slot.slot_type == Constants.SLOT_BLUE and gem != null and gem.gem_id == "gem_conductive":
		cells = _conductive_reactive_cells(state, reactive_source)
	if slot.slot_type == Constants.SLOT_BLUE and gem != null and gem.gem_id == "gem_light":
		cells = _blue_light_cells(state, endpoint, _last_active_ranged_player_attacker(state, unit))
	if slot.slot_type == Constants.SLOT_BLUE and gem != null and gem.gem_id == "gem_impact" and reactive_source != null:
		cells = _retreat_preview_path(state, endpoint, reactive_source.pos, unit)
	var intent := IntentState.new()
	intent.source_uid = unit.uid
	intent.target_uid = player.uid
	intent.target_pos = locked_target
	intent.path = move_path
	intent.affected_cells = cells
	intent.damage = _spell_preview_damage(state, player, gem, slot.slot_type, locked_target)
	intent.type = "mage_impact_charge" if gem.gem_id == "gem_impact" and slot.slot_type == Constants.SLOT_RED else "mage_spell"
	intent.preview_text = "%s%s·%s：%s；施法后销毁" % [
		_slot_label(slot.slot_type), _gem_name(gem), _spell_name(gem, slot.slot_type), _spell_preview_detail(gem, slot.slot_type)
	]
	intent.plan_metadata = {
		"mage_phase": "cast",
		"mage_slot_index": slot_index,
		"mage_gem_uid": gem_uid,
		"mage_gem_id": gem.gem_id,
		"mage_slot_type": slot.slot_type,
		"mage_target_pos": locked_target,
		"mage_reactive_source_uid": reactive_source.uid if reactive_source != null else "",
	}
	if intent.type == "mage_impact_charge":
		var direction := _charge_direction(state, unit, locked_target.y)
		intent.plan_metadata["mage_charge_direction"] = direction
		intent.plan_metadata["mage_charge_path"] = _charge_path(state, locked_target.y, direction)
	elif slot.slot_type == Constants.SLOT_BLUE and gem.gem_id == "gem_impact":
		intent.plan_metadata["mage_retreat_path"] = cells
	if slot.slot_type == Constants.SLOT_RED and gem.gem_id == "gem_conductive":
		intent.plan_metadata["mage_wet_cells"] = _wet_unit_cells(state, unit)
	return intent


static func _last_active_player_attacker(state: GameState, unit: UnitState) -> UnitState:
	var uid := str(state.battle_temp_flags.get("last_active_attacker:%s" % unit.uid, ""))
	var source: UnitState = state.units.get(uid, null)
	if source == null or not source.alive or source.team != Constants.TEAM_PLAYER:
		return null
	return source


static func _last_active_ranged_player_attacker(state: GameState, unit: UnitState) -> UnitState:
	if not bool(state.battle_temp_flags.get("last_active_attack_ranged:%s" % unit.uid, false)):
		return null
	return _last_active_player_attacker(state, unit)


static func _conductive_reactive_cells(state: GameState, source: UnitState) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if source == null:
		return cells
	cells.append(source.pos)
	var bounce: UnitState = null
	for candidate: UnitState in state.units.values():
		if not candidate.alive or candidate.uid == source.uid or candidate.team != Constants.TEAM_PLAYER:
			continue
		if BoardUtils.manhattan(source.pos, candidate.pos) > 2:
			continue
		if bounce == null or BoardUtils.manhattan(source.pos, candidate.pos) < BoardUtils.manhattan(source.pos, bounce.pos):
			bounce = candidate
	if bounce != null:
		cells.append(bounce.pos)
	return cells


static func _nearest_adjacent_player(state: GameState, pos: Vector2i) -> UnitState:
	var selected: UnitState = null
	for candidate: UnitState in state.units.values():
		if not candidate.alive or candidate.team != Constants.TEAM_PLAYER or BoardUtils.manhattan(pos, candidate.pos) != 1:
			continue
		if selected == null or candidate.uid < selected.uid:
			selected = candidate
	return selected


static func _blue_light_cells(state: GameState, origin: Vector2i, source: UnitState) -> Array[Vector2i]:
	if source == null:
		return []
	var cells: Array[Vector2i] = _light_path_to_target(state, origin, source.pos)
	for direction in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
		var candidate_path := _light_path_from(state, origin, direction)
		var has_other_target := false
		for cell in candidate_path:
			var victim := state.get_unit_at(cell)
			if victim != null and victim.alive and victim.team == Constants.TEAM_PLAYER and victim.uid != source.uid:
				has_other_target = true
				break
		if has_other_target:
			for cell in candidate_path:
				if cell not in cells:
					cells.append(cell)
			break
	return cells


static func _spell_move_path(state: GameState, unit: UnitState, player: UnitState, cell_blockers: Dictionary = {}) -> Array[Vector2i]:
	return BoardUtils.path_toward(state, unit.pos, player.pos, unit.move_points, unit.uid, {}, cell_blockers, unit)


static func _spell_move_endpoint(state: GameState, unit: UnitState, player: UnitState, cell_blockers: Dictionary = {}) -> Vector2i:
	var path := _spell_move_path(state, unit, player, cell_blockers)
	return path.back() if not path.is_empty() else unit.pos


static func _spell_cells(
	state: GameState,
	unit: UnitState,
	gem: GemState,
	slot_type: String,
	target: Vector2i,
	spell_origin: Vector2i = Vector2i(-1, -1)
) -> Array[Vector2i]:
	if gem == null:
		return []
	var origin := unit.pos if spell_origin.x < 0 else spell_origin
	if gem.gem_id == "gem_conductive":
		return _all_cells(state)
	if gem.gem_id == "gem_light":
		return _mage_light_line(state, origin, target)
	if gem.gem_id == "gem_impact" and slot_type == Constants.SLOT_RED:
		var row: Array[Vector2i] = []
		for x in range(state.board_size.x): row.append(Vector2i(x, target.y))
		return row
	if gem.gem_id == "gem_ice" and slot_type == Constants.SLOT_RED:
		return _frost_tide_cells(state, origin, target)
	return _in_bounds_cells(state, BoardUtils.cells_in_radius(target, 1))


static func _mage_light_line(state: GameState, origin: Vector2i, target: Vector2i) -> Array[Vector2i]:
	var horizontal := absi(origin.x - target.x) >= absi(origin.y - target.y)
	var step := Vector2i.RIGHT if horizontal else Vector2i.DOWN
	var cells: Array[Vector2i] = [target]
	for direction in [step, -step]:
		var current: Vector2i = target + direction
		while BoardUtils.in_bounds(state, current):
			cells.append(current)
			var entity := state.get_entity_at(current)
			if entity != null and entity.alive and entity.blocks_projectile():
				break
			current += direction
	return cells


static func _frost_tide_cells(state: GameState, origin: Vector2i, target: Vector2i) -> Array[Vector2i]:
	var delta := target - origin
	var forward := Vector2i.RIGHT if absi(delta.x) >= absi(delta.y) and delta.x >= 0 else Vector2i.LEFT
	if absi(delta.y) > absi(delta.x):
		forward = Vector2i.DOWN if delta.y >= 0 else Vector2i.UP
	var side := Vector2i.UP if forward.x != 0 else Vector2i.LEFT
	var cells: Array[Vector2i] = []
	for depth in range(1, 5):
		var center := origin + forward * depth
		for offset in [-1, 0, 1]:
			var cell: Vector2i = center + side * offset
			if BoardUtils.in_bounds(state, cell) and cell not in cells:
				cells.append(cell)
	# The fan is locked toward the chosen target, not merely toward a cardinal
	# approximation of it.  Keep that lock cell in the telegraph on diagonal
	# approaches as well, so the advertised target cannot fall between lanes.
	if BoardUtils.in_bounds(state, target) and target not in cells:
		cells.append(target)
	return cells


static func _spell_preview_damage(state: GameState, player: UnitState, gem: GemState, slot_type: String, target: Vector2i) -> int:
	if gem == null:
		return 0
	if slot_type == Constants.SLOT_BLUE:
		match gem.gem_id:
			"gem_explosion", "gem_conductive": return 8
			"gem_light": return 5
			_: return 0
	match gem.gem_id:
		"gem_explosion": return 12 if player.pos == target else 8
		"gem_conductive": return 10 if player.has_status(Constants.STATUS_WET) else 6
		"gem_fire": return 4
		"gem_ice": return 4
		"gem_poison": return 2
		"gem_light": return 9
		"gem_impact": return 8
	return 0


static func _execute_refill(state: GameState, unit: UnitState, intent: IntentState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var slot_index := int(intent.plan_metadata.get("mage_slot_index", -1))
	if slot_index < 0 or slot_index >= unit.slots.size():
		return events
	var slot: SlotState = unit.slots[slot_index]
	if slot.slot_type == Constants.SLOT_BLACK or not slot.gem_uid.is_empty():
		return events
	var target := _pool_target_for_gem(state, str(intent.plan_metadata.get("mage_gem_uid", "")))
	if target.is_empty() or not _can_claim_target(unit, target):
		return events
	var gem: GemState = state.gems.get(str(target["gem_uid"]), null)
	if gem == null:
		return events
	var tx := _CombatTransaction.begin(state, events)
	if tx.transfer_gem(gem, GemLocation.unit_slot(unit.uid, slot_index), {"reason": "old_mage_refill"}):
		state.battle_temp_flags[_key(unit, "gem_loaded_turn:%s" % gem.uid)] = state.turn_index
		state.battle_temp_flags.erase(_key(unit, "refill_gem_uid"))
		state.battle_temp_flags.erase(_key(unit, "refill_slot_index"))
		state.battle_temp_flags[_key(unit, "phase")] = "cast"
	_clear_recent_attack_source(state, unit)
	_ensure_final_preview(state, unit)
	return tx.finish("OldMage.refill")


static func _can_claim_target(unit: UnitState, target: Dictionary) -> bool:
	var target_pos: Vector2i = target.get("pos", Vector2i(-1, -1))
	if str(target.get("kind", "")) == "ground":
		return unit.pos == target_pos
	return BoardUtils.manhattan(unit.pos, target_pos) == 1


static func _execute_spell(state: GameState, unit: UnitState, intent: IntentState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var player := state.get_player()
	var gem_id := str(intent.plan_metadata.get("mage_gem_id", ""))
	var slot_type := str(intent.plan_metadata.get("mage_slot_type", ""))
	var target: Vector2i = intent.plan_metadata.get("mage_target_pos", intent.target_pos)
	var cells: Array[Vector2i] = intent.affected_cells
	var tx := _CombatTransaction.begin(state, events).bind_event_sink()
	var is_blue := slot_type == Constants.SLOT_BLUE
	if is_blue and gem_id == "gem_conductive":
		var source: UnitState = state.units.get(str(intent.plan_metadata.get("mage_reactive_source_uid", "")), null)
		if source != null and source.alive:
			events.append(_EventBuilder.lightning(unit.pos, source.pos, {"source_uid": unit.uid, "target_uid": source.uid}))
			tx.damage_unit(source, 8, unit.uid, "old_mage_blue_conductive")
			for candidate: UnitState in state.units.values():
				if not candidate.alive or candidate.uid == source.uid or candidate.team != Constants.TEAM_PLAYER:
					continue
				if candidate.pos in cells:
					events.append(_EventBuilder.arc(source.pos, candidate.pos, {"source_uid": unit.uid, "target_uid": candidate.uid}))
					tx.damage_unit(candidate, 4, unit.uid, "old_mage_blue_conductive_bounce")
	if gem_id == "gem_explosion":
		var explosion_center := unit.pos if is_blue else target
		events.append(_EventBuilder.explode(explosion_center, 1, {"source_uid": unit.uid, "cells": cells}))
	if gem_id == "gem_conductive":
		events.append(_EventBuilder.lightning(unit.pos, target, {"source_uid": unit.uid, "cells": cells}))
	if not (is_blue and gem_id == "gem_conductive"):
		for victim: UnitState in state.units.values():
			if not victim.alive or victim.uid == unit.uid or not victim.pos in cells:
				continue
			var amount := _spell_preview_damage(state, victim, state.gems.get(str(intent.plan_metadata.get("mage_gem_uid", "")), null), slot_type, target)
			if amount > 0:
				tx.damage_unit(victim, amount, unit.uid, "old_mage_%s" % gem_id, {} if is_blue else {"active_attack": true})
	var blue_target := _nearest_adjacent_player(state, unit.pos)
	if slot_type == Constants.SLOT_BLUE:
		match gem_id:
			"gem_fire":
				if blue_target != null:
					StatusRules.apply_burning(state, blue_target, 2, unit.uid)
					TileRules.create_fire(state, blue_target.pos, 2)
			"gem_ice":
				if blue_target != null:
					if blue_target.has_status(Constants.STATUS_SLOWED) or blue_target.has_status(Constants.STATUS_WET):
						_FrozenStatusRules.apply(state, blue_target, 1, unit.uid)
					else:
						StatusRules.apply_slowed(state, blue_target, 2, unit.uid, 0)
			"gem_poison":
				if blue_target != null:
					StatusRules.apply_poison(state, blue_target, 2, 2, unit.uid)
					_copy_longest_debuff(state, unit, blue_target)
			"gem_light":
				for victim: UnitState in state.units.values():
					if victim.alive and victim.team == Constants.TEAM_PLAYER and victim.pos in cells:
						StatusRules.apply_light_exposed(state, victim, 1, unit.uid)
			"gem_impact":
				var source: UnitState = state.units.get(str(intent.plan_metadata.get("mage_reactive_source_uid", "")), null)
				if source != null and source.alive:
					_displace_mage_away(state, unit, source, events)
	elif player != null and player.alive:
		match gem_id:
			"gem_fire":
				TileRules.begin_overlay_batch(state)
				for cell in cells: TileRules.create_fire(state, cell, 2)
				TileRules.end_overlay_batch(state)
			"gem_ice":
				if player.pos in cells:
					if player.has_status(Constants.STATUS_SLOWED) or player.has_status(Constants.STATUS_WET): _FrozenStatusRules.apply(state, player, 1, unit.uid)
					else: StatusRules.apply_slowed(state, player, 2, unit.uid, 0)
			"gem_poison":
				if player.pos in cells: StatusRules.apply_poison(state, player, 2, 2, unit.uid)
				TileRules.begin_overlay_batch(state)
				for cell in cells: TileRules.create_poison_fog(state, cell, 2)
				TileRules.end_overlay_batch(state)
			"gem_light":
				if player.pos in cells: StatusRules.apply_light_exposed(state, player, 1, unit.uid)
	_destroy_cast_gem(state, unit, intent)
	_clear_recent_attack_source(state, unit)
	_ensure_final_preview(state, unit)
	return tx.finish("OldMage.spell")


static func _copy_longest_debuff(state: GameState, source: UnitState, target: UnitState) -> void:
	var selected: StatusInstance = null
	for status: StatusInstance in source.statuses:
		if StatusRegistry.status_type(status.status_id) != StatusRegistry.TYPE_DEBUFF:
			continue
		if selected == null or status.duration > selected.duration:
			selected = status
	if selected == null:
		return
	var copy := StatusInstance.create(
		selected.status_id,
		selected.stacks,
		selected.duration,
		source.uid,
		selected.payload.duplicate(true)
	)
	copy.value = selected.value
	_CombatTransaction.begin_from_state(state).apply_status(target, copy, {"emit_event": false, "reason": "old_mage_blue_poison"})


static func _execute_impact_charge(state: GameState, unit: UnitState, intent: IntentState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var player := state.get_player()
	var direction: Vector2i = intent.plan_metadata.get("mage_charge_direction", Vector2i.RIGHT)
	var charge_path: Array = intent.plan_metadata.get("mage_charge_path", [])
	var final_cell: Vector2i = charge_path.back() if not charge_path.is_empty() else unit.pos
	events.append(_EventBuilder.impact_charge(unit.uid, unit.pos, final_cell, intent.target_pos, {
		"source_uid": unit.uid, "target_uid": player.uid if player != null else "", "steps": charge_path.size(),
	}))
	var tx := _CombatTransaction.begin(state, events).bind_event_sink()
	if player != null and player.alive and player.pos.y == intent.target_pos.y:
		tx.damage_unit(player, 8, unit.uid, "old_mage_impact", {"active_attack": true})
		var push_direction := _Displacement.Direction.EAST if direction.x > 0 else _Displacement.Direction.WEST
		_Displacement.push_cardinal(state, player, push_direction, state.board_size.x, unit.uid, events, 0)
	if final_cell != unit.pos and state.get_unit_at(final_cell) == null:
		tx.move_unit(unit, final_cell, {"forced": true, "reason": "old_mage_impact_charge"})
	_destroy_cast_gem(state, unit, intent)
	_clear_recent_attack_source(state, unit)
	_ensure_final_preview(state, unit)
	return tx.finish("OldMage.impact")


static func _execute_staff(state: GameState, unit: UnitState, intent: IntentState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var player := state.get_player()
	if player != null and player.alive and BoardUtils.are_units_adjacent(unit, player):
		_CombatTransaction.begin(state, events).damage_unit(player, 7, unit.uid, "old_mage_staff", {"active_attack": true})
	_clear_recent_attack_source(state, unit)
	_ensure_final_preview(state, unit)
	return events


static func _destroy_decoy(state: GameState, unit: UnitState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for slot in unit.slots:
		if slot.slot_type == Constants.SLOT_BLACK or slot.gem_uid.is_empty():
			continue
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem != null and not _is_pool_gem(gem):
			_GemTransfer.remove(state, gem.uid)
			state.log("老法师摧毁了异质宝石，空过本回合")
			break
	_mark_loaded_pool_gems(state, unit)
	state.battle_temp_flags[_key(unit, "phase")] = "refill"
	_clear_recent_attack_source(state, unit)
	_ensure_final_preview(state, unit)
	return events


static func _destroy_cast_gem(state: GameState, unit: UnitState, intent: IntentState) -> void:
	var slot_index := int(intent.plan_metadata.get("mage_slot_index", -1))
	if slot_index < 0 or slot_index >= unit.slots.size():
		return
	var slot: SlotState = unit.slots[slot_index]
	var gem_uid := str(intent.plan_metadata.get("mage_gem_uid", ""))
	if slot.gem_uid == gem_uid:
		_GemTransfer.remove(state, gem_uid)
	state.battle_temp_flags.erase(_key(unit, "gem_loaded_turn:%s" % gem_uid))
	_mark_loaded_pool_gems(state, unit)
	state.battle_temp_flags.erase(_key(unit, "cast_gem_uid"))
	state.battle_temp_flags.erase(_key(unit, "cast_slot_index"))
	state.battle_temp_flags.erase(_key(unit, "cast_target_pos"))
	state.battle_temp_flags.erase(_key(unit, "refill_slot_index"))
	state.battle_temp_flags[_key(unit, "phase")] = "refill"
	_sync_move_points(unit)


static func _staff_or_move_intent(state: GameState, unit: UnitState, cell_blockers: Dictionary, label: String) -> IntentState:
	var player := state.get_player()
	if player == null:
		return IntentState.wait(unit.uid)
	var path := BoardUtils.path_toward(state, unit.pos, player.pos, unit.move_points, unit.uid, {}, cell_blockers, unit)
	var endpoint: Vector2i = path.back() if not path.is_empty() else unit.pos
	var intent := IntentState.new()
	intent.source_uid = unit.uid
	intent.target_uid = player.uid
	intent.target_pos = endpoint
	intent.path = path
	if BoardUtils.are_units_adjacent_at(unit, endpoint, player):
		intent.type = "mage_staff_attack"
		intent.damage = 7
		intent.affected_cells = [player.pos]
		intent.preview_text = label
	else:
		intent.type = "move"
		intent.preview_text = "逼近玩家"
	return intent


static func _final_intent(state: GameState, unit: UnitState, cell_blockers: Dictionary) -> IntentState:
	return _cast_or_staff_intent(state, unit, cell_blockers)


static func _blacken_next_slot(state: GameState, unit: UnitState) -> void:
	var preview_index := int(state.battle_temp_flags.get(_key(unit, "next_black_slot"), -1))
	if preview_index >= 0 and preview_index < unit.slots.size() and unit.slots[preview_index].slot_type != Constants.SLOT_BLACK:
		_blacken_slot(state, unit, preview_index)
		return
	for prefer_loaded in [true, false]:
		for index in range(unit.slots.size()):
			var slot: SlotState = unit.slots[index]
			if slot.slot_type == Constants.SLOT_BLACK or (prefer_loaded and slot.gem_uid.is_empty()):
				continue
			_blacken_slot(state, unit, index)
			return


static func _blacken_slot(state: GameState, unit: UnitState, index: int) -> void:
	var slot: SlotState = unit.slots[index]
	slot.slot_type = Constants.SLOT_BLACK
	slot.dual_type = ""
	state.battle_temp_flags[_key(unit, "blackened_slot")] = index
	state.battle_temp_flags.erase(_key(unit, "next_black_slot"))
	state.log("老法师的槽位黑化")


static func _ensure_final_preview(state: GameState, unit: UnitState) -> void:
	if not _is_final_phase(unit):
		return
	var key := _key(unit, "next_black_slot")
	var locked_index := int(state.battle_temp_flags.get(key, -1))
	if locked_index >= 0 and locked_index < unit.slots.size() and unit.slots[locked_index].slot_type != Constants.SLOT_BLACK:
		return
	for prefer_loaded in [true, false]:
		for index in range(unit.slots.size()):
			var slot: SlotState = unit.slots[index]
			if slot.slot_type != Constants.SLOT_BLACK and (not prefer_loaded or not slot.gem_uid.is_empty()):
				state.battle_temp_flags[key] = index
				return


static func _displace_mage_away(state: GameState, unit: UnitState, player: UnitState, events: Array[Dictionary]) -> void:
	var dx := signi(unit.pos.x - player.pos.x)
	var dy := signi(unit.pos.y - player.pos.y)
	var target := unit.pos + Vector2i(dx, dy) * 3
	_Displacement.dash_toward(state, unit, target, 3, unit.uid, events, 0)


static func _has_retreat_cell(state: GameState, unit: UnitState, origin: Vector2i, source_pos: Vector2i) -> bool:
	return not _retreat_preview_path(state, origin, source_pos, unit).is_empty()


static func _retreat_preview_path(state: GameState, origin: Vector2i, source_pos: Vector2i, unit: UnitState) -> Array[Vector2i]:
	var delta := origin - source_pos
	if delta == Vector2i.ZERO:
		return []
	var direction := Vector2i(signi(delta.x), 0) if absi(delta.x) >= absi(delta.y) else Vector2i(0, signi(delta.y))
	var path: Array[Vector2i] = []
	var current := origin
	for _step in range(3):
		var next: Vector2i = current + direction
		if not BoardUtils.is_passable(state, next, unit.uid):
			break
		path.append(next)
		current = next
	return path


static func _has_second_light_path(state: GameState, origin: Vector2i, source: UnitState) -> bool:
	if source == null:
		return false
	var primary := _light_path_to_target(state, origin, source.pos)
	if primary.is_empty():
		return false
	# The reflected beam must have a distinct legal direction and at least one
	# player-side victim.  Current encounters are solo, but this stays correct
	# for future allied units without double-hitting the source.
	for direction in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
		var next: Vector2i = origin + direction
		if next == source.pos or not BoardUtils.in_bounds(state, next):
			continue
		var path := _light_path_from(state, origin, direction)
		for cell in path:
			var victim := state.get_unit_at(cell)
			if victim != null and victim.alive and victim.team == Constants.TEAM_PLAYER and victim.uid != source.uid:
				return true
	return false


static func _light_path_to_target(state: GameState, origin: Vector2i, target: Vector2i) -> Array[Vector2i]:
	if origin.x != target.x and origin.y != target.y:
		return []
	var direction := Vector2i(signi(target.x - origin.x), signi(target.y - origin.y))
	return _light_path_from(state, origin, direction)


static func _light_path_from(state: GameState, origin: Vector2i, direction: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var current: Vector2i = origin + direction
	while BoardUtils.in_bounds(state, current):
		cells.append(current)
		var entity := state.get_entity_at(current)
		if entity != null and entity.alive and entity.blocks_projectile():
			break
		current += direction
	return cells


static func _wet_unit_cells(state: GameState, source: UnitState) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for candidate: UnitState in state.units.values():
		if candidate.alive and candidate.uid != source.uid and candidate.has_status(Constants.STATUS_WET):
			cells.append(candidate.pos)
	return cells


static func _clear_recent_attack_source(state: GameState, unit: UnitState) -> void:
	state.battle_temp_flags.erase("last_active_attacker:%s" % unit.uid)
	state.battle_temp_flags.erase("last_active_attack_turn:%s" % unit.uid)
	state.battle_temp_flags.erase("last_active_attack_ranged:%s" % unit.uid)


static func _charge_path(state: GameState, row: int, direction: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var start := 0 if direction.x > 0 else state.board_size.x - 1
	var stop := state.board_size.x if direction.x > 0 else -1
	for x in range(start, stop, direction.x):
		var cell := Vector2i(x, row)
		var entity := state.get_entity_at(cell)
		if entity != null and entity.alive and entity.blocks_projectile():
			break
		path.append(cell)
	return path


static func _charge_direction(state: GameState, unit: UnitState, row: int) -> Vector2i:
	var left_distance := BoardUtils.path_distance_to_cell(state, unit.pos, Vector2i(0, row), unit.uid, {}, unit)
	var right_distance := BoardUtils.path_distance_to_cell(state, unit.pos, Vector2i(state.board_size.x - 1, row), unit.uid, {}, unit)
	if right_distance >= 0 and (left_distance < 0 or right_distance < left_distance):
		return Vector2i.LEFT
	return Vector2i.RIGHT


static func _all_cells(state: GameState) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(state.board_size.y):
		for x in range(state.board_size.x): cells.append(Vector2i(x, y))
	return cells


static func _in_bounds_cells(state: GameState, cells: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for raw in cells:
		if raw is Vector2i and BoardUtils.in_bounds(state, raw): result.append(raw)
	return result


static func _slot_label(slot_type: String) -> String:
	return "红" if slot_type == Constants.SLOT_RED else "蓝"


static func _gem_name(gem: GemState) -> String:
	return gem.gem_id.replace("gem_", "") if gem != null else "宝石"


static func _spell_name(gem: GemState, slot_type: String) -> String:
	if gem == null:
		return "法术"
	if slot_type == Constants.SLOT_BLUE:
		return "蓝槽触发"
	match gem.gem_id:
		"gem_explosion": return "爆裂星阵"
		"gem_conductive": return "雷狱"
		"gem_fire": return "焚星"
		"gem_ice": return "寒潮"
		"gem_poison": return "蚀毒雾"
		"gem_light": return "裁光"
		"gem_impact": return "横贯冲击"
	return "法术"


static func _spell_preview_detail(gem: GemState, slot_type: String) -> String:
	if gem == null:
		return "无有效结算"
	if slot_type == Constants.SLOT_BLUE:
		match gem.gem_id:
			"gem_explosion": return "落点3×3，8伤害"
			"gem_conductive": return "反击来源8，弹射4"
			"gem_fire": return "着火2层，火焰2回合"
			"gem_ice": return "缓速2；潮湿/已缓速则冻结1回合"
			"gem_poison": return "中毒2层，并复制最长负面状态"
			"gem_light": return "两道弱光，各5伤害＋曝光1"
			"gem_impact": return "远离攻击来源位移至多3格"
	match gem.gem_id:
		"gem_explosion": return "中心12，外围8"
		"gem_conductive": return "全场6；接地2；潮湿10"
		"gem_fire": return "3×3各4，火焰2回合"
		"gem_ice": return "三路寒潮4＋缓速2/冻结1"
		"gem_poison": return "3×3各2＋中毒2，毒雾2回合"
		"gem_light": return "整行/列9＋曝光1"
		"gem_impact": return "整行8，沿线击退"
	return "专属法术"
