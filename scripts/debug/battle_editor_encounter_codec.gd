class_name BattleEditorEncounterCodec
extends RefCounted


## Keeps the editor file format independent from command execution and UI output.
static func export_from_state(state: GameState) -> Dictionary:
	var player: UnitState = state.get_player()
	var enemies: Array[Dictionary] = []
	var entities: Array[Dictionary] = []
	var tiles: Array[Dictionary] = []
	for unit in state.units.values():
		if unit.uid == state.player_uid or not unit.alive or unit.team != Constants.TEAM_ENEMY:
			continue
		var enemy_entry := {"def_id": unit.unit_def_id, "pos": _encode_position(unit.pos)}
		var slot_defs := _collect_slot_entries(state, unit.slots)
		if not slot_defs.is_empty():
			enemy_entry["slots"] = slot_defs
		enemies.append(enemy_entry)
	enemies.sort_custom(_sort_encoded_positions)
	for entity in state.entities.values():
		if entity == null or not entity.alive:
			continue
		var entity_entry := {"entity_id": entity.entity_id, "pos": _encode_position(entity.pos)}
		if not entity.prop_sprite.is_empty():
			entity_entry["prop_sprite"] = entity.prop_sprite
		entities.append(entity_entry)
	entities.sort_custom(_sort_encoded_positions)
	for tile in state.tiles.values():
		var tile_entry := _build_tile_entry(state, tile)
		if not tile_entry.is_empty():
			tiles.append(tile_entry)
	tiles.sort_custom(_sort_encoded_positions)
	return {
		"schema_version": 2,
		"player_spawn": _encode_position(player.pos) if player != null else [0, 0],
		"floor_seed": state.run_seed,
		"enemies": enemies,
		"entities": entities,
		"tiles": tiles,
	}


static func parse_import(raw: Dictionary) -> Dictionary:
	var encounter := raw.duplicate(true)
	_decode_position_field(encounter, "player_spawn")
	_decode_entry_positions(encounter, "enemies")
	_decode_entry_positions(encounter, "entities")
	_decode_entry_positions(encounter, "tiles")
	return encounter


static func _build_tile_entry(state: GameState, tile: TileState) -> Dictionary:
	if tile == null:
		return {}
	var has_overlay := not tile.modifiers.is_empty()
	if tile.tile_id == Constants.TILE_FLOOR and not tile.has_slots() and not has_overlay:
		return {}
	var entry := {"pos": _encode_position(tile.pos), "tile_id": tile.tile_id}
	var slots := _collect_slot_entries(state, tile.slots)
	if not slots.is_empty():
		entry["slots"] = slots
	if has_overlay:
		var overlays: Array[Dictionary] = []
		for modifier in tile.modifiers:
			var overlay := {"type": str(modifier.get("type", "")), "duration": int(modifier.get("duration", 0))}
			var payload: Dictionary = modifier.get("payload", {})
			if not payload.is_empty():
				overlay["payload"] = payload.duplicate(true)
			overlays.append(overlay)
		entry["overlays"] = overlays
	return entry


static func _collect_slot_entries(state: GameState, slots: Array) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for slot in slots:
		var entry := {"slot_type": slot.slot_type}
		if bool(slot.locked):
			entry["locked"] = true
		if not str(slot.lock_type).is_empty():
			entry["lock_type"] = slot.lock_type
		if not str(slot.dual_type).is_empty():
			entry["dual_type"] = slot.dual_type
		if not slot.gem_uid.is_empty():
			var gem: GemState = state.gems.get(slot.gem_uid, null)
			if gem != null:
				entry["gem_id"] = gem.gem_id
				if not gem.def_overrides.is_empty():
					entry["gem_overrides"] = gem.def_overrides.duplicate(true)
		if entry.size() > 1:
			entries.append(entry)
	return entries


static func _decode_position_field(container: Dictionary, field: String) -> void:
	var value: Variant = container.get(field, [])
	if value is Array and value.size() >= 2:
		container[field] = Vector2i(int(value[0]), int(value[1]))


static func _decode_entry_positions(encounter: Dictionary, field: String) -> void:
	var entries: Array = encounter.get(field, [])
	for index in range(entries.size()):
		var entry: Dictionary = entries[index].duplicate(true)
		_decode_position_field(entry, "pos")
		entries[index] = entry
	if encounter.has(field):
		encounter[field] = entries


static func _encode_position(pos: Vector2i) -> Array[int]:
	return [pos.x, pos.y]


static func _sort_encoded_positions(a: Dictionary, b: Dictionary) -> bool:
	var a_pos: Array = a.get("pos", [0, 0])
	var b_pos: Array = b.get("pos", [0, 0])
	if int(a_pos[1]) == int(b_pos[1]):
		return int(a_pos[0]) < int(b_pos[0])
	return int(a_pos[1]) < int(b_pos[1])
