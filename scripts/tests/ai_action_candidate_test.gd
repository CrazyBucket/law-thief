extends SceneTree

const Candidate = preload("res://scripts/rules/ai_action_candidate.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var candidate := Candidate.new()
	_assert(candidate.type == 5, "default action type should remain WAIT")
	_assert(candidate.move_target == Vector2i(-1, -1), "default move target should be unset")
	_assert(candidate.action_target_uid.is_empty(), "default target should be empty")
	_assert(candidate.slot_index == -1, "default slot index should be unset")
	candidate.score = 12.5
	candidate.description = "test"
	_assert(is_equal_approx(candidate.score, 12.5), "score should remain writable")
	_assert(candidate.description == "test", "description should remain writable")
	print("AI_ACTION_CANDIDATE_TEST_PASS")
	quit()


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
