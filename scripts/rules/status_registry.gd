class_name StatusRegistry
extends RefCounted

const TICK_TURN_START := "turn_start"
const TICK_TURN_END := "turn_end"
const TICK_NONE := "none"

const TYPE_BUFF := "buff"
const TYPE_DEBUFF := "debuff"
const TYPE_SYSTEM := "system"

const STACK_REPLACE := "replace"
const STACK_VALUE := "stack_value"
const STACK_MAX_VALUE := "max_value"


static func get_def(status_id: String) -> Dictionary:
	return _DEFS.get(status_id, {})


static func display_name(status_id: String) -> String:
	return get_def(status_id).get("display_name", status_id)


static func status_color(status_id: String) -> Color:
	return get_def(status_id).get("color", Color(0.7, 0.7, 0.75))


static func status_type(status_id: String) -> String:
	return get_def(status_id).get("type", TYPE_DEBUFF)


static func tick_phase(status_id: String) -> String:
	return get_def(status_id).get("tick_phase", TICK_NONE)


static func blocks_movement(status_id: String) -> bool:
	return get_def(status_id).get("blocks_movement", false)


static func blocks_action(status_id: String) -> bool:
	return get_def(status_id).get("blocks_action", false)


static func apply_to_unit(unit: UnitState, incoming: StatusInstance) -> void:
	var existing: StatusInstance = unit.get_status(incoming.status_id)
	if existing == null:
		unit.statuses.append(incoming)
		return
	var rule: String = get_def(incoming.status_id).get("stack_rule", STACK_REPLACE)
	match rule:
		STACK_VALUE:
			existing.stacks += incoming.stacks
			existing.duration = maxi(existing.duration, incoming.duration)
			if incoming.value > 0:
				existing.value = maxi(existing.value, incoming.value)
		STACK_MAX_VALUE:
			existing.value = maxi(existing.value, incoming.value)
			existing.duration = maxi(existing.duration, incoming.duration)
		_:
			existing.stacks = incoming.stacks
			existing.value = incoming.value
			existing.duration = incoming.duration
			existing.source_uid = incoming.source_uid
			existing.payload = incoming.payload.duplicate()


static func is_true_damage(status_id: String) -> bool:
	return get_def(status_id).get("true_damage", false)


static func short_label(status: StatusInstance) -> String:
	match status.status_id:
		Constants.STATUS_POISON:
			return "毒%d" % status.stacks
		Constants.STATUS_BURNING:
			return "火%d" % status.stacks
		Constants.STATUS_PARALYZED:
			return "麻%d" % maxi(status.duration, 1)
		Constants.STATUS_SLOWED:
			return "缓%d" % status.stacks
		Constants.STATUS_WET:
			return "湿"
		Constants.STATUS_SLUGGISH:
			return "滞"
		Constants.STATUS_ARMOR:
			return "甲%d" % status.value
		Constants.STATUS_ROOTED:
			return "缚%d" % maxi(status.duration, 1)
		Constants.STATUS_EXPOSED:
			return "暴露"
		Constants.STATUS_LAWLESS:
			return "失律"
	return display_name(status.status_id)


static func tooltip(status: StatusInstance) -> String:
	match status.status_id:
		Constants.STATUS_POISON:
			return "中毒：回合结束受到 %d 点真实伤害，层数递减" % status.stacks
		Constants.STATUS_BURNING:
			return "着火：回合结束受到 %d 点真实伤害，层数递减；处于火焰中层数x2" % status.stacks
		Constants.STATUS_PARALYZED:
			return "麻痹：本回合无法行动，剩余 %d 回合" % status.duration
		Constants.STATUS_SLOWED:
			return "缓速：移动力减少 %d 格（最低1）" % status.stacks
		Constants.STATUS_WET:
			return "潮湿：与冰/电互动效果增强"
		Constants.STATUS_SLUGGISH:
			return "迟滞：下回合行动顺序垫底"
		Constants.STATUS_ARMOR:
			return "护甲 +%d，剩余 %d 回合" % [status.value, status.duration]
		Constants.STATUS_ROOTED:
			return "束缚：无法移动，剩余 %d 回合" % status.duration
		Constants.STATUS_EXPOSED:
			return "暴露：重甲锁槽已被破开"
		Constants.STATUS_LAWLESS:
			return "失律：追逐被窃走的宝石"
	return display_name(status.status_id)


