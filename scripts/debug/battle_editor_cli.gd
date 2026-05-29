class_name BattleEditorCli
extends RefCounted

var _ctrl: BattleController


func setup(controller: BattleController) -> void:
	_ctrl = controller


func run(raw_command: String) -> Dictionary:
	var ctrl: BattleController = _ctrl
	if ctrl == null or ctrl.state == null:
		return _fail("battle has not started")
	var tokens := _editor_tokens(raw_command)
	if tokens.is_empty():
		return _fail("enter a command")
	var cmd := _normalize_editor_command(tokens[0])
	match cmd:
		"help":
			return _ok({
				"message": "Editor CLI help",
				"lines": _editor_help_lines(),
			})
		"list":
			return _run_editor_list_command(ctrl, tokens)
		"spawn":
			return _run_editor_spawn_command(ctrl, tokens, 1)
		"spawn_many":
			return _run_editor_spawn_many_command(ctrl, tokens, 1)
		"remove":
			return _run_editor_remove_command(ctrl, tokens, 1)
		"move":
			return _run_editor_move_command(ctrl, tokens, 1)
		"set":
			return _run_editor_set_command(ctrl, tokens, 1)
		"export":
			return _run_editor_export_command(ctrl, tokens, 1)
		_:
			return _fail("unknown command: %s (use /help for usage)" % tokens[0])


# ═══════════════════════════════════════════════════════════════════════════
# Command dispatch
# ═══════════════════════════════════════════════════════════════════════════

func _run_editor_spawn_command(ctrl, tokens: Array, start_index: int) -> Dictionary:
	if tokens.size() <= start_index:
		return _fail("missing object id")
	var object_id := str(tokens[start_index])
	var object_kind := _editor_object_kind_from_id(ctrl, object_id)
	if object_kind.is_empty():
		return _fail("unknown object id: %s" % object_id)
	var arg_parse := _editor_parse_cli_args(tokens, start_index + 1)
	if not arg_parse.get("ok", false):
		return arg_parse
	var positionals: Array = arg_parse.get("positionals", [])
	var options: Dictionary = arg_parse.get("options", {})
	if positionals.is_empty():
		return _fail("missing position")
	if positionals.size() > 1:
		return _fail("spawn accepts exactly one position")
	match object_kind:
		"unit":
			var option_check := _editor_validate_option_keys(options, ["team"])
			if not option_check.get("ok", false):
				return option_check
			var unit_tokens: Array = [object_id, str(positionals[0])]
			if options.has("team"):
				unit_tokens.append(str(options["team"]))
			return _run_editor_spawn_unit(ctrl, unit_tokens, 0)
		"gem":
			var gem_option_check := _editor_validate_option_keys(options, ["slot", "target"])
			if not gem_option_check.get("ok", false):
				return gem_option_check
			var gem_tokens: Array = [object_id, str(positionals[0])]
			if options.has("slot"):
				gem_tokens.append(str(options["slot"]))
			if options.has("target"):
				gem_tokens.append(str(options["target"]))
			return _run_editor_spawn_gem(ctrl, gem_tokens, 0)
		"tile":
			var tile_option_check := _editor_validate_option_keys(options, [])
			if not tile_option_check.get("ok", false):
				return tile_option_check
			return _run_editor_set_tile(ctrl, [str(positionals[0]), object_id], 0)
	return _fail("unsupported object id: %s" % object_id)


func _run_editor_spawn_many_command(ctrl, tokens: Array, start_index: int) -> Dictionary:
	if tokens.size() <= start_index:
		return _fail("missing unit id")
	var unit_def_id := str(tokens[start_index])
	if not _data_registry(ctrl).has_unit_def(unit_def_id):
		return _fail("spawn-many only supports unit ids: %s" % unit_def_id)
	var arg_parse := _editor_parse_cli_args(tokens, start_index + 1)
	if not arg_parse.get("ok", false):
		return arg_parse
	var positionals: Array = arg_parse.get("positionals", [])
	var options: Dictionary = arg_parse.get("options", {})
	if positionals.is_empty():
		return _fail("missing batch positions")
	var option_check := _editor_validate_option_keys(options, ["team"])
	if not option_check.get("ok", false):
		return option_check
	var batch_tokens: Array = [unit_def_id]
	if options.has("team"):
		batch_tokens.append(str(options["team"]))
	for pos_token in positionals:
		batch_tokens.append(str(pos_token))
	return _run_editor_batch_spawn_unit(ctrl, batch_tokens, 0)


