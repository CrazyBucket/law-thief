class_name AiCandidateSelector
extends RefCounted

const ActionCandidate = preload("res://scripts/rules/ai_action_candidate.gd")


## Returns the first highest-scoring candidate so decision ties stay deterministic.
static func select_highest_scoring(candidates: Array) -> ActionCandidate:
	var best: ActionCandidate = null
	for candidate in candidates:
		if candidate == null:
			continue
		if best == null or candidate.score > best.score:
			best = candidate
	return best
