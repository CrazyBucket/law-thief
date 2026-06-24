class_name BattleEditorService
extends RefCounted

const BoardMapGenerator = preload("res://scripts/map/board_map_generator.gd")
const DoodlePropSprites = preload("res://scripts/ui/doodle_prop_sprites.gd")

var _ctrl: BattleController


func setup(controller: BattleController) -> void:
	_ctrl = controller


func execute(command_id: String, payload: Dictionary = {}) -> Dictionary:
	var ctrl: BattleController = _ctrl
	if ctrl == null or ctrl.state == null:
		return _fail("battle has not started")
	match command_id:
		"spawn_unit":
			return _spawn_unit(payload)
		"spawn_many_units":
			return _spawn_many_units(payload)
		"remove_unit":
			return _remove_unit(payload)
		"move_unit":
			return _move_unit(payload)
		"set_tile":
			return _set_tile(payload)
		"spawn_gem":
			return _spawn_gem(payload)
		"remove_gem":
			return _remove_gem(payload)
		"set_unit_stat":
			return _set_unit_stat(payload)
		"apply_unit_status":
			return _apply_unit_status(payload)
		"set_player_spawn":
			return _set_player_spawn(payload)
		"spawn_entity":
			return _spawn_entity(payload)
		"remove_entity":
			return _remove_entity(payload)
		"spawn_overlay":
			return _spawn_overlay(payload)
		"remove_overlay":
			return _remove_overlay(payload)
		"add_relic":
			return _add_relic(payload)
		"remove_relic":
			return _remove_relic(payload)
		"export_encounter":
			return _export_encounter(payload)
		"import_encounter_file":
			return _import_encounter_file(payload)
	return _fail("unknown editor command: %s" % command_id)


func _spawn_unit(payload: Dictionary) -> Dictionary:
	var ctrl := _ctrl
	var unit_def_id := str(payload.get("unit_def_id", ""))
	if not _data_registry().has_unit_def(unit_def_id):
		return _fail("unknown unit id: %s" % unit_def_id)
	var pos: Vector2i = payload.get("pos", Vector2i.ZERO)
	if not BoardUtils.in_bounds(ctrl.state, pos):
		return _fail("position out of bounds: %s" % pos)
	if ctrl.state.get_unit_at(pos) != null:
		return _fail("a live unit already exists at %s" % pos)
	var team := str(payload.get("team", Constants.TEAM_ENEMY))
	if team != Constants.TEAM_PLAYER and team != Constants.TEAM_ENEMY:
		return _fail("unknown team: %s" % team)
	var unit_uid: String = _data_registry().next_runtime_uid("runtime_unit")
	var unit: UnitState = UnitState.from_def(unit_uid, unit_def_id, team, pos, _data_registry().get_unit_def(unit_def_id))
	ctrl.state.register_unit(unit)
	TileRules.sync_standing_ground_effects(ctrl.state, unit)
	return _finalize_mutation("spawned %s at %s for team %s" % [unit_def_id, pos, team], false, {"unit_uid": unit_uid})


func _spawn_many_units(payload: Dictionary) -> Dictionary:
	var ctrl := _ctrl
	var unit_def_id := str(payload.get("unit_def_id", ""))
	if not _data_registry().has_unit_def(unit_def_id):
		return _fail("unknown unit id: %s" % unit_def_id)
	var team := str(payload.get("team", Constants.TEAM_ENEMY))
	if team != Constants.TEAM_PLAYER and team != Constants.TEAM_ENEMY:
		return _fail("unknown team: %s" % team)
	var positions: Array[Vector2i] = payload.get("positions", [] as Array[Vector2i])
	if positions.is_empty():
		return _fail("missing batch positions")
	var seen: Dictionary = {}
	for pos in positions:
		if not BoardUtils.in_bounds(ctrl.state, pos):
			return _fail("position out of bounds: %s" % pos)
		if ctrl.state.get_unit_at(pos) != null:
			return _fail("a live unit already exists at %s" % pos)
		var pos_key := ctrl.state.tile_key(pos)
		if seen.has(pos_key):
			return _fail("duplicate position in batch: %s" % pos)
		seen[pos_key] = true
	var created_uids: Array[String] = []
	for pos in positions:
		var unit_uid: String = _data_registry().next_runtime_uid("runtime_unit")
		var unit: UnitState = UnitState.from_def(unit_uid, unit_def_id, team, pos, _data_registry().get_unit_def(unit_def_id))
		ctrl.state.register_unit(unit)
		created_uids.append(unit_uid)
	return _finalize_mutation("spawned %d instances of %s for team %s" % [created_uids.size(), unit_def_id, team], false, {"unit_uids": created_uids})