func _run_editor_remove_command(ctrl, tokens: Array, start_index: int) -> Dictionary:
	if tokens.size() <= start_index:
		return _fail("missing remove target type")
	var noun := _normalize_editor_noun(tokens[start_index])
	match noun:
		"unit":
			return _run_editor_delete_unit(ctrl, tokens, start_index + 1)
		"gem":
			var arg_parse := _editor_parse_cli_args(tokens, start_index + 1)
			if not arg_parse.get("ok", false):
				return arg_parse
			var positionals: Array = arg_parse.get("positionals", [])
			var options: Dictionary = arg_parse.get("options", {})
			if positionals.is_empty():
				return _fail("missing position")
			if positionals.size() > 1:
				return _fail("remove gem accepts exactly one position")
			var option_check := _editor_validate_option_keys(options, ["slot", "target"])
			if not option_check.get("ok", false):
				return option_check
			var gem_tokens: Array = [str(positionals[0])]
			if options.has("slot"):
				gem_tokens.append(str(options["slot"]))
			if options.has("target"):
				gem_tokens.append(str(options["target"]))
			return _run_editor_delete_gem(ctrl, gem_tokens, 0)
		_:
			return _fail("remove only supports unit or gem")


func _run_editor_move_command(ctrl, tokens: Array, start_index: int) -> Dictionary:
	var move_start := start_index
	if tokens.size() > start_index:
		var noun := _normalize_editor_noun(tokens[start_index])
		if noun == "unit":
			move_start += 1
		elif not noun.is_empty():
			return _fail("move only supports units")
	return _run_editor_move_unit(ctrl, tokens, move_start)


func _run_editor_set_command(ctrl, tokens: Array, start_index: int) -> Dictionary:
	if tokens.size() <= start_index:
		return _fail("missing set target type")
	var noun := _normalize_editor_noun(tokens[start_index])
	match noun:
		"tile":
			return _run_editor_set_tile(ctrl, tokens, start_index + 1)
		"stat":
			return _run_editor_set_unit_stat(ctrl, tokens, start_index + 1)
		"player_spawn":
			return _run_editor_set_player_spawn(ctrl, tokens, start_index + 1)
		_:
			return _fail("set only supports tile, stat, or spawn")


func _run_editor_export_command(ctrl, tokens: Array, start_index: int) -> Dictionary:
	var export_start := start_index
	if tokens.size() > start_index and _normalize_editor_noun(tokens[start_index]) == "encounter":
		export_start += 1
	return _run_editor_export_encounter(ctrl, tokens, export_start)


func _run_editor_list_command(ctrl, tokens: Array, start_index: int = 1) -> Dictionary:
	if tokens.size() <= start_index:
		return _ok({
			"message": "Available catalogs: units, gems, tiles",
			"lines": ["list units", "list gems", "list tiles"],
		})
	var category := _normalize_editor_noun(tokens[start_index])
	var lines: Array[String] = []
	match category:
		"unit":
			lines.append("(string def_id)")
			for unit_def_id in _data_registry(ctrl).get_unit_def_ids():
				lines.append("  %s  %s" % [unit_def_id, _data_registry(ctrl).get_unit_display_name(unit_def_id)])
			return _ok({"message": "Unit definition ids (strings)", "lines": lines})
		"gem":
			lines.append("(string def_id)")
			for gem_id in _data_registry(ctrl).get_gem_ids():
				lines.append("  %s  %s" % [gem_id, _data_registry(ctrl).get_gem_display_name(gem_id)])
			return _ok({"message": "Gem definition ids (strings)", "lines": lines})
		"tile":
			lines.append("(string def_id)")
			for tile_id in _data_registry(ctrl).get_tile_ids():
				lines.append("  %s  %s" % [tile_id, _data_registry(ctrl).get_tile_display_name(tile_id)])
			return _ok({"message": "Tile definition ids (strings)", "lines": lines})
	return _fail("list only supports units, gems, or tiles")


# ═══════════════════════════════════════════════════════════════════════════
# Unit / gem / tile mutators
# ═══════════════════════════════════════════════════════════════════════════

func _run_editor_spawn_unit(ctrl, tokens: Array, start_index: int) -> Dictionary:
	if tokens.size() <= start_index:
		return _fail("missing unit id")
	var unit_def_id := str(tokens[start_index])
	if not _data_registry(ctrl).has_unit_def(unit_def_id):
		return _fail("unknown unit id: %s" % unit_def_id)
	var pos_parse := _editor_parse_pos(tokens, start_index + 1)
	if not pos_parse.get("ok", false):
		return pos_parse
	var pos: Vector2i = pos_parse.get("pos", Vector2i.ZERO)
	if not BoardUtils.in_bounds(ctrl.state, pos):
		return _fail("position out of bounds: %s" % pos)
	if ctrl.state.get_unit_at(pos) != null:
		return _fail("a live unit already exists at %s" % pos)
	var team := Constants.TEAM_ENEMY
	var next_index: int = int(pos_parse.get("next", start_index + 1))
	if tokens.size() > next_index:
		team = _normalize_editor_team(tokens[next_index])
		if team.is_empty():
			return _fail("unknown team: %s" % tokens[next_index])
	var unit_uid: String = _data_registry(ctrl).next_runtime_uid("runtime_unit")
	var unit := UnitState.from_def(unit_uid, unit_def_id, team, pos, _data_registry(ctrl).get_unit_def(unit_def_id))
	ctrl.state.register_unit(unit)
	TileRules.sync_standing_ground_effects(ctrl.state, unit)
	return _finalize_mutation(ctrl, "spawned %s at %s for team %s" % [unit_def_id, pos, team], false, {"unit_uid": unit_uid})


