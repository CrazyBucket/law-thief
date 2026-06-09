extends Node

const CONFIG_PATH := "res://resources/adventure/map_rule_defs.json"

var _defs: Dictionary = {}


func _ready() -> void:
	_load_defs()


func reload_config() -> void:
	_load_defs()


func get_rule_def(rule_id: String) -> Dictionary:
	var raw: Variant = _defs.get(rule_id, {})
	return (raw as Dictionary).duplicate(true) if raw is Dictionary else {}


func get_rule_display(rule_id: String) -> Dictionary:
	var def := get_rule_def(rule_id)
	return {
		"rule_id": rule_id,
		"name": str(def.get("name", rule_id)),
		"desc": str(def.get("desc", "")),
	}


func validate_rule(rule: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var rule_id := str(rule.get("rule_id", ""))
	if rule_id.is_empty():
		errors.append("missing_rule_id")
		return errors
	if get_rule_def(rule_id).is_empty():
		errors.append("unknown_rule_id")
	return errors


func add_rule(rule_id: String, scope: String = "run", source: String = "", ctx: Dictionary = {}) -> Dictionary:
	var def := get_rule_def(rule_id)
	if def.is_empty():
		return {"ok": false, "error": "unknown_rule_id"}
	var instance_id := "%s:%s:%s" % [scope, rule_id, str(ctx.get("room_id", source))]
	for raw_rule in RunService.get_adventure_rules():
		if raw_rule is Dictionary and str(raw_rule.get("instance_id", "")) == instance_id:
			return {"ok": true, "rule": (raw_rule as Dictionary).duplicate(true), "replayed": true}
	var rule := {
		"instance_id": instance_id,
		"rule_id": rule_id,
		"scope": scope,
		"source": source,
		"chapter": RunService.get_current_chapter(),
		"room_id": str(ctx.get("room_id", "")),
		"stacks": 1,
		"runtime": {},
	}
	RunService.append_adventure_rule(rule)
	return {"ok": true, "rule": rule}


func get_active_rules(ctx: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var current_chapter := RunService.get_current_chapter()
	var room_id := str(ctx.get("room_id", ""))
	for raw_rule in RunService.get_adventure_rules():
		if not raw_rule is Dictionary:
			continue
		var rule := (raw_rule as Dictionary).duplicate(true)
		match str(rule.get("scope", "run")):
			"run":
				result.append(rule)
			"chapter":
				if int(rule.get("chapter", current_chapter)) == current_chapter:
					result.append(rule)
			"node":
				if room_id != "" and str(rule.get("room_id", "")) == room_id:
					result.append(rule)
	return result


func query_modifier(modifier_id: String, base_value: Variant, ctx: Dictionary = {}) -> Dictionary:
	var final_value: float = float(base_value)
	var modifiers: Array[Dictionary] = []
	for rule in get_active_rules(ctx):
		var def := get_rule_def(str(rule.get("rule_id", "")))
		for raw_effect in def.get("effects", []):
			if not raw_effect is Dictionary:
				continue
			var effect := raw_effect as Dictionary
			if str(effect.get("modifier", "")) != modifier_id:
				continue
			var value := float(effect.get("value", 1.0))
			match modifier_id:
				"gold_gain_mult":
					final_value *= value
					modifiers.append({
						"id": str(rule.get("rule_id", "")),
						"operation": "multiply",
						"value": value,
					})
	return {
		"base_value": base_value,
		"final_value": final_value,
		"modifiers": modifiers,
	}


func get_active_rule_display(ctx: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for rule in get_active_rules(ctx):
		var display := get_rule_display(str(rule.get("rule_id", "")))
		display["scope"] = str(rule.get("scope", "run"))
		result.append(display)
	return result


func _load_defs() -> void:
	_defs = _load_json(CONFIG_PATH)


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return {}
	file.close()
	var data: Variant = json.get_data()
	return (data as Dictionary).duplicate(true) if data is Dictionary else {}