func _remove_unit(payload: Dictionary) -> Dictionary:
	var ctrl := _ctrl
	var pos: Vector2i = payload.get("pos", Vector2i.ZERO)
	var unit: UnitState = ctrl.state.get_unit_at(pos)
	if unit == null:
		return _fail("no live unit at %s" % pos)
	if unit.uid == ctrl.state.player_uid:
		return _fail("cannot remove the player; use `set spawn` instead")
	_clear_unit_gems(unit)
	ctrl.state.unregister_unit(unit)
	if ctrl.selected_unit_uid == unit.uid:
		ctrl.selected_unit_uid = ctrl.state.player_uid
	return _finalize_mutation("removed unit %s at %s" % [unit.unit_def_id, pos])


func _move_unit(payload: Dictionary) -> Dictionary:
	var ctrl := _ctrl
	var from_pos: Vector2i = payload.get("from_pos", Vector2i.ZERO)
	var to_pos: Vector2i = payload.get("to_pos", Vector2i.ZERO)
	if not BoardUtils.in_bounds(ctrl.state, to_pos):
		return _fail("destination out of bounds: %s" % to_pos)
	var unit: UnitState = ctrl.state.get_unit_at(from_pos)
	if unit == null:
		return _fail("no live unit at source position %s" % from_pos)
	if from_pos == to_pos:
		return _ok({"message": "unit is already at the destination"})
	var occupant: UnitState = ctrl.state.get_unit_at(to_pos)
	if occupant != null and occupant.uid != unit.uid:
		return _fail("destination is occupied: %s" % to_pos)
	ctrl.state.move_unit(unit, to_pos)
	TileRules.on_unit_entered(ctrl.state, unit, from_pos)
	var move_message := "moved %s from %s to %s" % [unit.unit_def_id, from_pos, to_pos]
	if unit.uid == ctrl.state.player_uid:
		move_message = "moved player spawn to %s" % to_pos
	return _finalize_mutation(move_message)


func _set_tile(payload: Dictionary) -> Dictionary:
	var ctrl := _ctrl
	var pos: Vector2i = payload.get("pos", Vector2i.ZERO)
	var tile_id := str(payload.get("tile_id", ""))
	if not _data_registry().has_tile_id(tile_id):
		return _fail("unknown tile id: %s" % tile_id)
	if not BoardUtils.in_bounds(ctrl.state, pos):
		return _fail("position out of bounds: %s" % pos)
	var existing: TileState = ctrl.state.get_tile(pos)
	_clear_tile_gems(existing)
	var tile: TileState = TileState.create(pos, tile_id)
	tile.surface_variant = str(payload.get("surface_variant", ""))
	var slot_defs := _default_tile_slot_defs(tile_id)
	if not slot_defs.is_empty():
		tile = TileState.create_with_slots(pos, tile_id, slot_defs)
		tile.surface_variant = str(payload.get("surface_variant", ""))
	ctrl.state.tiles[ctrl.state.tile_key(pos)] = tile
	return _finalize_mutation("set tile at %s to %s" % [pos, tile_id], true)


