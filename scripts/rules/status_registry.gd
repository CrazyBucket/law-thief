class_name StatusRegistry
extends RefCounted

const CombatConfig = preload("res://scripts/core/combat_config.gd")
const StatusConfig = preload("res://scripts/core/status_config.gd")

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
	if status_id == Constants.STATUS_DISARMED:
		return _translated("status.disarmed.name", "缴械")
	return get_def(status_id).get("display_name", status_id)


static func status_color(status_id: String) -> Color:
	return get_def(status_id).get("color", UiPalette.STATUS_FALLBACK)


static func status_type(status_id: String) -> String:
	return get_def(status_id).get("type", TYPE_DEBUFF)


static func tick_phase(status_id: String) -> String:
	return get_def(status_id).get("tick_phase", TICK_NONE)


static func blocks_movement(status_id: String) -> bool:
	return get_def(status_id).get("blocks_movement", false)


static func blocks_action(status_id: String) -> bool:
	return get_def(status_id).get("blocks_action", false)


static func blocks_attack(status_id: String) -> bool:
	return get_def(status_id).get("blocks_attack", false)


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
		Constants.STATUS_LIGHT_EXPOSED:
			return "曝%d" % status.stacks
		Constants.STATUS_BLINDED:
			return "盲%d" % maxi(status.duration, 1)
		Constants.STATUS_WET:
			return "湿"
		Constants.STATUS_SLUGGISH:
			return "滞"
		Constants.STATUS_ARMOR:
			return "盾%d" % status.value
		Constants.STATUS_ROOTED:
			return "缚%d" % maxi(status.duration, 1)
		Constants.STATUS_EXPOSED:
			return "暴露"
		Constants.STATUS_LAWLESS:
			return "失律"
		Constants.STATUS_OVERLOAD_AI_CONTROL:
			return "控"
		Constants.STATUS_BOMB_RAT_PLUNDER:
			return "掠"
		Constants.STATUS_VULNERABLE:
			return "易伤"
		Constants.STATUS_DISARMED:
			return _translated("status.disarmed.short", "械{stacks}", {"stacks": status.stacks})
		Constants.STATUS_WEAK:
			return "虚弱"
		Constants.STATUS_COUNTER_MARK:
			return "截"
		Constants.STATUS_EXTRA_ATTACK:
			return "攻"
		Constants.STATUS_EXTRA_MOVE:
			return "移"
	return display_name(status.status_id)


## 图标角标数字（层数/持续/护甲值）；无数字时返回空串
static func icon_badge(status: StatusInstance) -> String:
	match status.status_id:
		Constants.STATUS_POISON, Constants.STATUS_BURNING, Constants.STATUS_SLOWED, Constants.STATUS_LIGHT_EXPOSED:
			return str(status.stacks)
		Constants.STATUS_PARALYZED, Constants.STATUS_ROOTED, Constants.STATUS_BLINDED, Constants.STATUS_WEAK:
			return str(maxi(status.duration, 1))
		Constants.STATUS_ARMOR:
			return str(status.value)
		Constants.STATUS_DISARMED, Constants.STATUS_EXTRA_ATTACK, Constants.STATUS_EXTRA_MOVE:
			return str(status.stacks)
	return ""