func _run_editor_delete_unit(ctrl, tokens: Array, start_index: int) -> Dictionary:
	var pos_parse := _editor_parse_pos(tokens, start_index)
	if not pos_parse.get("ok", false):
		return pos_parse
	var pos: Vector2i = pos_parse.get("pos", Vector2i.ZERO)
	var unit: UnitState = ctrl.state.get_unit_at(pos)
	if unit == null:
		return _fail("no live unit at %s" % pos)
	if unit.uid == ctrl.state.player_uid:
		return _fail("cannot remove the player; use `set spawn` instead")
	_clear_unit_gems(ctrl, unit)
	ctrl.state.unregister_unit(unit)
	if ctrl.selected_unit_uid == unit.uid:
		ctrl.selected_unit_uid = ctrl.state.player_uid
	return _finalize_mutation(ctrl, "removed unit %s at %s" % [unit.unit_def_id, pos])


func _run_editor_move_unit(ctrl, tokens: Array, start_index: int) -> Dictionary:
	var from_parse := _editor_parse_pos(tokens, start_index)
	if not from_parse.get("ok", false):
		return from_parse
	var next_index: int = int(from_parse.get("next", start_index))
	var to_parse := _editor_parse_pos(tokens, next_index)
	if not to_parse.get("ok", false):
		return to_parse
	var from_pos: Vector2i = from_parse.get("pos", Vector2i.ZERO)
	var to_pos: Vector2i = to_parse.get("pos", Vector2i.ZERO)
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
	return _finalize_mutation(ctrl, move_message)


func _run_editor_batch_spawn_unit(ctrl, tokens: Array, start_index: int) -> Dictionary:
	if tokens.size() <= start_index:
		return _fail("missing unit id")
	var unit_def_id := str(tokens[start_index])
	if not _data_registry(ctrl).has_unit_def(unit_def_id):
		return _fail("unknown unit id: %s" % unit_def_id)
	var next_index := start_index + 1
	var team := Constants.TEAM_ENEMY
	if tokens.size() > next_index:
		var maybe_team := _normalize_editor_team(tokens[next_index])
		if not maybe_team.is_empty():
			team = maybe_team
			next_index += 1
	var positions_parse := _editor_parse_batch_positions(tokens, next_index)
	if not positions_parse.get("ok", false):
		return positions_parse
	var positions: Array[Vector2i] = positions_parse.get("positions", [] as Array[Vector2i])
	var seen: Dictionary = {}
	for pos in positions:
		if not BoardUtils.in_bounds(ctrl.state, pos):
			return _fail("position out of bounds: %s" % pos)
		if ctrl.state.get_unit_at(pos) != null:
			return _fail("a live unit already exists at %s" % pos)
		var pos_key: String = ctrl.state.tile_key(pos)
		if seen.has(pos_key):
			return _fail("duplicate position in batch: %s" % pos)
		seen[pos_key] = true
	var created_uids: Array[String] = []
	for pos in positions:
		var unit_uid: String = _data_registry(ctrl).next_runtime_uid("runtime_unit")
		var unit := UnitState.from_def(unit_uid, unit_def_id, team, pos, _data_registry(ctrl).get_unit_def(unit_def_id))
		ctrl.state.register_unit(unit)
		created_uids.append(unit_uid)
	return _finalize_mutation(ctrl, "spawned %d instances of %s for team %s" % [created_uids.size(), unit_def_id, team], false, {"unit_uids": created_uids})


func _run_editor_set_tile(ctrl, tokens: Array, start_index: int) -> Dictionary:
	var pos_parse := _editor_parse_pos(tokens, start_index)
	if not pos_parse.get("ok", false):
		return pos_parse
	var next_index: int = int(pos_parse.get("next", start_index))
	if tokens.size() <= next_index:
		return _fail("missing tile id")
	var tile_id := str(tokens[next_index])
	if not _data_registry(ctrl).has_tile_id(tile_id):
		return _fail("unknown tile id: %s" % tile_id)
	var pos: Vector2i = pos_parse.get("pos", Vector2i.ZERO)
	if not BoardUtils.in_bounds(ctrl.state, pos):
		return _fail("position out of bounds: %s" % pos)
	var existing: TileState = ctrl.state.get_tile(pos)
	_clear_tile_gems(ctrl, existing)
	var slot_defs := _default_tile_slot_defs(tile_id)
	var tile := TileState.create(pos, tile_id) if slot_defs.is_empty() else TileState.create_with_slots(pos, tile_id, slot_defs)
	ctrl.state.tiles[ctrl.state.tile_key(pos)] = tile
	return _finalize_mutation(ctrl, "set tile at %s to %s" % [pos, tile_id], true)


