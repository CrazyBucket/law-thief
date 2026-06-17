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
	_copy_optional(ev, opts, ["attacker_uid", "source_uid", "reason", "lethal", "remaining_hp", "keep_facing"])
	return ev


static func damage_at(pos: Vector2i, amount: int, opts: Dictionary = {}) -> Dictionary:
	var ev := {
		"type": "damage",
		"pos": pos,
		"damage": amount,
		"is_crit": bool(opts.get("is_crit", false)),
	}
	_copy_optional(ev, opts, ["uid", "victim_uid", "attacker_uid", "source_uid", "reason", "lethal", "remaining_hp", "keep_facing"])
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
