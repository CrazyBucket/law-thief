extends Node

var pending_encounter_id: String = "tutorial_001"
var pending_room_id: String = ""
var adventure_return: bool = false
var pending_battle_mode: String = "normal"


func start_battle(encounter_id: String) -> void:
	pending_encounter_id = encounter_id
	pending_battle_mode = "normal"
	SaveService.touch_active_slot({
		"pending_encounter_id": encounter_id,
	})


func start_editor_battle(encounter_id: String = "tutorial_001") -> void:
	pending_encounter_id = encounter_id
	pending_room_id = ""
	adventure_return = false
	pending_battle_mode = "editor"


func finish_battle(result: String, encounter_id: String, turn_count: int) -> void:
	RunHistoryService.record_encounter({
		"encounter_id": encounter_id,
		"result": result,
		"turn_count": turn_count,
	})
	if result == "win":
		AchievementService.notify_battle_win(encounter_id)
	else:
		AchievementService.refresh_progress_flags()
	SaveService.touch_active_slot({
		"last_battle_result": result,
		"last_encounter_id": encounter_id,
		"last_turn_count": turn_count,
	})


func reset_session_state() -> void:
	pending_encounter_id = "tutorial_001"
	pending_room_id = ""
	adventure_return = false
	pending_battle_mode = "normal"
