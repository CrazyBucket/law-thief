extends SceneTree

const Scorer = preload("res://scripts/rules/ai_red_skill_scorer.gd")


func _initialize() -> void:
	var state := GameState.new()
	var player := UnitState.new()
	player.uid = "player"
	player.team = Constants.TEAM_PLAYER
	player.pos = Vector2i(2, 2)
	player.alive = true
	var enemy := UnitState.new()
	enemy.uid = "enemy"
	enemy.team = Constants.TEAM_ENEMY
	enemy.pos = Vector2i(2, 1)
	enemy.alive = true
	enemy.base_attack = 4
	state.player_uid = player.uid
	state.units = {player.uid: player, enemy.uid: enemy}
	var profile := {"w_damage": 2.0, "w_status": 3.0}
	var candidates := Scorer.status_attack(state, enemy, enemy.pos, player, profile, 3, "test status")
	assert(candidates.size() == 1, "adjacent status skill should produce one candidate")
	var candidate = candidates[0]
	assert(candidate.score == 11.0, "status scoring should combine attack and status values")
	assert(candidate.action_target_uid == player.uid and candidate.move_target == enemy.pos, "candidate must retain target and origin")
	var poison_profile := {"w_damage": 2.0, "w_poison": 5.0}
	var poison_candidates := Scorer.poison(state, enemy, enemy.pos, player, poison_profile, 3)
	assert(poison_candidates.size() == 1 and poison_candidates[0].score == 13.0, "poison scoring should use its authored poison weight")
	print("AI_RED_SKILL_SCORER_TEST_PASS")
	quit()
