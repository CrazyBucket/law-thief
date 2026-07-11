class_name EventValidator
extends RefCounted

const _PresentationPlanner = preload("res://scripts/ui/battle_presentation_planner.gd")

## 事件流基础校验器
## 规则层产出 events 数组后，可用 validate_events 对整批事件做结构检查。
## 所有校验只在调试/测试路径中被主动调用，不影响正常游戏性能。

## 各事件类型的必填字段定义。
## 凡是这里列出的字段，出现在对应类型事件中时必须非空/非 null。
const _REQUIRED_FIELDS: Dictionary = {
	"move_step": ["uid", "from", "to"],
	"damage":    ["uid", "victim_uid", "pos", "damage", "is_crit"],
	"explode":   ["pos"],
	"projectile": ["from", "to"],
	"projectile_deflect": ["from", "to"],
	"light_beam": ["from", "to"],
	"die":       ["uid"],
	"spawn":     ["uid", "pos"],
	"status":    ["uid", "status_id"],
	"heal":      ["uid", "amount"],
	"knockback": ["uid", "from", "to"],
}


## 校验整批事件，返回所有违规条目（包含事件索引）。
## 空列表代表通过。
static func validate_events(events: Array) -> Array[String]:
	var violations: Array[String] = []
	for i in range(events.size()):
		var ev = events[i]
		if not ev is Dictionary:
			violations.append("[%d] event is not a Dictionary: %s" % [i, str(ev)])
			continue
		var ev_type: String = str(ev.get("type", ""))
		if ev_type.is_empty():
			violations.append("[%d] event missing 'type' field: %s" % [i, str(ev)])
			continue
		if not _PresentationPlanner.has_policy(ev_type):
			violations.append(
				"[%d] event type '%s' has no presentation policy; choose serial or parallel playback before adding it"
				% [i, ev_type]
			)
		_check_required_fields(ev, ev_type, i, violations)
		_check_type_specific(ev, ev_type, i, violations)
	return violations


## 校验通过时断言，失败时 push_error 并返回 false。
## 用于测试脚本以及希望在调试构建中尽早发现问题的路径。
static func assert_valid(events: Array, context: String = "") -> bool:
	var violations := validate_events(events)
	if violations.is_empty():
		return true
	var prefix := "[EventValidator]" if context.is_empty() else "[EventValidator:%s]" % context
	for v in violations:
		push_error("%s %s" % [prefix, v])
	return false


# ─── 通用必填字段检查 ──────────────────────────────────────────────────────────

static func _check_required_fields(
	ev: Dictionary,
	ev_type: String,
	index: int,
	out: Array[String]
) -> void:
	if not _REQUIRED_FIELDS.has(ev_type):
		return
	var required: Array = _REQUIRED_FIELDS[ev_type]
	for field in required:
		if not ev.has(field):
			out.append("[%d] '%s' event missing required field '%s'" % [index, ev_type, field])
		else:
			var val = ev[field]
			if val == null:
				out.append("[%d] '%s' event field '%s' is null" % [index, ev_type, field])
			elif val is String and (val as String).is_empty():
				out.append("[%d] '%s' event field '%s' is empty string" % [index, ev_type, field])


# ─── 事件类型专项约束 ──────────────────────────────────────────────────────────

static func _check_type_specific(
	ev: Dictionary,
	ev_type: String,
	index: int,
	out: Array[String]
) -> void:
	match ev_type:
		"move_step":
			_check_move_step(ev, index, out)
		"damage":
			_check_damage(ev, index, out)
		"heal":
			_check_heal(ev, index, out)
		"explode":
			_check_explode(ev, index, out)


static func _check_move_step(ev: Dictionary, index: int, out: Array[String]) -> void:
	var from = ev.get("from")
	var to = ev.get("to")
	if from is Vector2i and to is Vector2i and from == to:
		out.append("[%d] 'move_step' has identical 'from' and 'to': %s" % [index, from])


static func _check_damage(ev: Dictionary, index: int, out: Array[String]) -> void:
	var damage = ev.get("damage")
	if damage is int and damage < 0:
		out.append("[%d] 'damage' event has negative damage value: %d" % [index, damage])
	var is_crit = ev.get("is_crit")
	if is_crit != null and not is_crit is bool:
		out.append("[%d] 'damage' event 'is_crit' must be bool, got: %s" % [index, str(is_crit)])
	if ev.has("damage_tags"):
		var tags: Variant = ev["damage_tags"]
		if not tags is Array:
			out.append("[%d] 'damage' event 'damage_tags' must be an Array" % index)
		else:
			var seen: Dictionary = {}
			for raw_tag in tags:
				if not raw_tag is String or str(raw_tag).is_empty():
					out.append("[%d] 'damage' event has an invalid damage tag: %s" % [index, str(raw_tag)])
					continue
				if seen.has(raw_tag):
					out.append("[%d] 'damage' event has duplicate damage tag: %s" % [index, raw_tag])
				seen[raw_tag] = true


static func _check_heal(ev: Dictionary, index: int, out: Array[String]) -> void:
	var amount = ev.get("amount")
	if amount is int and amount < 0:
		out.append("[%d] 'heal' event has negative amount value: %d" % [index, amount])


static func _check_explode(ev: Dictionary, index: int, out: Array[String]) -> void:
	var pos = ev.get("pos")
	if pos != null and not pos is Vector2i:
		out.append("[%d] 'explode' event 'pos' is not a Vector2i: %s" % [index, str(pos)])
