extends EnemyBehavior

const RuffledCrowRules = preload("res://scripts/rules/ruffled_crow_rules.gd")


static func compute_intent(state: GameState, unit: UnitState, cell_blockers: Dictionary = {}) -> IntentState:
	return build_normal_intent(state, unit, cell_blockers)


static func build_normal_intent(state: GameState, unit: UnitState, cell_blockers: Dictionary = {}) -> IntentState:
	return EnemyBehavior.build_normal_intent(state, unit, cell_blockers)


static func build_melee_intent(state: GameState, unit: UnitState, _move_path: Array[Vector2i], intent: IntentState) -> void:
	intent.base_damage = CombatRules.attack_damage(state, unit)
	if StatusRules.is_lawless(unit):
		var count := RuffledCrowRules.disorder_hit_count(unit)
		var per_hit := RuffledCrowRules.segment_damage(state, unit)
		intent.damage = per_hit * count
		intent.preview_text = "乱羽 %d×%d · %d%%" % [per_hit, count, roundi(RuffledCrowRules.disorder_hit_chance(unit) * 100.0)]
		return
	var preview := RuffledCrowRules.normal_preview(state, unit)
	intent.damage = int(preview["segment_damage"]) * int(preview["count"])
	intent.preview_text = "连啄 %d×%d · %d%%" % [int(preview["segment_damage"]), int(preview["count"]), roundi(RuffledCrowRules.normal_hit_chance(unit) * 100.0)]


static func execute_custom_intent(
	state: GameState,
	unit: UnitState,
	intent: IntentState,
	_move_start_pos: Vector2i
) -> Dictionary:
	if intent.type != "melee_attack":
		return EnemyBehavior.execute_custom_intent(state, unit, intent, _move_start_pos)
	var target: UnitState = state.units.get(intent.target_uid, null)
	if target == null or not target.alive or not BoardUtils.are_units_adjacent(unit, target):
		return {"handled": true, "events": [] as Array[Dictionary]}
	var payload := {"hit_chance": RuffledCrowRules.normal_hit_chance(unit)}
	var was_disordered := StatusRules.is_lawless(unit)
	if was_disordered:
		payload["disable_flurry"] = true
		payload["forced_hit_count"] = RuffledCrowRules.disorder_hit_count(unit)
		payload["forced_segment_damage"] = RuffledCrowRules.segment_damage(state, unit)
		payload["segments_are_attack_events"] = true
		payload["hit_chance"] = RuffledCrowRules.disorder_hit_chance(unit)
	var result := AttackPipeline.execute(state, unit, target, [AttackPipeline.TAG_MELEE], payload)
	if bool(result.get("ok", false)) and was_disordered:
		RuffledCrowRules.halve_feathers(unit)
	return {
		"handled": true,
		"events": EnemyBehavior._events_from_result(result),
	}


static func on_gem_extracted(state: GameState, unit: UnitState, slot_type: String, gem_uid: String) -> void:
	if unit.team != Constants.TEAM_ENEMY or slot_type != Constants.SLOT_RED:
		return
	var gem: GemState = state.gems.get(gem_uid, null)
	if gem != null and gem.gem_id == Constants.GEM_FLURRY:
		RuffledCrowRules.enter_disorder(state, unit, gem_uid)


static func on_gem_inserted(state: GameState, unit: UnitState, gem_uid: String) -> void:
	if not StatusRules.is_lawless(unit):
		return
	var red_slot := unit.get_slot(Constants.SLOT_RED)
	var gem: GemState = state.gems.get(gem_uid, null)
	if red_slot != null and red_slot.gem_uid == gem_uid and gem != null and gem.gem_id == Constants.GEM_FLURRY:
		RuffledCrowRules.recover_order(unit)


static func on_turn_start(state: GameState, unit: UnitState) -> void:
	RuffledCrowRules.on_turn_start(state, unit)


static func on_damage_taken(state: GameState, unit: UnitState, amount: int, source_uid: String = "") -> void:
	RuffledCrowRules.on_damage_taken(state, unit, amount, source_uid)
