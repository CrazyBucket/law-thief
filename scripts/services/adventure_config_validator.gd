class_name AdventureConfigValidator
extends RefCounted

const _TextResolver = preload("res://scripts/services/numeric_text_resolver.gd")

const ROOM_TYPES := [
	"START",
	"REST_SITE",
	"SHOP",
	"EVENT",
	"END",
	"NORMAL_COMBAT",
	"ELITE_COMBAT",
]

const ROOM_UI_KINDS := [
	"start",
	"rest",
	"shop",
	"event",
	"end",
	"battle",
]

const EFFECT_ACTIONS := [
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
	"chapter_gte",
]

const MODIFIER_IDS := [
	"gold_gain_mult",
	"shop_price_mult",
	"rest_heal_mult",
]

const AMOUNT_REF_KINDS := [
	"flat",
	"ratio",
	"legacy",
]


static func ensure_valid(file_path: String, errors: Array[String]) -> void:
	if errors.is_empty():
		return
	var message := "Adventure config invalid: %s\n- %s" % [file_path, "\n- ".join(errors)]
	push_error(message)
	if OS.is_debug_build():
		assert(false, message)


static func validate_economy_config(config: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for key in ["starting_gold", "normal_combat_gold", "elite_combat_gold", "boss_combat_gold", "gem_base_price", "relic_base_price"]:
		if not config.has(key):
			errors.append("economy_config.%s missing" % key)
		elif not config[key] is int and not config[key] is float:
			errors.append("economy_config.%s should be number" % key)
	var amount_refs: Variant = config.get("amount_refs", {})
	if not amount_refs is Dictionary:
		errors.append("economy_config.amount_refs should be object")
	else:
		for ref_id in (amount_refs as Dictionary).keys():
			var raw_ref: Variant = (amount_refs as Dictionary)[ref_id]
			errors.append_array(_validate_amount_ref_def("economy_config.amount_refs.%s" % str(ref_id), raw_ref))
	return errors


static func validate_shop_pools(config: Dictionary, known_gem_sources: Dictionary = {}, known_relic_sources: Dictionary = {}) -> Array[String]:
	var errors: Array[String] = []
	if not config.has("default"):
		errors.append("shop_pools.default missing")
		return errors
	var pool: Variant = config.get("default", {})
	if not pool is Dictionary:
		errors.append("shop_pools.default should be object")
		return errors
	for key in ["gem_offer_count", "relic_offer_count", "gem_source", "relic_source"]:
		if not (pool as Dictionary).has(key):
			errors.append("shop_pools.default.%s missing" % key)
	for key in ["gem_offer_count", "relic_offer_count"]:
		if not (pool as Dictionary).has(key):
			continue
		var raw_count: Variant = (pool as Dictionary)[key]
		if not raw_count is int and not raw_count is float:
			errors.append("shop_pools.default.%s should be number" % key)
		elif int(raw_count) != float(raw_count):
			errors.append("shop_pools.default.%s should be integer" % key)
		elif int(raw_count) < 0:
			errors.append("shop_pools.default.%s should be non-negative" % key)
	for key in ["gem_source", "relic_source"]:
		if not (pool as Dictionary).has(key):
			continue
		if not (pool as Dictionary)[key] is String:
			errors.append("shop_pools.default.%s should be string" % key)
		elif str((pool as Dictionary)[key]).is_empty():
			errors.append("shop_pools.default.%s should not be empty" % key)
	var gem_source := str((pool as Dictionary).get("gem_source", ""))
	if not gem_source.is_empty() and not known_gem_sources.is_empty() and not known_gem_sources.has(gem_source):
		errors.append("shop_pools.default.gem_source unknown: %s" % gem_source)
	var relic_source := str((pool as Dictionary).get("relic_source", ""))
	if not relic_source.is_empty() and not known_relic_sources.is_empty() and not known_relic_sources.has(relic_source):
		errors.append("shop_pools.default.relic_source unknown: %s" % relic_source)
	if int((pool as Dictionary).get("gem_offer_count", 0)) + int((pool as Dictionary).get("relic_offer_count", 0)) <= 0:
		errors.append("shop_pools.default should offer at least one item")
	return errors


static func validate_reward_offer_config(config: Dictionary, known_relic_sources: Dictionary = {}) -> Array[String]:
	var errors: Array[String] = []
	var battle_rewards: Variant = config.get("battle_rewards", {})
	if not battle_rewards is Dictionary:
		errors.append("reward_offer_config.battle_rewards should be object")
		return errors
	var rewards := battle_rewards as Dictionary
	if not rewards.has("default"):
		errors.append("reward_offer_config.battle_rewards.default missing")
	for reward_id in rewards.keys():
		var raw_reward: Variant = rewards[reward_id]
		if not raw_reward is Dictionary:
			errors.append("reward_offer_config.battle_rewards.%s should be object" % str(reward_id))
			continue
		var reward := raw_reward as Dictionary
		if not reward.has("relic_source"):
			errors.append("reward_offer_config.battle_rewards.%s.relic_source missing" % str(reward_id))
		elif not reward["relic_source"] is String:
			errors.append("reward_offer_config.battle_rewards.%s.relic_source should be string" % str(reward_id))
		elif str(reward.get("relic_source", "")).is_empty():
			errors.append("reward_offer_config.battle_rewards.%s.relic_source should not be empty" % str(reward_id))
		elif not known_relic_sources.is_empty() and not known_relic_sources.has(str(reward.get("relic_source", ""))):
			errors.append("reward_offer_config.battle_rewards.%s.relic_source unknown: %s" % [str(reward_id), str(reward.get("relic_source", ""))])
		if not reward.has("relic_offer_count"):
			errors.append("reward_offer_config.battle_rewards.%s.relic_offer_count missing" % str(reward_id))
		else:
			errors.append_array(_validate_non_negative_integer(
				"reward_offer_config.battle_rewards.%s.relic_offer_count" % str(reward_id),
				reward["relic_offer_count"]
			))
	return errors


static func validate_room_defs(defs: Dictionary, amount_refs: Dictionary = {}) -> Array[String]:
	var errors: Array[String] = []
	for required_room_type in ["START", "REST_SITE", "SHOP", "EVENT", "END"]:
		if not defs.has(required_room_type):
			errors.append("room_defs.%s missing" % required_room_type)
	for room_type in defs.keys():
		var def: Variant = defs[room_type]
		if not def is Dictionary:
			errors.append("room_defs.%s should be object" % room_type)
			continue
		var room_def := def as Dictionary
		if str(room_def.get("room_type", "")) != str(room_type):
			errors.append("room_defs.%s.room_type mismatch" % room_type)
		if not str(room_type) in ROOM_TYPES:
			errors.append("room_defs.%s unknown room type" % room_type)
		if str(room_def.get("ui_kind", "")) not in ROOM_UI_KINDS:
			errors.append("room_defs.%s.ui_kind invalid" % room_type)
		if not room_def.get("effects", []) is Array:
			errors.append("room_defs.%s.effects should be array" % room_type)
		else:
			errors.append_array(_validate_effects("room_defs.%s.effects" % room_type, room_def.get("effects", []), amount_refs))
	return errors


static func validate_event_defs(defs: Dictionary, amount_refs: Dictionary = {}) -> Array[String]:
	var errors: Array[String] = []
	for event_id in defs.keys():
		var raw_def: Variant = defs[event_id]
		if not raw_def is Dictionary:
			errors.append("event_defs.%s should be object" % event_id)
			continue
		var event_def := raw_def as Dictionary
		for key in ["title", "body", "options"]:
			if not event_def.has(key):
				errors.append("event_defs.%s.%s missing" % [event_id, key])
		errors.append_array(_validate_text_tokens("event_defs.%s.title" % event_id, str(event_def.get("title", "")), amount_refs, {}))
		errors.append_array(_validate_text_tokens("event_defs.%s.body" % event_id, str(event_def.get("body", "")), amount_refs, {}))
		var options: Variant = event_def.get("options", [])
		if not options is Array:
			errors.append("event_defs.%s.options should be array" % event_id)
			continue
		for i in range((options as Array).size()):
			var raw_option: Variant = (options as Array)[i]
			if not raw_option is Dictionary:
				errors.append("event_defs.%s.options[%d] should be object" % [event_id, i])
				continue
			var option := raw_option as Dictionary
			for key in ["id", "label", "effects"]:
				if not option.has(key):
					errors.append("event_defs.%s.options[%d].%s missing" % [event_id, i, key])
			errors.append_array(_validate_text_tokens("event_defs.%s.options[%d].label" % [event_id, i], str(option.get("label", "")), amount_refs, {}))
			var conditions: Variant = option.get("conditions", [])
			if not conditions is Array:
				errors.append("event_defs.%s.options[%d].conditions should be array" % [event_id, i])
			else:
				errors.append_array(_validate_conditions("event_defs.%s.options[%d].conditions" % [event_id, i], conditions, amount_refs))
			var effects: Variant = option.get("effects", [])
			if not effects is Array:
				errors.append("event_defs.%s.options[%d].effects should be array" % [event_id, i])
			else:
				errors.append_array(_validate_effects("event_defs.%s.options[%d].effects" % [event_id, i], effects, amount_refs))
	return errors


static func validate_map_rule_defs(defs: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for rule_id in defs.keys():
		var raw_def: Variant = defs[rule_id]
		if not raw_def is Dictionary:
			errors.append("map_rule_defs.%s should be object" % rule_id)
			continue
		var rule_def := raw_def as Dictionary
		for key in ["name", "desc", "effects"]:
			if not rule_def.has(key):
				errors.append("map_rule_defs.%s.%s missing" % [rule_id, key])
		var effects: Variant = rule_def.get("effects", [])
		if not effects is Array:
			errors.append("map_rule_defs.%s.effects should be array" % rule_id)
			continue
		var effect_values := _effect_value_map(effects as Array)
		errors.append_array(_validate_text_tokens("map_rule_defs.%s.name" % rule_id, str(rule_def.get("name", "")), {}, effect_values))
		errors.append_array(_validate_text_tokens("map_rule_defs.%s.desc" % rule_id, str(rule_def.get("desc", "")), {}, effect_values))
		for i in range((effects as Array).size()):
			var raw_effect: Variant = (effects as Array)[i]
			if not raw_effect is Dictionary:
				errors.append("map_rule_defs.%s.effects[%d] should be object" % [rule_id, i])
				continue
			var effect := raw_effect as Dictionary
			var modifier := str(effect.get("modifier", ""))
			if modifier.is_empty():
				errors.append("map_rule_defs.%s.effects[%d].modifier missing" % [rule_id, i])
			elif modifier not in MODIFIER_IDS:
				errors.append("map_rule_defs.%s.effects[%d].modifier unknown: %s" % [rule_id, i, modifier])
			if not effect.has("value"):
				errors.append("map_rule_defs.%s.effects[%d].value missing" % [rule_id, i])
	return errors


static func _validate_effects(prefix: String, effects: Array, amount_refs: Dictionary = {}) -> Array[String]:
	var errors: Array[String] = []
	for i in range(effects.size()):
		var raw_effect: Variant = effects[i]
		if not raw_effect is Dictionary:
			errors.append("%s[%d] should be object" % [prefix, i])
			continue
		var effect := raw_effect as Dictionary
		var action := str(effect.get("action", ""))
		if action.is_empty():
			errors.append("%s[%d].action missing" % [prefix, i])
		elif action not in EFFECT_ACTIONS:
			errors.append("%s[%d].action unknown: %s" % [prefix, i, action])
		else:
			errors.append_array(_validate_effect_payload("%s[%d]" % [prefix, i], action, effect, amount_refs))
	return errors


static func _validate_conditions(prefix: String, conditions: Array, amount_refs: Dictionary = {}) -> Array[String]:
	var errors: Array[String] = []
	for i in range(conditions.size()):
		var raw_condition: Variant = conditions[i]
		if not raw_condition is Dictionary:
			errors.append("%s[%d] should be object" % [prefix, i])
			continue
		var condition := raw_condition as Dictionary
		var condition_type := str(condition.get("type", ""))
		if condition_type.is_empty():
			errors.append("%s[%d].type missing" % [prefix, i])
		elif condition_type not in CONDITION_TYPES:
			errors.append("%s[%d].type unknown: %s" % [prefix, i, condition_type])
		else:
			errors.append_array(_validate_condition_payload("%s[%d]" % [prefix, i], condition_type, condition, amount_refs))
	return errors


static func _validate_effect_payload(prefix: String, action: String, effect: Dictionary, amount_refs: Dictionary = {}) -> Array[String]:
	var errors: Array[String] = []
	match action:
		"grant_resource", "spend_resource":
			var resource_id := str(effect.get("resource_id", ""))
			if resource_id.is_empty():
				errors.append("%s.resource_id missing" % prefix)
			errors.append_array(_validate_amount_fields(prefix, effect, amount_refs))
			errors.append_array(_validate_amount_ref_usage(prefix, effect, amount_refs, "flat", [resource_id]))
		"heal_player", "damage_player":
			errors.append_array(_validate_amount_fields(prefix, effect, amount_refs))
			errors.append_array(_validate_amount_ref_usage(prefix, effect, amount_refs, "flat", ["hp"]))
		"heal_player_percent":
			errors.append_array(_validate_amount_fields(prefix, effect, amount_refs))
			errors.append_array(_validate_amount_ref_usage(prefix, effect, amount_refs, "ratio", ["max_hp"]))
	return errors


static func _validate_condition_payload(prefix: String, condition_type: String, condition: Dictionary, amount_refs: Dictionary = {}) -> Array[String]:
	var errors: Array[String] = []
	match condition_type:
		"resource_gte":
			var resource_id := str(condition.get("resource_id", ""))
			if resource_id.is_empty():
				errors.append("%s.resource_id missing" % prefix)
			errors.append_array(_validate_amount_fields(prefix, condition, amount_refs))
			errors.append_array(_validate_amount_ref_usage(prefix, condition, amount_refs, "flat", [resource_id]))
	return errors


static func _validate_amount_fields(prefix: String, payload: Dictionary, amount_refs: Dictionary = {}) -> Array[String]:
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
	return errors


static func _validate_amount_ref_usage(prefix: String, payload: Dictionary, amount_refs: Dictionary, expected_kind: String, expected_units: Array[String]) -> Array[String]:
	var errors: Array[String] = []
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


static func _validate_text_tokens(prefix: String, text: String, amount_refs: Dictionary, effect_values: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if _TextResolver.has_literal_number_outside_tokens(text):
		errors.append("%s should use numeric text tokens instead of literal numbers" % prefix)
	for token in _TextResolver.extract_tokens(text):
		var token_type := str(token.get("type", ""))
		var token_value := str(token.get("value", ""))
		match token_type:
			"amount_ref":
				if not amount_refs.is_empty() and not amount_refs.has(token_value):
					errors.append("%s unknown amount_ref token: %s" % [prefix, token_value])
			"effect_percent_delta":
				if not effect_values.has(token_value):
					errors.append("%s unknown effect_percent_delta token: %s" % [prefix, token_value])
			_:
				errors.append("%s unknown text token type: %s" % [prefix, token_type])
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
	elif kind not in AMOUNT_REF_KINDS:
		errors.append("%s.kind unknown: %s" % [prefix, kind])
	var unit := str(ref_def.get("unit", ""))
	if unit.is_empty():
		errors.append("%s.unit missing" % prefix)
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


static func _amount_ref_def(raw_ref: Variant) -> Dictionary:
	if raw_ref is Dictionary:
		return raw_ref as Dictionary
	return {
		"value": raw_ref,
		"kind": "legacy",
		"unit": "",
	}


static func _effect_value_map(effects: Array) -> Dictionary:
	var values := {}
	for raw_effect in effects:
		if not raw_effect is Dictionary:
			continue
		var effect := raw_effect as Dictionary
		values[str(effect.get("modifier", ""))] = float(effect.get("value", 1.0))
	return values
