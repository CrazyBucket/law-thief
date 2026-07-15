class_name StateSnapshot
extends RefCounted

## Stable, JSON-safe battle snapshots for tests and AI inspection.


static func capture(state: GameState, events: Array = [], include_log: bool = true) -> Dictionary:
	var snapshot := {
		"schema_version": 1,
		"encounter_id": state.encounter_id,
		"run_seed": state.run_seed,
		"turn_index": state.turn_index,
		"phase": state.phase,
		"board_size": _vec(state.board_size),
		"player_uid": state.player_uid,
		"held_gem_uid": state.held_gem_uid,
		"result": state.result,
		"units": [],
		"gems": [],
		"dropped_gems": [],
		"tiles": [],
		"entities": [],
		"events": _json_safe(events),
		"invariants": BattleInvariantChecker.check_all(state),
		"event_violations": EventValidator.validate_events(events),
	}
	if include_log:
		snapshot["combat_log"] = state.combat_log.duplicate()

	var unit_uids := state.units.keys()
	unit_uids.sort()
	for uid in unit_uids:
		snapshot["units"].append(_unit(state.units[uid]))

	var gem_uids := state.gems.keys()
	gem_uids.sort()
	for uid in gem_uids:
		snapshot["gems"].append(_gem(state.gems[uid]))

	var dropped_gem_uids := state.dropped_gems.keys()
	dropped_gem_uids.sort()
	for uid in dropped_gem_uids:
		snapshot["dropped_gems"].append(_dropped_gem(state.dropped_gems[uid]))

	var tile_keys := state.tiles.keys()
	tile_keys.sort()
	for key in tile_keys:
		var tile: TileState = state.tiles[key]
		if tile.tile_id != "tile_floor" or not tile.modifiers.is_empty() or not tile.slots.is_empty():
			snapshot["tiles"].append(_tile(tile))

	var entity_uids := state.entities.keys()
	entity_uids.sort()
	for uid in entity_uids:
		snapshot["entities"].append(_entity(state.entities[uid]))
	return snapshot


static func write_json(path: String, snapshot: Dictionary) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(snapshot, "\t") + "\n")
	return OK


static func json_safe(value: Variant) -> Variant:
	return _json_safe(value)


static func _unit(unit: UnitState) -> Dictionary:
	var slots: Array = []
	for i in range(unit.slots.size()):
		var slot: SlotState = unit.slots[i]
		slots.append({
			"index": i,
			"slot_type": slot.slot_type,
			"dual_type": slot.dual_type,
			"gem_uid": slot.gem_uid,
			"locked": slot.locked,
			"lock_type": slot.lock_type,
			"unlock_until_turn": slot.unlock_until_turn,
		})
	var statuses: Array = []
	for status: StatusInstance in unit.statuses:
		statuses.append({
			"status_id": status.status_id,
			"value": status.value,
			"stacks": status.stacks,
			"duration": status.duration,
			"source_uid": status.source_uid,
			"payload": _json_safe(status.payload),
		})
	statuses.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["status_id"] < b["status_id"])
	return {
		"uid": unit.uid,
		"unit_def_id": unit.unit_def_id,
		"team": unit.team,
		"pos": _vec(unit.pos),
		"footprint_size": _vec(unit.footprint_size),
		"hp": unit.hp,
		"max_hp": unit.max_hp,
		"base_attack": unit.base_attack,
		"move_points": unit.move_points,
		"speed": unit.speed,
		"armor": unit.armor,
		"alive": unit.alive,
		"facing": unit.facing,
		"tags": unit.tags.duplicate(),
		"spawn_origin_uid": unit.spawn_origin_uid,
		"reward_origin_uid": unit.reward_origin_uid,
		"grants_death_rewards": unit.grants_death_rewards,
		"temporary_summon": unit.is_temporary_summon,
		"slots": slots,
		"statuses": statuses,
		"intent": _intent(unit.intent),
	}


static func _gem(gem: GemState) -> Dictionary:
	return {
		"uid": gem.uid,
		"gem_id": gem.gem_id,
		"owner_uid": gem.owner_uid,
		"slot_index": gem.slot_index,
		"location": _json_safe(gem.location.to_dict()),
		"def_overrides": _json_safe(gem.def_overrides),
	}


static func _tile(tile: TileState) -> Dictionary:
	var slots: Array = []
	for slot: SlotState in tile.slots:
		slots.append({
			"slot_type": slot.slot_type,
			"dual_type": slot.dual_type,
			"gem_uid": slot.gem_uid,
			"locked": slot.locked,
			"lock_type": slot.lock_type,
		})
	return {
		"pos": _vec(tile.pos),
		"tile_id": tile.tile_id,
		"ground_tags": tile.ground_tags.duplicate(),
		"modifiers": _json_safe(tile.modifiers),
		"slots": slots,
	}


static func _entity(entity: EntityState) -> Dictionary:
	return {
		"uid": entity.uid,
		"entity_id": entity.entity_id,
		"pos": _vec(entity.pos),
		"hp": entity.hp,
		"max_hp": entity.max_hp,
		"alive": entity.alive,
		"tags": entity.tags.duplicate(),
	}


static func _dropped_gem(drop: Dictionary) -> Dictionary:
	return {
		"gem_uid": str(drop.get("gem_uid", "")),
		"gem_id": str(drop.get("gem_id", "")),
		"pos": _json_safe(drop.get("pos", Vector2i.ZERO)),
		"source_unit_uid": str(drop.get("source_unit_uid", "")),
		"source_slot_type": str(drop.get("source_slot_type", "")),
	}


static func _intent(intent: IntentState) -> Variant:
	if intent == null:
		return null
	return {
		"type": intent.type,
		"source_uid": intent.source_uid,
		"target_uid": intent.target_uid,
		"target_pos": _vec(intent.target_pos),
		"path": _json_safe(intent.path),
		"affected_cells": _json_safe(intent.affected_cells),
		"base_damage": intent.base_damage,
		"damage": intent.damage,
		"damage_components": _json_safe(intent.damage_components.map(
			func(component: IntentDamageComponent): return component.to_dict()
		)),
		"preview_text": intent.preview_text,
		"action_plan": _json_safe(intent.action_plan.to_dict()) if intent.action_plan != null else null,
	}


static func _json_safe(value: Variant) -> Variant:
	if value is Vector2i:
		return _vec(value)
	if value is Vector2:
		return {"x": value.x, "y": value.y}
	if value is Color:
		return value.to_html(true)
	if value is Dictionary:
		var out := {}
		var keys: Array = value.keys()
		keys.sort_custom(func(a, b) -> bool: return str(a) < str(b))
		for key in keys:
			out[str(key)] = _json_safe(value[key])
		return out
	if value is Array:
		var out: Array = []
		for item in value:
			out.append(_json_safe(item))
		return out
	return value


static func _vec(value: Vector2i) -> Dictionary:
	return {"x": value.x, "y": value.y}
