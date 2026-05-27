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


static func intent_icon(intent_type: String) -> String:
	match intent_type:
		"melee_attack":  return "⚔"
		"charge_explode": return "💣"
		"pull":          return "🪝"
		"poison_attack": return "☠"
		"arc_attack":    return "⚡"
		"fire_attack":   return "🔥"
		"ice_attack":    return "❄"
		"extract":       return "💎"
		"move":          return "➡"
		"lawless_extract": return "💢"
		"lawless_attack":  return "💢"
		"lawless_move":    return "💢"
		"wait":          return "…"
	return "?"


static func wait(source_uid: String) -> IntentState:
	var intent := IntentState.new()
	intent.type = "wait"
	intent.source_uid = source_uid
	intent.preview_text = "等待"
	return intent
