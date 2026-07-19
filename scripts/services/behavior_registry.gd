class_name BehaviorRegistry
extends RefCounted

const _DEFAULT_BEHAVIOR_ID := "generic_melee"
const _MAP := {
	"generic_melee": preload("res://scripts/rules/behaviors/behavior_generic_melee.gd"),
	"bomb_rat": preload("res://scripts/rules/behaviors/behavior_bomb_rat.gd"),
	"patrol_guard": preload("res://scripts/rules/behaviors/behavior_patrol_guard.gd"),
	"stone_bow_guard": preload("res://scripts/rules/behaviors/behavior_stone_bow_guard.gd"),
	"fission_slime": preload("res://scripts/rules/behaviors/behavior_fission_slime.gd"),
	"law_worm": preload("res://scripts/rules/behaviors/behavior_law_worm.gd"),
	"broodmother": preload("res://scripts/rules/behaviors/behavior_broodmother.gd"),
	"ruffled_crow": preload("res://scripts/rules/behaviors/behavior_ruffled_crow.gd"),
	"rolling_armadillo": preload("res://scripts/rules/behaviors/behavior_rolling_armadillo.gd"),
	"training_dummy": preload("res://scripts/rules/behaviors/behavior_training_dummy.gd"),
}


static func get_behavior(behavior_id: String) -> GDScript:
	if _MAP.has(behavior_id):
		return _MAP[behavior_id]
	return _MAP[_DEFAULT_BEHAVIOR_ID]


static func get_behavior_ids() -> Array[String]:
	var ids: Array[String] = []
	for behavior_id in _MAP.keys():
		ids.append(str(behavior_id))
	ids.sort()
	return ids
