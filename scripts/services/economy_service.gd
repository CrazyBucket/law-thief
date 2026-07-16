extends Node

const CONFIG_PATH := "res://resources/adventure/economy_config.json"
const _Validator = preload("res://scripts/services/adventure_config_validator.gd")

var _config: Dictionary = {}


func _ready() -> void:
	_load_config()


func reload_config() -> void:
	_load_config()


func get_balance(resource_id: String = "gold") -> int:
	return RunService.get_balance(resource_id)


func get_starting_gold() -> int:
	return int(_required_config_value("starting_gold"))


func get_combat_reward_range(room_type: String) -> Dictionary:
	var rewards := _config.get("combat_rewards", {}) as Dictionary
	var tier := _combat_reward_tier(room_type)
	var raw_range: Variant = rewards.get(tier, {})
	return (raw_range as Dictionary).duplicate(true) if raw_range is Dictionary else {}


func get_combat_reward(room_type: String, roll_key: String = "") -> int:
	return _roll_integer_range(
		get_combat_reward_range(room_type),
		["combat_reward", _combat_reward_tier(room_type), roll_key]
	)


func get_shop_price_range(item_type: String, rarity: String = "default") -> Dictionary:
	var all_prices := _config.get("shop_prices", {}) as Dictionary
	var normalized_type := item_type.to_lower()
	var raw_type_prices: Variant = all_prices.get(normalized_type, {})
	if not raw_type_prices is Dictionary:
		push_error("EconomyService: unknown shop item type: %s" % item_type)
		return {}
	var type_prices := raw_type_prices as Dictionary
	var normalized_rarity := rarity.to_lower()
	var raw_range: Variant = type_prices.get(normalized_rarity, type_prices.get("default", {}))
	return (raw_range as Dictionary).duplicate(true) if raw_range is Dictionary else {}


func roll_shop_price(item_type: String, rarity: String, roll_key: String) -> int:
	return _roll_integer_range(
		get_shop_price_range(item_type, rarity),
		["shop_price", item_type.to_lower(), rarity.to_lower(), roll_key]
	)


## Compatibility helper for callers that need a stable representative value instead of a roll.
func get_base_price(item_type: String, rarity: String = "default") -> int:
	var price_range := get_shop_price_range(item_type, rarity)
	return roundi((float(price_range.get("min", 0)) + float(price_range.get("max", 0))) / 2.0)


func has_amount_ref(ref_id: String) -> bool:
	return (_config.get("amount_refs", {}) as Dictionary).has(ref_id)


func get_amount_ref(ref_id: String) -> float:
	var amount_refs := _config.get("amount_refs", {}) as Dictionary
	if not amount_refs.has(ref_id):
		push_error("EconomyService: unknown amount ref: %s" % ref_id)
		return 0.0
	return _amount_ref_value(amount_refs[ref_id])


func get_amount_ref_def(ref_id: String) -> Dictionary:
	var amount_refs := _config.get("amount_refs", {}) as Dictionary
	if not amount_refs.has(ref_id):
		return {}
	var raw_ref: Variant = amount_refs.get(ref_id)
	if raw_ref is Dictionary:
		var ref_def := (raw_ref as Dictionary).duplicate(true)
		ref_def["value"] = _amount_ref_value(raw_ref)
		return ref_def
	return {
		"value": _amount_ref_value(raw_ref),
		"kind": "legacy",
		"unit": "",
	}


func get_amount_refs() -> Dictionary:
	return (_config.get("amount_refs", {}) as Dictionary).duplicate(true)


func resolve_numeric_field(payload: Dictionary, field_id: String) -> Dictionary:
	if payload.has(field_id):
		return {"ok": true, "value": float(payload[field_id])}
	var ref_id := str(payload.get("%s_ref" % field_id, ""))
	if ref_id.is_empty():
		return {
			"ok": false,
			"error": "missing_numeric_field",
			"reason": "missing %s" % field_id,
			"field": field_id,
		}
	if not has_amount_ref(ref_id):
		return {
			"ok": false,
			"error": "unknown_amount_ref",
			"reason": "unknown amount ref %s" % ref_id,
			"field": field_id,
			"amount_ref": ref_id,
		}
	return {"ok": true, "value": get_amount_ref(ref_id), "amount_ref": ref_id}


func can_afford(cost: Dictionary) -> bool:
	for resource_id in cost.keys():
		if get_balance(str(resource_id)) < int(cost.get(resource_id, 0)):
			return false
	return true


func quote(resource_id: String, base_amount: int, reason: String, ctx: Dictionary = {}) -> Dictionary:
	var trace := _build_trace(resource_id, base_amount, reason, ctx)
	return {
		"resource_id": resource_id,
		"base_amount": base_amount,
		"final_amount": int(trace.get("final_amount", base_amount)),
		"reason": reason,
		"modifiers": trace.get("modifiers", []).duplicate(true),
	}


func grant(resource_id: String, base_amount: int, reason: String, ctx: Dictionary = {}) -> Dictionary:
	if not RunService.is_run_active():
		return {"ok": false, "error": "no_active_run"}
	var transaction_id := str(ctx.get("transaction_id", ""))
	var existing := _find_ledger_entry(transaction_id)
	if transaction_id != "" and not existing.is_empty():
		return {"ok": true, "entry": existing, "replayed": true}
	var before := get_balance(resource_id)
	var trace := _build_trace(resource_id, base_amount, reason, ctx)
	var final_amount := maxi(0, int(trace.get("final_amount", base_amount)))
	var after := before + final_amount
	var entry := {
		"transaction_id": transaction_id,
		"resource_id": resource_id,
		"base_amount": base_amount,
		"final_amount": final_amount,
		"before": before,
		"after": after,
		"reason": reason,
		"ctx": ctx.duplicate(true),
		"modifiers": trace.get("modifiers", []).duplicate(true),
	}
	RunService.set_resource_balance(resource_id, after, false)
	RunService.append_ledger_entry(entry)
	return {"ok": true, "entry": entry}


