extends Node

var _unlocked: Dictionary = {}


func notify_battle_win(encounter_id: String) -> void:
	unlock("win_%s" % encounter_id)


func unlock(achievement_id: String) -> void:
	if _unlocked.has(achievement_id):
		return
	_unlocked[achievement_id] = true
	DebugService.log_info("Achievement unlocked: %s" % achievement_id)


func is_unlocked(achievement_id: String) -> bool:
	return _unlocked.has(achievement_id)
