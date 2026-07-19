class_name SplitMoveRules
extends RefCounted

## 游标卡尺的暂存只属于第一段移动的单位；控制类状态在施加时立即使其失效。
static func invalidate_if_blocked(state: GameState, unit: UnitState) -> void:
	if unit != null and state.split_move_uid == unit.uid:
		state.clear_split_move()


## 移动力降低只扣除相同差值，之后恢复或新增移动力不会返还已损失的暂存。
static func reconcile_capacity(state: GameState, unit: UnitState, current_capacity: int) -> void:
	if unit != null and state.split_move_uid == unit.uid:
		state.reconcile_split_move(unit.uid, current_capacity)
