class_name AdventureConfigValidator
extends RefCounted

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
	"shop_offer_count_bonus",
	"event_reward_mult",
	"rest_heal_mult",
	"battle_reward_option_bonus",
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
	for key in ["starting_gold", "normal_combat_gold", "elite_combat_gold", "gem_base_price", "relic_base_price", "shop_offer_count"]:
		if not config.has(key):
			errors.append("economy_config.%s missing" % key)
		elif not config[key] is int and not config[key] is float:
			errors.append("economy_config.%s should be number" % key)
	return errors


static func validate_shop_pools(config: Dictionary) -> Array[String]:
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
	return errors


static func validate_room_defs(defs: Dictionary) -> Array[String]:
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
			errors.append_array(_validate_effects("room_defs.%s.effects" % room_type, room_def.get("effects", [])))
	return errors


static func validate_event_defs(defs: Dictionary) -> Array[String]:
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
			var conditions: Variant = option.get("conditions", [])
			if not conditions is Array:
				errors.append("event_defs.%s.options[%d].conditions should be array" % [event_id, i])
			else:
				errors.append_array(_validate_conditions("event_defs.%s.options[%d].conditions" % [event_id, i], conditions))
			var effects: Variant = option.get("effects", [])
			if not effects is Array:
				errors.append("event_defs.%s.options[%d].effects should be array" % [event_id, i])
			else:
				errors.append_array(_validate_effects("event_defs.%s.options[%d].effects" % [event_id, i], effects))
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


static func _validate_effects(prefix: String, effects: Array) -> Array[String]:
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
	return errors


static func _validate_conditions(prefix: String, conditions: Array) -> Array[String]:
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
	return errors
