class_name FrozenStatusRules
extends RefCounted

const _CombatTransaction = preload("res://scripts/rules/combat_transaction.gd")
const _SplitMoveRules = preload("res://scripts/rules/split_move_rules.gd")
const _StatusRegistry = preload("res://scripts/rules/status_registry.gd")
const StatusConfig = preload("res://scripts/core/status_config.gd")


static func apply(
	state: GameState,
	unit: UnitState,
	duration: int = -1,
	source_uid: String = ""
) -> void:
	var resolved_duration := duration if duration >= 0 else StatusConfig.default_duration("frozen")
	var incoming := StatusInstance.create(
		Constants.STATUS_FROZEN,
		1,
		maxi(1, resolved_duration),
		source_uid
	)
	_CombatTransaction.begin_from_state(state).apply_status(
		unit,
		incoming,
		{"emit_event": false, "reason": "frozen_status_apply"}
	)
	unit.remove_status(Constants.STATUS_WET)
	_SplitMoveRules.invalidate_if_blocked(state, unit)
	state.log("%s 获得状态 %s" % [unit.uid, _StatusRegistry.display_name(Constants.STATUS_FROZEN)])


static func is_frozen(unit: UnitState) -> bool:
	return unit != null and unit.has_status(Constants.STATUS_FROZEN)
