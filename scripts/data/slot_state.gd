class_name SlotState
extends RefCounted

var slot_type: String = ""
var gem_uid: String = ""
var locked: bool = false
var lock_type: String = ""
var unlock_until_turn: int = -1


static func create(slot_type: String, gem_uid: String = "", locked: bool = false, lock_type: String = "") -> SlotState:
	var slot := SlotState.new()
	slot.slot_type = slot_type
	slot.gem_uid = gem_uid
	slot.locked = locked
	slot.lock_type = lock_type
	return slot


func is_empty() -> bool:
	return gem_uid.is_empty()


func is_operable(turn_index: int) -> bool:
	if locked:
		if unlock_until_turn >= turn_index:
			return false
		locked = false
		lock_type = ""
	return true
