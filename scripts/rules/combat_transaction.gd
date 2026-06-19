class_name CombatTransaction
extends RefCounted

const _EventBuilder = preload("res://scripts/rules/combat_event_builder.gd")
const _EventValidator = preload("res://scripts/debug/event_validator.gd")
const _InvariantChecker = preload("res://scripts/debug/battle_invariant_checker.gd")

var state: GameState = null
var events: Array[Dictionary] = []
var _bound_event_sink: bool = false


static func begin(battle_state: GameState, existing_events: Array[Dictionary] = []) -> CombatTransaction:
	var tx := CombatTransaction.new()
	tx.state = battle_state
	tx.events = existing_events
	return tx


static func begin_from_state(battle_state: GameState) -> CombatTransaction:
	if battle_state != null and battle_state.has_combat_event_sink():
		return begin(battle_state, battle_state.get_combat_event_sink())
	return begin(battle_state)


func bind_event_sink() -> CombatTransaction:
	if state == null or _bound_event_sink:
		return self
	if state.has_combat_event_sink():
		return self
	state.bind_combat_events(events)
	_bound_event_sink = true
	return self


func move_unit(unit: UnitState, to_pos: Vector2i, opts: Dictionary = {}) -> void:
	if state == null or unit == null or not unit.alive:
		return
	var from_pos := unit.pos
	if from_pos == to_pos:
		return
	if not bool(opts.get("keep_facing", false)):
		unit.facing = UnitState.facing_from_step(from_pos, to_pos)
	state.move_unit(unit, to_pos)
	if bool(opts.get("emit_signal", true)):
		state.on_unit_move.emit(unit.uid, from_pos, to_pos)
	if bool(opts.get("emit_event", true)):
		append_event(_EventBuilder.move_step(unit.uid, from_pos, to_pos, opts))


func damage_unit(unit: UnitState, amount: int, source_uid: String, reason: String, opts: Dictionary = {}) -> int:
	if state == null or unit == null or not unit.alive or amount <= 0:
		return 0
	var had_event_sink := state.has_combat_event_sink()
	if not had_event_sink:
		state.bind_combat_events(events)
	var dealt := CombatRules.apply_damage(state, unit, amount, source_uid, reason)
	if not had_event_sink:
		state.unbind_combat_events()
	if dealt <= 0:
		return 0
	var event_opts := _damage_event_opts(unit, source_uid, reason, opts)
	append_event(_EventBuilder.damage(unit, dealt, event_opts))
	return dealt


func true_damage_unit(unit: UnitState, amount: int, source_uid: String, reason: String, opts: Dictionary = {}) -> int:
	if state == null or unit == null or not unit.alive or amount <= 0:
		return 0
	var had_event_sink := state.has_combat_event_sink()
	if not had_event_sink:
		state.bind_combat_events(events)
	var dealt := CombatRules.apply_true_damage(state, unit, amount, source_uid, reason)
	if not had_event_sink:
		state.unbind_combat_events()
	if dealt <= 0:
		return 0
	var event_opts := _damage_event_opts(unit, source_uid, reason, opts)
	append_event(_EventBuilder.damage(unit, dealt, event_opts))
	return dealt


func append_event(event: Dictionary) -> void:
	if event.is_empty():
		return
	events.append(event)


func append_events(new_events: Array) -> void:
	for event in new_events:
		if event is Dictionary:
			append_event(event)


func finish(context: String = "") -> Array[Dictionary]:
	if OS.is_debug_build():
		_EventValidator.assert_valid(events, context)
		if state != null:
			_InvariantChecker.assert_valid(state, context)
	if _bound_event_sink and state != null:
		state.unbind_combat_events()
		_bound_event_sink = false
	return events


func _damage_event_opts(unit: UnitState, source_uid: String, reason: String, opts: Dictionary) -> Dictionary:
	var event_opts := opts.duplicate(true)
	event_opts["attacker_uid"] = source_uid
	event_opts["source_uid"] = source_uid
	event_opts["reason"] = reason
	event_opts["lethal"] = not unit.alive
	event_opts["remaining_hp"] = unit.hp
	return event_opts
