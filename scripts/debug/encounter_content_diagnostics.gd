class_name EncounterContentDiagnostics
extends RefCounted

const EMPTY_ENEMY_GEMS := "enemy_empty_gems"
const ALLOW_EMPTY_TAG := "unit:allow_empty_gems"
const TEST_FIXTURE_TAG := "unit:test_fixture"


static func refresh(state: GameState) -> Array[Dictionary]:
	var warnings := collect(state)
	state.content_warnings = warnings.duplicate(true)
	return warnings


static func refresh_messages(state: GameState) -> Array[String]:
	var messages: Array[String] = []
	for warning in refresh(state):
		messages.append(format_warning(warning))
	return messages


static func report(state: GameState) -> void:
	for message in refresh_messages(state):
		push_warning(message)


static func collect(state: GameState) -> Array[Dictionary]:
	var warnings: Array[Dictionary] = []
	if state == null:
		return warnings
	for unit_value in state.units.values():
		var unit := unit_value as UnitState
		if not _requires_warning(unit):
			continue
		warnings.append({
			"code": EMPTY_ENEMY_GEMS,
			"severity": "warning",
			"encounter_id": state.encounter_id,
			"uid": unit.uid,
			"unit_def_id": unit.unit_def_id,
			"pos": unit.pos,
		})
	warnings.sort_custom(_sort_warnings)
	return warnings


static func format_warning(warning: Dictionary) -> String:
	var pos: Vector2i = warning.get("pos", Vector2i.ZERO)
	return (
		"Encounter '%s' enemy '%s' (%s) at (%d, %d) has gem slots but no gem; "
		+ "set allow_empty_gems=true only when this is intentional."
	) % [
		str(warning.get("encounter_id", "")),
		str(warning.get("uid", "")),
		str(warning.get("unit_def_id", "")),
		pos.x,
		pos.y,
	]


static func _requires_warning(unit: UnitState) -> bool:
	if unit == null or not unit.alive or unit.team != Constants.TEAM_ENEMY:
		return false
	if unit.slots.is_empty() or unit.has_tag(ALLOW_EMPTY_TAG) or unit.has_tag(TEST_FIXTURE_TAG):
		return false
	for slot_value in unit.slots:
		var slot := slot_value as SlotState
		if slot != null and not slot.gem_uid.is_empty():
			return false
	return true


static func _sort_warnings(a: Dictionary, b: Dictionary) -> bool:
	var a_pos: Vector2i = a.get("pos", Vector2i.ZERO)
	var b_pos: Vector2i = b.get("pos", Vector2i.ZERO)
	if a_pos.y != b_pos.y:
		return a_pos.y < b_pos.y
	if a_pos.x != b_pos.x:
		return a_pos.x < b_pos.x
	return str(a.get("uid", "")) < str(b.get("uid", ""))
