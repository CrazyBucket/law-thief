extends EnemyBehavior

const RollingArmadilloRules = preload("res://scripts/rules/rolling_armadillo_rules.gd")


static func compute_intent(state: GameState, unit: UnitState, cell_blockers: Dictionary = {}) -> IntentState:
	return RollingArmadilloRules.compute_intent(state, unit, cell_blockers)


static func execute_custom_intent(
	state: GameState,
	unit: UnitState,
	intent: IntentState,
	_move_start_pos: Vector2i
) -> Dictionary:
	if intent.type != "rolling_uncontrolled":
		return EnemyBehavior.execute_custom_intent(state, unit, intent, _move_start_pos)
	return {
		"handled": true,
		"events": RollingArmadilloRules.execute_uncontrolled_roll(state, unit, intent),
	}


static func on_gem_extracted(state: GameState, unit: UnitState, slot_type: String, gem_uid: String) -> void:
	if unit.team != Constants.TEAM_ENEMY or slot_type != Constants.SLOT_RED:
		return
	var gem: GemState = state.gems.get(gem_uid, null)
	if gem != null and gem.gem_id == Constants.GEM_IMPACT:
		RollingArmadilloRules.enter_lawless(state, unit, gem_uid)


static func on_gem_inserted(state: GameState, unit: UnitState, gem_uid: String) -> void:
	if not StatusRules.is_lawless(unit):
		return
	var red_slot := unit.get_slot(Constants.SLOT_RED)
	var gem: GemState = state.gems.get(gem_uid, null)
	if red_slot != null and red_slot.gem_uid == gem_uid and gem != null and gem.gem_id == Constants.GEM_IMPACT:
		RollingArmadilloRules.recover_order(unit)
