class_name UnitState
extends RefCounted

const _StatusRegistry = preload("res://scripts/rules/status_registry.gd")

var uid: String = ""
var unit_def_id: String = ""
var team: String = ""
var pos: Vector2i = Vector2i.ZERO
var facing: String = "DR"
var hp: int = 1
var max_hp: int = 1
var move_points: int = 1
var speed: int = 10
var base_attack: int = 1
var armor: int = 0  # 编辑器/单位模板字段，战斗减伤仅走护盾状态
var slots: Array = []
var statuses: Array = []
var intent: IntentState = null
var alive: bool = true
var ai_profile_id: String = ""
var behavior_id: String = ""
var tags: Array[String] = []
var split_origin_uid: String = ""  # 若此单位是分裂分身，记录原体 uid
var footprint_size: Vector2i = Vector2i(1, 1)


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
	unit.behavior_id = def.get("behavior_id", unit.ai_profile_id if not unit.ai_profile_id.is_empty() else "generic_melee")
	var fp = def.get("footprint_size", null)
	if fp is Vector2i:
		unit.footprint_size = fp
	elif fp is Array and fp.size() == 2:
		unit.footprint_size = Vector2i(int(fp[0]), int(fp[1]))
	for tag in def.get("tags", []):
		unit.add_tag(str(tag))
	for slot_data in def.get("slots", []):
		var slot := SlotState.create(
			slot_data.get("slot_type", Constants.SLOT_RED),
			slot_data.get("gem_uid", ""),
			slot_data.get("locked", false),
			slot_data.get("lock_type", "")
		)
		slot.dual_type = str(slot_data.get("dual_type", ""))
		slot.unlock_until_turn = int(slot_data.get("unlock_until_turn", -1))
		if slot.locked and slot.unlock_until_turn == -1:
			slot.unlock_until_turn = -1
		unit.slots.append(slot)
	return unit


## pos 为锚点（左上角），返回 footprint 覆盖的所有格子
func occupied_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for dx in range(footprint_size.x):
		for dy in range(footprint_size.y):
			cells.append(pos + Vector2i(dx, dy))
	return cells


func get_slot(slot_type: String) -> SlotState:
	for slot in slots:
		if slot.slot_type == slot_type:
			return slot
	return null


func slots_accepting(slot_type: String) -> Array:
	var result: Array = []
	for slot in slots:
		if slot.accepts_slot_type(slot_type):
			result.append(slot)
	return result


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


static func facing_from_step(from: Vector2i, to: Vector2i) -> String:
	var dx := to.x - from.x
	var dy := to.y - from.y
	if absi(dx) >= absi(dy):
		return "DR" if dx > 0 else "UL"
	return "DL" if dy > 0 else "UR"


static func facing_from_unit_to_cell(unit: UnitState, to_cell: Vector2i) -> String:
	if unit.footprint_size == Vector2i(1, 1):
		return facing_from_step(unit.pos, to_cell)
	var closest_cell := unit.pos
	var min_dist := 99999
	for cell in unit.occupied_cells():
		var dist := absi(cell.x - to_cell.x) + absi(cell.y - to_cell.y)
		if dist < min_dist:
			min_dist = dist
			closest_cell = cell
	if min_dist == 0:
		return unit.facing
	return facing_from_step(closest_cell, to_cell)


func clone() -> UnitState:
	var unit := UnitState.new()
	unit.uid = uid
	unit.unit_def_id = unit_def_id
	unit.team = team
	unit.pos = pos
	unit.facing = facing
	unit.hp = hp
	unit.max_hp = max_hp
	unit.move_points = move_points
	unit.speed = speed
	unit.base_attack = base_attack
	unit.armor = armor
	unit.intent = intent.clone() if intent != null else null
	unit.alive = alive
	unit.ai_profile_id = ai_profile_id
	unit.behavior_id = behavior_id
	unit.tags = tags.duplicate()
	unit.split_origin_uid = split_origin_uid
	unit.footprint_size = footprint_size
	for slot in slots:
		unit.slots.append(slot.clone() if slot != null else null)
	for status in statuses:
		unit.statuses.append(status.clone() if status != null else null)
	return unit