func _spawn_gem(payload: Dictionary) -> Dictionary:
	var ctrl := _ctrl
	var gem_id := str(payload.get("gem_id", ""))
	if not _data_registry().has_gem_def(gem_id):
		return _fail("unknown gem id: %s" % gem_id)
	var pos: Vector2i = payload.get("pos", Vector2i.ZERO)
	if not BoardUtils.in_bounds(ctrl.state, pos):
		return _fail("position out of bounds: %s" % pos)
	var preferred_slot := str(payload.get("slot_type", ""))
	var target_kind := str(payload.get("target_kind", ""))
	var requested_slot_index := int(payload.get("slot_index", -1))
	var create_slot_type := str(payload.get("create_slot_type", ""))
	if not create_slot_type.is_empty() and create_slot_type not in [
		Constants.SLOT_RED, Constants.SLOT_BLUE, Constants.SLOT_BLACK
	]:
		return _fail("invalid slot type: %s" % create_slot_type)
	var unit: UnitState = ctrl.state.get_unit_at(pos)
	var tile: TileState = ctrl.state.get_tile(pos)
	if target_kind.is_empty():
		target_kind = "unit" if unit != null else "tile"
	var slot_index := -1
	var slot: SlotState = null
	var target_label := ""
	if target_kind == "unit":
		if unit == null:
			return _fail("no unit at %s" % pos)
		if not create_slot_type.is_empty():
			unit.slots.append(SlotState.create(create_slot_type))
			requested_slot_index = unit.slots.size() - 1
			slot_index = requested_slot_index
		elif requested_slot_index >= 0:
			slot_index = requested_slot_index if requested_slot_index < unit.slots.size() else -1
		else:
			slot_index = _find_slot_index(unit.slots, preferred_slot)
		if slot_index < 0:
			return _fail("no available slot on unit at %s" % pos)
		slot = unit.get_slot_by_index(slot_index)
		target_label = "unit %s slot %s" % [unit.unit_def_id, _slot_label(slot)]
	else:
		if tile == null:
			return _fail("no tile at %s" % pos)
		if not create_slot_type.is_empty():
			tile.slots.append(SlotState.create(create_slot_type))
			requested_slot_index = tile.slots.size() - 1
			slot_index = requested_slot_index
		elif requested_slot_index >= 0:
			slot_index = requested_slot_index if requested_slot_index < tile.slots.size() else -1
		else:
			slot_index = _find_slot_index(tile.slots, preferred_slot)
		if slot_index < 0:
			return _fail("no available slot on tile at %s" % pos)
		slot = tile.get_slot_by_index(slot_index)
		target_label = "tile %s slot %s" % [tile.tile_id, _slot_label(slot)]
	if slot == null or slot.locked or slot.is_split_disabled():
		return _fail("selected slot is not editable")
	_clear_slot_gem(slot)
	var gem_uid: String = _data_registry().next_runtime_uid("runtime_gem")
	var gem: GemState = _data_registry().create_gem_instance(gem_uid, gem_id)
	if target_kind == "unit" and unit != null:
		gem.owner_uid = unit.uid
		gem.slot_index = slot_index
	else:
		gem.owner_uid = ""
		gem.slot_index = -1
	ctrl.state.gems[gem.uid] = gem
	slot.gem_uid = gem.uid
	return _finalize_mutation("spawned %s in %s" % [gem_id, target_label], false, {"gem_uid": gem.uid})


func _remove_gem(payload: Dictionary) -> Dictionary:
	var ctrl := _ctrl
	var pos: Vector2i = payload.get("pos", Vector2i.ZERO)
	if not BoardUtils.in_bounds(ctrl.state, pos):
		return _fail("position out of bounds: %s" % pos)
	var preferred_slot := str(payload.get("slot_type", ""))
	var target_kind := str(payload.get("target_kind", ""))
	var unit: UnitState = ctrl.state.get_unit_at(pos)
	var tile: TileState = ctrl.state.get_tile(pos)
	var slot_index := int(payload.get("slot_index", -1))
	var slot: SlotState = null
	var target_label := ""
	if target_kind == "unit" or (target_kind.is_empty() and unit != null and _find_filled_slot_index(unit.slots, preferred_slot) >= 0):
		if unit == null:
			return _fail("no unit at %s" % pos)
		if slot_index >= 0:
			slot = unit.get_slot_by_index(slot_index)
		else:
			slot_index = _find_filled_slot_index(unit.slots, preferred_slot)
			if slot_index >= 0:
				slot = unit.get_slot_by_index(slot_index)
		if slot == null or slot.gem_uid.is_empty():
			return _fail("no gem found on unit at %s" % pos)
		target_label = "unit %s slot %s" % [unit.unit_def_id, _slot_label(slot)]
	else:
		if tile == null or not tile.has_slots():
			return _fail("no slotted tile at %s" % pos)
		if slot_index >= 0:
			slot = tile.get_slot_by_index(slot_index)
		else:
			slot_index = _find_filled_slot_index(tile.slots, preferred_slot)
			if slot_index >= 0:
				slot = tile.get_slot_by_index(slot_index)
		if slot == null or slot.gem_uid.is_empty():
			return _fail("no gem found on tile at %s" % pos)
		target_label = "tile %s slot %s" % [tile.tile_id, _slot_label(slot)]
	var gem: GemState = ctrl.state.gems.get(slot.gem_uid, null)
	var gem_id := gem.gem_id if gem != null else "unknown_gem"
	_clear_slot_gem(slot)
	return _finalize_mutation("removed %s from %s" % [gem_id, target_label])


