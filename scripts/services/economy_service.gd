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
	return int(_config.get("starting_gold", 0))


func get_combat_reward(room_type: String) -> int:
	match room_type:
		"ELITE_COMBAT":
			return int(_config.get("elite_combat_gold", 20))
		"END":
			return int(_config.get("boss_combat_gold", 40))
		_:
			return int(_config.get("normal_combat_gold", 10))


func get_base_price(item_type: String) -> int:
	match item_type:
		"relic":
			return int(_config.get("relic_base_price", 30))
		_:
			return int(_config.get("gem_base_price", 15))


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
	_config = _load_json(CONFIG_PATH)
	_Validator.ensure_valid(CONFIG_PATH, _Validator.validate_economy_config(_config))


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
