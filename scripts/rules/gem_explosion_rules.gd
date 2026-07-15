class_name GemExplosionRules
extends RefCounted

const BoardUtils = preload("res://scripts/rules/board_utils.gd")
const CombatConfig = preload("res://scripts/core/combat_config.gd")


static func cross_cells(center: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [center]
	for neighbor in BoardUtils.neighbors4(center):
		cells.append(neighbor)
	return cells


static func blast_pattern(level_def: Dictionary) -> String:
	return str(level_def.get("blast_pattern", "cross"))


static func uses_square_blast(level_def: Dictionary) -> bool:
	return blast_pattern(level_def) == "square"


static func damage_multiplier(level_def: Dictionary) -> float:
	return float(level_def.get("damage_multiplier", 1.0))


static func scaled_damage(base_damage: int, level_def: Dictionary) -> int:
	return maxi(1, int(float(base_damage) * damage_multiplier(level_def)))


static func red_blast_cells(center: Vector2i, level_def: Dictionary) -> Array[Vector2i]:
	if uses_square_blast(level_def):
		return BoardUtils.cells_in_radius(center, CombatConfig.explosion_radius())
	return cross_cells(center)


static func resolve_center(fallback: Vector2i, aim_cell: Variant = null) -> Vector2i:
	if aim_cell is Vector2i:
		return aim_cell
	return fallback
