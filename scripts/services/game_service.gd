extends Node

var pending_encounter_id: String = "tutorial_001"
var pending_room_id: String = ""
var adventure_return: bool = false
var pending_battle_mode: String = "normal"

const MAP_SCENE := "res://scenes/map/adventure_map.tscn"
const ROOM_SCENE := "res://scenes/adventure/room_placeholder.tscn"
const SHOP_SCENE := "res://scenes/adventure/shop_scene.tscn"
const EVENT_SCENE := "res://scenes/adventure/event_scene.tscn"
const BATTLE_SCENE := "res://scenes/battle/battle_scene.tscn"


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


func continue_scene_for_active_run() -> String:
	var phase := RunService.get_run_phase()
	var pending: Dictionary = RunService.get_pending_decision()
	match phase:
		"ROOM":
			pending_room_id = str(pending.get("room_id", pending_room_id))
			AdventureService.pending_room_type = str(pending.get("room_type", AdventureService.pending_room_type))
			match AdventureService.pending_room_type:
				"SHOP":
					return SHOP_SCENE
				"EVENT":
					return EVENT_SCENE
				_:
					return ROOM_SCENE
		"BATTLE":
			pending_room_id = str(pending.get("room_id", ""))
			pending_encounter_id = str(pending.get("encounter_id", pending_encounter_id))
			adventure_return = true
			AdventureService.pending_room_type = str(pending.get("room_type", AdventureService.pending_room_type))
			return BATTLE_SCENE
		"BATTLE_REWARD":
			pending_room_id = str(pending.get("room_id", ""))
			pending_encounter_id = str(pending.get("encounter_id", pending_encounter_id))
			adventure_return = true
			AdventureService.pending_room_type = str(pending.get("room_type", AdventureService.pending_room_type))
			return BATTLE_SCENE
		_:
			return MAP_SCENE