func _run_editor_spawn_gem(ctrl, tokens: Array, start_index: int) -> Dictionary:
	if tokens.size() <= start_index:
		return _fail("missing gem id")
	var gem_id := str(tokens[start_index])
	if not _data_registry(ctrl).has_gem_def(gem_id):
		return _fail("unknown gem id: %s" % gem_id)
	var pos_parse := _editor_parse_pos(tokens, start_index + 1)
	if not pos_parse.get("ok", false):
		return pos_parse
	var pos: Vector2i = pos_parse.get("pos", Vector2i.ZERO)
	if not BoardUtils.in_bounds(ctrl.state, pos):
		return _fail("position out of bounds: %s" % pos)
	var next_index: int = int(pos_parse.get("next", start_index + 1))
	var preferred_slot := ""
	if tokens.size() > next_index:
		var maybe_slot := _normalize_editor_slot_type(tokens[next_index])
		if not maybe_slot.is_empty():
			preferred_slot = maybe_slot
			next_index += 1
	var target_kind := ""
	if tokens.size() > next_index:
		target_kind = _normalize_editor_target_kind(tokens[next_index])
		if target_kind.is_empty():
			return _fail("unknown gem target: %s" % tokens[next_index])
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
		slot_index = _find_editor_slot_index(unit.slots, preferred_slot)
		if slot_index < 0:
			return _fail("no available slot on unit at %s" % pos)
		slot = unit.get_slot_by_index(slot_index)
		target_label = "unit %s slot %s" % [unit.unit_def_id, _editor_slot_label(slot)]
	else:
		if tile == null or not tile.has_slots():
			return _fail("no slotted tile at %s" % pos)
		slot_index = _find_editor_slot_index(tile.slots, preferred_slot)
		if slot_index < 0:
			return _fail("no available slot on tile at %s" % pos)
		slot = tile.get_slot_by_index(slot_index)
		target_label = "tile %s slot %s" % [tile.tile_id, _editor_slot_label(slot)]
	_clear_slot_gem(ctrl, slot)
	var gem_uid: String = _data_registry(ctrl).next_runtime_uid("runtime_gem")
	var gem: GemState = _data_registry(ctrl).create_gem_instance(gem_uid, gem_id)
	if target_kind == "unit" and unit != null:
		gem.owner_uid = unit.uid
		gem.slot_index = slot_index
	else:
		gem.owner_uid = ""
		gem.slot_index = -1
	ctrl.state.gems[gem.uid] = gem
	slot.gem_uid = gem.uid
	return _finalize_mutation(ctrl, "spawned %s in %s" % [gem_id, target_label], false, {"gem_uid": gem.uid})


func _run_editor_delete_gem(ctrl, tokens: Array, start_index: int) -> Dictionary:
	var pos_parse := _editor_parse_pos(tokens, start_index)
	if not pos_parse.get("ok", false):
		return pos_parse
	var pos: Vector2i = pos_parse.get("pos", Vector2i.ZERO)
	if not BoardUtils.in_bounds(ctrl.state, pos):
		return _fail("position out of bounds: %s" % pos)
	var next_index: int = int(pos_parse.get("next", start_index))
	var preferred_slot := ""
	if tokens.size() > next_index:
		var maybe_slot := _normalize_editor_slot_type(tokens[next_index])
		if not maybe_slot.is_empty():
			preferred_slot = maybe_slot
			next_index += 1
	var target_kind := ""
	if tokens.size() > next_index:
		target_kind = _normalize_editor_target_kind(tokens[next_index])
		if target_kind.is_empty():
			return _fail("unknown gem target: %s" % tokens[next_index])
	var unit: UnitState = ctrl.state.get_unit_at(pos)
	var tile: TileState = ctrl.state.get_tile(pos)
	var slot_index := -1
	var slot: SlotState = null
	var target_label := ""
	if target_kind == "unit" or (target_kind.is_empty() and unit != null and _find_editor_filled_slot_index(unit.slots, preferred_slot) >= 0):
		if unit == null:
			return _fail("no unit at %s" % pos)
		slot_index = _find_editor_filled_slot_index(unit.slots, preferred_slot)
		if slot_index < 0:
			return _fail("no gem found on unit at %s" % pos)
		slot = unit.get_slot_by_index(slot_index)
		target_label = "unit %s slot %s" % [unit.unit_def_id, _editor_slot_label(slot)]
	else:
		if tile == null or not tile.has_slots():
			return _fail("no slotted tile at %s" % pos)
		slot_index = _find_editor_filled_slot_index(tile.slots, preferred_slot)
		if slot_index < 0:
			return _fail("no gem found on tile at %s" % pos)
		slot = tile.get_slot_by_index(slot_index)
		target_label = "tile %s slot %s" % [tile.tile_id, _editor_slot_label(slot)]
	var gem: GemState = ctrl.state.gems.get(slot.gem_uid, null)
	var gem_id := gem.gem_id if gem != null else "unknown_gem"
	_clear_slot_gem(ctrl, slot)
	return _finalize_mutation(ctrl, "removed %s from %s" % [gem_id, target_label])


