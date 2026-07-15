class_name CombatTransaction
extends RefCounted

const _EventBuilder = preload("res://scripts/rules/combat_event_builder.gd")
const _EventValidator = preload("res://scripts/debug/event_validator.gd")
const _InvariantChecker = preload("res://scripts/debug/battle_invariant_checker.gd")
const DamageContext = preload("res://scripts/rules/damage_context.gd")
const _GemLocation = preload("res://scripts/data/gem_location.gd")
const _GemTransfer = preload("res://scripts/rules/gem_transfer.gd")
const _StatusRegistry = preload("res://scripts/rules/status_registry.gd")

var state: GameState = null
var events: Array[Dictionary] = []
var _bound_event_sink: bool = false
var errors: Array[String] = []


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
	var event_start := events.size()
	if not had_event_sink:
		state.bind_combat_events(events)
	var damage_context := DamageContext.from_options(source_uid, reason, opts)
	var dealt := CombatRules.apply_damage(state, unit, amount, source_uid, reason, damage_context)
	if not had_event_sink:
		state.unbind_combat_events()
	if dealt <= 0:
		return 0
	var event_opts := _damage_event_opts(unit, source_uid, reason, opts, damage_context)
	events.insert(event_start, _EventBuilder.damage(unit, dealt, event_opts))
	return dealt


func true_damage_unit(unit: UnitState, amount: int, source_uid: String, reason: String, opts: Dictionary = {}) -> int:
	if state == null or unit == null or not unit.alive or amount <= 0:
		return 0
	var had_event_sink := state.has_combat_event_sink()
	var event_start := events.size()
	if not had_event_sink:
		state.bind_combat_events(events)
	var damage_context := DamageContext.from_options(source_uid, reason, opts)
	var dealt := CombatRules.apply_true_damage(state, unit, amount, source_uid, reason, damage_context)
	if not had_event_sink:
		state.unbind_combat_events()
	if dealt <= 0:
		return 0
	var event_opts := _damage_event_opts(unit, source_uid, reason, opts, damage_context)
	events.insert(event_start, _EventBuilder.damage(unit, dealt, event_opts))
	return dealt


func kill_unit(unit: UnitState, killer_uid: String = "", reason: String = "transaction_kill", opts: Dictionary = {}) -> bool:
	if state == null or unit == null or not unit.alive:
		return _reject("cannot kill missing or dead unit")
	true_damage_unit(unit, maxi(1, unit.hp), killer_uid, reason, opts)
	return not unit.alive


func spawn_unit(unit: UnitState, opts: Dictionary = {}) -> bool:
	if state == null or unit == null or unit.uid.is_empty():
		return _reject("cannot spawn missing unit or uid")
	if state.units.has(unit.uid):
		return _reject("unit uid already registered: %s" % unit.uid)
	if bool(opts.get("validate_placement", true)) \
		and not BoardUtils.unit_footprint_passable(state, unit, unit.pos, unit.uid):
		return _reject("spawn footprint is blocked: %s" % unit.pos)
	state.register_unit(unit)
	if bool(opts.get("emit_event", true)):
		var event_opts := opts.duplicate(true)
		event_opts["spawn_origin_uid"] = unit.spawn_origin_uid
		event_opts["reward_origin_uid"] = unit.reward_origin_uid
		event_opts["grants_death_rewards"] = unit.grants_death_rewards
		event_opts["temporary"] = unit.is_temporary_summon
		append_event(_EventBuilder.spawn(unit, event_opts))
	return true


func apply_status(unit: UnitState, status_value: StatusInstance, opts: Dictionary = {}) -> bool:
	if state == null or unit == null or not unit.alive or status_value == null or status_value.status_id.is_empty():
		return _reject("cannot apply invalid status")
	_StatusRegistry.apply_to_unit(unit, status_value)
	if bool(opts.get("emit_event", true)):
		append_event(_EventBuilder.status(unit, status_value, opts))
	return true


func transfer_gem(gem: GemState, target, opts: Dictionary = {}) -> bool:
	if state == null or gem == null or target == null:
		return _reject("cannot transfer missing gem or location")
	var from_location: Dictionary = gem.location.to_dict()
	var moved := false
	match target.kind:
		_GemLocation.DETACHED:
			moved = _GemTransfer.detach(state, gem)
		_GemLocation.HAND:
			moved = _GemTransfer.to_hand(state, gem, target.owner_uid)
		_GemLocation.UNIT_SLOT:
			var unit: UnitState = state.units.get(target.owner_uid, null)
			var slot: SlotState = unit.get_slot_by_index(target.slot_index) if unit != null else null
			moved = _GemTransfer.to_unit_slot(state, gem, unit, slot)
		_GemLocation.TILE_SLOT:
			var tile: TileState = state.get_tile(target.pos)
			var slot: SlotState = tile.slots[target.slot_index] if target.slot_index >= 0 and target.slot_index < tile.slots.size() else null
			moved = _GemTransfer.to_tile_slot(state, gem, tile, slot)
		_GemLocation.GROUND:
			moved = _GemTransfer.to_ground(state, gem, target.pos, opts.get("metadata", {}))
		_:
			return _reject("unknown gem location: %s" % str(target.kind))
	if not moved:
		return _reject("gem transfer rejected: %s -> %s" % [gem.uid, target.describe()])
	if bool(opts.get("emit_event", true)):
		append_event(_EventBuilder.gem_transfer(gem.uid, from_location, gem.location.to_dict(), opts))
	return true


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


func is_valid() -> bool:
	return errors.is_empty()


func _reject(message: String) -> bool:
	errors.append(message)
	return false


func _damage_event_opts(
	unit: UnitState,
	source_uid: String,
	reason: String,
	opts: Dictionary,
	damage_context: Dictionary
) -> Dictionary:
	var event_opts := opts.duplicate(true)
	event_opts["attacker_uid"] = source_uid
	event_opts["source_uid"] = source_uid
	event_opts["reason"] = reason
	event_opts["lethal"] = not unit.alive
	event_opts["remaining_hp"] = unit.hp
	event_opts["damage_tags"] = DamageContext.tags(damage_context)
	return event_opts
