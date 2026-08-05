extends SceneTree

const Candidate = preload("res://scripts/rules/ai_action_candidate.gd")
const Selector = preload("res://scripts/rules/ai_candidate_selector.gd")


func _initialize() -> void:
	var low := Candidate.new()
	assert(low.type == 5, "new candidates should default to the WAIT action")
	assert(low.move_target == Vector2i(-1, -1), "new candidates should have no planned origin")
	assert(low.action_target_uid.is_empty(), "new candidates should have no target")
	assert(low.slot_index == -1, "new candidates should have no selected slot")
	low.score = 3.0
	var first_high := Candidate.new()
	first_high.score = 7.0
	var tied_high := Candidate.new()
	tied_high.score = 7.0

	assert(Selector.select_highest_scoring([]) == null, "empty candidate lists should have no selection")
	assert(
		Selector.select_highest_scoring([low, first_high, tied_high]) == first_high,
		"equal scores must keep the first candidate for deterministic decisions"
	)
	print("AI_CANDIDATE_SELECTOR_TEST_PASS")
	quit()
