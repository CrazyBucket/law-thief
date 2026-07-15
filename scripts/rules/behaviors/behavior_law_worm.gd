extends EnemyBehavior

const LawWormRules = preload("res://scripts/rules/law_worm_rules.gd")


static func compute_intent(state: GameState, unit: UnitState, cell_blockers: Dictionary = {}) -> IntentState:
	return LawWormRules.compute_law_worm_intent(state, unit, cell_blockers)


static func execute_custom_intent(
	state: GameState,
	unit: UnitState,
	intent: IntentState,
	_move_start_pos: Vector2i
) -> Dictionary:
	return LawWormRules.execute_law_worm_intent(state, unit, intent)


static func on_gem_extracted(_state: GameState, _unit: UnitState, _slot_type: String, _gem_uid: String) -> void:
	pass


static func on_gem_inserted(_state: GameState, _unit: UnitState, _gem_uid: String) -> void:
	pass
