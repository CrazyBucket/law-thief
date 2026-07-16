class_name AdventureMapCopyPresenter extends RefCounted


static func present(active_rules: Array, debug_context: Dictionary = {}, include_debug: bool = false) -> Dictionary:
	return {
		"rule_names": player_rule_names(active_rules),
		"debug_lines": debug_metadata_lines(active_rules, debug_context) if include_debug else PackedStringArray(),
	}


static func player_rule_names(active_rules: Array) -> Array[String]:
	var names: Array[String] = []
	for raw_rule in active_rules:
		if not raw_rule is Dictionary:
			continue
		var rule := raw_rule as Dictionary
		var rule_id := str(rule.get("rule_id", "")).strip_edges()
		var display_name := str(rule.get("name", "")).strip_edges()
		if display_name.is_empty() or display_name == rule_id or display_name in names:
			continue
		names.append(display_name)
	return names


static func debug_metadata_lines(active_rules: Array, debug_context: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	var cell: Variant = debug_context.get("cell", null)
	if cell is Vector2i:
		lines.append("cell=%s" % str(cell))
	_append_debug_value(lines, "room_id", debug_context.get("room_id", ""))
	_append_debug_value(lines, "event_id", debug_context.get("event_id", ""))
	var rule_ids: Array[String] = []
	for raw_rule in active_rules:
		if not raw_rule is Dictionary:
			continue
		var rule_id := str((raw_rule as Dictionary).get("rule_id", "")).strip_edges()
		if not rule_id.is_empty() and rule_id not in rule_ids:
			rule_ids.append(rule_id)
	if not rule_ids.is_empty():
		lines.append("rule_ids=%s" % ",".join(rule_ids))
	return lines


static func _append_debug_value(lines: PackedStringArray, label: String, value: Variant) -> void:
	var text := str(value).strip_edges()
	if not text.is_empty():
		lines.append("%s=%s" % [label, text])