func _run_editor_set_unit_stat(ctrl, tokens: Array, start_index: int) -> Dictionary:
	var pos_parse := _editor_parse_pos(tokens, start_index)
	if not pos_parse.get("ok", false):
		return pos_parse
	var next_index: int = int(pos_parse.get("next", start_index))
	if tokens.size() <= next_index + 1:
		return _fail("missing stat field or value")
	var pos: Vector2i = pos_parse.get("pos", Vector2i.ZERO)
	var unit: UnitState = ctrl.state.get_unit_at(pos)
	if unit == null:
		return _fail("no live unit at %s" % pos)
	var field := _normalize_editor_stat_field(tokens[next_index])
	if field.is_empty():
		return _fail("unsupported stat field: %s" % tokens[next_index])
	var raw_value := str(tokens[next_index + 1])
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
			var alive_parse := _editor_parse_bool(raw_value)
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
	return _finalize_mutation(ctrl, "set %s.%s = %s" % [unit.unit_def_id, field, raw_value])


func _run_editor_set_player_spawn(ctrl, tokens: Array, start_index: int) -> Dictionary:
	var pos_parse := _editor_parse_pos(tokens, start_index)
	if not pos_parse.get("ok", false):
		return pos_parse
	var pos: Vector2i = pos_parse.get("pos", Vector2i.ZERO)
	if not BoardUtils.in_bounds(ctrl.state, pos):
		return _fail("position out of bounds: %s" % pos)
	var player: UnitState = ctrl.state.get_player()
	if player == null:
		return _fail("player does not exist")
	var occupant: UnitState = ctrl.state.get_unit_at(pos)
	if occupant != null and occupant.uid != player.uid:
		return _fail("destination is occupied: %s" % pos)
	ctrl.state.move_unit(player, pos)
	return _finalize_mutation(ctrl, "set player spawn to %s" % pos)


func _run_editor_export_encounter(ctrl, tokens: Array, start_index: int) -> Dictionary:
	var encounter_id := "editor_export_%s" % ctrl.state.encounter_id
	if tokens.size() > start_index:
		encounter_id = str(tokens[start_index])
	var encounter := _build_editor_export_encounter(ctrl)
	return _ok({
		"message": "exported encounter %s" % encounter_id,
		"lines": _format_editor_export_encounter(ctrl, encounter_id, encounter),
		"encounter": encounter,
	})


# ═══════════════════════════════════════════════════════════════════════════
# Mutation finalizer
# ═══════════════════════════════════════════════════════════════════════════

func _finalize_mutation(ctrl, message: String, rebuild_tiles: bool = false, payload: Dictionary = {}) -> Dictionary:
	ctrl.state.log("[Editor CLI] %s" % message)
	if rebuild_tiles:
		_refresh_runtime_tile_visuals(ctrl)
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


func _refresh_runtime_tile_visuals(ctrl) -> void:
	for tile in ctrl.state.tiles.values():
		if tile.tile_id == Constants.TILE_FLOOR:
			tile.floor_variant = absi(hash(str(ctrl.state.run_seed, ":", tile.pos.x, ":", tile.pos.y))) % 3
		else:
			tile.floor_variant = 0
	BoardMapGenerator._compute_edge_masks(ctrl.state)


# ═══════════════════════════════════════════════════════════════════════════
# Export formatting
# ═══════════════════════════════════════════════════════════════════════════

func _build_editor_export_encounter(ctrl) -> Dictionary:
	var player: UnitState = ctrl.state.get_player()
	var enemies: Array[Dictionary] = []
	var tiles: Array[Dictionary] = []
	for unit in ctrl.state.units.values():
		if unit.uid == ctrl.state.player_uid or not unit.alive or unit.team != Constants.TEAM_ENEMY:
			continue
		var enemy_entry := {
			"def_id": unit.unit_def_id,
			"pos": unit.pos,
		}
		var slot_defs := _collect_editor_slot_entries(ctrl, unit.slots)
		if not slot_defs.is_empty():
			enemy_entry["slots"] = slot_defs
		enemies.append(enemy_entry)
	enemies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _compare_editor_positions(a.get("pos", Vector2i.ZERO), b.get("pos", Vector2i.ZERO))
	)
	for tile in ctrl.state.tiles.values():
		if tile.tile_id == Constants.TILE_FLOOR and not tile.has_slots():
			continue
		var tile_entry := {
			"pos": tile.pos,
			"tile_id": tile.tile_id,
		}
		var tile_slots := _collect_editor_slot_entries(ctrl, tile.slots)
		if not tile_slots.is_empty():
			tile_entry["slots"] = tile_slots
		tiles.append(tile_entry)
	tiles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _compare_editor_positions(a.get("pos", Vector2i.ZERO), b.get("pos", Vector2i.ZERO))
	)
	return {
		"player_spawn": player.pos if player != null else Vector2i.ZERO,
		"floor_seed": ctrl.state.run_seed,
		"enemies": enemies,
		"tiles": tiles,
	}