func _set_unit_stat(payload: Dictionary) -> Dictionary:
	var ctrl := _ctrl
	var pos: Vector2i = payload.get("pos", Vector2i.ZERO)
	var field := str(payload.get("field", ""))
	var raw_value := str(payload.get("value", ""))
	var unit: UnitState = ctrl.state.get_unit_at(pos)
	if unit == null:
		return _fail("no live unit at %s" % pos)
	match field:
		"hp":
			if not raw_value.is_valid_int():
				return _fail("hp must be an integer")
			unit.hp = maxi(0, int(raw_value))
			if unit.hp > unit.max_hp:
				unit.max_hp = unit.hp
			unit.alive = unit.hp > 0
		"max_hp":
			if not raw_value.is_valid_int():
				return _fail("max_hp must be an integer")
			unit.max_hp = maxi(1, int(raw_value))
			if unit.hp > unit.max_hp:
				unit.hp = unit.max_hp
			if unit.alive and unit.hp <= 0:
				unit.hp = unit.max_hp
		"move_points":
			if not raw_value.is_valid_int():
				return _fail("move_points must be an integer")
			unit.move_points = maxi(0, int(raw_value))
		"speed":
			if not raw_value.is_valid_int():
				return _fail("speed must be an integer")
			unit.speed = maxi(0, int(raw_value))
		"base_attack":
			if not raw_value.is_valid_int():
				return _fail("base_attack must be an integer")
			unit.base_attack = int(raw_value)
		"armor":
			if not raw_value.is_valid_int():
				return _fail("armor must be an integer")
			unit.armor = maxi(0, int(raw_value))
		"alive":
			var alive_parse := _parse_bool(raw_value)
			if not alive_parse.get("ok", false):
				return _fail("alive only supports true or false")
			var new_alive: bool = alive_parse.get("value", false)
			if new_alive and not unit.alive:
				unit.alive = true
				unit.hp = maxi(1, unit.max_hp)
				ctrl.state._add_unit_to_occupancy(unit)
			elif not new_alive and unit.alive:
				unit.hp = 0
				ctrl.state.kill_unit(unit)
		_:
			return _fail("unsupported stat field: %s" % field)
	return _finalize_mutation("set %s.%s = %s" % [unit.unit_def_id, field, raw_value])


func _apply_unit_status(payload: Dictionary) -> Dictionary:
	var ctrl := _ctrl
	var pos: Vector2i = payload.get("pos", Vector2i.ZERO)
	var status_id := str(payload.get("status_id", ""))
	var unit: UnitState = ctrl.state.get_unit_at(pos)
	if unit == null or not unit.alive:
		return _fail("no live unit at %s" % pos)
	match status_id:
		Constants.STATUS_POISON:
			StatusRules.apply_poison(ctrl.state, unit, 1, 2, "editor")
		Constants.STATUS_BURNING:
			StatusRules.apply_burning(ctrl.state, unit, 1, "editor")
		Constants.STATUS_SLOWED:
			StatusRules.apply_slowed(ctrl.state, unit, 1, "editor")
		Constants.STATUS_PARALYZED:
			StatusRules.apply_paralyzed(ctrl.state, unit, 1, "editor")
		Constants.STATUS_WET:
			StatusRules.apply_wet(ctrl.state, unit, 2, "editor")
		Constants.STATUS_ROOTED:
			StatusRules.apply_rooted(ctrl.state, unit, 2, "editor")
		Constants.STATUS_VULNERABLE:
			StatusRules.apply_vulnerable(ctrl.state, unit, 1, "editor")
		Constants.STATUS_WEAK:
			StatusRules.apply_weak(ctrl.state, unit, 1, "editor")
		Constants.STATUS_LIGHT_EXPOSED:
			StatusRules.apply_light_exposed(ctrl.state, unit, 1, "editor")
		Constants.STATUS_BLINDED:
			StatusRules.apply_blinded(ctrl.state, unit, 1, "editor")
		Constants.STATUS_ARMOR:
			StatusRules.apply_armor(ctrl.state, unit, 3, 1, "editor")
		_:
			return _fail("unsupported status: %s" % status_id)
	return _finalize_mutation("applied %s to %s" % [status_id, unit.uid])


