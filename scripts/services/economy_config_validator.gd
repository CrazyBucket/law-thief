class_name EconomyConfigValidator
extends RefCounted


static func validate(config: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var required_fields := ["starting_gold", "combat_rewards", "shop_prices", "amount_refs"]
	for key in config.keys():
		if str(key) not in required_fields:
			errors.append("economy_config.%s is unknown" % key)
	for key in required_fields:
		if not config.has(key):
			errors.append("economy_config.%s missing" % key)
	if config.has("starting_gold"):
		errors.append_array(_validate_non_negative_integer("economy_config.starting_gold", config["starting_gold"]))
	_validate_combat_rewards(config.get("combat_rewards", {}), errors)
	_validate_shop_prices(config.get("shop_prices", {}), errors)
	_validate_amount_refs(config.get("amount_refs", {}), errors)
	return errors


static func _validate_combat_rewards(raw_rewards: Variant, errors: Array[String]) -> void:
	if not raw_rewards is Dictionary:
		errors.append("economy_config.combat_rewards should be object")
		return
	var rewards := raw_rewards as Dictionary
	for tier in ["normal", "elite", "boss"]:
		if not rewards.has(tier):
			errors.append("economy_config.combat_rewards.%s missing" % tier)
	for tier in rewards.keys():
		if str(tier) not in ["normal", "elite", "boss"]:
			errors.append("economy_config.combat_rewards.%s is unknown" % tier)
			continue
		errors.append_array(_validate_integer_range("economy_config.combat_rewards.%s" % str(tier), rewards[tier]))


static func _validate_shop_prices(raw_prices: Variant, errors: Array[String]) -> void:
	if not raw_prices is Dictionary:
		errors.append("economy_config.shop_prices should be object")
		return
	var prices := raw_prices as Dictionary
	for item_type in ["gem", "relic", "consumable"]:
		if not prices.has(item_type):
			errors.append("economy_config.shop_prices.%s missing" % item_type)
	for item_type in prices.keys():
		var rarity_prices: Variant = prices[item_type]
		var type_prefix := "economy_config.shop_prices.%s" % str(item_type)
		if not rarity_prices is Dictionary or (rarity_prices as Dictionary).is_empty():
			errors.append("%s should be a non-empty object" % type_prefix)
			continue
		if not (rarity_prices as Dictionary).has("default"):
			errors.append("%s.default missing" % type_prefix)
		for rarity in (rarity_prices as Dictionary).keys():
			errors.append_array(_validate_integer_range("%s.%s" % [type_prefix, str(rarity)], (rarity_prices as Dictionary)[rarity]))


static func _validate_amount_refs(raw_refs: Variant, errors: Array[String]) -> void:
	if not raw_refs is Dictionary or (raw_refs as Dictionary).is_empty():
		errors.append("economy_config.amount_refs should be a non-empty object")
		return
	for ref_id in (raw_refs as Dictionary).keys():
		errors.append_array(_validate_amount_ref_def("economy_config.amount_refs.%s" % str(ref_id), (raw_refs as Dictionary)[ref_id]))


static func _validate_integer_range(prefix: String, value: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not value is Dictionary:
		errors.append("%s should be object" % prefix)
		return errors
	var range_def := value as Dictionary
	for key in range_def.keys():
		if str(key) not in ["min", "max"]:
			errors.append("%s.%s is unknown" % [prefix, str(key)])
	for key in ["min", "max"]:
		if not range_def.has(key):
			errors.append("%s.%s missing" % [prefix, key])
		else:
			errors.append_array(_validate_non_negative_integer("%s.%s" % [prefix, key], range_def[key]))
	if range_def.has("min") and range_def.has("max") and _is_integer(range_def["min"]) and _is_integer(range_def["max"]) and int(range_def["min"]) > int(range_def["max"]):
		errors.append("%s.min should not exceed max" % prefix)
	return errors


static func _validate_non_negative_integer(prefix: String, value: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not value is int and not value is float:
		errors.append("%s should be number" % prefix)
	elif int(value) != float(value):
		errors.append("%s should be integer" % prefix)
	elif int(value) < 0:
		errors.append("%s should be non-negative" % prefix)
	return errors


static func _validate_amount_ref_def(prefix: String, raw_ref: Variant) -> Array[String]:
	var errors: Array[String] = []
	if raw_ref is int or raw_ref is float:
		return errors
	if not raw_ref is Dictionary:
		errors.append("%s should be number or object" % prefix)
		return errors
	var ref_def := raw_ref as Dictionary
	if not ref_def.has("value"):
		errors.append("%s.value missing" % prefix)
	elif not ref_def["value"] is int and not ref_def["value"] is float:
		errors.append("%s.value should be number" % prefix)
	var kind := str(ref_def.get("kind", ""))
	if kind.is_empty():
		errors.append("%s.kind missing" % prefix)
	elif kind not in ["flat", "ratio", "legacy"]:
		errors.append("%s.kind unknown: %s" % [prefix, kind])
	if str(ref_def.get("unit", "")).is_empty():
		errors.append("%s.unit missing" % prefix)
	return errors


static func _is_integer(value: Variant) -> bool:
	return (value is int or value is float) and int(value) == float(value)
