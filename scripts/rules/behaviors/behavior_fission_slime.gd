extends EnemyBehavior

const FissionSlimeRules = preload("res://scripts/rules/fission_slime_rules.gd")


static func compute_intent(state: GameState, unit: UnitState, cell_blockers: Dictionary = {}) -> IntentState:
	return FissionSlimeRules.compute_intent(state, unit, cell_blockers)


static func execute_custom_intent(
	state: GameState,
	unit: UnitState,
	intent: IntentState,
	_move_start_pos: Vector2i
) -> Dictionary:
	if intent.type == "slam_attack":
		return {
			"handled": true,
			"events": FissionSlimeRules.execute_slam(state, unit, intent),
		}
	return EnemyBehavior.execute_custom_intent(state, unit, intent, _move_start_pos)


static func split_clone_ratio(unit: UnitState) -> float:
	return FissionSlimeRules.split_stat_ratio(unit)


static func should_trigger_split_blue(unit: UnitState, reason: String) -> bool:
	return FissionSlimeRules.should_trigger_split_blue(unit, reason)
