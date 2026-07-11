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

const ENCOUNTER_FIELDS := {
	"catalog_visible": true,
	"player_spawn": true,
	"enemies": true,
	"enemy_groups": true,
	"random_enemies": true,
	"tiles": true,
	"entities": true,
}

const ENCOUNTER_SLOT_TYPES := ["red", "blue", "black"]


static func ensure_valid(file_path: String, errors: Array[String]) -> void:
	if errors.is_empty():
		return
	var message := "Adventure config invalid: %s\n- %s" % [file_path, "\n- ".join(errors)]
	push_error(message)
	if OS.is_debug_build():
		assert(false, message)


static func validate_adventure_progression(
	config: Dictionary,
	known_encounters: Dictionary = {},
	known_events: Dictionary = {}
) -> Array[String]:
	var errors: Array[String] = []
	var top_fields := ["chapter_count", "chapter_seed_stride", "map", "combat_encounters", "boss_encounters"]
	for field_id in config.keys():
		if str(field_id) not in top_fields:
			errors.append("adventure_progression.%s is unknown" % field_id)
	for field_id in top_fields:
		if not config.has(field_id):
			errors.append("adventure_progression.%s missing" % field_id)
	var chapter_count: Variant = config.get("chapter_count", null)
	if not _is_positive_integer(chapter_count):
		errors.append("adventure_progression.chapter_count should be a positive integer")
	var seed_stride: Variant = config.get("chapter_seed_stride", null)
	if not _is_positive_integer(seed_stride):
		errors.append("adventure_progression.chapter_seed_stride should be a positive integer")
	var raw_map: Variant = config.get("map", null)
	if not raw_map is Dictionary:
		errors.append("adventure_progression.map should be object")
	else:
		errors.append_array(_validate_progression_map(raw_map as Dictionary, known_events))
	var combat_pools: Variant = config.get("combat_encounters", null)
	if not combat_pools is Dictionary:
		errors.append("adventure_progression.combat_encounters should be object")
	else:
		for room_type in ["NORMAL_COMBAT", "ELITE_COMBAT"]:
			var pool: Variant = (combat_pools as Dictionary).get(room_type, null)
			errors.append_array(_validate_progression_id_pool(
				"adventure_progression.combat_encounters.%s" % room_type,
				pool,
				known_encounters
			))
		for room_type in (combat_pools as Dictionary).keys():
			if str(room_type) not in ["NORMAL_COMBAT", "ELITE_COMBAT"]:
				errors.append("adventure_progression.combat_encounters.%s is unknown" % room_type)
	var bosses: Variant = config.get("boss_encounters", null)
	errors.append_array(_validate_progression_id_pool("adventure_progression.boss_encounters", bosses, known_encounters))
	if bosses is Array and _is_positive_integer(chapter_count) and (bosses as Array).size() != int(chapter_count):
		errors.append("adventure_progression.boss_encounters should contain one entry per chapter")
	return errors


