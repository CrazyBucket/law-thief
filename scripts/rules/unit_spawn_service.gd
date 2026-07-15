class_name UnitSpawnService
extends RefCounted

const _CombatTransaction = preload("res://scripts/rules/combat_transaction.gd")
const _EventBuilder = preload("res://scripts/rules/combat_event_builder.gd")
const _UnitRewardRules = preload("res://scripts/rules/unit_reward_rules.gd")
const _GemTransfer = preload("res://scripts/rules/gem_transfer.gd")


static func spawn_from_def(
	state: GameState,
	unit_def_id: String,
	team: String,
	pos: Vector2i,
	events: Array[Dictionary] = [],
	opts: Dictionary = {}
) -> Dictionary:
	var registry := _data_registry()
	if registry == null or not registry.has_unit_def(unit_def_id):
		return {"ok": false, "reason": "unknown_unit_def", "events": events}
	var uid := str(opts.get("uid", ""))
	if uid.is_empty():
		uid = str(registry.next_runtime_uid(unit_def_id))
	var unit := UnitState.from_def(uid, unit_def_id, team, pos, registry.get_unit_def(unit_def_id))
	var result := register_spawn(state, unit, events, opts)
	result["unit"] = unit if bool(result.get("ok", false)) else null
	return result


static func register_spawn(
	state: GameState,
	unit: UnitState,
	events: Array[Dictionary] = [],
	opts: Dictionary = {}
) -> Dictionary:
	if state == null or unit == null:
		return {"ok": false, "reason": "invalid_spawn", "events": events}
	var origin: UnitState = opts.get("origin", null)
	if bool(opts.get("root_spawn", false)):
		_UnitRewardRules.configure_root(unit)
	else:
		_UnitRewardRules.configure_spawn(unit, origin, opts)
	var tx := _CombatTransaction.begin(state, events)
	var event_kind := str(opts.get("event_kind", "spawn"))
	var spawn_opts := opts.duplicate(true)
	spawn_opts["emit_event"] = event_kind == "spawn"
	if not tx.spawn_unit(unit, spawn_opts):
		return {"ok": false, "reason": tx.errors[0] if not tx.errors.is_empty() else "spawn_rejected", "events": events}
	_GemTransfer.reindex_unit(state, unit)
	if event_kind == "split_spawn":
		tx.append_event(_EventBuilder.split_spawn(unit, opts))
	if bool(opts.get("refresh_intent", unit.team == Constants.TEAM_ENEMY)):
		load("res://scripts/rules/intent_system.gd").refresh_unit_intent(state, unit)
	return {"ok": true, "unit": unit, "events": tx.finish("UnitSpawnService.register_spawn")}


static func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("DataRegistry")