func _set_player_spawn(payload: Dictionary) -> Dictionary:
	var ctrl := _ctrl
	var pos: Vector2i = payload.get("pos", Vector2i.ZERO)
	if not BoardUtils.in_bounds(ctrl.state, pos):
		return _fail("position out of bounds: %s" % pos)
	var player: UnitState = ctrl.state.get_player()
	if player == null:
		return _fail("player does not exist")
	var occupant: UnitState = ctrl.state.get_unit_at(pos)
	if occupant != null and occupant.uid != player.uid:
		return _fail("destination is occupied: %s" % pos)
	ctrl.state.move_unit(player, pos)
	return _finalize_mutation("set player spawn to %s" % pos)


func _spawn_entity(payload: Dictionary) -> Dictionary:
	var ctrl := _ctrl
	var entity_id := str(payload.get("entity_id", ""))
	if not _data_registry().has_entity_id(entity_id):
		return _fail("unknown entity id: %s" % entity_id)
	var pos: Vector2i = payload.get("pos", Vector2i.ZERO)
	if not BoardUtils.in_bounds(ctrl.state, pos):
		return _fail("position out of bounds: %s" % pos)
	var existing := ctrl.state.get_entity_at(pos)
	if existing != null and existing.alive:
		return _fail("an entity already exists at %s" % pos)
	var entity_uid: String = _data_registry().next_runtime_uid("runtime_entity")
	var entity: EntityState = EntityState.create(entity_uid, entity_id, pos)
	var prop_sprite := str(payload.get("prop_sprite", ""))
	if not prop_sprite.is_empty():
		entity.prop_sprite = prop_sprite
	elif entity_id == Constants.ENTITY_PROP or entity_id == Constants.ENTITY_ROCK:
		entity.prop_sprite = DoodlePropSprites.pick_sprite_id_for_entity(entity_id, ctrl.state.run_seed, pos, entity_uid)
	ctrl.state.add_entity(entity)
	return _finalize_mutation("spawned %s at %s" % [entity_id, pos], false, {"entity_uid": entity_uid})


func _remove_entity(payload: Dictionary) -> Dictionary:
	var ctrl := _ctrl
	var pos: Vector2i = payload.get("pos", Vector2i.ZERO)
	var entity := ctrl.state.get_entity_at(pos)
	if entity == null or not entity.alive:
		return _fail("no entity at %s" % pos)
	ctrl.state.remove_entity(entity.uid)
	return _finalize_mutation("removed entity %s at %s" % [entity.entity_id, pos])


func _spawn_overlay(payload: Dictionary) -> Dictionary:
	var ctrl := _ctrl
	var overlay_id := str(payload.get("overlay_id", ""))
	if not _data_registry().has_overlay_id(overlay_id):
		return _fail("unknown overlay id: %s" % overlay_id)
	var pos: Vector2i = payload.get("pos", Vector2i.ZERO)
	if not BoardUtils.in_bounds(ctrl.state, pos):
		return _fail("position out of bounds: %s" % pos)
	var duration := int(payload.get("duration", _data_registry().get_overlay_default_duration(overlay_id)))
	var result := TileRules.create_overlay(ctrl.state, overlay_id, pos, duration, payload.get("modifier_payload", {}))
	if not result.get("ok", false):
		return result
	return _finalize_mutation("spawned overlay %s at %s" % [overlay_id, pos], true)


