extends EnemyBehavior

const StoneBowGuardRules = preload("res://scripts/rules/stone_bow_guard_rules.gd")


static func compute_intent(state: GameState, unit: UnitState, cell_blockers: Dictionary = {}) -> IntentState:
	if StatusRules.is_lawless(unit):
		return build_lawless_intent(state, unit, cell_blockers)
	return build_normal_intent(state, unit, cell_blockers)


static func build_normal_intent(state: GameState, unit: UnitState, cell_blockers: Dictionary = {}) -> IntentState:
	var decision := StoneBowGuardRules.decide(state, unit, cell_blockers)
	return IntentSystem.enemy_intent_from_decision(state, unit, decision, cell_blockers)


static func build_lawless_intent(state: GameState, unit: UnitState, cell_blockers: Dictionary = {}) -> IntentState:
	var intent := EnemyBehavior.build_normal_intent(state, unit, cell_blockers)
	if intent.type != "wait":
		intent.preview_text = "盲射·%s" % intent.preview_text
	return intent


static func on_gem_extracted(state: GameState, unit: UnitState, slot_type: String, gem_uid: String) -> void:
	if unit.team != Constants.TEAM_ENEMY or unit_has_any_gem(unit):
		return
	StoneBowGuardRules.on_red_gem_stolen(state, unit, gem_uid)


static func on_gem_inserted(_state: GameState, unit: UnitState, gem_uid: String) -> void:
	if StatusRules.is_lawless(unit) and StatusRules.get_lawless_gem_uid(unit) == gem_uid:
		StoneBowGuardRules.on_lawless_recovered(unit)
		StatusRules.clear_lawless(unit)


static func on_red_gem_stolen(state: GameState, unit: UnitState, gem_uid: String) -> void:
	StoneBowGuardRules.on_red_gem_stolen(state, unit, gem_uid)


static func on_lawless_recovered(unit: UnitState) -> void:
	StoneBowGuardRules.on_lawless_recovered(unit)


static func build_ranged_intent(state: GameState, unit: UnitState, move_path: Array[Vector2i], intent: IntentState) -> void:
	intent.damage = StoneBowGuardRules.ranged_damage_preview(state, unit)
	var range: int = StoneBowGuardRules.attack_range_for(unit.pos, move_path)
	if StoneBowGuardRules.is_deployed(unit.pos, move_path):
		intent.preview_text = "架设射击 %d格 (%d)" % [range, intent.damage]
	else:
		intent.preview_text = "射击 %d格 (%d)" % [range, intent.damage]


static func ranged_attack_context(
	state: GameState,
	unit: UnitState,
	move_start_pos: Vector2i,
	intent_path: Array[Vector2i]
) -> Dictionary:
	var payload: Dictionary = {}
	var bonus: int = StoneBowGuardRules.bonus_damage(unit)
	if bonus > 0:
		payload["bonus_damage"] = bonus
	if StoneBowGuardRules.is_faulty_blind_shot(unit) and not StoneBowGuardRules.roll_hit(state, unit.uid):
		payload["force_miss"] = true
	return {
		"max_range": StoneBowGuardRules.attack_range_for(move_start_pos, intent_path),
		"payload": payload,
	}
