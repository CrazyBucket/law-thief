class_name AiRedSkillScorer
extends RefCounted

const CombatConfig = preload("res://scripts/core/combat_config.gd")
const CandidateFactory = preload("res://scripts/rules/ai_skill_candidate_factory.gd")
const IntentPreviewRules = preload("res://scripts/rules/intent_preview_rules.gd")


## Scores red-slot strategies that need only combat state and an authored AI profile.
static func arc(
	state: GameState,
	enemy: UnitState,
	from_pos: Vector2i,
	player: UnitState,
	profile: Dictionary,
	action_type: int
) -> Array:
	if not BoardUtils.are_units_adjacent_at(enemy, from_pos, player):
		return []
	var candidate := CandidateFactory.targeted(action_type, from_pos, player.uid)
	var base := float(CombatRules.attack_damage(state, enemy))
	var score: float = base * _weight(profile, "w_damage")
	for unit in state.units.values():
		if not unit.alive or unit.team == player.team or unit.uid == player.uid:
			continue
		if BoardUtils.chebyshev(player.pos, unit.pos) <= CombatConfig.arc_chain_range():
			score += base * CombatConfig.arc_chain_damage_ratio() * _weight(profile, "w_damage") * _tuning(profile, "arc_chain_bonus_mult")
	candidate.score = score
	candidate.description = "电击"
	return [candidate]


static func status_attack(
	state: GameState,
	enemy: UnitState,
	from_pos: Vector2i,
	player: UnitState,
	profile: Dictionary,
	action_type: int,
	description: String
) -> Array:
	if not BoardUtils.are_units_adjacent_at(enemy, from_pos, player):
		return []
	var candidate := CandidateFactory.targeted(action_type, from_pos, player.uid)
	candidate.score = float(CombatRules.attack_damage(state, enemy)) * _weight(profile, "w_damage") + _weight(profile, "w_status")
	candidate.description = description
	return [candidate]


static func echo(
	state: GameState,
	enemy: UnitState,
	from_pos: Vector2i,
	player: UnitState,
	profile: Dictionary,
	action_type: int
) -> Array:
	var max_range := GemEffects.red_attack_range(state, enemy, CombatConfig.attack_range())
	if not BoardUtils.can_unit_reach_unit_at(enemy, from_pos, player, max_range):
		return []
	var candidate := CandidateFactory.targeted(action_type, from_pos, player.uid)
	candidate.score = float(CombatRules.attack_damage(state, enemy)) * _weight(profile, "w_damage") + _weight(profile, "w_status")
	candidate.description = "回响"
	return [candidate]


static func impact(
	state: GameState,
	enemy: UnitState,
	from_pos: Vector2i,
	player: UnitState,
	profile: Dictionary,
	action_type: int
) -> Array:
	var max_range := GemEffects.red_attack_range(state, enemy, CombatConfig.attack_range())
	if not BoardUtils.can_unit_reach_unit_at(enemy, from_pos, player, max_range):
		return []
	var candidate := CandidateFactory.targeted(action_type, from_pos, player.uid)
	var damage := previewed_red_damage_to(state, enemy, from_pos, player)
	candidate.score = float(damage) * _weight(profile, "w_damage")
	candidate.description = "冲击攻击"
	return [candidate]


static func poison(
	state: GameState,
	enemy: UnitState,
	from_pos: Vector2i,
	player: UnitState,
	profile: Dictionary,
	action_type: int
) -> Array:
	if not BoardUtils.are_units_adjacent_at(enemy, from_pos, player):
		return []
	var candidate := CandidateFactory.targeted(action_type, from_pos, player.uid)
	candidate.score = float(CombatRules.attack_damage(state, enemy)) * _weight(profile, "w_damage") + _weight(profile, "w_poison")
	candidate.description = "毒攻击"
	return [candidate]


static func split(
	state: GameState, enemy: UnitState, from_pos: Vector2i, player: UnitState, profile: Dictionary, action_type: int
) -> Array:
	if not BoardUtils.are_units_adjacent_at(enemy, from_pos, player):
		return []
	var damage := previewed_red_damage_to(state, enemy, from_pos, player)
	if damage <= 0:
		return []
	var candidate := CandidateFactory.targeted(action_type, from_pos, player.uid)
	candidate.score = float(damage) * _weight(profile, "w_damage")
	candidate.description = "分裂攻击"
	return [candidate]


static func explosion_attack(
	state: GameState, enemy: UnitState, from_pos: Vector2i, player: UnitState, profile: Dictionary, action_type: int
) -> Array:
	if BoardUtils.manhattan(from_pos, player.pos) != 1:
		return []
	var damage := previewed_red_damage_to(state, enemy, from_pos, player)
	if damage <= 0:
		return []
	var candidate := CandidateFactory.targeted(action_type, from_pos, player.uid)
	candidate.score = float(damage) * _weight(profile, "w_damage")
	if player.hp <= damage:
		candidate.score += _weight(profile, "w_kill_player")
	candidate.score += tile_safety(state, from_pos, profile)
	candidate.description = "爆炸攻击"
	return [candidate]


