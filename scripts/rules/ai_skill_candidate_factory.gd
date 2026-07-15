class_name AiSkillCandidateFactory
extends RefCounted

const ActionCandidate = preload("res://scripts/rules/ai_action_candidate.gd")


## Every targeted skill candidate must preserve the planned origin and victim identity.
static func targeted(action_type: int, from_pos: Vector2i, target_uid: String) -> ActionCandidate:
	var candidate := ActionCandidate.new()
	candidate.type = action_type
	candidate.move_target = from_pos
	candidate.action_target_uid = target_uid
	return candidate