func _remove_overlay(payload: Dictionary) -> Dictionary:
	var ctrl := _ctrl
	var overlay_id := str(payload.get("overlay_id", ""))
	if not _data_registry().has_overlay_id(overlay_id):
		return _fail("unknown overlay id: %s" % overlay_id)
	var pos: Vector2i = payload.get("pos", Vector2i.ZERO)
	if not BoardUtils.in_bounds(ctrl.state, pos):
		return _fail("position out of bounds: %s" % pos)
	var tile := ctrl.state.get_tile(pos)
	if tile == null or not tile.has_modifier(overlay_id):
		return _fail("overlay %s not found at %s" % [overlay_id, pos])
	tile.remove_modifier(overlay_id)
	return _finalize_mutation("removed overlay %s at %s" % [overlay_id, pos], true)


func _add_relic(payload: Dictionary) -> Dictionary:
	var relic_id := str(payload.get("relic_id", ""))
	if not _data_registry().has_relic_def(relic_id):
		return _fail("unknown relic id: %s" % relic_id)
	var run_service := _ensure_run_for_relic_edit()
	if run_service == null:
		return _fail("RunService unavailable")
	if run_service.has_relic(relic_id):
		return _ok({"message": "relic already owned: %s" % relic_id})
	run_service.acquire_relic(relic_id)
	return _finalize_mutation("added relic %s" % relic_id)


func _remove_relic(payload: Dictionary) -> Dictionary:
	var relic_id := str(payload.get("relic_id", ""))
	if not _data_registry().has_relic_def(relic_id):
		return _fail("unknown relic id: %s" % relic_id)
	var run_service := _ensure_run_for_relic_edit()
	if run_service == null:
		return _fail("RunService unavailable")
	if not run_service.has_relic(relic_id):
		return _ok({"message": "relic not owned: %s" % relic_id})
	run_service.remove_relic(relic_id)
	return _finalize_mutation("removed relic %s" % relic_id)


func _ensure_run_for_relic_edit() -> Node:
	var run_service := _run_service()
	if run_service == null:
		return null
	if not run_service.is_run_active():
		run_service.start_run(1, 1)
	return run_service


func _export_encounter(payload: Dictionary) -> Dictionary:
	var encounter_id := str(payload.get("encounter_id", ""))
	if encounter_id.is_empty():
		encounter_id = "editor_export_%s" % _ctrl.state.encounter_id
	var encounter := _build_export_encounter()
	var lines := JSON.stringify(encounter, "\t").split("\n")
	return _ok({
		"message": "exported encounter %s" % encounter_id,
		"lines": lines,
		"encounter": encounter,
		"encounter_id": encounter_id,
	})


func _import_encounter_file(payload: Dictionary) -> Dictionary:
	var file_path := str(payload.get("path", "")).strip_edges()
	if file_path.is_empty():
		return _fail("missing import file path")
	if not FileAccess.file_exists(file_path):
		return _fail("file not found: %s" % file_path)
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return _fail("failed to open file: %s" % file_path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return _fail("encounter json must be an object")
	var encounter := _parse_import_encounter(parsed as Dictionary)
	return _apply_import_encounter(encounter, file_path)


func _finalize_mutation(message: String, rebuild_tiles: bool = false, payload: Dictionary = {}) -> Dictionary:
	var ctrl := _ctrl
	ctrl.state.log("[Editor CLI] %s" % message)
	if rebuild_tiles:
		BoardMapGenerator.refresh_runtime_visual_data(ctrl.state)
	if ctrl.state.phase == Constants.PHASE_ENDED:
		var player: UnitState = ctrl.state.get_player()
		if player != null and player.alive and not ctrl.state.get_alive_enemies().is_empty():
			ctrl.state.phase = Constants.PHASE_PLAYER
			ctrl.state.result = ""
			ctrl.state.player_moved = false
			ctrl.state.player_acted = false
	IntentSystem.refresh_all_intents(ctrl.state)
	ctrl._check_battle_end()
	payload["message"] = message
	ctrl._emit_changed()
	return _ok(payload)


func _build_export_encounter() -> Dictionary:
	var ctrl := _ctrl
	var player: UnitState = ctrl.state.get_player()
	var enemies: Array[Dictionary] = []
	var entities: Array[Dictionary] = []
	var tiles: Array[Dictionary] = []
	for unit in ctrl.state.units.values():
		if unit.uid == ctrl.state.player_uid or not unit.alive or unit.team != Constants.TEAM_ENEMY:
			continue
		var enemy_entry := {
			"def_id": unit.unit_def_id,
			"pos": [unit.pos.x, unit.pos.y],
		}
		var slot_defs := _collect_slot_entries(unit.slots)
		if not slot_defs.is_empty():
			enemy_entry["slots"] = slot_defs
		enemies.append(enemy_entry)
	enemies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _compare_export_positions(a.get("pos", [0, 0]), b.get("pos", [0, 0]))
	)
	for entity in ctrl.state.entities.values():
		if entity == null or not entity.alive:
			continue
		var entity_entry := {
			"entity_id": entity.entity_id,
			"pos": [entity.pos.x, entity.pos.y],
		}
		if not entity.prop_sprite.is_empty():
			entity_entry["prop_sprite"] = entity.prop_sprite
		entities.append(entity_entry)
	entities.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _compare_export_positions(a.get("pos", [0, 0]), b.get("pos", [0, 0]))
	)
	for tile in ctrl.state.tiles.values():
		var tile_entry := _build_tile_export_entry(tile)
		if tile_entry.is_empty():
			continue
		tiles.append(tile_entry)
	tiles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _compare_export_positions(a.get("pos", [0, 0]), b.get("pos", [0, 0]))
	)
	var encounter := {
		"schema_version": 2,
		"player_spawn": [player.pos.x, player.pos.y] if player != null else [0, 0],
		"floor_seed": ctrl.state.run_seed,
		"enemies": enemies,
		"entities": entities,
		"tiles": tiles,
	}
	return encounter


