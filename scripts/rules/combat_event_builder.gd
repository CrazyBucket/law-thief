class_name CombatEventBuilder
extends RefCounted


static func move_step(uid: String, from_pos: Vector2i, to_pos: Vector2i, opts: Dictionary = {}) -> Dictionary:
	var ev := {
		"type": "move_step",
		"uid": uid,
		"from": from_pos,
		"to": to_pos,
	}
	_copy_optional(ev, opts, ["source_uid", "reason", "path_index", "path_total"])
	if opts.has("forced"):
		ev["forced"] = bool(opts["forced"])
	return ev


static func displacement_impact(
	uid: String,
	from_pos: Vector2i,
	contact_pos: Vector2i,
	opts: Dictionary = {}
) -> Dictionary:
	var ev := {
		"type": "displacement_impact",
		"uid": uid,
		"from": from_pos,
		"contact": contact_pos,
		"forced": true,
	}
	_copy_optional(ev, opts, [
		"source_uid", "reason", "blocker_kind", "blocker_uid", "entity_id"
	])
	return ev


static func damage(unit: UnitState, amount: int, opts: Dictionary = {}) -> Dictionary:
	var pos: Vector2i = opts.get("pos", unit.pos if unit != null else Vector2i.ZERO)
	var uid := unit.uid if unit != null else str(opts.get("uid", opts.get("victim_uid", "")))
	var ev := {
		"type": "damage",
		"uid": uid,
		"victim_uid": uid,
		"pos": pos,
		"damage": amount,
		"is_crit": bool(opts.get("is_crit", false)),
	}
	_copy_optional(ev, opts, ["attacker_uid", "source_uid", "reason", "lethal", "remaining_hp", "keep_facing", "damage_tags"])
	return ev


static func damage_at(pos: Vector2i, amount: int, opts: Dictionary = {}) -> Dictionary:
	var ev := {
		"type": "damage",
		"pos": pos,
		"damage": amount,
		"is_crit": bool(opts.get("is_crit", false)),
	}
	_copy_optional(ev, opts, ["uid", "victim_uid", "attacker_uid", "source_uid", "reason", "lethal", "remaining_hp", "keep_facing", "damage_tags"])
	if ev.has("uid") and not ev.has("victim_uid"):
		ev["victim_uid"] = ev["uid"]
	elif ev.has("victim_uid") and not ev.has("uid"):
		ev["uid"] = ev["victim_uid"]
	return ev


static func explode(pos: Vector2i, radius: int, opts: Dictionary = {}) -> Dictionary:
	var ev := {
		"type": "explode",
		"pos": pos,
		"radius": radius,
	}
	_copy_optional(ev, opts, ["pattern", "cells", "source_uid", "combo"])
	return ev


static func spawn(unit: UnitState, opts: Dictionary = {}) -> Dictionary:
	var ev := {
		"type": "spawn",
		"uid": unit.uid,
		"pos": unit.pos,
		"unit_id": unit.unit_def_id,
	}
	_copy_optional(ev, opts, [
		"source_uid", "reason", "spawn_origin_uid", "reward_origin_uid",
		"grants_death_rewards", "temporary"
	])
	return ev


static func split_spawn(unit: UnitState, opts: Dictionary = {}) -> Dictionary:
	var ev := {
		"type": "split_spawn",
		"uid": unit.uid,
		"pos": unit.pos,
		"unit_id": unit.unit_def_id,
		"temporary": unit.is_temporary_summon,
	}
	_copy_optional(ev, opts, ["source_uid", "reason", "spawn_origin_uid", "reward_origin_uid"])
	return ev


static func die(unit: UnitState, opts: Dictionary = {}) -> Dictionary:
	var ev := {
		"type": "die",
		"uid": unit.uid,
		"pos": unit.pos,
		"reason": str(opts.get("reason", "unknown")),
	}
	_copy_optional(ev, opts, ["killer_uid", "source_uid", "reward_origin_uid"])
	return ev


static func status(unit: UnitState, status_value: StatusInstance, opts: Dictionary = {}) -> Dictionary:
	var ev := {
		"type": "status",
		"uid": unit.uid,
		"status_id": status_value.status_id,
		"stacks": status_value.stacks,
		"duration": status_value.duration,
	}
	_copy_optional(ev, opts, ["source_uid", "reason", "operation"])
	if not ev.has("source_uid") and not status_value.source_uid.is_empty():
		ev["source_uid"] = status_value.source_uid
	return ev


static func transform(unit: UnitState, from_unit_id: String, opts: Dictionary = {}) -> Dictionary:
	var ev := {
		"type": "transform",
		"uid": unit.uid,
		"pos": unit.pos,
		"from_unit_id": from_unit_id,
		"to_unit_id": unit.unit_def_id,
	}
	_copy_optional(ev, opts, ["source_uid", "reason"])
	return ev


static func gem_flash(pos: Vector2i, opts: Dictionary = {}) -> Dictionary:
	var ev := {"type": "gem_flash", "pos": pos}
	_copy_optional(ev, opts, ["uid", "gem_uid", "color", "reason", "echo_followup"])
	return ev


static func area_effect(event_type: String, pos: Vector2i, opts: Dictionary = {}) -> Dictionary:
	var ev := {"type": event_type, "pos": pos}
	_copy_optional(ev, opts, ["uid", "radius", "spread", "combo", "source_uid", "target_pos"])
	return ev


static func arc(from_pos: Vector2i, target_pos: Vector2i, opts: Dictionary = {}) -> Dictionary:
	var ev := {"type": "arc", "from": from_pos, "pos": from_pos, "target_pos": target_pos}
	_copy_optional(ev, opts, ["source_uid", "target_uid", "combo"])
	return ev


static func lightning(pos: Vector2i, target_pos: Vector2i, opts: Dictionary = {}) -> Dictionary:
	var ev := {"type": "lightning", "pos": pos, "target_pos": target_pos}
	_copy_optional(ev, opts, ["source_uid", "target_uid", "combo"])
	return ev


static func entity_destroyed(pos: Vector2i, entity_id: String, opts: Dictionary = {}) -> Dictionary:
	var ev := {"type": "entity_destroyed", "pos": pos, "entity_id": entity_id}
	_copy_optional(ev, opts, ["uid", "source_uid", "reason"])
	return ev


static func trample_start(unit: UnitState, target: UnitState, opts: Dictionary = {}) -> Dictionary:
	var ev := {
		"type": "trample_start",
		"uid": unit.uid,
		"target_uid": target.uid,
		"pos": target.pos,
	}
	_copy_optional(ev, opts, ["source_uid", "reason"])
	return ev


static func gem_transfer(
	gem_uid: String,
	from_location: Dictionary,
	to_location: Dictionary,
	opts: Dictionary = {}
) -> Dictionary:
	var ev := {
		"type": "gem_transfer",
		"gem_uid": gem_uid,
		"from": from_location.duplicate(true),
		"to": to_location.duplicate(true),
	}
	_copy_optional(ev, opts, ["source_uid", "reason"])
	return ev


static func _copy_optional(ev: Dictionary, opts: Dictionary, keys: Array[String]) -> void:
	for key in keys:
		if not opts.has(key):
			continue
		var value: Variant = opts[key]
		if value == null:
			continue
		if value is String and value.is_empty():
			continue
		ev[key] = value
