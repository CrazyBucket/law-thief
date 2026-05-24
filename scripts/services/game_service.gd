extends Node

var pending_encounter_id: String = "tutorial_001"


func start_battle(encounter_id: String) -> void:
	pending_encounter_id = encounter_id


func finish_battle(result: String, encounter_id: String, turn_count: int) -> void:
	RunHistoryService.record_encounter({
		"encounter_id": encounter_id,
		"result": result,
		"turn_count": turn_count,
	})
	if result == "win":
		AchievementService.notify_battle_win(encounter_id)