static func _validate_progression_map(config: Dictionary, known_events: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var fields := ["grid_size", "fallback_room_type", "room_rules", "event_pool"]
	for field_id in config.keys():
		if str(field_id) not in fields:
			errors.append("adventure_progression.map.%s is unknown" % field_id)
	for field_id in fields:
		if not config.has(field_id):
			errors.append("adventure_progression.map.%s missing" % field_id)
	var grid_size: Variant = config.get("grid_size", null)
	if not _is_positive_integer(grid_size) or int(grid_size) < 2:
		errors.append("adventure_progression.map.grid_size should be an integer of at least 2")
	var rules: Variant = config.get("room_rules", null)
	if not rules is Dictionary:
		errors.append("adventure_progression.map.room_rules should be object")
	else:
		for room_type in ROOM_TYPES:
			if not (rules as Dictionary).has(room_type):
				errors.append("adventure_progression.map.room_rules.%s missing" % room_type)
		for room_type in (rules as Dictionary).keys():
			if str(room_type) not in ROOM_TYPES:
				errors.append("adventure_progression.map.room_rules.%s is unknown" % room_type)
				continue
			var raw_rule: Variant = (rules as Dictionary)[room_type]
			if not raw_rule is Dictionary:
				errors.append("adventure_progression.map.room_rules.%s should be object" % room_type)
				continue
			errors.append_array(_validate_progression_room_rule(str(room_type), raw_rule as Dictionary))
		var fallback_room := str(config.get("fallback_room_type", ""))
		if fallback_room.is_empty() or not (rules as Dictionary).has(fallback_room):
			errors.append("adventure_progression.map.fallback_room_type should reference a room rule")
	errors.append_array(_validate_progression_id_pool("adventure_progression.map.event_pool", config.get("event_pool", null), known_events))
	return errors


static func _validate_progression_room_rule(room_type: String, rule: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var fields := ["fixed_layer", "weight", "min_layer", "max_layer", "no_consecutive"]
	for field_id in rule.keys():
		if str(field_id) not in fields:
			errors.append("adventure_progression.map.room_rules.%s.%s is unknown" % [room_type, field_id])
	if rule.has("fixed_layer"):
		if str(rule["fixed_layer"]) not in ["start", "end"]:
			errors.append("adventure_progression.map.room_rules.%s.fixed_layer should be start or end" % room_type)
		elif room_type == "START" and str(rule["fixed_layer"]) != "start":
			errors.append("adventure_progression.map.room_rules.START.fixed_layer should be start")
		elif room_type == "END" and str(rule["fixed_layer"]) != "end":
			errors.append("adventure_progression.map.room_rules.END.fixed_layer should be end")
		elif room_type not in ["START", "END"]:
			errors.append("adventure_progression.map.room_rules.%s should not use fixed_layer" % room_type)
	if not rule.has("weight") or not _is_positive_integer(rule["weight"]):
		errors.append("adventure_progression.map.room_rules.%s.weight should be a positive integer" % room_type)
	for field_id in ["min_layer", "max_layer"]:
		if rule.has(field_id) and (
			not (rule[field_id] is int or rule[field_id] is float)
			or int(rule[field_id]) != float(rule[field_id])
			or int(rule[field_id]) < 0
		):
			errors.append("adventure_progression.map.room_rules.%s.%s should be a non-negative integer" % [room_type, field_id])
	if rule.has("no_consecutive") and not rule["no_consecutive"] is bool:
		errors.append("adventure_progression.map.room_rules.%s.no_consecutive should be bool" % room_type)
	return errors


static func _validate_progression_id_pool(prefix: String, raw_pool: Variant, known_ids: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not raw_pool is Array or (raw_pool as Array).is_empty():
		errors.append("%s should be a non-empty array" % prefix)
		return errors
	var seen: Dictionary = {}
	for raw_id in raw_pool as Array:
		var id := str(raw_id)
		if not raw_id is String or id.is_empty():
			errors.append("%s should contain non-empty strings" % prefix)
		elif seen.has(id):
			errors.append("%s contains duplicate id: %s" % [prefix, id])
		elif not known_ids.is_empty() and not known_ids.has(id):
			errors.append("%s references unknown id: %s" % [prefix, id])
		seen[id] = true
	return errors


static func validate_encounter_def(
	encounter_id: String,
	encounter: Dictionary,
	unit_defs: Dictionary,
	known_tile_ids: Dictionary,
	known_entity_ids: Dictionary,
	known_overlay_ids: Dictionary,
	known_gem_ids: Dictionary,
	board_size: Vector2i
) -> Array[String]:
	var errors: Array[String] = []
	var prefix := "encounters.%s" % encounter_id
	if encounter.is_empty():
		errors.append("%s should not be empty" % prefix)
		return errors
	for field_id in encounter.keys():
		if not ENCOUNTER_FIELDS.has(str(field_id)):
			errors.append("%s.%s is unknown" % [prefix, field_id])
	if encounter.has("catalog_visible") and not encounter["catalog_visible"] is bool:
		errors.append("%s.catalog_visible should be bool" % prefix)
	if not encounter.has("player_spawn"):
		errors.append("%s.player_spawn missing" % prefix)
	else:
		errors.append_array(_validate_grid_position("%s.player_spawn" % prefix, encounter["player_spawn"], board_size))
	var authored_enemy_count := 0
	var enemies: Variant = encounter.get("enemies", [])
	if not enemies is Array:
		errors.append("%s.enemies should be array" % prefix)
	else:
		authored_enemy_count += (enemies as Array).size()
		for index in range((enemies as Array).size()):
			errors.append_array(_validate_encounter_enemy(
				"%s.enemies[%d]" % [prefix, index],
				(enemies as Array)[index],
				unit_defs,
				board_size
			))
	var groups: Variant = encounter.get("enemy_groups", [])
	if not groups is Array:
		errors.append("%s.enemy_groups should be array" % prefix)
	else:
		var total_group_weight := 0.0
		for group_index in range((groups as Array).size()):
			var group_prefix := "%s.enemy_groups[%d]" % [prefix, group_index]
			var raw_group: Variant = (groups as Array)[group_index]
			if not raw_group is Dictionary:
				errors.append("%s should be object" % group_prefix)
				continue
			var group := raw_group as Dictionary
			for field_id in group.keys():
				if str(field_id) not in ["weight", "enemies"]:
					errors.append("%s.%s is unknown" % [group_prefix, field_id])
			var weight: Variant = group.get("weight", null)
			if not weight is int and not weight is float or float(weight) <= 0.0:
				errors.append("%s.weight should be positive" % group_prefix)
			else:
				total_group_weight += float(weight)
			var group_enemies: Variant = group.get("enemies", null)
			if not group_enemies is Array or (group_enemies as Array).is_empty():
				errors.append("%s.enemies should be a non-empty array" % group_prefix)
				continue
			authored_enemy_count += (group_enemies as Array).size()
			for enemy_index in range((group_enemies as Array).size()):
				errors.append_array(_validate_encounter_enemy(
					"%s.enemies[%d]" % [group_prefix, enemy_index],
					(group_enemies as Array)[enemy_index],
					unit_defs,
					board_size
				))
		if not (groups as Array).is_empty() and total_group_weight <= 0.0:
			errors.append("%s.enemy_groups should have positive total weight" % prefix)
	var random_enemies: Variant = encounter.get("random_enemies", [])
	if not random_enemies is Array:
		errors.append("%s.random_enemies should be array" % prefix)
	else:
		authored_enemy_count += (random_enemies as Array).size()
		for slot_index in range((random_enemies as Array).size()):
			errors.append_array(_validate_random_enemy_slot(
				"%s.random_enemies[%d]" % [prefix, slot_index],
				(random_enemies as Array)[slot_index],
				unit_defs,
				board_size
			))
	if authored_enemy_count <= 0:
		errors.append("%s should author at least one enemy" % prefix)
	var tiles: Variant = encounter.get("tiles", [])
	if not tiles is Array:
		errors.append("%s.tiles should be array" % prefix)
	else:
		for index in range((tiles as Array).size()):
			errors.append_array(_validate_encounter_tile(
				"%s.tiles[%d]" % [prefix, index],
				(tiles as Array)[index],
				known_tile_ids,
				known_overlay_ids,
				known_gem_ids,
				board_size
			))
	var entities: Variant = encounter.get("entities", [])
	if not entities is Array:
		errors.append("%s.entities should be array" % prefix)
	else:
		for index in range((entities as Array).size()):
			errors.append_array(_validate_encounter_entity(
				"%s.entities[%d]" % [prefix, index],
				(entities as Array)[index],
				known_entity_ids,
				board_size
			))
	return errors


static func validate_economy_config(config: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var required_fields := ["starting_gold", "normal_combat_gold", "elite_combat_gold", "boss_combat_gold", "gem_base_price", "relic_base_price", "amount_refs"]
	for key in config.keys():
		if str(key) not in required_fields:
			errors.append("economy_config.%s is unknown" % key)
	for key in required_fields:
		if not config.has(key):
			errors.append("economy_config.%s missing" % key)
	for key in ["starting_gold", "normal_combat_gold", "elite_combat_gold", "boss_combat_gold", "gem_base_price", "relic_base_price"]:
		if not config.has(key):
			continue
		elif not config[key] is int and not config[key] is float:
			errors.append("economy_config.%s should be number" % key)
		elif int(config[key]) != float(config[key]) or int(config[key]) < 0:
			errors.append("economy_config.%s should be a non-negative integer" % key)
	var amount_refs: Variant = config.get("amount_refs", {})
	if not amount_refs is Dictionary or (amount_refs as Dictionary).is_empty():
		errors.append("economy_config.amount_refs should be a non-empty object")
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


static func validate_battle_reward_ui_config(config: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var settlement_keys := [
		"canvas_layer",
		"panel_width",
		"panel_margin",
		"content_separation",
		"row_separation",
		"row_width",
		"row_height",
		"row_action_width",
		"row_action_height",
		"continue_button_width",
		"continue_button_height",
	]
	var reward_overlay_keys := [
		"canvas_layer",
		"content_separation",
		"card_separation",
		"scroll_max_width",
		"scroll_viewport_ratio",
		"scroll_hover_pad",
		"scroll_bar_reserve",
		"scroll_edge_pad",
		"action_button_width",
		"action_button_height",
		"fallback_viewport_width",
	]
	var card_kinds := {
		"relic": ["width", "height", "desc_width", "desc_height", "icon_size", "pick_button_height"],
		"gem": ["width", "height", "icon_size", "pick_button_height"],
		"dropped_gem": ["width", "height", "icon_size", "pick_button_height"],
		"slot_embed": ["width", "height", "pick_button_height"],
	}
	errors.append_array(_validate_layout_section(config, "settlement", settlement_keys))
	errors.append_array(_validate_layout_section(config, "reward_overlay", reward_overlay_keys))
	var cards: Variant = config.get("cards", {})
	if not cards is Dictionary:
		errors.append("battle_reward_ui_config.cards should be object")
	else:
		for card_kind in card_kinds.keys():
			var prefix := "battle_reward_ui_config.cards.%s" % str(card_kind)
			var raw_card: Variant = (cards as Dictionary).get(card_kind, null)
			if not raw_card is Dictionary:
				errors.append("%s missing" % prefix)
				continue
			for key in card_kinds[card_kind]:
				var field_prefix := "%s.%s" % [prefix, str(key)]
				var raw_value: Variant = (raw_card as Dictionary).get(key, null)
				if raw_value == null:
					errors.append("%s missing" % field_prefix)
				else:
					errors.append_array(_validate_positive_number(field_prefix, raw_value))
	var ratio_section: Variant = config.get("reward_overlay", null)
	if ratio_section is Dictionary:
		var ratio_value: Variant = (ratio_section as Dictionary).get("scroll_viewport_ratio", null)
		if ratio_value is int or ratio_value is float:
			var ratio := float(ratio_value)
			if ratio <= 0.0 or ratio > 1.0:
				errors.append("battle_reward_ui_config.reward_overlay.scroll_viewport_ratio should be in (0, 1]")
	return errors


static func _validate_layout_section(config: Dictionary, section: String, keys: Array) -> Array[String]:
	var errors: Array[String] = []
	var prefix := "battle_reward_ui_config.%s" % section
	var raw_section: Variant = config.get(section, null)
	if not raw_section is Dictionary:
		errors.append("%s missing" % prefix)
		return errors
	var section_dict := raw_section as Dictionary
	for key in keys:
		var field_prefix := "%s.%s" % [prefix, str(key)]
		if not section_dict.has(key):
			errors.append("%s missing" % field_prefix)
		else:
			errors.append_array(_validate_positive_number(field_prefix, section_dict[key]))
	return errors


static func _validate_positive_number(prefix: String, value: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not value is int and not value is float:
		errors.append("%s should be number" % prefix)
	elif float(value) <= 0.0:
		errors.append("%s should be positive" % prefix)
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


static func _validate_encounter_enemy(
	prefix: String,
	raw_enemy: Variant,
	unit_defs: Dictionary,
	board_size: Vector2i
) -> Array[String]:
	var errors: Array[String] = []
	if not raw_enemy is Dictionary:
		errors.append("%s should be object" % prefix)
		return errors
	var enemy := raw_enemy as Dictionary
	for field_id in enemy.keys():
		if str(field_id) not in ["def_id", "pos"]:
			errors.append("%s.%s is unknown" % [prefix, field_id])
	var def_id := str(enemy.get("def_id", ""))
	if not enemy.get("def_id", null) is String or def_id.is_empty():
		errors.append("%s.def_id should be a non-empty string" % prefix)
	elif not unit_defs.has(def_id):
		errors.append("%s.def_id references unknown unit: %s" % [prefix, def_id])
	var footprint := _unit_footprint(unit_defs.get(def_id, {}))
	if not enemy.has("pos"):
		errors.append("%s.pos missing" % prefix)
	else:
		errors.append_array(_validate_grid_position("%s.pos" % prefix, enemy["pos"], board_size, footprint))
	return errors


static func _validate_random_enemy_slot(
	prefix: String,
	raw_slot: Variant,
	unit_defs: Dictionary,
	board_size: Vector2i
) -> Array[String]:
	var errors: Array[String] = []
	if not raw_slot is Dictionary:
		errors.append("%s should be object" % prefix)
		return errors
	var slot := raw_slot as Dictionary
	for field_id in slot.keys():
		if str(field_id) not in ["pos", "candidates"]:
			errors.append("%s.%s is unknown" % [prefix, field_id])
	var candidates: Variant = slot.get("candidates", null)
	if not candidates is Array or (candidates as Array).is_empty():
		errors.append("%s.candidates should be a non-empty array" % prefix)
		return errors
	var total_weight := 0.0
	for index in range((candidates as Array).size()):
		var candidate_prefix := "%s.candidates[%d]" % [prefix, index]
		var raw_candidate: Variant = (candidates as Array)[index]
		var def_id := ""
		var weight := 1.0
		if raw_candidate is String:
			def_id = str(raw_candidate)
		elif raw_candidate is Dictionary:
			var candidate := raw_candidate as Dictionary
			for field_id in candidate.keys():
				if str(field_id) not in ["def_id", "weight"]:
					errors.append("%s.%s is unknown" % [candidate_prefix, field_id])
			def_id = str(candidate.get("def_id", ""))
			var raw_weight: Variant = candidate.get("weight", 1.0)
			if not raw_weight is int and not raw_weight is float or float(raw_weight) <= 0.0:
				errors.append("%s.weight should be positive" % candidate_prefix)
				weight = 0.0
			else:
				weight = float(raw_weight)
		else:
			errors.append("%s should be a unit id or object" % candidate_prefix)
			continue
		if def_id.is_empty():
			errors.append("%s.def_id should be a non-empty string" % candidate_prefix)
		elif not unit_defs.has(def_id):
			errors.append("%s.def_id references unknown unit: %s" % [candidate_prefix, def_id])
		elif slot.has("pos"):
			errors.append_array(_validate_grid_position(
				"%s.pos" % prefix,
				slot["pos"],
				board_size,
				_unit_footprint(unit_defs.get(def_id, {}))
			))
		total_weight += weight
	if not slot.has("pos"):
		errors.append("%s.pos missing" % prefix)
	if total_weight <= 0.0:
		errors.append("%s.candidates should have positive total weight" % prefix)
	return errors


static func _validate_encounter_tile(
	prefix: String,
	raw_tile: Variant,
	known_tile_ids: Dictionary,
	known_overlay_ids: Dictionary,
	known_gem_ids: Dictionary,
	board_size: Vector2i
) -> Array[String]:
	var errors: Array[String] = []
	if not raw_tile is Dictionary:
		errors.append("%s should be object" % prefix)
		return errors
	var tile := raw_tile as Dictionary
	for field_id in tile.keys():
		if str(field_id) not in ["pos", "tile_id", "slots", "overlays"]:
			errors.append("%s.%s is unknown" % [prefix, field_id])
	var tile_id := str(tile.get("tile_id", ""))
	if tile_id.is_empty():
		errors.append("%s.tile_id should be a non-empty string" % prefix)
	elif not known_tile_ids.is_empty() and not known_tile_ids.has(tile_id):
		errors.append("%s.tile_id references unknown tile: %s" % [prefix, tile_id])
	if not tile.has("pos"):
		errors.append("%s.pos missing" % prefix)
	else:
		errors.append_array(_validate_grid_position("%s.pos" % prefix, tile["pos"], board_size))
	var slots: Variant = tile.get("slots", [])
	if not slots is Array:
		errors.append("%s.slots should be array" % prefix)
	else:
		for index in range((slots as Array).size()):
			errors.append_array(_validate_encounter_slot("%s.slots[%d]" % [prefix, index], (slots as Array)[index], known_gem_ids))
	var overlays: Variant = tile.get("overlays", [])
	if not overlays is Array:
		errors.append("%s.overlays should be array" % prefix)
	else:
		for index in range((overlays as Array).size()):
			var overlay_prefix := "%s.overlays[%d]" % [prefix, index]
			var raw_overlay: Variant = (overlays as Array)[index]
			if not raw_overlay is Dictionary:
				errors.append("%s should be object" % overlay_prefix)
				continue
			var overlay := raw_overlay as Dictionary
			for field_id in overlay.keys():
				if str(field_id) not in ["type", "duration"]:
					errors.append("%s.%s is unknown" % [overlay_prefix, field_id])
			var overlay_id := str(overlay.get("type", ""))
			if overlay_id.is_empty():
				errors.append("%s.type should be a non-empty string" % overlay_prefix)
			elif not known_overlay_ids.is_empty() and not known_overlay_ids.has(overlay_id):
				errors.append("%s.type references unknown overlay: %s" % [overlay_prefix, overlay_id])
			if not _is_positive_integer(overlay.get("duration", null)):
				errors.append("%s.duration should be a positive integer" % overlay_prefix)
	return errors


static func _validate_encounter_slot(prefix: String, raw_slot: Variant, known_gem_ids: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not raw_slot is Dictionary:
		errors.append("%s should be object" % prefix)
		return errors
	var slot := raw_slot as Dictionary
	for field_id in slot.keys():
		if str(field_id) not in ["slot_type", "gem_id"]:
			errors.append("%s.%s is unknown" % [prefix, field_id])
	var slot_type := str(slot.get("slot_type", ""))
	if slot_type not in ENCOUNTER_SLOT_TYPES:
		errors.append("%s.slot_type unknown: %s" % [prefix, slot_type])
	if slot.has("gem_id"):
		var gem_id := str(slot.get("gem_id", ""))
		if gem_id.is_empty():
			errors.append("%s.gem_id should be a non-empty string" % prefix)
		elif not known_gem_ids.is_empty() and not known_gem_ids.has(gem_id):
			errors.append("%s.gem_id references unknown gem: %s" % [prefix, gem_id])
	return errors


static func _validate_encounter_entity(
	prefix: String,
	raw_entity: Variant,
	known_entity_ids: Dictionary,
	board_size: Vector2i
) -> Array[String]:
	var errors: Array[String] = []
	if not raw_entity is Dictionary:
		errors.append("%s should be object" % prefix)
		return errors
	var entity := raw_entity as Dictionary
	for field_id in entity.keys():
		if str(field_id) not in ["entity_id", "pos", "prop_sprite"]:
			errors.append("%s.%s is unknown" % [prefix, field_id])
	var entity_id := str(entity.get("entity_id", ""))
	if entity_id.is_empty():
		errors.append("%s.entity_id should be a non-empty string" % prefix)
	elif not known_entity_ids.is_empty() and not known_entity_ids.has(entity_id):
		errors.append("%s.entity_id references unknown entity: %s" % [prefix, entity_id])
	if not entity.has("pos"):
		errors.append("%s.pos missing" % prefix)
	else:
		errors.append_array(_validate_grid_position("%s.pos" % prefix, entity["pos"], board_size))
	if entity.has("prop_sprite") and (not entity["prop_sprite"] is String or str(entity["prop_sprite"]).is_empty()):
		errors.append("%s.prop_sprite should be a non-empty string" % prefix)
	return errors


static func _validate_grid_position(
	prefix: String,
	value: Variant,
	board_size: Vector2i,
	footprint: Vector2i = Vector2i.ONE
) -> Array[String]:
	var errors: Array[String] = []
	if not value is Array or (value as Array).size() != 2:
		errors.append("%s should contain 2 integers" % prefix)
		return errors
	var coords := value as Array
	for coord in coords:
		if not coord is int and not coord is float or int(coord) != float(coord):
			errors.append("%s should contain 2 integers" % prefix)
			return errors
	var pos := Vector2i(int(coords[0]), int(coords[1]))
	if pos.x < 0 or pos.y < 0 or pos.x + footprint.x > board_size.x or pos.y + footprint.y > board_size.y:
		errors.append("%s is outside %dx%d board for %dx%d footprint" % [prefix, board_size.x, board_size.y, footprint.x, footprint.y])
	return errors


static func _unit_footprint(raw_unit_def: Variant) -> Vector2i:
	if not raw_unit_def is Dictionary:
		return Vector2i.ONE
	var raw_footprint: Variant = (raw_unit_def as Dictionary).get("footprint_size", [1, 1])
	if not raw_footprint is Array or (raw_footprint as Array).size() != 2:
		return Vector2i.ONE
	return Vector2i(int((raw_footprint as Array)[0]), int((raw_footprint as Array)[1]))


static func _is_positive_integer(value: Variant) -> bool:
	return (value is int or value is float) and int(value) == float(value) and int(value) > 0


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
