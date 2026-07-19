class_name EconomyConfigValidator
extends RefCounted


static func validate(config: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var required_fields := ["starting_gold", "combat_rewards", "shop_prices", "amount_refs"]
	var optional_fields := ["economy_model"]
	for key in config.keys():
		if str(key) not in required_fields and str(key) not in optional_fields:
			errors.append("economy_config.%s is unknown" % key)
	for key in required_fields:
		if not config.has(key):
			errors.append("economy_config.%s missing" % key)
	if config.has("starting_gold"):
		errors.append_array(_validate_non_negative_integer("economy_config.starting_gold", config["starting_gold"]))
	if config.has("economy_model"):
		errors.append_array(_validate_economy_model(config["economy_model"]))
	_validate_combat_rewards(config.get("combat_rewards", {}), errors)
	_validate_shop_prices(config.get("shop_prices", {}), errors)
	_validate_amount_refs(config.get("amount_refs", {}), errors)
	return errors


static func _validate_economy_model(raw_model: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not raw_model is Dictionary:
		errors.append("economy_config.economy_model should be object")
		return errors
	var model := raw_model as Dictionary
	var required_fields := [
		"mu", "G_init", "acts", "nodes_per_act", "shops_per_act",
		"combat_normal_mu", "sigma_combat", "combat_elite_mu", "sigma_elite",
		"combat_boss_mu", "sigma_boss", "event_positive_mu", "event_positive_rate",
		"sigma_event_pos", "event_negative_mu", "event_negative_rate", "sigma_event_neg",
		"include_events", "price_sigma", "prices"
	]
	for key in model.keys():
		if str(key) not in required_fields:
			errors.append("economy_config.economy_model.%s is unknown" % key)
	for key in required_fields:
		if not model.has(key):
			errors.append("economy_config.economy_model.%s missing" % key)
	for key in ["mu", "combat_normal_mu", "combat_elite_mu", "combat_boss_mu"]:
		if model.has(key):
			errors.append_array(_validate_positive_number("economy_config.economy_model.%s" % key, model[key]))
	for key in ["sigma_combat", "sigma_elite", "sigma_boss", "sigma_event_pos", "sigma_event_neg"]:
		if model.has(key):
			errors.append_array(_validate_non_negative_number("economy_config.economy_model.%s" % key, model[key]))
	if model.has("price_sigma"):
		errors.append_array(_validate_non_negative_number("economy_config.economy_model.price_sigma", model["price_sigma"]))
	for key in ["event_positive_rate", "event_negative_rate"]:
		if model.has(key):
			errors.append_array(_validate_probability("economy_config.economy_model.%s" % key, model[key]))
	for key in ["G_init", "acts", "nodes_per_act", "shops_per_act"]:
		if model.has(key):
			errors.append_array(_validate_non_negative_integer("economy_config.economy_model.%s" % key, model[key]))
	if model.has("acts") and _is_integer(model["acts"]) and int(model["acts"]) <= 0:
		errors.append("economy_config.economy_model.acts should be positive")
	if model.has("nodes_per_act") and _is_integer(model["nodes_per_act"]) and int(model["nodes_per_act"]) <= 0:
		errors.append("economy_config.economy_model.nodes_per_act should be positive")
	if model.has("shops_per_act") and model.has("nodes_per_act") and _is_integer(model["shops_per_act"]) and _is_integer(model["nodes_per_act"]) and int(model["shops_per_act"]) > int(model["nodes_per_act"]):
		errors.append("economy_config.economy_model.shops_per_act should not exceed nodes_per_act")
	if model.has("include_events") and not model["include_events"] is bool:
		errors.append("economy_config.economy_model.include_events should be bool")
	var raw_prices: Variant = model.get("prices", {})
	if not raw_prices is Dictionary:
		errors.append("economy_config.economy_model.prices should be object")
	else:
		var prices := raw_prices as Dictionary
		var price_keys := ["basic_card", "uncommon_card", "rare_card", "basic_relic", "uncommon_relic", "rare_relic", "potion", "remove"]
		for key in prices.keys():
			if str(key) not in price_keys:
				errors.append("economy_config.economy_model.prices.%s is unknown" % key)
		for key in price_keys:
			if not prices.has(key):
				errors.append("economy_config.economy_model.prices.%s missing" % key)
			else:
				errors.append_array(_validate_positive_number("economy_config.economy_model.prices.%s" % key, prices[key]))
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


static func _validate_non_negative_number(prefix: String, value: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not value is int and not value is float:
		errors.append("%s should be number" % prefix)
	elif float(value) < 0.0:
		errors.append("%s should be non-negative" % prefix)
	return errors


static func _validate_positive_number(prefix: String, value: Variant) -> Array[String]:
	var errors := _validate_non_negative_number(prefix, value)
	if errors.is_empty() and float(value) <= 0.0:
		errors.append("%s should be positive" % prefix)
	return errors


static func _validate_probability(prefix: String, value: Variant) -> Array[String]:
	var errors := _validate_non_negative_number(prefix, value)
	if errors.is_empty() and float(value) > 1.0:
		errors.append("%s should be between 0 and 1" % prefix)
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
