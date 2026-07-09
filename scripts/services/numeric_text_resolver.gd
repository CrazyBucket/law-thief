class_name NumericTextResolver
extends RefCounted

const TOKEN_PATTERN := "\\{([a-z_]+):([^}]+)\\}"
const LITERAL_NUMBER_PATTERN := "[0-9０-９]"


static func format_text(template: String, ctx: Dictionary = {}) -> String:
	if template.is_empty():
		return template
	var regex := RegEx.new()
	if regex.compile(TOKEN_PATTERN) != OK:
		return template
	var result := template
	var matches := regex.search_all(template)
	for i in range(matches.size() - 1, -1, -1):
		var token_match: RegExMatch = matches[i]
		var token_type := token_match.get_string(1)
		var token_value := token_match.get_string(2)
		var replacement := _resolve_token(token_type, token_value, ctx)
		result = "%s%s%s" % [
			result.substr(0, token_match.get_start()),
			replacement,
			result.substr(token_match.get_end()),
		]
	return result


static func extract_tokens(template: String) -> Array[Dictionary]:
	var tokens: Array[Dictionary] = []
	if template.is_empty():
		return tokens
	var regex := RegEx.new()
	if regex.compile(TOKEN_PATTERN) != OK:
		return tokens
	for token_match in regex.search_all(template):
		tokens.append({
			"type": token_match.get_string(1),
			"value": token_match.get_string(2),
		})
	return tokens


static func has_literal_number_outside_tokens(template: String) -> bool:
	var text := strip_tokens(template)
	var regex := RegEx.new()
	if regex.compile(LITERAL_NUMBER_PATTERN) != OK:
		return false
	return regex.search(text) != null


static func strip_tokens(template: String) -> String:
	if template.is_empty():
		return template
	var regex := RegEx.new()
	if regex.compile(TOKEN_PATTERN) != OK:
		return template
	var result := template
	var matches := regex.search_all(template)
	for i in range(matches.size() - 1, -1, -1):
		var token_match: RegExMatch = matches[i]
		result = "%s%s" % [
			result.substr(0, token_match.get_start()),
			result.substr(token_match.get_end()),
		]
	return result


static func _resolve_token(token_type: String, token_value: String, ctx: Dictionary) -> String:
	match token_type:
		"amount_ref":
			var amount_refs := ctx.get("amount_refs", {}) as Dictionary
			if amount_refs.has(token_value):
				return _format_number(_amount_ref_value(amount_refs.get(token_value)))
		"effect_percent_delta":
			var effect_values := ctx.get("effect_values", {}) as Dictionary
			if effect_values.has(token_value):
				return _format_percent_delta(float(effect_values.get(token_value, 1.0)))
		"relic_numeric_ref":
			var relic_numeric_refs := ctx.get("relic_numeric_refs", {}) as Dictionary
			if relic_numeric_refs.has(token_value):
				return _format_number(_numeric_ref_value(relic_numeric_refs.get(token_value)))
		"relic_numeric_signed":
			var relic_numeric_refs := ctx.get("relic_numeric_refs", {}) as Dictionary
			if relic_numeric_refs.has(token_value):
				return _format_signed_number(_numeric_ref_value(relic_numeric_refs.get(token_value)))
		"relic_numeric_percent":
			var relic_numeric_refs := ctx.get("relic_numeric_refs", {}) as Dictionary
			if relic_numeric_refs.has(token_value):
				return _format_percent_value(_numeric_ref_value(relic_numeric_refs.get(token_value)))
	return "{%s:%s}" % [token_type, token_value]


static func _format_number(value: float) -> String:
	if is_equal_approx(value, round(value)):
		return str(int(roundi(value)))
	return str(snappedf(value, 0.01))


static func _format_percent_delta(multiplier: float) -> String:
	var percent_delta := (multiplier - 1.0) * 100.0
	if is_equal_approx(percent_delta, round(percent_delta)):
		return "%+d%%" % int(roundi(percent_delta))
	return "%+.1f%%" % snappedf(percent_delta, 0.1)


static func _format_percent_value(ratio: float) -> String:
	var percent := ratio * 100.0
	if is_equal_approx(percent, round(percent)):
		return "%d%%" % int(roundi(percent))
	return "%.1f%%" % snappedf(percent, 0.1)


static func _format_signed_number(value: float) -> String:
	if is_equal_approx(value, round(value)):
		return "%+d" % int(roundi(value))
	return "%+.2f" % snappedf(value, 0.01)


static func _amount_ref_value(raw_ref: Variant, fallback: float = 0.0) -> float:
	return _numeric_ref_value(raw_ref, fallback)


static func _numeric_ref_value(raw_ref: Variant, fallback: float = 0.0) -> float:
	if raw_ref is int or raw_ref is float:
		return float(raw_ref)
	if raw_ref is Dictionary:
		return float((raw_ref as Dictionary).get("value", fallback))
	return fallback
