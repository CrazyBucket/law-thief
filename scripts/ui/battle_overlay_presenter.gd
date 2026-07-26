class_name BattleOverlayPresenter
extends RefCounted


static func empty_highlights() -> Dictionary:
	return {
		"reachable": [],
		"targets": [],
		"attack_range": [],
		"paths": [],
		"danger": [],
		"effect_preview": [],
		"overlays": [],
		"routes": [],
	}


static func apply_to_board(board: Control, highlight_state: Dictionary) -> void:
	if board == null:
		return
	board.call(
		"set_overlays",
		highlight_state.get("overlays", []),
		highlight_state.get("routes", [])
	)


func present(legacy_highlights: Dictionary, context: Dictionary = {}) -> Dictionary:
	var result := legacy_highlights.duplicate(true)
	result["overlays"] = []
	result["routes"] = []

	var action := str(context.get("action", ""))
	match action:
		Constants.ACTION_MOVE:
			_append_overlay(result, "move", result.get("reachable", []))
			_append_route(result, "move", context.get("move_route", []), {
				"arrow_reverse": false,
				"unit_uid": str(context.get("source_uid", "")),
			})
		Constants.ACTION_ATTACK:
			_append_overlay(result, "attack_range", result.get("attack_range", []))
			_append_route(result, "impact", context.get("attack_route", []), {
				"arrow_reverse": false,
				"unit_uid": str(context.get("source_uid", "")),
			})
			var effect_options := {"source_uid": str(context.get("source_uid", ""))}
			if context.has("target_cell"):
				effect_options["target_cell"] = context["target_cell"]
			_append_overlay(result, "effect", result.get("effect_preview", []), effect_options)
		Constants.ACTION_EXTRACT, Constants.ACTION_INSERT:
			_append_overlay(result, "target", result.get("targets", []), {"action": action})

	var selected_unit: UnitState = context.get("selected_unit", null)
	if selected_unit == null or not selected_unit.alive or selected_unit.intent == null:
		return result

	var intent_path: Array = result.get("paths", [])
	_append_overlay(result, "intent_path", intent_path, {"unit_uid": selected_unit.uid})
	if not intent_path.is_empty():
		var route: Array = [selected_unit.pos]
		route.append_array(intent_path)
		_append_route(result, "intent", route, {
			"unit_uid": selected_unit.uid,
			"arrow_reverse": false,
		})
	_append_overlay(result, "danger", result.get("danger", []), {"unit_uid": selected_unit.uid})
	for effect in selected_unit.intent.preview_effects:
		if effect.kind in ["movement", "damage"]:
			continue
		var overlay_kind := "effect"
		if effect.kind == "mage_pool_candidate":
			overlay_kind = "intent_path"
		elif effect.kind == "mage_pool_lock":
			overlay_kind = "target"
		elif effect.kind == "mage_charge_route":
			overlay_kind = "danger"
		elif effect.kind == "mage_grounded":
			overlay_kind = "safe"
		elif effect.kind == "mage_wet_danger":
			overlay_kind = "critical"
		_append_overlay(result, overlay_kind, effect.cells, {
			"unit_uid": selected_unit.uid,
			"preview_kind": effect.kind,
			"certainty": effect.certainty,
		})
		if effect.kind == "mage_pool_lock" and not effect.cells.is_empty():
			_append_route(result, "mage_lock", [selected_unit.pos, effect.cells[0]], {"unit_uid": selected_unit.uid})
		elif effect.kind == "mage_charge_route" and effect.cells.size() > 1:
			_append_route(result, "impact", effect.cells, {"unit_uid": selected_unit.uid})
	return result


func _append_overlay(result: Dictionary, kind: String, cells: Array, options: Dictionary = {}) -> void:
	if cells.is_empty():
		return
	var unique_cells: Array[Vector2i] = []
	var seen := {}
	for raw_cell in cells:
		var cell: Vector2i = raw_cell
		if seen.has(cell):
			continue
		seen[cell] = true
		unique_cells.append(cell)
	if unique_cells.is_empty():
		return
	var overlay := {
		"kind": kind,
		"cells": unique_cells,
	}
	for key in options.keys():
		overlay[key] = options[key]
	result["overlays"].append(overlay)


func _append_route(result: Dictionary, kind: String, path: Array, options: Dictionary = {}) -> void:
	if path.size() < 2:
		return
	var clean_path: Array[Vector2i] = []
	for raw_cell in path:
		clean_path.append(raw_cell)
	var route := {
		"kind": kind,
		"path": clean_path,
	}
	for key in options.keys():
		route[key] = options[key]
	result["routes"].append(route)
