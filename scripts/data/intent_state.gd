class_name IntentState
extends RefCounted

const CombatConfig = preload("res://scripts/core/combat_config.gd")
const _ActionPlan = preload("res://scripts/data/action_plan.gd")

var type: String = "wait"
var source_uid: String = ""
var target_uid: String = ""
var target_pos: Vector2i = Vector2i(-1, -1)
var path: Array[Vector2i] = []
var affected_cells: Array[Vector2i] = []
var base_damage: int = 0
var damage: int = 0
var damage_components: Array[IntentDamageComponent] = []
var preview_effects: Array = []
var preview_text: String = ""
var plan_metadata: Dictionary = {}
var action_plan = null


static func intent_icon(intent_type: String) -> String:
	match intent_type:
		"melee_attack":  return "⚔"
		"split_attack":  return "⚔"
		"trample":       return "🦶"
		"slam_attack":   return "🔨"
		"ranged_attack": return "🏹"
		"explosion_attack": return "💥"
		"charge_explode": return "💣"
		"impact_attack": return "➤"
		"rolling_uncontrolled": return "💢"
		"pull":          return "🪝"
		"poison_attack": return "☠"
		"arc_attack":    return "⚡"
		"fire_attack":   return "🔥"
		"ice_attack":    return "❄"
		"light_beam":    return "☼"
		"extract":       return "💎"
		"move":          return "➡"
		"lawless_extract": return "💢"
		"lawless_attack":  return "💢"
		"lawless_move":    return "💢"
		"black_suicide": return "💀"
		"bomb_rat_plunder_wait": return "😶"
		"bomb_rat_plunder_steal": return "💢"
		"law_worm_seek": return "💎"
		"law_worm_consume": return "💎"
		"law_worm_transform": return "孵"
		"broodmother_split": return "殖"
		"broodmother_ranged_attack": return "🏹"
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
	intent.preview_text = "冲刺爆炸 (%d)" % CombatConfig.explosion_damage()
	return intent


func clone() -> IntentState:
	var intent := IntentState.new()
	intent.type = type
	intent.source_uid = source_uid
	intent.target_uid = target_uid
	intent.target_pos = target_pos
	intent.path = path.duplicate()
	intent.affected_cells = affected_cells.duplicate()
	intent.base_damage = base_damage
	intent.damage = damage
	for component in damage_components:
		intent.damage_components.append(component.clone())
	for effect in preview_effects:
		intent.preview_effects.append(effect.clone())
	intent.preview_text = preview_text
	intent.plan_metadata = plan_metadata.duplicate(true)
	intent.action_plan = action_plan.clone() if action_plan != null else null
	return intent


func finalize_action_plan(turn_index: int, source_pos: Vector2i) -> void:
	action_plan = _ActionPlan.capture(self, turn_index, source_pos)


func execution_view(turn_index: int, source_pos: Vector2i) -> IntentState:
	if action_plan == null:
		finalize_action_plan(turn_index, source_pos)
	var intent := clone()
	action_plan.apply_to(intent)
	intent.action_plan = action_plan.clone()
	return intent


func set_damage_components(components: Array) -> void:
	damage_components.clear()
	for raw_component in components:
		if raw_component is IntentDamageComponent:
			damage_components.append(raw_component)
	if not damage_components.is_empty():
		damage = damage_components[0].damage_per_hit


func predicted_raw_damage_to(target_uid: String, include_conditional: bool = true) -> int:
	var total := 0
	for component in damage_components:
		if not include_conditional and component.certainty == IntentDamageComponent.CERTAINTY_CONDITIONAL:
			continue
		total += component.predicted_raw_damage_to(target_uid)
	return total
