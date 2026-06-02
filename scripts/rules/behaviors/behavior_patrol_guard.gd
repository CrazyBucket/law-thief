extends EnemyBehavior

const PatrolGuardRules = preload("res://scripts/rules/patrol_guard_rules.gd")


static func compute_intent(state: GameState, unit: UnitState, cell_blockers: Dictionary = {}) -> IntentState:
	if StatusRules.is_lawless(unit):
		return build_lawless_intent(state, unit, cell_blockers)
	return build_normal_intent(state, unit, cell_blockers)


static func build_normal_intent(state: GameState, unit: UnitState, cell_blockers: Dictionary = {}) -> IntentState:
	return EnemyBehavior.build_normal_intent(state, unit, cell_blockers)


static func build_lawless_intent(state: GameState, unit: UnitState, cell_blockers: Dictionary = {}) -> IntentState:
	var saved_mp: int = unit.move_points
	unit.move_points = PatrolGuardRules.rampage_move_points(unit)
	var decision: Dictionary = EnemyBehavior.run_ai_decide(state, unit, cell_blockers)
	unit.move_points = saved_mp
	var intent: IntentState = IntentSystem.enemy_intent_from_decision(state, unit, decision, cell_blockers)
	if intent.type != "wait":
		intent.preview_text = "暴走·%s" % intent.preview_text
	return intent


static func on_gem_extracted(state: GameState, unit: UnitState, slot_type: String, gem_uid: String) -> void:
	if unit.team != Constants.TEAM_ENEMY or unit_has_any_gem(unit):
		return
	PatrolGuardRules.on_red_gem_stolen(state, unit, gem_uid)


static func on_gem_inserted(_state: GameState, unit: UnitState, gem_uid: String) -> void:
	if StatusRules.is_lawless(unit) and StatusRules.get_lawless_gem_uid(unit) == gem_uid:
		PatrolGuardRules.on_lawless_recovered(unit)
		StatusRules.clear_lawless(unit)


static func on_red_gem_stolen(state: GameState, unit: UnitState, gem_uid: String) -> void:
	PatrolGuardRules.on_red_gem_stolen(state, unit, gem_uid)


static func on_lawless_recovered(unit: UnitState) -> void:
	PatrolGuardRules.on_lawless_recovered(unit)


static func build_melee_intent(state: GameState, unit: UnitState, move_path: Array[Vector2i], intent: IntentState) -> void:
	var target_pos := _target_pos(state, intent.target_uid)
	intent.damage = PatrolGuardRules.melee_damage_preview(state, unit, unit.pos, move_path, target_pos)
	var bonus: int = PatrolGuardRules.charge_bonus(state, unit, unit.pos, move_path)
	var label := "冲锋" if bonus > 0 else "近战"
	intent.preview_text = "%s攻击 (%d)" % [label, intent.damage]


static func melee_charge_bonus(
	state: GameState,
	_unit: UnitState,
	move_start_pos: Vector2i,
	intent_path: Array[Vector2i],
	target_uid: String = ""
) -> int:
	return PatrolGuardRules.charge_bonus(state, _unit, move_start_pos, intent_path)


static func _target_pos(state: GameState, target_uid: String) -> Vector2i:
	var target: UnitState = state.units.get(target_uid, null)
	if target == null:
		return Vector2i(-999, -999)
	return target.pos