func _parse_import_encounter(raw: Dictionary) -> Dictionary:
	var encounter := raw.duplicate(true)
	if encounter.has("player_spawn"):
		var spawn: Variant = encounter.get("player_spawn", [])
		if spawn is Array and spawn.size() >= 2:
			encounter["player_spawn"] = Vector2i(int(spawn[0]), int(spawn[1]))
	if encounter.has("enemies"):
		var enemies: Array = encounter.get("enemies", [])
		for i in range(enemies.size()):
			var entry: Dictionary = enemies[i].duplicate(true)
			var pos_raw: Variant = entry.get("pos", [])
			if pos_raw is Array and pos_raw.size() >= 2:
				entry["pos"] = Vector2i(int(pos_raw[0]), int(pos_raw[1]))
			enemies[i] = entry
		encounter["enemies"] = enemies
	if encounter.has("entities"):
		var entities: Array = encounter.get("entities", [])
		for i in range(entities.size()):
			var entry: Dictionary = entities[i].duplicate(true)
			var pos_raw: Variant = entry.get("pos", [])
			if pos_raw is Array and pos_raw.size() >= 2:
				entry["pos"] = Vector2i(int(pos_raw[0]), int(pos_raw[1]))
			entities[i] = entry
		encounter["entities"] = entities
	if encounter.has("tiles"):
		var tiles: Array = encounter.get("tiles", [])
		for i in range(tiles.size()):
			var entry: Dictionary = tiles[i].duplicate(true)
			var pos_raw: Variant = entry.get("pos", [])
			if pos_raw is Array and pos_raw.size() >= 2:
				entry["pos"] = Vector2i(int(pos_raw[0]), int(pos_raw[1]))
			tiles[i] = entry
		encounter["tiles"] = tiles
	return encounter


func _apply_import_encounter(encounter: Dictionary, source_label: String) -> Dictionary:
	if encounter.is_empty():
		return _fail("encounter payload is empty")
	var ctrl := _ctrl
	var import_id := "editor_import_%s" % Time.get_unix_time_from_system()
	var state: GameState = _data_registry().create_battle_state_from_editor_payload(import_id, encounter)
	if state == null:
		return _fail("failed to create battle state from imported encounter")
	ctrl.state = state
	ctrl.selected_action = ""
	ctrl.selected_unit_uid = state.player_uid
	ctrl.state.battle_temp_flags.clear()
	ctrl._connect_relic_signals(state)
	ctrl.state.on_battle_start.emit()
	ctrl._emit_changed()
	return _ok({
		"message": "imported encounter from %s" % source_label,
		"encounter_id": import_id,
	})


