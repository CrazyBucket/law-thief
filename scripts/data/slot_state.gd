class_name SlotState
extends RefCounted

var slot_type: String = ""
## 双色槽第二颜色；非空时，该槽接受 slot_type 或 dual_type 的宝石嵌入
var dual_type: String = ""
var gem_uid: String = ""
var locked: bool = false
var lock_type: String = ""
var unlock_until_turn: int = -1
## 过载是槽位来源身份，不是临时锁状态；分裂禁用不得覆盖它。
var overload_slot: bool = false


static func create(slot_type: String, gem_uid: String = "", locked: bool = false, lock_type: String = "") -> SlotState:
	var slot := SlotState.new()
	slot.slot_type = slot_type
	slot.gem_uid = gem_uid
	slot.locked = locked
	slot.lock_type = lock_type
	slot.overload_slot = lock_type == Constants.LOCK_OVERLOAD_SLOT
	return slot


func clone() -> SlotState:
	var slot := SlotState.new()
	slot.slot_type = slot_type
	slot.dual_type = dual_type
	slot.gem_uid = gem_uid
	slot.locked = locked
	slot.lock_type = lock_type
	slot.unlock_until_turn = unlock_until_turn
	slot.overload_slot = overload_slot
	return slot


## 判断某个 slot_type 的宝石能否嵌入该槽（普通槽精确匹配，双色槽任一颜色均可）
func accepts_slot_type(query_type: String) -> bool:
	if slot_type == query_type:
		return true
	if not dual_type.is_empty() and dual_type == query_type:
		return true
	return false


func is_empty() -> bool:
	return gem_uid.is_empty()


func is_split_disabled() -> bool:
	return lock_type == Constants.LOCK_SPLIT_DISABLED


func is_overload_slot() -> bool:
	# lock_type fallback keeps old saves and fixtures compatible.
	return overload_slot or lock_type == Constants.LOCK_OVERLOAD_SLOT


func is_operable(turn_index: int) -> bool:
	if is_split_disabled():
		return false
	if locked:
		if unlock_until_turn < 0:
			return false
		if unlock_until_turn >= turn_index:
			return false
		locked = false
		lock_type = ""
	return true
