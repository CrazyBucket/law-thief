class_name EventGraphConfigValidator
extends RefCounted

const _TextResolver = preload("res://scripts/services/numeric_text_resolver.gd")

const FUNCTION_IDS := [
	"grant_resource",
	"spend_resource",
	"heal_player",
	"heal_player_percent",
	"damage_player",
	"grant_relic",
	"grant_gem",
	"add_adventure_rule",
	"remove_adventure_rule",
]

const CONDITION_TYPES := [
	"resource_gte",
	"hp_below_ratio",
	"has_relic",
	"not_has_relic",
	"has_carried_gem",
	"carried_gem_empty",
	"chapter_gte",
]


static func validate_event_graph(event_id: String, event_def: Dictionary, amount_refs: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var prefix := "event_defs.%s" % event_id
	var entry := str(event_def.get("entry", ""))
	if entry.is_empty():
		errors.append("%s.entry missing" % prefix)
	var raw_nodes: Variant = event_def.get("nodes", null)
	if not raw_nodes is Dictionary:
		errors.append("%s.nodes should be object" % prefix)
		return errors
	var nodes := raw_nodes as Dictionary
	if not entry.is_empty() and not nodes.has(entry):
		errors.append("%s.entry references unknown node: %s" % [prefix, entry])
	for node_id in nodes.keys():
		var node_prefix := "%s.nodes.%s" % [prefix, node_id]
		var raw_node: Variant = nodes[node_id]
		if not raw_node is Dictionary:
			errors.append("%s should be object" % node_prefix)
			continue
		var event_node := raw_node as Dictionary
		for text_field in ["title", "body"]:
			if not event_node.has(text_field):
				errors.append("%s.%s missing" % [node_prefix, text_field])
			elif not event_node[text_field] is String:
				errors.append("%s.%s should be string" % [node_prefix, text_field])
			else:
				errors.append_array(_validate_text_tokens("%s.%s" % [node_prefix, text_field], str(event_node[text_field]), amount_refs))
		var raw_options: Variant = event_node.get("options", null)
		if not raw_options is Array:
			errors.append("%s.options should be array" % node_prefix)
			continue
		var option_ids := {}
		for i in range((raw_options as Array).size()):
			errors.append_array(_validate_option(
				"%s.options[%d]" % [node_prefix, i],
				(raw_options as Array)[i],
				nodes,
				option_ids,
				amount_refs
			))
	return errors


static func _validate_option(
	prefix: String,
	raw_option: Variant,
	nodes: Dictionary,
	option_ids: Dictionary,
	amount_refs: Dictionary
) -> Array[String]:
	var errors: Array[String] = []
	if not raw_option is Dictionary:
		errors.append("%s should be object" % prefix)
		return errors
	var option := raw_option as Dictionary
	var option_id := str(option.get("id", ""))
	if option_id.is_empty():
		errors.append("%s.id missing" % prefix)
	elif option_ids.has(option_id):
		errors.append("%s.id duplicated: %s" % [prefix, option_id])
	else:
		option_ids[option_id] = true
	if not option.get("label", null) is String or str(option.get("label", "")).is_empty():
		errors.append("%s.label should be a non-empty string" % prefix)
	else:
		errors.append_array(_validate_text_tokens("%s.label" % prefix, str(option.get("label", "")), amount_refs))
	var conditions: Variant = option.get("conditions", [])
	if not conditions is Array:
		errors.append("%s.conditions should be array" % prefix)
	else:
		errors.append_array(_validate_conditions("%s.conditions" % prefix, conditions, amount_refs))
	var calls: Variant = option.get("calls", null)
	if not calls is Array:
		errors.append("%s.calls should be array" % prefix)
	else:
		errors.append_array(_validate_calls("%s.calls" % prefix, calls, amount_refs))
	var next_node := str(option.get("next", ""))
	var has_next := not next_node.is_empty()
	var finishes := bool(option.get("finish", false))
	if option.has("finish") and not option["finish"] is bool:
		errors.append("%s.finish should be bool" % prefix)
	elif has_next == finishes:
		errors.append("%s should define exactly one of next or finish=true" % prefix)
	if has_next and not nodes.has(next_node):
		errors.append("%s.next references unknown node: %s" % [prefix, next_node])
	return errors


static func _validate_calls(prefix: String, calls: Array, amount_refs: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for i in range(calls.size()):
		var call_prefix := "%s[%d]" % [prefix, i]
		var raw_call: Variant = calls[i]
		if not raw_call is Dictionary:
			errors.append("%s should be object" % call_prefix)
			continue
		var event_call := raw_call as Dictionary
		var function_id := str(event_call.get("function", ""))
		if function_id.is_empty():
			errors.append("%s.function missing" % call_prefix)
		elif function_id not in FUNCTION_IDS:
			errors.append("%s.function unknown: %s" % [call_prefix, function_id])
		var raw_args: Variant = event_call.get("args", null)
		if not raw_args is Dictionary:
			errors.append("%s.args should be object" % call_prefix)
			continue
		if not function_id.is_empty() and function_id in FUNCTION_IDS:
			errors.append_array(_validate_function_args(call_prefix, function_id, raw_args as Dictionary, amount_refs))
	return errors


static func _validate_conditions(prefix: String, conditions: Array, amount_refs: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for i in range(conditions.size()):
		var condition_prefix := "%s[%d]" % [prefix, i]
		var raw_condition: Variant = conditions[i]
		if not raw_condition is Dictionary:
			errors.append("%s should be object" % condition_prefix)
			continue
		var condition := raw_condition as Dictionary
		var condition_type := str(condition.get("type", ""))
		if condition_type.is_empty():
			errors.append("%s.type missing" % condition_prefix)
		elif condition_type not in CONDITION_TYPES:
			errors.append("%s.type unknown: %s" % [condition_prefix, condition_type])
		elif condition_type == "resource_gte":
			var resource_id := str(condition.get("resource_id", ""))
			if resource_id.is_empty():
				errors.append("%s.resource_id missing" % condition_prefix)
			errors.append_array(_validate_amount(condition_prefix, condition, amount_refs, "flat", [resource_id]))
	return errors


static func _validate_function_args(prefix: String, function_id: String, args: Dictionary, amount_refs: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	match function_id:
		"grant_resource", "spend_resource":
			var resource_id := str(args.get("resource_id", ""))
			if resource_id.is_empty():
				errors.append("%s.resource_id missing" % prefix)
			errors.append_array(_validate_amount(prefix, args, amount_refs, "flat", [resource_id]))
		"heal_player", "damage_player":
			errors.append_array(_validate_amount(prefix, args, amount_refs, "flat", ["hp"]))
		"heal_player_percent":
			errors.append_array(_validate_amount(prefix, args, amount_refs, "ratio", ["max_hp"]))
		"grant_relic":
			if str(args.get("relic_id", "")).is_empty():
				errors.append("%s.relic_id missing" % prefix)
		"grant_gem":
			if str(args.get("gem_id", "")).is_empty():
				errors.append("%s.gem_id missing" % prefix)
		"add_adventure_rule", "remove_adventure_rule":
			if str(args.get("rule_id", "")).is_empty():
				errors.append("%s.rule_id missing" % prefix)
	return errors


static func _validate_amount(
	prefix: String,
	payload: Dictionary,
	amount_refs: Dictionary,
	expected_kind: String,
	expected_units: Array[String]
) -> Array[String]:
	var errors: Array[String] = []
	var has_amount := payload.has("amount")
	var has_amount_ref := payload.has("amount_ref")
	if not has_amount and not has_amount_ref:
		errors.append("%s.amount or amount_ref missing" % prefix)
	if has_amount and not payload["amount"] is int and not payload["amount"] is float:
		errors.append("%s.amount should be number" % prefix)
	elif has_amount and not amount_refs.is_empty():
		errors.append("%s.amount should use amount_ref in authored config" % prefix)
	if has_amount_ref and not payload["amount_ref"] is String:
		errors.append("%s.amount_ref should be string" % prefix)
	elif has_amount_ref and str(payload.get("amount_ref", "")).is_empty():
		errors.append("%s.amount_ref should not be empty" % prefix)
	elif has_amount_ref and not amount_refs.is_empty() and not amount_refs.has(str(payload.get("amount_ref", ""))):
		errors.append("%s.amount_ref unknown: %s" % [prefix, str(payload.get("amount_ref", ""))])
	if not payload.get("amount_ref", null) is String:
		return errors
	var ref_id := str(payload.get("amount_ref", ""))
	if ref_id.is_empty() or amount_refs.is_empty() or not amount_refs.has(ref_id):
		return errors
	var ref_def := _amount_ref_def(amount_refs.get(ref_id))
	var kind := str(ref_def.get("kind", "legacy"))
	if kind == "legacy":
		return errors
	var unit := str(ref_def.get("unit", ""))
	if expected_kind != kind:
		errors.append("%s.amount_ref kind mismatch: %s expected %s got %s" % [prefix, ref_id, expected_kind, kind])
	var concrete_units: Array[String] = []
	for expected_unit in expected_units:
		if not str(expected_unit).is_empty():
			concrete_units.append(str(expected_unit))
	if not concrete_units.is_empty() and unit not in concrete_units:
		errors.append("%s.amount_ref unit mismatch: %s expected %s got %s" % [prefix, ref_id, ", ".join(concrete_units), unit])
	return errors


static func _validate_text_tokens(prefix: String, text: String, amount_refs: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if _TextResolver.has_literal_number_outside_tokens(text):
		errors.append("%s should use numeric text tokens instead of literal numbers" % prefix)
	for token in _TextResolver.extract_tokens(text):
		var token_type := str(token.get("type", ""))
		var token_value := str(token.get("value", ""))
		if token_type != "amount_ref":
			errors.append("%s unknown text token type: %s" % [prefix, token_type])
		elif not amount_refs.is_empty() and not amount_refs.has(token_value):
			errors.append("%s unknown amount_ref token: %s" % [prefix, token_value])
	return errors


static func _amount_ref_def(raw_ref: Variant) -> Dictionary:
	if raw_ref is Dictionary:
		return raw_ref as Dictionary
	return {"value": raw_ref, "kind": "legacy", "unit": ""}
