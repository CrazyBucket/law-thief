extends EnemyBehavior

const FissionSlimeRules = preload("res://scripts/rules/fission_slime_rules.gd")
const EnemyAI = preload("res://scripts/rules/enemy_ai.gd")
const AIProfiles = preload("res://scripts/rules/ai_profiles.gd")
const IntentSystem = preload("res://scripts/rules/intent_system.gd")


static func compute_intent(state: GameState, unit: UnitState, cell_blockers: Dictionary = {}) -> IntentState:
	var red_skill_intent := _red_skill_override_intent(state, unit, cell_blockers)
	if red_skill_intent != null:
		return red_skill_intent
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
	if intent.type == "trample":
		return {
			"handled": true,
			"events": FissionSlimeRules.execute_trample(state, unit, intent),
		}
	return EnemyBehavior.execute_custom_intent(state, unit, intent, _move_start_pos)


static func split_clone_ratio(unit: UnitState) -> float:
	return FissionSlimeRules.split_stat_ratio(unit)


static func should_trigger_split_blue(unit: UnitState, reason: String) -> bool:
	return FissionSlimeRules.should_trigger_split_blue(unit, reason)


static func _red_skill_override_intent(
	state: GameState,
	unit: UnitState,
	cell_blockers: Dictionary = {}
) -> IntentState:
	var player := state.get_player()
	if player == null or not player.alive:
		return null
	var profile: Dictionary = AIProfiles.get_profile(unit.ai_profile_id)
	var reachable: Array[Vector2i] = []
	if StatusRules.can_move(unit):
		reachable = BoardUtils.reachable_cells(
			state, unit.pos, unit.move_points, unit.uid, {}, cell_blockers, unit
		)
	reachable.append(unit.pos)
	var candidates: Array = []
	for anchor in reachable:
		if not FissionSlimeRules._anchor_passable_for_plan(state, unit, anchor, cell_blockers):
			continue
		if anchor != unit.pos:
			var path := BoardUtils.path_toward(
				state, unit.pos, anchor, unit.move_points, unit.uid, {}, cell_blockers, unit
			)
			if path.is_empty() or path[path.size() - 1] != anchor:
				continue
		candidates.append_array(EnemyAI.evaluate_red_skill_candidates(state, unit, anchor, profile))
	if candidates.is_empty():
		return null
	var best = candidates[0]
	for candidate in candidates:
		if candidate.score > best.score:
			best = candidate
	if best.type != EnemyAI.ActionType.SKILL_RED:
		return null
	return IntentSystem.enemy_intent_from_decision(
		state,
		unit,
		{"move_path": _path_to_target_anchor(state, unit, best.move_target, cell_blockers), "action": best},
		cell_blockers
	)


static func _path_to_target_anchor(
	state: GameState,
	unit: UnitState,
	anchor: Vector2i,
	cell_blockers: Dictionary
) -> Array[Vector2i]:
	if anchor == unit.pos:
		return []
	return BoardUtils.path_toward(
		state, unit.pos, anchor, unit.move_points, unit.uid, {}, cell_blockers, unit
	)
