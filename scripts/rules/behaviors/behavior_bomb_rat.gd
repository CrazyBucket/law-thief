extends EnemyBehavior

const BombRatRules = preload("res://scripts/rules/bomb_rat_rules.gd")


static func compute_intent(state: GameState, unit: UnitState, cell_blockers: Dictionary = {}) -> IntentState:
	if StatusRules.is_lawless(unit):
		return BombRatRules.compute_lawless_intent(state, unit, cell_blockers)
	return BombRatRules.compute_intent(state, unit, cell_blockers)


static func supports_priority_target_intent() -> bool:
	return false


static func execute_custom_intent(
	state: GameState,
	unit: UnitState,
	intent: IntentState,
	_move_start_pos: Vector2i
) -> Dictionary:
	match intent.type:
		"black_suicide":
			if intent.path.is_empty():
				var suicide_target: UnitState = state.units.get(intent.target_uid, null)
				if suicide_target != null:
					unit.facing = UnitState.facing_from_unit_to_cell(unit, suicide_target.pos)
			return {
				"handled": true,
				"events": BombRatRules.execute_black_suicide(state, unit),
			}
		"bomb_rat_plunder_wait":
			BombRatRules.execute_plunder_wait(unit)
			return {
				"handled": true,
				"events": [] as Array[Dictionary],
			}
		"bomb_rat_plunder_steal":
			return {
				"handled": true,
				"events": BombRatRules.execute_plunder_steal(state, unit, intent),
			}
		_:
			return EnemyBehavior.execute_custom_intent(state, unit, intent, _move_start_pos)


static func on_gem_extracted(state: GameState, unit: UnitState, slot_type: String, gem_uid: String) -> void:
	EnemyBehavior.on_gem_extracted(state, unit, slot_type, gem_uid)
	BombRatRules.sync_plunder_state(state, unit)


static func on_gem_inserted(state: GameState, unit: UnitState, gem_uid: String) -> void:
	EnemyBehavior.on_gem_inserted(state, unit, gem_uid)
	BombRatRules.sync_plunder_state(state, unit)
