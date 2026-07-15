class_name IntentPreviewEffect
extends RefCounted

const CERTAIN := "certain"
const CONDITIONAL := "conditional"

var kind: String = ""
var source_uid: String = ""
var target_uid: String = ""
var cells: Array[Vector2i] = []
var certainty: String = CERTAIN
var metadata: Dictionary = {}


static func create(
	effect_kind: String,
	effect_cells: Array,
	options: Dictionary = {}
) -> RefCounted:
	var effect = load("res://scripts/data/intent_preview_effect.gd").new()
	effect.kind = effect_kind
	effect.source_uid = str(options.get("source_uid", ""))
	effect.target_uid = str(options.get("target_uid", ""))
	for cell in effect_cells:
		if cell is Vector2i and cell not in effect.cells:
			effect.cells.append(cell)
	effect.certainty = str(options.get("certainty", CERTAIN))
	effect.metadata = options.get("metadata", {}).duplicate(true)
	return effect


func clone() -> RefCounted:
	return create(kind, cells, {
		"source_uid": source_uid,
		"target_uid": target_uid,
		"certainty": certainty,
		"metadata": metadata,
	})


func to_dict() -> Dictionary:
	return {
		"kind": kind,
		"source_uid": source_uid,
		"target_uid": target_uid,
		"cells": cells.duplicate(),
		"certainty": certainty,
		"metadata": metadata.duplicate(true),
	}
