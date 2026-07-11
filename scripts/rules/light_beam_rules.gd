class_name LightBeamRules
extends RefCounted

const SplitShotRules = preload("res://scripts/rules/split_shot_rules.gd")


static func compute_paths(
	state: GameState,
	attacker: UnitState,
	anchor: Vector2i,
	aim_cell: Vector2i,
	gem_ctx: Dictionary,
	use_split_shot: bool = false
) -> Array[Dictionary]:
	var paths: Array[Dictionary] = []
	var from_cell := BoardUtils.projectile_origin_cell_at(attacker, anchor, aim_cell)
	var aim_cells: Array[Vector2i] = [aim_cell]
	if use_split_shot:
		aim_cells = _split_aim_cells(state, from_cell, aim_cell, gem_ctx)
	var light_level := maxi(1, GemTagResolver.tag_level(gem_ctx, "light"))
	var level_def: Dictionary = _data_registry().get_gem_effect_level_def(
		"light", Constants.SLOT_RED, light_level
	)
	var pierce_blockers := bool(level_def["pierce_blockers"])
	for resolved_aim in aim_cells:
		var cells := _beam_cells(state, from_cell, resolved_aim, pierce_blockers)
		if cells.is_empty():
			continue
		paths.append({
			"from": from_cell,
			"aim": resolved_aim,
			"cells": cells,
		})
	return paths


static func _split_aim_cells(
	state: GameState,
	from_cell: Vector2i,
	aim_cell: Vector2i,
	gem_ctx: Dictionary
) -> Array[Vector2i]:
	var forward := SplitShotRules.forward_step(from_cell, aim_cell)
	var split_level := maxi(1, GemTagResolver.tag_level(gem_ctx, "split"))
	var aim_cells: Array[Vector2i] = []
	for direction in _split_directions(forward, split_level):
		var resolved_aim := from_cell + direction
		if BoardUtils.in_bounds(state, resolved_aim):
			aim_cells.append(resolved_aim)
	if aim_cells.is_empty():
		aim_cells.append(aim_cell)
	return aim_cells


static func _split_directions(forward: Vector2i, split_level: int) -> Array[Vector2i]:
	var directions: Array[Vector2i] = []
	var dir_index := SplitShotRules.DIR8.find(forward)
	if dir_index < 0:
		return [forward] as Array[Vector2i]
	var level_def: Dictionary = _data_registry().get_gem_effect_level_def(
		"split", Constants.SLOT_RED, split_level
	)
	for offset in _int_array(level_def["light_direction_offsets"]):
		var index := (dir_index + offset + SplitShotRules.DIR8.size()) % SplitShotRules.DIR8.size()
		var direction: Vector2i = SplitShotRules.DIR8[index]
		if direction not in directions:
			directions.append(direction)
	return directions


static func _beam_cells(
	state: GameState,
	from_cell: Vector2i,
	aim_cell: Vector2i,
	pierce_blockers: bool
) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var step := Vector2i(signi(aim_cell.x - from_cell.x), signi(aim_cell.y - from_cell.y))
	if step == Vector2i.ZERO:
		return cells
	var current := from_cell + step
	while BoardUtils.in_bounds(state, current):
		cells.append(current)
		var entity := state.get_entity_at(current)
		if not pierce_blockers and entity != null and entity.alive and entity.blocks_projectile():
			break
		current += step
	return cells


static func _int_array(raw: Variant) -> Array[int]:
	var values: Array[int] = []
	if raw is Array:
		for entry in raw:
			values.append(int(entry))
	return values


static func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node("DataRegistry")
