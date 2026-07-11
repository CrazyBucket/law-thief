class_name SplitShotRules
extends RefCounted

## 分裂射击：瞄准格 = 点击/悬停格（V 顶点）；两翼由 8 方向 LUT 相对瞄准格偏移

const DIR8: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(1, 1),
	Vector2i(0, 1),
	Vector2i(-1, 1),
	Vector2i(-1, 0),
	Vector2i(-1, -1),
	Vector2i(0, -1),
	Vector2i(1, -1),
]

const WING_OFFSETS_LUT := {
	Vector2i(1, 0): [Vector2i(-1, 1), Vector2i(-1, -1)],
	Vector2i(1, 1): [Vector2i(-1, 0), Vector2i(0, -1)],
	Vector2i(0, 1): [Vector2i(1, -1), Vector2i(-1, -1)],
	Vector2i(-1, 1): [Vector2i(0, -1), Vector2i(1, 0)],
	Vector2i(-1, 0): [Vector2i(1, -1), Vector2i(1, 1)],
	Vector2i(-1, -1): [Vector2i(1, 0), Vector2i(0, 1)],
	Vector2i(0, -1): [Vector2i(-1, 1), Vector2i(1, 1)],
	Vector2i(1, -1): [Vector2i(0, 1), Vector2i(-1, 0)],
}


static func is_inside_board(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x < Constants.BOARD_SIZE.x and pos.y < Constants.BOARD_SIZE.y


static func compute_forward_step(origin_pos: Vector2i, aim_pos: Vector2i) -> Vector2i:
	var delta := aim_pos - origin_pos
	if delta == Vector2i.ZERO:
		return Vector2i(1, 0)
	var angle := Vector2(delta).angle()
	var snapped_idx := int(round(angle / (PI / 4.0))) % 8
	if snapped_idx < 0:
		snapped_idx += 8
	return DIR8[snapped_idx]


static func compute_shot(origin_pos: Vector2i, aim_pos: Vector2i, shot_level: int = 1) -> Dictionary:
	if origin_pos == aim_pos:
		return {
			"main": aim_pos,
			"wings": [] as Array[Vector2i],
		}
	var forward := compute_forward_step(origin_pos, aim_pos)
	var offsets: Array = WING_OFFSETS_LUT.get(forward, [Vector2i.ZERO, Vector2i.ZERO]).duplicate()
	if shot_level >= 2:
		offsets.append(-forward)
	if shot_level >= 3:
		offsets.append(forward)
	var valid_wings: Array[Vector2i] = []
	for offset in offsets:
		var wing_pos: Vector2i = aim_pos + offset
		if is_inside_board(wing_pos):
			valid_wings.append(wing_pos)
	return {
		"main": aim_pos,
		"forward": forward,
		"wings": valid_wings,
	}


static func all_hit_cells(origin_pos: Vector2i, aim_pos: Vector2i, forbidden: Array = [], shot_level: int = 1) -> Array[Vector2i]:
	var shot := compute_shot(origin_pos, aim_pos, shot_level)
	var cells: Array[Vector2i] = []
	if is_inside_board(shot.main) and not is_blocked_cell(shot.main, origin_pos, forbidden):
		cells.append(shot.main)
	for wing in shot.wings:
		if wing in cells:
			continue
		if is_blocked_cell(wing, origin_pos, forbidden):
			continue
		cells.append(wing)
	return cells


static func wing_cells(origin_pos: Vector2i, aim_pos: Vector2i, forbidden: Array = [], shot_level: int = 1) -> Array[Vector2i]:
	var shot := compute_shot(origin_pos, aim_pos, shot_level)
	var result: Array[Vector2i] = []
	for wing in shot.wings:
		if is_blocked_cell(wing, origin_pos, forbidden):
			continue
		result.append(wing)
	return result


static func is_blocked_cell(cell: Vector2i, origin_pos: Vector2i, forbidden: Array = []) -> bool:
	if cell == origin_pos:
		return true
	for blocked in forbidden:
		if cell == blocked:
			return true
	return false


static func resolve_shot(attacker: UnitState, aim_cell: Vector2i, shot_level: int = 1) -> Dictionary:
	var origin := attacker_origin(attacker, aim_cell)
	var forbidden := attacker.occupied_cells()
	return {
		"origin": origin,
		"aim": aim_cell,
		"cells": all_hit_cells(origin, aim_cell, forbidden, shot_level),
	}


static func attacker_origin(attacker: UnitState, aim_pos: Vector2i) -> Vector2i:
	if attacker.footprint_size == Vector2i(1, 1):
		return attacker.pos
	var best := attacker.pos
	var best_dist := 999999
	for cell in attacker.occupied_cells():
		var d := BoardUtils.chebyshev(cell, aim_pos)
		if d < best_dist:
			best_dist = d
			best = cell
	return best


static func aim_pos_for_cell(_state: GameState, _attacker_pos: Vector2i, cell: Vector2i) -> Vector2i:
	return cell


static func aim_pos_for_target(_attacker_pos: Vector2i, target: UnitState) -> Vector2i:
	return aim_pos_for_cell(null, _attacker_pos, target.pos)


static func forward_step(origin_pos: Vector2i, aim_pos: Vector2i) -> Vector2i:
	return compute_forward_step(origin_pos, aim_pos)
