class_name StatusActionRules
extends RefCounted

const _StatusRegistry = preload("res://scripts/rules/status_registry.gd")


static func can_move(unit: UnitState) -> bool:
	if unit == null:
		return false
	for status in unit.statuses:
		if _StatusRegistry.blocks_movement(status.status_id):
			return false
	return true


static func can_attack(unit: UnitState) -> bool:
	if unit == null:
		return false
	for status in unit.statuses:
		if _StatusRegistry.blocks_attack(status.status_id):
			return false
	return true


static func can_act(unit: UnitState) -> bool:
	if unit == null:
		return false
	for status in unit.statuses:
		if _StatusRegistry.blocks_action(status.status_id):
			return false
	return true


static func move_block_reason(unit: UnitState) -> String:
	for status in unit.statuses:
		if not _StatusRegistry.blocks_movement(status.status_id):
			continue
		match status.status_id:
			Constants.STATUS_PARALYZED:
				return "被麻痹，无法移动"
			Constants.STATUS_FROZEN:
				return _translated("status.frozen.move_block", "被冻结，无法移动")
			Constants.STATUS_ROOTED:
				return "被束缚，无法移动"
	return ""


static func action_block_reason(unit: UnitState) -> String:
	if unit != null and unit.has_status(Constants.STATUS_FROZEN):
		return _translated("status.frozen.block", "被冻结，无法行动")
	if unit != null and unit.has_status(Constants.STATUS_PARALYZED):
		return _translated("status.paralyzed.block", "被麻痹，无法行动")
	return ""


static func turn_skip_status(unit: UnitState) -> String:
	if unit == null:
		return ""
	if unit.has_status(Constants.STATUS_FROZEN):
		return Constants.STATUS_FROZEN
	if unit.has_status(Constants.STATUS_PARALYZED):
		return Constants.STATUS_PARALYZED
	return ""


static func consume_turn_skip_status(unit: UnitState) -> String:
	var status_id := turn_skip_status(unit)
	if status_id.is_empty():
		return ""
	unit.remove_status(status_id)
	return status_id


static func has_extra_attack(unit: UnitState) -> bool:
	return _has_stack_status(unit, Constants.STATUS_EXTRA_ATTACK)


static func has_extra_move(unit: UnitState) -> bool:
	return _has_stack_status(unit, Constants.STATUS_EXTRA_MOVE)


static func consume_extra_attack(unit: UnitState) -> bool:
	return _consume_stack_status(unit, Constants.STATUS_EXTRA_ATTACK)


static func consume_extra_move(unit: UnitState) -> bool:
	return _consume_stack_status(unit, Constants.STATUS_EXTRA_MOVE)


static func clear_extra_actions(unit: UnitState) -> void:
	if unit == null:
		return
	unit.remove_status(Constants.STATUS_EXTRA_ATTACK)
	unit.remove_status(Constants.STATUS_EXTRA_MOVE)


static func effective_move_points(unit: UnitState, base: int, default_min_move_points: int) -> int:
	if unit == null:
		return base
	var slow: StatusInstance = unit.get_status(Constants.STATUS_SLOWED)
	if slow == null:
		return base
	var min_move_points := int(slow.payload.get("min_move_points", default_min_move_points))
	return maxi(min_move_points, base - slow.stacks)


static func _has_stack_status(unit: UnitState, status_id: String) -> bool:
	if unit == null:
		return false
	var status: StatusInstance = unit.get_status(status_id)
	return status != null and status.stacks > 0


static func _consume_stack_status(unit: UnitState, status_id: String) -> bool:
	if unit == null:
		return false
	var status: StatusInstance = unit.get_status(status_id)
	if status == null or status.stacks <= 0:
		return false
	status.stacks -= 1
	if status.stacks <= 0:
		unit.remove_status(status_id)
	return true


static func _translated(key: String, fallback: String) -> String:
	var text := TranslationServer.translate(key)
	return fallback if text == key else text
