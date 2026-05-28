class_name UnitState
extends RefCounted

const _StatusRegistry = preload("res://scripts/rules/status_registry.gd")

var uid: String = ""
var unit_def_id: String = ""
var team: String = ""
var pos: Vector2i = Vector2i.ZERO
var hp: int = 1
var max_hp: int = 1
var move_points: int = 1
var speed: int = 10
var base_attack: int = 1
var armor: int = 0
var slots: Array = []
var statuses: Array = []
var intent: IntentState = null
var alive: bool = true
var ai_profile_id: String = ""
var tags: Array[String] = []


static func from_def(uid: String, unit_def_id: String, team: String, pos: Vector2i, def: Dictionary) -> UnitState:
	var unit := UnitState.new()
	unit.uid = uid
	unit.unit_def_id = unit_def_id
	unit.team = team
	unit.pos = pos
	unit.hp = def.get("max_hp", 1)
	unit.max_hp = def.get("max_hp", 1)
	unit.move_points = def.get("move_points", 1)
	unit.speed = def.get("speed", 10)
	unit.base_attack = def.get("base_attack", 1)
	unit.armor = def.get("armor", 0)
	unit.ai_profile_id = def.get("ai_profile_id", "melee_chase")
	for tag in def.get("tags", []):
		unit.add_tag(str(tag))
	for slot_data in def.get("slots", []):
		unit.slots.append(
			SlotState.create(
				slot_data.get("slot_type", Constants.SLOT_RED),
				slot_data.get("gem_uid", ""),
				slot_data.get("locked", false),
				slot_data.get("lock_type", "")
			)
		)
	return unit


func get_slot(slot_type: String) -> SlotState:
	for slot in slots:
		if slot.slot_type == slot_type:
			return slot
	return null


func get_slot_by_index(index: int) -> SlotState:
	if index < 0 or index >= slots.size():
		return null
	return slots[index]


func has_status(status_id: String) -> bool:
	for status in statuses:
		if status.status_id == status_id:
			return true
	return false


func get_status(status_id: String) -> StatusInstance:
	for status in statuses:
		if status.status_id == status_id:
			return status
	return null


func remove_status(status_id: String) -> void:
	statuses = statuses.filter(func(item): return item.status_id != status_id)


func list_statuses() -> Array:
	return _StatusRegistry.sort_statuses(statuses)


func has_tag(tag: String) -> bool:
	return tag in tags


func add_tag(tag: String) -> void:
	if tag not in tags:
		tags.append(tag)


func remove_tag(tag: String) -> void:
	tags.erase(tag)


func clone() -> UnitState:
	var unit := UnitState.new()
	unit.uid = uid
	unit.unit_def_id = unit_def_id
	unit.team = team
	unit.pos = pos
	unit.hp = hp
	unit.max_hp = max_hp
	unit.move_points = move_points
	unit.speed = speed
	unit.base_attack = base_attack
	unit.armor = armor
	unit.intent = intent.clone() if intent != null else null
	unit.alive = alive
	unit.ai_profile_id = ai_profile_id
	unit.tags = tags.duplicate()
	for slot in slots:
		unit.slots.append(slot.clone() if slot != null else null)
	for status in statuses:
		unit.statuses.append(status.clone() if status != null else null)
	return unit
