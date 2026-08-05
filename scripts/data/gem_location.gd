class_name GemLocation
extends RefCounted

const DETACHED := "detached"
const HAND := "hand"
const UNIT_SLOT := "unit_slot"
const GROUND := "ground"

var kind: String = DETACHED
var owner_uid: String = ""
var slot_index: int = -1
var pos: Vector2i = Vector2i(-1, -1)


static func detached():
	return load("res://scripts/data/gem_location.gd").new()


static func hand(holder_uid: String):
	var value = load("res://scripts/data/gem_location.gd").new()
	value.kind = HAND
	value.owner_uid = holder_uid
	return value


static func unit_slot(unit_uid: String, index: int):
	var value = load("res://scripts/data/gem_location.gd").new()
	value.kind = UNIT_SLOT
	value.owner_uid = unit_uid
	value.slot_index = index
	return value


static func ground(drop_pos: Vector2i):
	var value = load("res://scripts/data/gem_location.gd").new()
	value.kind = GROUND
	value.pos = drop_pos
	return value


static func from_dict(data: Dictionary):
	var value = load("res://scripts/data/gem_location.gd").new()
	value.kind = str(data.get("kind", DETACHED))
	value.owner_uid = str(data.get("owner_uid", ""))
	value.slot_index = int(data.get("slot_index", -1))
	var raw_pos: Variant = data.get("pos", Vector2i(-1, -1))
	if raw_pos is Vector2i:
		value.pos = raw_pos
	return value


func clone():
	return from_dict(to_dict())


func to_dict() -> Dictionary:
	return {
		"kind": kind,
		"owner_uid": owner_uid,
		"slot_index": slot_index,
		"pos": pos,
	}


func equals(other) -> bool:
	return other != null \
		and kind == other.kind \
		and owner_uid == other.owner_uid \
		and slot_index == other.slot_index \
		and pos == other.pos


func is_valid() -> bool:
	match kind:
		DETACHED:
			return owner_uid.is_empty() and slot_index == -1 and pos == Vector2i(-1, -1)
		HAND:
			return not owner_uid.is_empty() and slot_index == -1 and pos == Vector2i(-1, -1)
		UNIT_SLOT:
			return not owner_uid.is_empty() and slot_index >= 0 and pos == Vector2i(-1, -1)
		GROUND:
			return owner_uid.is_empty() and slot_index == -1 and pos != Vector2i(-1, -1)
	return false


func describe() -> String:
	match kind:
		HAND:
			return "hand:%s" % owner_uid
		UNIT_SLOT:
			return "unit:%s:%d" % [owner_uid, slot_index]
		GROUND:
			return "ground:%s" % pos
	return DETACHED