static func light(
	state: GameState, enemy: UnitState, from_pos: Vector2i, player: UnitState, profile: Dictionary, action_type: int
) -> Array:
	var max_range := Constants.BOARD_SIZE.x + Constants.BOARD_SIZE.y
	if not BoardUtils.can_unit_attack_cell_at(enemy, state, from_pos, player.pos, max_range):
		return []
	var damage := previewed_red_damage_to(state, enemy, from_pos, player)
	if damage <= 0:
		return []
	var candidate := CandidateFactory.targeted(action_type, from_pos, player.uid)
	candidate.score = float(damage) * _weight(profile, "w_damage") + _weight(profile, "w_status")
	candidate.description = "光束"
	return [candidate]


static func charge_explode(state: GameState, enemy: UnitState, from_pos: Vector2i, player: UnitState, profile: Dictionary, action_type: int) -> Array:
	var distance := BoardUtils.manhattan(from_pos, player.pos)
	var threat_range := CombatConfig.charge_explode_dash_range() + CombatConfig.explosion_radius()
	if distance > threat_range:
		return []
	var candidate := CandidateFactory.targeted(action_type, from_pos, player.uid)
	var score := float(CombatConfig.explosion_damage()) * _weight(profile, "w_damage")
	if distance <= CombatConfig.explosion_radius():
		score *= _tuning(profile, "explosion_adjacent_bonus_mult")
	score += _weight(profile, "w_self_sacrifice")
	for cell in BoardUtils.cells_in_radius(player.pos, CombatConfig.explosion_radius()):
		var unit: UnitState = state.get_unit_at(cell)
		if unit != null and unit.alive and unit.team == Constants.TEAM_ENEMY and unit.uid != enemy.uid:
			score -= _weight(profile, "w_friendly_fire")
	candidate.score = score
	candidate.description = "冲刺爆炸"
	return [candidate]


static func pull(state: GameState, enemy: UnitState, from_pos: Vector2i, player: UnitState, profile: Dictionary, action_type: int) -> Array:
	# Red gravity augments a normal attack; it is not a separate long-range pull.
	# Melee stays range 1; ranged behaviors retain their authored attack range.
	var base_range := GemEffects.enemy_normal_attack_base_range(state, enemy, from_pos)
	var max_range := GemEffects.red_attack_range(state, enemy, base_range)
	var distance := BoardUtils.distance_between_unit_at_and_unit(enemy, from_pos, player)
	if distance > max_range:
		return []
	var candidate := CandidateFactory.targeted(action_type, from_pos, player.uid)
	var score := _weight(profile, "w_pull") + _tuning(profile, "pull_base_bonus")
	var destination := BoardUtils.step_toward(player.pos, from_pos)
	if BoardUtils.spike_entity_at(state, destination) != null:
		score += float(CombatConfig.spike_damage()) * _weight(profile, "w_damage")
	var tile: TileState = state.get_tile(destination)
	if tile.has_modifier("poison_fog"):
		score += _weight(profile, "w_damage") * _tuning(profile, "pull_damage_bonus_mult")
	score += float(distance) * _tuning(profile, "pull_distance_score_mult")
	candidate.score = score
	candidate.description = "引力拉近(%d格)" % max_range
	return [candidate]


static func previewed_red_damage_to(state: GameState, enemy: UnitState, from_pos: Vector2i, target: UnitState) -> int:
	var preview := IntentPreviewRules.build_red_attack_profile(state, enemy, from_pos, target.pos, CombatRules.attack_damage(state, enemy))
	return IntentPreviewRules.predicted_raw_damage_to(preview, target.uid)


static func _weight(profile: Dictionary, key: String) -> float:
	if profile.has(key):
		return float(profile[key])
	push_error("AiRedSkillScorer: required profile value missing: %s" % key)
	return 0.0


static func tile_safety(state: GameState, pos: Vector2i, profile: Dictionary) -> float:
	var score := 0.0
	if BoardUtils.spike_entity_at(state, pos) != null:
		score -= float(CombatConfig.spike_damage()) * _weight(profile, "w_self_damage")
	var tile: TileState = state.get_tile(pos)
	if tile.has_modifier("poison_fog"):
		score -= float(CombatConfig.poison_fog_damage()) * _weight(profile, "w_self_damage")
	return score


static func _tuning(profile: Dictionary, key: String) -> float:
	if profile.has(key):
		return float(profile[key])
	return float(AIProfiles.get_tuning_value(key))
