class_name AttackContext
extends RefCounted

const CombatTransaction = preload("res://scripts/rules/combat_transaction.gd")
const DamageContext = preload("res://scripts/rules/damage_context.gd")

var state: GameState
var attacker: UnitState
var aim_cell: Vector2i
var target: UnitState = null

var tags: Array[String] = []
var base_damage: int = 0
var events: Array[Dictionary] = []
var payload: Dictionary = {}
var trace: Array[Dictionary] = []
## Per-cell identity retained for the duration of one attack. Damage targeting
## still comes from live occupancy; cell/TAG effects may use a defeated anchor.
var _effect_anchors: Dictionary = {}


func _init(p_state: GameState, p_attacker: UnitState, p_aim_cell: Vector2i, p_target: UnitState = null) -> void:
	state = p_state
	attacker = p_attacker
	aim_cell = p_aim_cell
	target = p_target
	if target != null:
		_effect_anchors[target.pos] = target


func add_tag(tag: String) -> void:
	if tag not in tags:
		tags.append(tag)


func has_tag(tag: String) -> bool:
	return tag in tags


func remove_tag(tag: String) -> void:
	tags.erase(tag)


func push_event(event: Dictionary) -> void:
	events.append(event)


func build_damage_context(reason: String, opts: Dictionary = {}) -> Dictionary:
	var gem_ctx: Dictionary = opts.get("gem_tag_context", payload.get("gem_tag_context", {}))
	var context := DamageContext.create(
		attacker.uid,
		reason,
		opts.get("damage_tags", []),
		gem_ctx,
		bool(opts.get("active_attack", false))
	)
	var attack_event_id := str(payload.get("current_attack_event_id", payload.get("attack_event_id", "")))
	if not attack_event_id.is_empty():
		context["attack_event_id"] = attack_event_id
	context["attack_segment_index"] = int(payload.get("attack_segment_index", 0))
	context["attack_segment_count"] = int(payload.get("attack_segment_count", 1))
	return context


func damage_unit(unit: UnitState, amount: int, reason: String, opts: Dictionary = {}) -> int:
	var damage_opts := opts.duplicate(true)
	if not damage_opts.has("damage_context"):
		damage_opts["damage_context"] = build_damage_context(reason, damage_opts)
	var transaction := CombatTransaction.begin(state, events)
	return transaction.damage_unit(unit, amount, attacker.uid, reason, damage_opts)


func effect_anchor_at(cell: Vector2i, live_target: UnitState = null) -> UnitState:
	if live_target != null:
		_effect_anchors[cell] = live_target
		return live_target
	return _effect_anchors.get(cell, null)


func push_trace(step: Dictionary) -> void:
	if payload.get("debug_trace", false):
		trace.append(step)