static func tooltip(status: StatusInstance) -> String:
	match status.status_id:
		Constants.STATUS_POISON:
			return "中毒：回合结束受到 %d 点真实伤害，层数递减" % (status.stacks * CombatConfig.poison_fog_damage())
		Constants.STATUS_BURNING:
			return "着火：回合结束受到 %d 点真实伤害，层数递减；处于火焰中层数x2" % status.stacks
		Constants.STATUS_PARALYZED:
			return "麻痹：本回合无法行动，剩余 %d 回合" % status.duration
		Constants.STATUS_SLOWED:
			return "缓速：移动力减少 %d 格（最低1）" % status.stacks
		Constants.STATUS_LIGHT_EXPOSED:
			return "曝光：被光束标记，层数可被黑槽光清算"
		Constants.STATUS_BLINDED:
			return "致盲：攻击容易落空，剩余 %d 回合" % status.duration
		Constants.STATUS_WET:
			return "潮湿：与冰/电互动效果增强"
		Constants.STATUS_SLUGGISH:
			return "迟滞：下回合行动顺序垫底"
		Constants.STATUS_ARMOR:
			return "护盾 +%d，剩余 %d 回合" % [status.value, status.duration] if status.duration > 0 else "护盾 +%d" % status.value
		Constants.STATUS_ROOTED:
			return "束缚：无法移动，剩余 %d 回合" % status.duration
		Constants.STATUS_EXPOSED:
			return "暴露：重甲锁槽已被破开"
		Constants.STATUS_LAWLESS:
			return "失律：追逐被窃走的宝石"
		Constants.STATUS_OVERLOAD_AI_CONTROL:
			return "AI接管：过载正在自动操作角色"
		Constants.STATUS_BOMB_RAT_PLUNDER:
			return "无律掠夺：黑槽空，准备夺取宝石"
		Constants.STATUS_VULNERABLE:
			var damage_taken_mult := StatusConfig.float_value("vulnerable", "damage_taken_mult")
			return "易伤：受到伤害 +%d%%，剩余 %d 回合" % [_percent_bonus_from_mult(damage_taken_mult), status.duration]
		Constants.STATUS_DISARMED:
			return _translated(
				"status.disarmed.tooltip",
				"缴械：无法攻击，剩余 {stacks} 次行动",
				{"stacks": status.stacks}
			)
		Constants.STATUS_WEAK:
			var attack_damage_mult := StatusConfig.float_value("weak", "attack_damage_mult")
			return "虚弱：普通攻击伤害变为 %d%%，剩余 %d 回合" % [_percent_from_mult(attack_damage_mult), status.duration]
		Constants.STATUS_COUNTER_MARK:
			return "截击：若该单位在本轮结束前伤害标记者，会立刻吃一次追击"
		Constants.STATUS_EXTRA_ATTACK:
			return "额外攻击：本回合已攻击后，仍可再攻击 %d 次" % status.stacks
		Constants.STATUS_EXTRA_MOVE:
			return "额外移动：本回合已移动后，仍可再移动 %d 次" % status.stacks
	return display_name(status.status_id)


static func _percent_bonus_from_mult(mult: float) -> int:
	return int(round((mult - 1.0) * 100.0))


static func _percent_from_mult(mult: float) -> int:
	return int(round(mult * 100.0))