static func sort_statuses(statuses: Array) -> Array:
	var ordered: Array = statuses.duplicate()
	ordered.sort_custom(func(a: StatusInstance, b: StatusInstance) -> bool:
		var rank_a: int = _sort_rank(a.status_id)
		var rank_b: int = _sort_rank(b.status_id)
		if rank_a == rank_b:
			return a.status_id < b.status_id
		return rank_a < rank_b
	)
	return ordered


static func _sort_rank(status_id: String) -> int:
	match status_type(status_id):
		TYPE_DEBUFF:
			return 0
		TYPE_SYSTEM:
			return 1
		TYPE_BUFF:
			return 2
	return 3


static var _DEFS: Dictionary = {
	Constants.STATUS_POISON: {
		"display_name": "中毒",
		"type": TYPE_DEBUFF,
		"color": Color(0.45, 0.92, 0.35),
		"stack_rule": STACK_VALUE,
		"tick_phase": TICK_TURN_END,
		"true_damage": true,
		"blocks_movement": false,
	},
	Constants.STATUS_BURNING: {
		"display_name": "着火",
		"type": TYPE_DEBUFF,
		"color": Color(1.0, 0.5, 0.1),
		"stack_rule": STACK_VALUE,
		"tick_phase": TICK_TURN_END,
		"true_damage": true,
		"blocks_movement": false,
	},
	Constants.STATUS_ARMOR: {
		"display_name": "护甲",
		"type": TYPE_BUFF,
		"color": Color(0.72, 0.78, 0.88),
		"stack_rule": STACK_MAX_VALUE,
		"tick_phase": TICK_TURN_END,
		"blocks_movement": false,
	},
	Constants.STATUS_ROOTED: {
		"display_name": "束缚",
		"type": TYPE_DEBUFF,
		"color": Color(0.55, 0.45, 0.95),
		"stack_rule": STACK_REPLACE,
		"tick_phase": TICK_TURN_START,
		"blocks_movement": true,
	},
	Constants.STATUS_EXPOSED: {
		"display_name": "暴露",
		"type": TYPE_SYSTEM,
		"color": Color(0.95, 0.75, 0.35),
		"stack_rule": STACK_REPLACE,
		"tick_phase": TICK_TURN_END,
		"blocks_movement": false,
	},
	Constants.STATUS_LAWLESS: {
		"display_name": "失律",
		"type": TYPE_SYSTEM,
		"color": Color(0.95, 0.35, 0.35),
		"stack_rule": STACK_REPLACE,
		"tick_phase": TICK_NONE,
		"blocks_movement": false,
	},
	Constants.STATUS_PARALYZED: {
		"display_name": "麻痹",
		"type": TYPE_DEBUFF,
		"color": Color(0.9, 0.9, 0.2),
		"stack_rule": STACK_REPLACE,
		"tick_phase": TICK_NONE,
		"blocks_movement": true,
		"blocks_action": true,
	},
	Constants.STATUS_SLOWED: {
		"display_name": "缓速",
		"type": TYPE_DEBUFF,
		"color": Color(0.55, 0.85, 0.95),
		"stack_rule": STACK_VALUE,
		"tick_phase": TICK_TURN_START,
		"blocks_movement": false,
	},
	Constants.STATUS_WET: {
		"display_name": "潮湿",
		"type": TYPE_DEBUFF,
		"color": Color(0.4, 0.7, 1.0),
		"stack_rule": STACK_REPLACE,
		"tick_phase": TICK_TURN_END,
		"blocks_movement": false,
	},
	Constants.STATUS_SLUGGISH: {
		"display_name": "迟滞",
		"type": TYPE_DEBUFF,
		"color": Color(0.6, 0.85, 1.0),
		"stack_rule": STACK_REPLACE,
		"tick_phase": TICK_TURN_END,
		"blocks_movement": false,
	},
}