func _format_editor_export_encounter(ctrl, encounter_id: String, encounter: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	lines.append("\"%s\": {" % encounter_id)
	lines.append("\t\"player_spawn\": %s," % _format_editor_vector2i(encounter.get("player_spawn", Vector2i.ZERO)))
	lines.append("\t\"floor_seed\": %d," % int(encounter.get("floor_seed", ctrl.state.run_seed)))
	lines.append("\t\"enemies\": [")
	var enemies: Array = encounter.get("enemies", [])
	for i in range(enemies.size()):
		lines.append("\t\t%s%s" % [_format_editor_export_enemy_line(enemies[i]), "," if i < enemies.size() - 1 else ""])
	lines.append("\t],")
	lines.append("\t\"tiles\": [")
	var enc_tiles: Array = encounter.get("tiles", [])
	for i in range(enc_tiles.size()):
		lines.append("\t\t%s%s" % [_format_editor_export_tile_line(enc_tiles[i]), "," if i < enc_tiles.size() - 1 else ""])
	lines.append("\t]")
	lines.append("},")
	return lines


func _format_editor_export_enemy_line(enemy: Dictionary) -> String:
	var parts: Array[String] = [
		"\"def_id\": \"%s\"" % str(enemy.get("def_id", "")),
		"\"pos\": %s" % _format_editor_vector2i(enemy.get("pos", Vector2i.ZERO)),
	]
	var slots: Array = enemy.get("slots", [])
	if not slots.is_empty():
		parts.append("\"slots\": %s" % _format_editor_slot_entries_inline(slots))
	return "{%s}" % ", ".join(parts)


func _format_editor_export_tile_line(tile_entry: Dictionary) -> String:
	var parts: Array[String] = [
		"\"pos\": %s" % _format_editor_vector2i(tile_entry.get("pos", Vector2i.ZERO)),
		"\"tile_id\": \"%s\"" % str(tile_entry.get("tile_id", Constants.TILE_FLOOR)),
	]
	var slots: Array = tile_entry.get("slots", [])
	if not slots.is_empty():
		parts.append("\"slots\": %s" % _format_editor_slot_entries_inline(slots))
	return "{%s}" % ", ".join(parts)


func _format_editor_slot_entries_inline(slot_entries: Array) -> String:
	var parts: Array[String] = []
	for entry in slot_entries:
		var fields: Array[String] = ["\"slot_type\": \"%s\"" % str(entry.get("slot_type", ""))]
		if entry.has("gem_id"):
			fields.append("\"gem_id\": \"%s\"" % str(entry.get("gem_id", "")))
		if entry.has("gem_overrides"):
			fields.append("\"gem_overrides\": %s" % var_to_str(entry.get("gem_overrides", {})))
		if bool(entry.get("locked", false)):
			fields.append("\"locked\": true")
		if entry.has("lock_type") and not str(entry.get("lock_type", "")).is_empty():
			fields.append("\"lock_type\": \"%s\"" % str(entry.get("lock_type", "")))
		parts.append("{%s}" % ", ".join(fields))
	return "[%s]" % ", ".join(parts)


func _format_editor_vector2i(value: Variant) -> String:
	var pos: Vector2i = value
	return "Vector2i(%d, %d)" % [pos.x, pos.y]


func _compare_editor_positions(a: Vector2i, b: Vector2i) -> bool:
	if a.y == b.y:
		return a.x < b.x
	return a.y < b.y


func _collect_editor_slot_entries(ctrl, slots: Array) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for slot in slots:
		var slot_entry := {
			"slot_type": slot.slot_type,
		}
		if bool(slot.locked):
			slot_entry["locked"] = true
		if not str(slot.lock_type).is_empty():
			slot_entry["lock_type"] = slot.lock_type
		if not slot.gem_uid.is_empty():
			var gem: GemState = ctrl.state.gems.get(slot.gem_uid, null)
			if gem != null:
				slot_entry["gem_id"] = gem.gem_id
				if not gem.def_overrides.is_empty():
					slot_entry["gem_overrides"] = gem.def_overrides.duplicate(true)
		if slot_entry.size() > 1:
			entries.append(slot_entry)
	return entries


# ═══════════════════════════════════════════════════════════════════════════
# Gem / slot cleanup helpers
# ═══════════════════════════════════════════════════════════════════════════

func _clear_tile_gems(ctrl, tile: TileState) -> void:
	if tile == null:
		return
	for slot in tile.slots:
		_clear_slot_gem(ctrl, slot)


func _clear_unit_gems(ctrl, unit: UnitState) -> void:
	if unit == null:
		return
	for slot in unit.slots:
		_clear_slot_gem(ctrl, slot)


func _clear_slot_gem(ctrl, slot: SlotState) -> void:
	if slot == null or slot.gem_uid.is_empty():
		return
	if ctrl.state.held_gem_uid == slot.gem_uid:
		ctrl.state.held_gem_uid = ""
	ctrl.state.gems.erase(slot.gem_uid)
	slot.gem_uid = ""


func _default_tile_slot_defs(tile_id: String) -> Array:
	match tile_id:
		Constants.TILE_PILLAR:
			return [{"slot_type": Constants.SLOT_BLUE}]
		_:
			return []


# ═══════════════════════════════════════════════════════════════════════════
# Slot search helpers
# ═══════════════════════════════════════════════════════════════════════════

func _editor_slot_label(slot: SlotState) -> String:
	match slot.slot_type:
		Constants.SLOT_RED:
			return "red"
		Constants.SLOT_BLUE:
			return "blue"
		Constants.SLOT_BLACK:
			return "black"
	return "unknown"


func _find_editor_slot_index(slots: Array, preferred_slot_type: String = "") -> int:
	var fallback := -1
	for i in range(slots.size()):
		var slot: SlotState = slots[i]
		if not preferred_slot_type.is_empty() and slot.slot_type != preferred_slot_type:
			continue
		if slot.gem_uid.is_empty():
			return i
		if fallback < 0:
			fallback = i
	return fallback


func _find_editor_filled_slot_index(slots: Array, preferred_slot_type: String = "") -> int:
	for i in range(slots.size()):
		var slot: SlotState = slots[i]
		if not preferred_slot_type.is_empty() and slot.slot_type != preferred_slot_type:
			continue
		if not slot.gem_uid.is_empty():
			return i
	return -1


# ═══════════════════════════════════════════════════════════════════════════
# Argument parsing
# ═══════════════════════════════════════════════════════════════════════════

func _editor_parse_batch_positions(tokens: Array, start_index: int) -> Dictionary:
	if tokens.size() <= start_index:
		return _fail("missing batch positions; use x,y x,y ...")
	var positions: Array[Vector2i] = []
	for i in range(start_index, tokens.size()):
		var pos_parse := _editor_parse_single_pos_token(str(tokens[i]))
		if not pos_parse.get("ok", false):
			return _fail("batch positions must use x,y format: %s" % tokens[i])
		positions.append(pos_parse.get("pos", Vector2i.ZERO))
	return _ok({"positions": positions})


func _editor_parse_cli_args(tokens: Array, start_index: int) -> Dictionary:
	var positionals: Array[String] = []
	var options := {}
	var index := start_index
	while index < tokens.size():
		var token := str(tokens[index])
		if token.begins_with("--"):
			var option_key := token.trim_prefix("--").replace("-", "_")
			if option_key.is_empty():
				return _fail("invalid option: %s" % token)
			if index + 1 >= tokens.size():
				return _fail("missing option value for %s" % token)
			options[option_key] = str(tokens[index + 1])
			index += 2
			continue
		positionals.append(token)
		index += 1
	return _ok({
		"positionals": positionals,
		"options": options,
	})


func _editor_validate_option_keys(options: Dictionary, allowed_keys: Array[String]) -> Dictionary:
	for key in options.keys():
		var option_key := str(key)
		if not allowed_keys.has(option_key):
			return _fail("unsupported option: --%s" % option_key.replace("_", "-"))
	return _ok()


func _editor_object_kind_from_id(ctrl, object_id: String) -> String:
	if _data_registry(ctrl).has_unit_def(object_id):
		return "unit"
	if _data_registry(ctrl).has_gem_def(object_id):
		return "gem"
	if _data_registry(ctrl).has_tile_id(object_id):
		return "tile"
	return ""


func _editor_parse_single_pos_token(token: String) -> Dictionary:
	if not token.contains(","):
		return _fail("position format must be x,y")
	var parts := token.split(",", false)
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return _fail("position format must be x,y")
	return _ok({"pos": Vector2i(int(parts[0]), int(parts[1]))})


func _editor_parse_pos(tokens: Array, start_index: int) -> Dictionary:
	if tokens.size() <= start_index:
		return _fail("missing position")
	var first := str(tokens[start_index])
	if first.contains(","):
		var parts := first.split(",", false)
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
			return _fail("position format must be x,y or x y")
		return _ok({
			"pos": Vector2i(int(parts[0]), int(parts[1])),
			"next": start_index + 1,
		})
	if tokens.size() <= start_index + 1:
		return _fail("position format must be x,y or x y")
	var second := str(tokens[start_index + 1])
	if not first.is_valid_int() or not second.is_valid_int():
		return _fail("position coordinates must be integers")
	return _ok({
		"pos": Vector2i(int(first), int(second)),
		"next": start_index + 2,
	})


func _editor_parse_bool(raw_value: String) -> Dictionary:
	var lowered := raw_value.to_lower()
	if lowered in ["true", "1", "yes", "on"]:
		return _ok({"value": true})
	if lowered in ["false", "0", "no", "off"]:
		return _ok({"value": false})
	return _fail("invalid bool")


func _editor_tokens(raw_command: String) -> Array[String]:
	var normalized := raw_command.strip_edges()
	normalized = normalized.replace("\t", " ")
	while normalized.contains("  "):
		normalized = normalized.replace("  ", " ")
	var tokens: Array[String] = []
	for token in normalized.split(" ", false):
		var value := String(token).strip_edges()
		if value.begins_with("/"):
			value = value.substr(1)
		if value.is_empty():
			continue
		if _is_editor_filler_token(value):
			continue
		tokens.append(value)
	return tokens


func _is_editor_filler_token(token: String) -> bool:
	return token.to_lower() in ["at", "to", "into", "on"]


# ═══════════════════════════════════════════════════════════════════════════
# Normalization helpers
# ═══════════════════════════════════════════════════════════════════════════

func _normalize_editor_command(token: String) -> String:
	var lowered := token.to_lower()
	match lowered:
		"help", "?":
			return "help"
		"list", "ls":
			return "list"
		"spawn", "create":
			return "spawn"
		"spawn_many", "spawn-many":
			return "spawn_many"
		"set":
			return "set"
		"remove", "delete":
			return "remove"
		"move":
			return "move"
		"export", "save":
			return "export"
	return lowered


func _normalize_editor_noun(token: String) -> String:
	var lowered := token.to_lower()
	match lowered:
		"unit", "units", "monster", "monsters", "enemy", "enemies":
			return "unit"
		"gem", "gems":
			return "gem"
		"tile", "tiles", "cell", "cells":
			return "tile"
		"stat", "stats", "attr", "attribute":
			return "stat"
		"player_spawn", "spawn", "spawn_point":
			return "player_spawn"
		"encounter", "level", "map":
			return "encounter"
	return ""


func _normalize_editor_slot_type(token: String) -> String:
	var lowered := token.to_lower()
	match lowered:
		"red", "r":
			return Constants.SLOT_RED
		"blue", "b":
			return Constants.SLOT_BLUE
		"black", "k":
			return Constants.SLOT_BLACK
	return ""


func _normalize_editor_target_kind(token: String) -> String:
	var lowered := token.to_lower()
	match lowered:
		"unit", "monster", "enemy":
			return "unit"
		"tile", "cell":
			return "tile"
	return ""


func _normalize_editor_team(token: String) -> String:
	var lowered := token.to_lower()
	match lowered:
		"enemy", "monster":
			return Constants.TEAM_ENEMY
		"player", "ally":
			return Constants.TEAM_PLAYER
	return ""


func _normalize_editor_stat_field(token: String) -> String:
	var lowered := token.to_lower()
	match lowered:
		"hp":
			return "hp"
		"max_hp", "maxhp":
			return "max_hp"
		"move_points", "move":
			return "move_points"
		"speed", "spd":
			return "speed"
		"base_attack", "attack", "atk":
			return "base_attack"
		"armor", "def":
			return "armor"
		"alive":
			return "alive"
	return ""


func _editor_help_lines() -> Array[String]:
	return [
		"Editor CLI (F9)",
		"Commands start with /. Bare names like help still work.",
		"IDs are string resource keys (unit_bomb_rat, gem_poison, tile_water), not numeric.",
		"Runtime unit_uid / gem_uid are also strings; list only shows definition ids.",
		"",
		"Catalogs:",
		"  /list units                Show spawnable unit ids",
		"  /list gems                 Show spawnable gem ids",
		"  /list tiles                Show placeable tile ids",
		"",
		"Commands:",
		"  /spawn <object_id> <pos> [--team enemy|player]",
		"    - object_id can be a unit id, gem id, or tile id",
		"    - units spawn on the board; gems auto-detect unit/tile unless overridden",
		"    - example: /spawn unit_bomb_rat 2,4 --team enemy",
		"    - example: /spawn gem_poison 2,4 --slot red --target tile",
		"    - example: /spawn tile_pillar 4,4",
		"  /spawn-many <unit_id> <pos> <pos> ... [--team enemy|player]",
		"    - example: /spawn-many unit_patrol_guard 0,0 1,0 2,0 --team enemy",
		"  /move [unit] <from_pos> <to_pos>",
		"    - example: /move 2,4 3,4",
		"  /remove unit <pos>",
		"    - example: /remove unit 3,4",
		"  /remove gem <pos> [--slot red|blue|black] [--target unit|tile]",
		"    - example: /remove gem 2,4 --slot red --target unit",
		"  /set tile <pos> <tile_id>",
		"    - example: /set tile 4,4 tile_water",
		"  /set stat <pos> <field> <value>",
		"    - supported fields: hp, max_hp, move_points, speed, base_attack, armor, alive",
		"    - example: /set stat 2,4 hp 12",
		"  /set spawn <pos>",
		"    - example: /set spawn 1,6",
		"  /export [encounter] [encounter_id]",
		"    - example: /export encounter custom_level_001",
	]


# ═══════════════════════════════════════════════════════════════════════════
# Utilities
# ═══════════════════════════════════════════════════════════════════════════

func _data_registry(ctrl) -> Node:
	return Engine.get_main_loop().root.get_node("DataRegistry")


func _ok(payload: Dictionary = {}) -> Dictionary:
	payload["ok"] = true
	return payload


func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