static func _translated(key: String, fallback: String, params: Dictionary = {}) -> String:
	var text := TranslationServer.translate(key)
	if text == key:
		text = fallback
	return text.format(params) if not params.is_empty() else text


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
		"color": UiPalette.POISON_GREEN,
		"stack_rule": STACK_VALUE,
		"tick_phase": TICK_TURN_END,
		"true_damage": true,
		"blocks_movement": false,
	},
	Constants.STATUS_BURNING: {
		"display_name": "着火",
		"type": TYPE_DEBUFF,
		"color": UiPalette.FIRE_ORANGE,
		"stack_rule": STACK_VALUE,
		"tick_phase": TICK_TURN_END,
		"true_damage": true,
		"blocks_movement": false,
	},
	Constants.STATUS_ARMOR: {
		"display_name": "护盾",
		"type": TYPE_BUFF,
		"color": UiPalette.ARMOR_STEEL,
		"stack_rule": STACK_MAX_VALUE,
		"tick_phase": TICK_TURN_END,
		"blocks_movement": false,
	},
	Constants.STATUS_LIGHT_EXPOSED: {
		"display_name": "曝光",
		"type": TYPE_DEBUFF,
		"color": UiPalette.EXPOSE_YELLOW,
		"stack_rule": STACK_VALUE,
		"tick_phase": TICK_NONE,
		"blocks_movement": false,
	},
	Constants.STATUS_BLINDED: {
		"display_name": "致盲",
		"type": TYPE_DEBUFF,
		"color": UiPalette.BLIND_SAND,
		"stack_rule": STACK_REPLACE,
		"tick_phase": TICK_TURN_START,
		"blocks_movement": false,
	},
	Constants.STATUS_ROOTED: {
		"display_name": "束缚",
		"type": TYPE_DEBUFF,
		"color": UiPalette.BIND_VIOLET,
		"stack_rule": STACK_REPLACE,
		"tick_phase": TICK_TURN_START,
		"blocks_movement": true,
	},
	Constants.STATUS_EXPOSED: {
		"display_name": "暴露",
		"type": TYPE_SYSTEM,
		"color": UiPalette.REVEAL_AMBER,
		"stack_rule": STACK_REPLACE,
		"tick_phase": TICK_TURN_END,
		"blocks_movement": false,
	},
	Constants.STATUS_LAWLESS: {
		"display_name": "失律",
		"type": TYPE_SYSTEM,
		"color": UiPalette.DISORDER_RED,
		"stack_rule": STACK_REPLACE,
		"tick_phase": TICK_NONE,
		"blocks_movement": false,
	},
	Constants.STATUS_OVERLOAD_AI_CONTROL: {
		"display_name": "AI接管",
		"type": TYPE_SYSTEM,
		"color": UiPalette.AI_MAGENTA,
		"stack_rule": STACK_REPLACE,
		"tick_phase": TICK_TURN_END,
		"blocks_movement": false,
	},
	Constants.STATUS_BOMB_RAT_PLUNDER: {
		"display_name": "无律掠夺",
		"type": TYPE_SYSTEM,
		"color": UiPalette.PLUNDER_ORANGE,
		"stack_rule": STACK_REPLACE,
		"tick_phase": TICK_NONE,
		"blocks_movement": false,
	},
	Constants.STATUS_PARALYZED: {
		"display_name": "麻痹",
		"type": TYPE_DEBUFF,
		"color": UiPalette.PARALYZE_YELLOW,
		"stack_rule": STACK_REPLACE,
		"tick_phase": TICK_TURN_START,
		"blocks_movement": true,
		"blocks_action": true,
	},
	Constants.STATUS_SLOWED: {
		"display_name": "缓速",
		"type": TYPE_DEBUFF,
		"color": UiPalette.SLOW_CYAN,
		"stack_rule": STACK_VALUE,
		"tick_phase": TICK_TURN_START,
		"blocks_movement": false,
	},
	Constants.STATUS_WET: {
		"display_name": "潮湿",
		"type": TYPE_DEBUFF,
		"color": UiPalette.WET_BLUE,
		"stack_rule": STACK_REPLACE,
		"tick_phase": TICK_TURN_END,
		"blocks_movement": false,
	},
	Constants.STATUS_SLUGGISH: {
		"display_name": "迟滞",
		"type": TYPE_DEBUFF,
		"color": UiPalette.STAGNATE_ICE,
		"stack_rule": STACK_REPLACE,
		"tick_phase": TICK_TURN_END,
		"blocks_movement": false,
	},
	Constants.STATUS_VULNERABLE: {
		"display_name": "易伤",
		"type": TYPE_DEBUFF,
		"color": UiPalette.VULNERABLE_RED,
		"stack_rule": STACK_REPLACE,
		"tick_phase": TICK_TURN_END,
		"blocks_movement": false,
	},
	Constants.STATUS_DISARMED: {
		"display_name": "缴械",
		"type": TYPE_DEBUFF,
		"color": UiPalette.VULNERABLE_RED,
		"stack_rule": STACK_VALUE,
		"tick_phase": TICK_NONE,
		"blocks_movement": false,
		"blocks_attack": true,
	},
	Constants.STATUS_WEAK: {
		"display_name": "虚弱",
		"type": TYPE_DEBUFF,
		"color": UiPalette.VULNERABLE_RED,
		"stack_rule": STACK_REPLACE,
		"tick_phase": TICK_TURN_END,
		"blocks_movement": false,
	},
	Constants.STATUS_COUNTER_MARK: {
		"display_name": "截击",
		"type": TYPE_SYSTEM,
		"color": UiPalette.DISORDER_RED,
		"stack_rule": STACK_REPLACE,
		"tick_phase": TICK_TURN_END,
		"blocks_movement": false,
	},
	Constants.STATUS_EXTRA_ATTACK: {
		"display_name": "额外攻击",
		"type": TYPE_BUFF,
		"color": UiPalette.EXPOSE_YELLOW,
		"stack_rule": STACK_VALUE,
		"tick_phase": TICK_NONE,
		"blocks_movement": false,
	},
	Constants.STATUS_EXTRA_MOVE: {
		"display_name": "额外移动",
		"type": TYPE_BUFF,
		"color": UiPalette.WET_BLUE,
		"stack_rule": STACK_VALUE,
		"tick_phase": TICK_NONE,
		"blocks_movement": false,
	},
}