func _build_tile_export_entry(tile: TileState) -> Dictionary:
	if tile == null:
		return {}
	var has_overlay := not tile.modifiers.is_empty()
	if tile.tile_id == Constants.TILE_FLOOR and not tile.has_slots() and not has_overlay:
		return {}
	var tile_entry := {
		"pos": [tile.pos.x, tile.pos.y],
		"tile_id": tile.tile_id,
	}
	var tile_slots := _collect_slot_entries(tile.slots)
	if not tile_slots.is_empty():
		tile_entry["slots"] = tile_slots
	if has_overlay:
		var overlays: Array[Dictionary] = []
		for modifier in tile.modifiers:
			var entry := {
				"type": str(modifier.get("type", "")),
				"duration": int(modifier.get("duration", 0)),
			}
			var payload: Dictionary = modifier.get("payload", {})
			if not payload.is_empty():
				entry["payload"] = payload.duplicate(true)
			overlays.append(entry)
		tile_entry["overlays"] = overlays
	return tile_entry


func _collect_slot_entries(slots: Array) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for slot in slots:
		var slot_entry := {
			"slot_type": slot.slot_type,
		}
		if bool(slot.locked):
			slot_entry["locked"] = true
		if not str(slot.lock_type).is_empty():
			slot_entry["lock_type"] = slot.lock_type
		if not str(slot.dual_type).is_empty():
			slot_entry["dual_type"] = slot.dual_type
		if not slot.gem_uid.is_empty():
			var gem: GemState = _ctrl.state.gems.get(slot.gem_uid, null)
			if gem != null:
				slot_entry["gem_id"] = gem.gem_id
				if not gem.def_overrides.is_empty():
					slot_entry["gem_overrides"] = gem.def_overrides.duplicate(true)
		if slot_entry.size() > 1:
			entries.append(slot_entry)
	return entries


func _clear_tile_gems(tile: TileState) -> void:
	if tile == null:
		return
	for slot in tile.slots:
		_clear_slot_gem(slot)


func _clear_unit_gems(unit: UnitState) -> void:
	if unit == null:
		return
	for slot in unit.slots:
		_clear_slot_gem(slot)


func _clear_slot_gem(slot: SlotState) -> void:
	if slot == null or slot.gem_uid.is_empty():
		return
	if _ctrl.state.held_gem_uid == slot.gem_uid:
		_ctrl.state.held_gem_uid = ""
	_ctrl.state.gems.erase(slot.gem_uid)
	slot.gem_uid = ""


func _default_tile_slot_defs(tile_id: String) -> Array:
	match tile_id:
		Constants.TILE_PILLAR:
			return [{"slot_type": Constants.SLOT_BLUE}]
		_:
			return []


func _slot_label(slot: SlotState) -> String:
	match slot.slot_type:
		Constants.SLOT_RED:
			return "red"
		Constants.SLOT_BLUE:
			return "blue"
		Constants.SLOT_BLACK:
			return "black"
	return "unknown"


func _find_slot_index(slots: Array, preferred_slot_type: String = "") -> int:
	var fallback := -1
	for i in range(slots.size()):
		var slot: SlotState = slots[i]
		if not preferred_slot_type.is_empty() and not slot.accepts_slot_type(preferred_slot_type):
			continue
		if slot.gem_uid.is_empty():
			return i
		if fallback < 0:
			fallback = i
	return fallback


func _find_filled_slot_index(slots: Array, preferred_slot_type: String = "") -> int:
	for i in range(slots.size()):
		var slot: SlotState = slots[i]
		if not preferred_slot_type.is_empty() and not slot.accepts_slot_type(preferred_slot_type):
			continue
		if not slot.gem_uid.is_empty():
			return i
	return -1


func _compare_export_positions(a: Array, b: Array) -> bool:
	if int(a[1]) == int(b[1]):
		return int(a[0]) < int(b[0])
	return int(a[1]) < int(b[1])


func _parse_bool(raw_value: String) -> Dictionary:
	var lowered := raw_value.to_lower()
	if lowered in ["true", "1", "yes", "on"]:
		return _ok({"value": true})
	if lowered in ["false", "0", "no", "off"]:
		return _ok({"value": false})
	return _fail("invalid bool")


func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node("DataRegistry")


func _run_service() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("RunService")


func _ok(payload: Dictionary = {}) -> Dictionary:
	payload["ok"] = true
	return payload


func _fail(reason: String) -> Dictionary:
	return {"ok": false, "message": reason}
