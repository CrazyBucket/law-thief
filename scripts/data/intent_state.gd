class_name IntentState
extends RefCounted

var type: String = "wait"
var source_uid: String = ""
var target_uid: String = ""
var target_pos: Vector2i = Vector2i(-1, -1)
var path: Array[Vector2i] = []
var affected_cells: Array[Vector2i] = []
var damage: int = 0
var preview_text: String = ""


static func wait(source_uid: String) -> IntentState:
	var intent := IntentState.new()
	intent.type = "wait"
	intent.source_uid = source_uid
	intent.preview_text = "等待"
	return intent