func spend(resource_id: String, amount: int, reason: String, ctx: Dictionary = {}) -> Dictionary:
	if not RunService.is_run_active():
		return {"ok": false, "error": "no_active_run"}
	var transaction_id := str(ctx.get("transaction_id", ""))
	var existing := _find_ledger_entry(transaction_id)
	if transaction_id != "" and not existing.is_empty():
		return {"ok": true, "entry": existing, "replayed": true}
	var before := get_balance(resource_id)
	var trace := _build_trace(resource_id, amount, reason, ctx)
	var final_amount := maxi(0, int(trace.get("final_amount", amount)))
	if before < final_amount:
		return {
			"ok": false,
			"error": "insufficient_funds",
			"resource_id": resource_id,
			"required": final_amount,
			"balance": before,
		}
	var after := before - final_amount
	var entry := {
		"transaction_id": transaction_id,
		"resource_id": resource_id,
		"base_amount": amount,
		"final_amount": -final_amount,
		"before": before,
		"after": after,
		"reason": reason,
		"ctx": ctx.duplicate(true),
		"modifiers": trace.get("modifiers", []).duplicate(true),
	}
	RunService.set_resource_balance(resource_id, after, false)
	RunService.append_ledger_entry(entry)
	return {"ok": true, "entry": entry}


func format_entry(entry: Dictionary) -> String:
	var delta := int(entry.get("final_amount", 0))
	var sign := "+" if delta >= 0 else ""
	var base_amount := int(entry.get("base_amount", 0))
	var details: Array[String] = []
	details.append("基础 %+d" % base_amount if delta >= 0 else "基础 -%d" % base_amount)
	for raw_modifier in entry.get("modifiers", []):
		if not raw_modifier is Dictionary:
			continue
		var modifier := raw_modifier as Dictionary
		var label := str(modifier.get("id", "modifier"))
		var value := float(modifier.get("value", 1.0))
		details.append("%s x%.2f" % [label, value])
	return "金币 %s%d（%s）" % [sign, delta, "，".join(details)]


func _load_config() -> void:
	var raw := _load_json(CONFIG_PATH)
	var errors := _Validator.validate_economy_config(raw)
	_Validator.ensure_valid(CONFIG_PATH, errors)
	_config = raw.duplicate(true) if errors.is_empty() else {}


func _required_config_value(key: String) -> Variant:
	if _config.has(key):
		return _config[key]
	push_error("EconomyService: required config value missing: %s" % key)
	return 0


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


func _build_trace(resource_id: String, base_amount: int, reason: String, ctx: Dictionary) -> Dictionary:
	var modifiers: Array[Dictionary] = []
	var final_amount := base_amount
	if resource_id == "gold" and reason.find("reward") >= 0:
		var query := AdventureRuleRegistry.query_modifier("gold_gain_mult", base_amount, ctx)
		final_amount = roundi(float(query.get("final_value", base_amount)))
		var raw_modifiers: Variant = query.get("modifiers", [])
		if raw_modifiers is Array:
			for raw_modifier in raw_modifiers:
				if raw_modifier is Dictionary:
					modifiers.append((raw_modifier as Dictionary).duplicate(true))
	elif resource_id == "gold" and reason == "shop_price":
		var query := AdventureRuleRegistry.query_modifier("shop_price_mult", base_amount, ctx)
		final_amount = roundi(float(query.get("final_value", base_amount)))
		var raw_modifiers: Variant = query.get("modifiers", [])
		if raw_modifiers is Array:
			for raw_modifier in raw_modifiers:
				if raw_modifier is Dictionary:
					modifiers.append((raw_modifier as Dictionary).duplicate(true))
	else:
		final_amount = roundi(float(base_amount))
	return {
		"final_amount": final_amount,
		"modifiers": modifiers,
		"reason": reason,
		"ctx": ctx.duplicate(true),
	}


func _find_ledger_entry(transaction_id: String) -> Dictionary:
	if transaction_id.is_empty():
		return {}
	for raw_entry in RunService.get_resource_ledger():
		if raw_entry is Dictionary and str(raw_entry.get("transaction_id", "")) == transaction_id:
			return (raw_entry as Dictionary).duplicate(true)
	return {}


func _amount_ref_value(raw_ref: Variant) -> float:
	if raw_ref is int or raw_ref is float:
		return float(raw_ref)
	if raw_ref is Dictionary:
		return float((raw_ref as Dictionary).get("value", 0.0))
	push_error("EconomyService: malformed amount ref")
	return 0.0


func _combat_reward_tier(room_type: String) -> String:
	match room_type.to_upper():
		"ELITE_COMBAT", "ELITE":
			return "elite"
		"END", "BOSS_COMBAT", "BOSS":
			return "boss"
		_:
			return "normal"


func _roll_integer_range(range_def: Dictionary, seed_parts: Array) -> int:
	var min_value := int(range_def.get("min", 0))
	var max_value := int(range_def.get("max", min_value))
	if max_value <= min_value:
		return min_value
	var seed_value := RngService.derive_seed(seed_parts)
	var rng := RngService.create_rng(seed_value, "economy")
	return rng.randi_range(min_value, max_value)
