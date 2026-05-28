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
		"slam_attack":   return "🔨"
		"ranged_attack": return "🏹"
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
		"black_suicide": return "💀"
		"bomb_rat_plunder_wait": return "😶"
		"bomb_rat_plunder_steal": return "💢"
		"wait":          return "…"
	return "?"


static func wait(source_uid: String) -> IntentState:
	var intent := IntentState.new()
	intent.type = "wait"
	intent.source_uid = source_uid
	intent.preview_text = "等待"
	return intent


## 构造一个标准冲刺自爆意图，用于测试或直接触发自爆效果
static func charge_explode(source_uid: String, target_uid: String) -> IntentState:
	var intent := IntentState.new()
	intent.type = "charge_explode"
	intent.source_uid = source_uid
	intent.target_uid = target_uid
	intent.preview_text = "冲刺爆炸 (%d)" % Constants.EXPLOSION_DAMAGE
	return intent


func clone() -> IntentState:
	var intent := IntentState.new()
	intent.type = type
	intent.source_uid = source_uid
	intent.target_uid = target_uid
	intent.target_pos = target_pos
	intent.path = path.duplicate()
	intent.affected_cells = affected_cells.duplicate()
	intent.damage = damage
	intent.preview_text = preview_text
	return intent
