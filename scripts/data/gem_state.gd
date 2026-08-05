class_name GemState
extends RefCounted

const _GemLocation = preload("res://scripts/data/gem_location.gd")

var uid: String = ""
var gem_id: String = ""
var location = _GemLocation.detached()
## 兼容旧存档与只读调用；运行时位置变更必须走 GemTransfer。
var owner_uid: String:
	get:
		return location.owner_uid
	set(value):
		location.owner_uid = value
		_infer_legacy_location_kind()
var slot_index: int:
	get:
		return location.slot_index
	set(value):
		location.slot_index = value
		_infer_legacy_location_kind()
var def_overrides: Dictionary = {}


static func create(uid: String, gem_id: String, def_overrides: Dictionary = {}) -> GemState:
	var gem := GemState.new()
	gem.uid = uid
	gem.gem_id = gem_id
	gem.def_overrides = def_overrides.duplicate(true)
	return gem


## GemTransfer 是跨 GameState 容器的唯一运行时写入口；这些方法只维护宝石自身的位置镜像。
func mark_detached() -> void:
	location = _GemLocation.detached()


func mark_held(holder_uid: String) -> void:
	location = _GemLocation.hand(holder_uid)


func mark_slotted(slot_owner_uid: String, index: int) -> void:
	location = _GemLocation.unit_slot(slot_owner_uid, index) if not slot_owner_uid.is_empty() \
		else _GemLocation.detached()


func mark_unit_slotted(unit_uid: String, index: int) -> void:
	location = _GemLocation.unit_slot(unit_uid, index)


func mark_ground(drop_pos: Vector2i) -> void:
	location = _GemLocation.ground(drop_pos)


func clone() -> GemState:
	var gem := GemState.new()
	gem.uid = uid
	gem.gem_id = gem_id
	gem.location = location.clone()
	gem.def_overrides = def_overrides.duplicate(true)
	return gem


func _infer_legacy_location_kind() -> void:
	location.pos = Vector2i(-1, -1)
	if location.slot_index >= 0:
		location.kind = _GemLocation.UNIT_SLOT if not location.owner_uid.is_empty() else _GemLocation.DETACHED
	elif not location.owner_uid.is_empty():
		location.kind = _GemLocation.HAND
	else:
		location.kind = _GemLocation.DETACHED
