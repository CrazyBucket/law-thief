extends SceneTree

const Factory = preload("res://scripts/rules/ai_skill_candidate_factory.gd")


func _initialize() -> void:
	var candidate := Factory.targeted(3, Vector2i(2, 5), "player_test")
	assert(candidate.type == 3, "candidate factory should retain the supplied action type")
	assert(candidate.move_target == Vector2i(2, 5), "candidate factory should retain the planned origin")
	assert(candidate.action_target_uid == "player_test", "candidate factory should retain the target identity")
	print("AI_SKILL_CANDIDATE_FACTORY_TEST_PASS")
	quit()
