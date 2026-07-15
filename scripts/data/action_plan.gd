class_name ActionPlan
extends RefCounted

var action_type: String = "wait"
var source_uid: String = ""
var source_pos: Vector2i = Vector2i(-1, -1)
var target_uid: String = ""
var target_pos: Vector2i = Vector2i(-1, -1)
var path: Array[Vector2i] = []
var affected_cells: Array[Vector2i] = []
var base_damage: int = 0
var damage: int = 0
var damage_components: Array = []
var preview_effects: Array = []
var planned_turn: int = -1
var metadata: Dictionary = {}


static func capture(intent, turn_index: int, planned_source_pos: Vector2i):
	var plan = load("res://scripts/data/action_plan.gd").new()
	plan.action_type = intent.type
	plan.source_uid = intent.source_uid
	plan.source_pos = planned_source_pos
	plan.target_uid = intent.target_uid
	plan.target_pos = intent.target_pos
	plan.path = intent.path.duplicate()
	plan.affected_cells = intent.affected_cells.duplicate()
	plan.base_damage = intent.base_damage
	plan.damage = intent.damage
	for component in intent.damage_components:
		plan.damage_components.append(component.clone())
	for effect in intent.preview_effects:
		plan.preview_effects.append(effect.clone())
	plan.planned_turn = turn_index
	plan.metadata = intent.plan_metadata.duplicate(true)
	return plan


func clone():
	var plan = load("res://scripts/data/action_plan.gd").new()
	plan.action_type = action_type
	plan.source_uid = source_uid
	plan.source_pos = source_pos
	plan.target_uid = target_uid
	plan.target_pos = target_pos
	plan.path = path.duplicate()
	plan.affected_cells = affected_cells.duplicate()
	plan.base_damage = base_damage
	plan.damage = damage
	for component in damage_components:
		plan.damage_components.append(component.clone())
	for effect in preview_effects:
		plan.preview_effects.append(effect.clone())
	plan.planned_turn = planned_turn
	plan.metadata = metadata.duplicate(true)
	return plan


func apply_to(intent) -> void:
	intent.type = action_type
	intent.source_uid = source_uid
	intent.target_uid = target_uid
	intent.target_pos = target_pos
	intent.path = path.duplicate()
	intent.affected_cells = affected_cells.duplicate()
	intent.base_damage = base_damage
	intent.damage = damage
	intent.damage_components.clear()
	for component in damage_components:
		intent.damage_components.append(component.clone())
	intent.preview_effects.clear()
	for effect in preview_effects:
		intent.preview_effects.append(effect.clone())
	intent.plan_metadata = metadata.duplicate(true)


func is_applicable(state: GameState, unit: UnitState) -> bool:
	if state == null or unit == null or not unit.alive or unit.uid != source_uid:
		return false
	if planned_turn >= 0 and state.turn_index != planned_turn:
		return false
	if source_pos != Vector2i(-1, -1) and unit.pos != source_pos:
		return false
	if not target_uid.is_empty() and str(metadata.get("target_kind", "")) == "unit":
		var target: UnitState = state.units.get(target_uid, null)
		if target == null or not target.alive:
			return false
	if not target_uid.is_empty() and str(metadata.get("target_kind", "")) == "gem":
		var drop: Variant = state.dropped_gems.get(target_uid, null)
		if not drop is Dictionary or not state.gems.has(target_uid):
			return false
		if target_pos != Vector2i(-1, -1) and (drop as Dictionary).get("pos", Vector2i(-1, -1)) != target_pos:
			return false
	return true


func signature() -> String:
	return "%s|%s|%s|%s|%s|%s|%d|%d" % [
		action_type,
		source_uid,
		source_pos,
		target_uid,
		target_pos,
		str(path),
		base_damage,
		damage,
	]


func to_dict() -> Dictionary:
	return {
		"action_type": action_type,
		"source_uid": source_uid,
		"source_pos": source_pos,
		"target_uid": target_uid,
		"target_pos": target_pos,
		"path": path.duplicate(),
		"affected_cells": affected_cells.duplicate(),
		"base_damage": base_damage,
		"damage": damage,
		"damage_components": damage_components.map(func(component): return component.to_dict()),
		"preview_effects": preview_effects.map(func(effect): return effect.to_dict()),
		"planned_turn": planned_turn,
		"metadata": metadata.duplicate(true),
	}
