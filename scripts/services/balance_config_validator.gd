class_name BalanceConfigValidator
extends RefCounted

const NumericTextResolver = preload("res://scripts/services/numeric_text_resolver.gd")

const ROOM_TYPE_KEYS := [
	"NORMAL_COMBAT",
	"ELITE_COMBAT",
	"BOSS_COMBAT",
]

const UNIT_BALANCE_NUMERIC_KEYS := {
	"rampage_move_bonus": true,
	"charge_bonus": true,
	"charge_min_steps": true,
	"attack_range": true,
	"deploy_range_bonus": true,
	"faulty_miss_chance": true,
	"faulty_damage_bonus": true,
	"kite_ideal_range": true,
	"kite_min_range": true,
	"ranged_damage_score_mult": true,
	"kill_bonus": true,
	"move_step_cost": true,
	"ideal_range_penalty": true,
	"too_close_extra_penalty": true,
	"max_range_bonus": true,
	"hold_position_bonus": true,
	"deploy_hold_bonus": true,
	"move_when_shooting_penalty": true,
	"closer_when_shooting_penalty": true,
	"emergency_retreat_bonus_per_tile": true,
	"extra_distance_penalty_per_tile": true,
	"closer_to_gain_shot_bonus_per_tile": true,
	"setup_deploy_bonus": true,
	"approach_progress_score": true,
	"approach_distance_cost": true,
	"approach_too_close_penalty": true,
	"approach_ideal_band_bonus": true,
	"retreat_bonus_per_tile": true,
	"retreat_ideal_range_penalty": true,
	"retreat_too_close_penalty": true,
	"line_unreachable_penalty": true,
	"line_setup_bonus": true,
	"line_setup_distance_cost": true,
	"line_progress_bonus_per_step": true,
	"line_no_progress_penalty": true,
	"wait_score": true,
	"split_stat_ratio": true,
	"slam_push_steps": true,
	"trample_damage": true,
}

const COMBAT_CONFIG_NUMERIC_KEYS := {
	"attack_range": true,
	"extract_range": true,
	"insert_range": true,
	"trigger_range": true,
	"split_attack_range": true,
	"split_attack_damage_ratio": true,
	"split_damage_redirect_ratio": true,
	"split_surround_radius": true,
	"split_black_stat_ratio": true,
	"explosion_damage": true,
	"explosion_radius": true,
	"explosion_cross_damage": true,
	"explosion_death_radius": true,
	"charge_explode_dash_range": true,
	"knockback_collision_damage": true,
	"spike_damage": true,
	"spike_collision_damage": true,
	"barrel_hp": true,
	"barrel_explosion_damage": true,
	"gravity_collision_damage": true,
	"enemy_gravity_pull_range": true,
	"poison_fog_damage": true,
	"poison_fog_duration": true,
	"arc_proc_chance": true,
	"arc_paralysis_chance": true,
	"arc_chain_damage_ratio": true,
	"arc_chain_range": true,
	"arc_hit_damage": true,
	"lightning_death_damage": true,
	"fire_death_fire_count": true,
	"fire_death_radius": true,
	"ice_death_radius": true,
	"split_death_hp_merge_divisor": true,
	"overload_gem_op_damage_amount": true,
	"overload_ai_control_min_chapter": true,
	"overload_ai_control_max_chapter": true,
	"overload_ai_control_base_percent": true,
	"overload_ai_control_chapter_baseline": true,
	"overload_ai_control_chapter_penalty": true,
	"overload_ai_control_gem_baseline": true,
	"overload_ai_control_gem_penalty": true,
	"overload_ai_control_min_probability": true,
	"overload_ai_control_max_probability": true,
	"fire_duration": true,
	"fire_spread_chance": true,
	"grass_grow_chance": true,
}

const AI_PROFILE_NUMERIC_KEYS := {
	"w_damage": true,
	"w_kill_player": true,
	"w_self_sacrifice": true,
	"w_self_damage": true,
	"w_friendly_fire": true,
	"w_approach": true,
	"w_move_cost": true,
	"w_pull": true,
	"w_poison": true,
	"w_status": true,
	"w_deploy_bonus": true,
	"w_keep_distance": true,
	"wait_score": true,
	"path_base_step_cost": true,
	"path_spike_damage_weight": true,
	"path_water_cost_bias": true,
}

const AI_PROFILE_BOOL_KEYS := {
	"can_extract": true,
	"prefer_distance": true,
	"guard_ally": true,
	"can_ranged_attack": true,
	"ranged_only": true,
	"allow_partial_path": true,
}

const AI_TUNING_NUMERIC_KEYS := {
	"ranged_keep_distance_scale": true,
	"explosion_adjacent_bonus_mult": true,
	"pull_base_bonus": true,
	"pull_damage_bonus_mult": true,
	"pull_distance_score_mult": true,
	"arc_chain_bonus_mult": true,
	"approach_progress_floor": true,
	"path_self_damage_ratio": true,
}

const STATUS_CONFIG_ENTRY_KEYS := {
	"poison": true,
	"burning": true,
	"armor": true,
	"shield": true,
	"rooted": true,
	"exposed": true,
	"lawless": true,
	"bomb_rat_plunder": true,
	"paralyzed": true,
	"slowed": true,
	"wet": true,
	"sluggish": true,
	"vulnerable": true,
	"weak": true,
	"light_exposed": true,
	"blinded": true,
	"counter_mark": true,
	"extra_attack": true,
	"extra_move": true,
}

const STATUS_CONFIG_FIELD_KEYS := {
	"default_stacks": true,
	"default_duration": true,
	"default_level": true,
	"damage_taken_mult": true,
	"attack_damage_mult": true,
	"min_move_points": true,
	"firelike_stack_mult": true,
}

const GEM_EFFECT_LEVEL_SLOT_KEYS := [
	Constants.SLOT_RED,
	Constants.SLOT_BLUE,
	Constants.SLOT_BLACK,
]

const GEM_EFFECT_LEVEL_VALUE_TYPES := {
	"blast_pattern": "string",
	"damage_multiplier": "number",
	"fog_pattern": "string",
	"duration_bonus": "number",
	"hit_poison_stacks": "number",
	"hit_poison_duration": "number",
	"spread_count": "number",
	"burning_bonus_spread_count": "number",
	"pull_steps": "number",
	"range_bonus": "number",
	"bounce_hops": "number",
	"range": "number",
	"damage_ratio": "number",
	"light_direction_offsets": "int_array",
	"exposed_stacks": "number",
	"pierce_blockers": "bool",
	"beam_power": "number",
	"beam_width": "number",
	"hit_slowed_stacks": "number",
	"freeze_if_target_slowed": "bool",
	"mark_stacks": "number",
	"followup_ratio": "number",
	"turn_end_spread": "bool",
	"copy_debuff_on_contact": "bool",
	"copy_debuff_on_damaged": "bool",
	"contact_poison_stacks": "number",
	"contact_poison_duration": "number",
	"turn_end_poison_stacks": "number",
	"turn_end_poison_duration": "number",
	"pillar_radius": "number",
	"pillar_poison_stacks": "number",
	"pillar_poison_duration": "number",
	"detonate_on_any_damage": "bool",
	"detonate_on_burning": "bool",
	"pillar_damage": "number",
	"deflect_chance": "number",
	"redirect_enemy_only": "bool",
	"slow_on_damaged": "bool",
	"root_on_damaged": "bool",
	"pillar_pull_radius": "number",
	"pillar_pull_steps": "number",
	"rebound_chance": "number",
	"spawn_temp_clone": "bool",
	"even_redirect_distribution": "bool",
	"reflect_beams": "number",
	"reflect_damage_ratio": "number",
	"reflect_exposed_stacks": "number",
	"reflect_power": "number",
	"reflect_impact_size": "number",
	"use_ranged_counter": "bool",
	"grant_extra_move_on_kill": "bool",
	"create_fire_on_contact": "bool",
	"double_burning_on_already_burning": "bool",
	"contact_burning_stacks": "number",
	"contact_slowed_stacks": "number",
	"upgrade_slowed_to_sluggish": "bool",
	"first_tag_strength": "number",
	"chain_followup": "bool",
	"spawn_fog": "bool",
	"fog_radius": "number",
	"debuff_copies": "number",
	"debuff_spread_radius": "number",
	"apply_slow": "bool",
	"apply_root": "bool",
	"strike_count": "number",
	"strike_all_targets": "bool",
	"prefer_occupied_cells": "bool",
	"death_fire_count_bonus": "number",
	"death_duration_bonus": "number",
	"apply_slowed": "bool",
	"apply_paralyzed": "bool",
	"stat_ratio": "number",
	"impact_size": "number",
	"blind_on_survive": "bool",
	"first_tag_repeat_count": "number",
}

const NUMERIC_REF_KINDS := [
	"flat",
	"ratio",
	"multiplier",
	"legacy",
]

const RELIC_ACTION_AMOUNT_UNITS := {
	"add_shield": "shield",
	"add_armor": "shield",
	"heal": "hp",
	"add_move": "move_points",
	"add_temp_move": "move_points",
}

const RELIC_ACTION_RATIO_UNITS := {
	"apply_max_hp_reduction": "max_hp",
}

const RELIC_MODIFIER_VALUE_UNITS := {
	"split_red_damage_ratio": {"kind": "ratio", "unit": "damage"},
	"split_blue_redirect_ratio": {"kind": "ratio", "unit": "damage"},
	"split_black_stat_ratio": {"kind": "ratio", "unit": "stats"},
	"overlay_move_cost_reduction": {"kind": "flat", "unit": "move_cost"},
	"arc_bounce_count_bonus": {"kind": "flat", "unit": "target_count"},
	"collision_damage_mult": {"kind": "multiplier", "unit": "damage"},
	"armor_lock_break_bonus": {"kind": "flat", "unit": "damage"},
	"move_bonus": {"kind": "flat", "unit": "move_points"},
	"extract_range_bonus": {"kind": "flat", "unit": "range"},
	"insert_range_bonus": {"kind": "flat", "unit": "range"},
	"arc_damage_mult": {"kind": "multiplier", "unit": "damage"},
	"attack_miss_chance": {"kind": "ratio", "unit": "chance"},
	"attack_damage_bonus": {"kind": "flat", "unit": "damage"},
	"first_damage_cap": {"kind": "flat", "unit": "damage"},
}

const RELIC_WEIGHT_RULE_TYPES := [
	"has_gem",
	"has_gem_color",
	"has_relic",
	"slot_count_gte",
	"empty_slot_count_gte",
]

const RELIC_WEIGHT_RULE_VALUE_TYPES := {
	"slot_count_gte": {"kind": "flat", "unit": "slot_count"},
	"empty_slot_count_gte": {"kind": "flat", "unit": "slot_count"},
}

const RELIC_TEXT_TOKEN_TYPES := {
	"relic_numeric_ref": true,
	"relic_numeric_signed": true,
	"relic_numeric_percent": true,
}


static func ensure_valid(file_path: String, errors: Array[String]) -> void:
	if errors.is_empty():
		return
	var message := "Balance config invalid: %s\n- %s" % [file_path, "\n- ".join(errors)]
	push_error(message)
	if OS.is_debug_build():
		assert(false, message)


static func validate_relic_source_weights(config: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for source in config.keys():
		var weights: Variant = config[source]
		if not weights is Dictionary:
			errors.append("relic_source_weights.%s should be object" % source)
			continue
		for rarity in (weights as Dictionary).keys():
			if not _is_number(weights[rarity]):
				errors.append("relic_source_weights.%s.%s should be number" % [source, rarity])
	return errors


static func validate_relic_numeric_refs(config: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for ref_id in config.keys():
		errors.append_array(_validate_numeric_ref_def("relic_numeric_refs.%s" % str(ref_id), config[ref_id]))
	return errors


static func validate_relic_defs(defs: Dictionary, numeric_refs: Dictionary = {}) -> Array[String]:
	var errors: Array[String] = []
	for relic_id in defs.keys():
		var raw_def: Variant = defs[relic_id]
		if not raw_def is Dictionary:
			errors.append("relic_defs.%s should be object" % relic_id)
			continue
		var relic_def := raw_def as Dictionary
		if relic_def.has("desc"):
			if not relic_def["desc"] is String:
				errors.append("relic_defs.%s.desc should be string" % relic_id)
			else:
				errors.append_array(_validate_relic_text_tokens("relic_defs.%s.desc" % relic_id, str(relic_def["desc"]), numeric_refs))
		var weight_rules: Variant = relic_def.get("weight_rules", [])
		if not weight_rules is Array:
			errors.append("relic_defs.%s.weight_rules should be array" % relic_id)
		else:
			for i in range((weight_rules as Array).size()):
				var raw_rule: Variant = (weight_rules as Array)[i]
				if not raw_rule is Dictionary:
					errors.append("relic_defs.%s.weight_rules[%d] should be object" % [relic_id, i])
					continue
				errors.append_array(_validate_relic_weight_rule("relic_defs.%s.weight_rules[%d]" % [relic_id, i], raw_rule as Dictionary, numeric_refs))
		var effects: Variant = relic_def.get("effects", [])
		if not effects is Array:
			errors.append("relic_defs.%s.effects should be array" % relic_id)
			continue
		for i in range((effects as Array).size()):
			var raw_effect: Variant = (effects as Array)[i]
			if not raw_effect is Dictionary:
				errors.append("relic_defs.%s.effects[%d] should be object" % [relic_id, i])
				continue
			var effect := raw_effect as Dictionary
			var action := str(effect.get("action", ""))
			if RELIC_ACTION_AMOUNT_UNITS.has(action):
				errors.append_array(_validate_relic_numeric_field("relic_defs.%s.effects[%d]" % [relic_id, i], effect, "amount", numeric_refs, "flat", str(RELIC_ACTION_AMOUNT_UNITS[action]), true))
			if RELIC_ACTION_RATIO_UNITS.has(action):
				errors.append_array(_validate_relic_numeric_field("relic_defs.%s.effects[%d]" % [relic_id, i], effect, "ratio", numeric_refs, "ratio", str(RELIC_ACTION_RATIO_UNITS[action]), true))
			var modifier := str(effect.get("modifier", ""))
			if RELIC_MODIFIER_VALUE_UNITS.has(modifier):
				if not effect.has("per_empty_slot") and not effect.has("per_empty_slot_ref") and not effect.has("empty_slot_mult") and not effect.has("empty_slot_mult_ref"):
					var expected: Dictionary = RELIC_MODIFIER_VALUE_UNITS[modifier]
					errors.append_array(_validate_relic_numeric_field("relic_defs.%s.effects[%d]" % [relic_id, i], effect, "value", numeric_refs, str(expected.get("kind", "")), str(expected.get("unit", "")), true))
			if effect.has("per_empty_slot") or effect.has("per_empty_slot_ref"):
				errors.append_array(_validate_relic_numeric_field("relic_defs.%s.effects[%d]" % [relic_id, i], effect, "per_empty_slot", numeric_refs, "flat", "range", true))
			if effect.has("empty_slot_mult") or effect.has("empty_slot_mult_ref"):
				errors.append_array(_validate_relic_numeric_field("relic_defs.%s.effects[%d]" % [relic_id, i], effect, "empty_slot_mult", numeric_refs, "multiplier", "empty_slot", true))
			if effect.has("rng_chance") or effect.has("rng_chance_ref"):
				errors.append_array(_validate_relic_numeric_field("relic_defs.%s.effects[%d]" % [relic_id, i], effect, "rng_chance", numeric_refs, "ratio", "chance", true))
	return errors


static func validate_enemy_slot_curves(config: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for room_type in ROOM_TYPE_KEYS:
		if not config.has(room_type):
			errors.append("enemy_slot_curves.%s missing" % room_type)
	for room_type in config.keys():
		var curve: Variant = config[room_type]
		if not curve is Dictionary:
			errors.append("enemy_slot_curves.%s should be object" % room_type)
			continue
		var curve_dict := curve as Dictionary
		if not curve_dict.has("default"):
			errors.append("enemy_slot_curves.%s.default missing" % room_type)
		for chapter_key in curve_dict.keys():
			var weights: Variant = curve_dict[chapter_key]
			if not weights is Array:
				errors.append("enemy_slot_curves.%s.%s should be array" % [room_type, chapter_key])
				continue
			if (weights as Array).size() != 4:
				errors.append("enemy_slot_curves.%s.%s should have 4 weights" % [room_type, chapter_key])
				continue
			for i in range((weights as Array).size()):
				if not _is_number((weights as Array)[i]):
					errors.append("enemy_slot_curves.%s.%s[%d] should be number" % [room_type, chapter_key, i])
	return errors


static func validate_ai_profiles(config: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var default_profile := str(config.get("default_profile", ""))
	if default_profile.is_empty():
		errors.append("ai_profiles.default_profile missing")
	var tuning: Variant = config.get("tuning", {})
	if not tuning is Dictionary:
		errors.append("ai_profiles.tuning should be object")
	else:
		for key in (tuning as Dictionary).keys():
			if AI_TUNING_NUMERIC_KEYS.has(str(key)) and not _is_number((tuning as Dictionary)[key]):
				errors.append("ai_profiles.tuning.%s should be number" % str(key))
	var profiles: Variant = config.get("profiles", {})
	if not profiles is Dictionary:
		errors.append("ai_profiles.profiles should be object")
		return errors
	if not default_profile.is_empty() and not (profiles as Dictionary).has(default_profile):
		errors.append("ai_profiles.default_profile references missing profile: %s" % default_profile)
	for profile_id in (profiles as Dictionary).keys():
		if not (profiles as Dictionary)[profile_id] is Dictionary:
			errors.append("ai_profiles.profiles.%s should be object" % profile_id)
			continue
		var profile := (profiles as Dictionary)[profile_id] as Dictionary
		for key in profile.keys():
			var key_id := str(key)
			if AI_PROFILE_NUMERIC_KEYS.has(key_id) and not _is_number(profile[key]):
				errors.append("ai_profiles.profiles.%s.%s should be number" % [profile_id, key_id])
			elif AI_PROFILE_BOOL_KEYS.has(key_id) and not profile[key] is bool:
				errors.append("ai_profiles.profiles.%s.%s should be bool" % [profile_id, key_id])
	var aliases: Variant = config.get("aliases", {})
	if not aliases is Dictionary:
		errors.append("ai_profiles.aliases should be object")
	else:
		for alias_id in (aliases as Dictionary).keys():
			var target := str((aliases as Dictionary).get(alias_id, ""))
			if target.is_empty():
				errors.append("ai_profiles.aliases.%s should not be empty" % alias_id)
			elif not (profiles as Dictionary).has(target):
				errors.append("ai_profiles.aliases.%s references missing profile: %s" % [alias_id, target])
	return errors


static func validate_unit_balance_defs(defs: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for unit_id in defs.keys():
		var raw_def: Variant = defs[unit_id]
		if not raw_def is Dictionary:
			errors.append("unit_defs.%s should be object" % unit_id)
			continue
		var unit_def := raw_def as Dictionary
		if not unit_def.has("balance"):
			continue
		var balance: Variant = unit_def.get("balance", {})
		if not balance is Dictionary:
			errors.append("unit_defs.%s.balance should be object" % unit_id)
			continue
		for key in (balance as Dictionary).keys():
			if UNIT_BALANCE_NUMERIC_KEYS.has(str(key)) and not _is_number((balance as Dictionary)[key]):
				errors.append("unit_defs.%s.balance.%s should be number" % [unit_id, key])
	return errors


static func validate_combat_config(config: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for key in COMBAT_CONFIG_NUMERIC_KEYS.keys():
		if not config.has(key):
			errors.append("combat_config.%s missing" % key)
			continue
		if not _is_number(config[key]):
			errors.append("combat_config.%s should be number" % key)
	return errors


static func validate_gem_effect_levels(config: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for slot_type in GEM_EFFECT_LEVEL_SLOT_KEYS:
		if not config.has(slot_type):
			errors.append("gem_effect_levels.%s missing" % slot_type)
	for slot_type in config.keys():
		var slot_defs: Variant = config[slot_type]
		if not slot_defs is Dictionary:
			errors.append("gem_effect_levels.%s should be object" % slot_type)
			continue
		for tag in (slot_defs as Dictionary).keys():
			var tag_defs: Variant = (slot_defs as Dictionary)[tag]
			if not tag_defs is Dictionary:
				errors.append("gem_effect_levels.%s.%s should be object" % [slot_type, tag])
				continue
			for level_key in (tag_defs as Dictionary).keys():
				var level_id := str(level_key)
				if not level_id.is_valid_int() or int(level_id) < 1:
					errors.append("gem_effect_levels.%s.%s.%s should use positive integer level keys" % [slot_type, tag, level_id])
					continue
				var entry: Variant = (tag_defs as Dictionary)[level_key]
				if not entry is Dictionary:
					errors.append("gem_effect_levels.%s.%s.%s should be object" % [slot_type, tag, level_id])
					continue
				for field_key in (entry as Dictionary).keys():
					var field_id := str(field_key)
					if not GEM_EFFECT_LEVEL_VALUE_TYPES.has(field_id):
						errors.append("gem_effect_levels.%s.%s.%s.%s is unknown" % [slot_type, tag, level_id, field_id])
						continue
					var expected_type := str(GEM_EFFECT_LEVEL_VALUE_TYPES[field_id])
					if not _matches_gem_effect_level_type((entry as Dictionary)[field_key], expected_type):
						errors.append("gem_effect_levels.%s.%s.%s.%s should be %s" % [slot_type, tag, level_id, field_id, expected_type])
	return errors


static func validate_status_config(config: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for entry_id in config.keys():
		if not STATUS_CONFIG_ENTRY_KEYS.has(str(entry_id)):
			errors.append("status_config.%s is unknown" % str(entry_id))
			continue
		var entry: Variant = config[entry_id]
		if not entry is Dictionary:
			errors.append("status_config.%s should be object" % str(entry_id))
			continue
		for field_id in (entry as Dictionary).keys():
			var key_id := str(field_id)
			if not STATUS_CONFIG_FIELD_KEYS.has(key_id):
				errors.append("status_config.%s.%s is unknown" % [str(entry_id), key_id])
				continue
			if not _is_number((entry as Dictionary)[field_id]):
				errors.append("status_config.%s.%s should be number" % [str(entry_id), key_id])
	return errors


static func _validate_relic_weight_rule(prefix: String, rule: Dictionary, numeric_refs: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var rule_type := str(rule.get("type", ""))
	if rule_type.is_empty():
		errors.append("%s.type missing" % prefix)
	elif rule_type not in RELIC_WEIGHT_RULE_TYPES:
		errors.append("%s.type unknown: %s" % [prefix, rule_type])
	match rule_type:
		"has_gem", "has_gem_color", "has_relic":
			if not rule.has("value"):
				errors.append("%s.value missing" % prefix)
			elif not rule["value"] is String:
				errors.append("%s.value should be string" % prefix)
		"slot_count_gte", "empty_slot_count_gte":
			var expected: Dictionary = RELIC_WEIGHT_RULE_VALUE_TYPES.get(rule_type, {})
			errors.append_array(_validate_relic_numeric_field(prefix, rule, "value", numeric_refs, str(expected.get("kind", "")), str(expected.get("unit", "")), true))
	errors.append_array(_validate_relic_numeric_field(prefix, rule, "multiplier", numeric_refs, "multiplier", "selection_weight", true))
	return errors


static func _validate_relic_text_tokens(prefix: String, text: String, numeric_refs: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if NumericTextResolver.has_literal_number_outside_tokens(text):
		errors.append("%s should use relic numeric text tokens instead of literal numbers" % prefix)
	for token in NumericTextResolver.extract_tokens(text):
		var token_type := str(token.get("type", ""))
		var token_value := str(token.get("value", ""))
		if not RELIC_TEXT_TOKEN_TYPES.has(token_type):
			errors.append("%s unknown text token type: %s" % [prefix, token_type])
			continue
		if token_value.is_empty():
			errors.append("%s empty text token value" % prefix)
		elif not numeric_refs.is_empty() and not numeric_refs.has(token_value):
			errors.append("%s unknown relic numeric token: %s" % [prefix, token_value])
	return errors


static func _validate_relic_numeric_field(
	prefix: String,
	effect: Dictionary,
	field_id: String,
	numeric_refs: Dictionary,
	expected_kind: String,
	expected_unit: String,
	required: bool = false
) -> Array[String]:
	var errors: Array[String] = []
	var ref_field_id := "%s_ref" % field_id
	var has_field := effect.has(field_id)
	var has_ref := effect.has(ref_field_id)
	if required and not has_field and not has_ref:
		errors.append("%s.%s or %s missing" % [prefix, field_id, ref_field_id])
	if has_field and not _is_number(effect[field_id]):
		errors.append("%s.%s should be number" % [prefix, field_id])
	elif has_field and not numeric_refs.is_empty():
		errors.append("%s.%s should use %s in authored config" % [prefix, field_id, ref_field_id])
	if has_ref and not effect[ref_field_id] is String:
		errors.append("%s.%s should be string" % [prefix, ref_field_id])
		return errors
	var ref_id := str(effect.get(ref_field_id, ""))
	if has_ref and ref_id.is_empty():
		errors.append("%s.%s should not be empty" % [prefix, ref_field_id])
	if ref_id.is_empty() or numeric_refs.is_empty():
		return errors
	if not numeric_refs.has(ref_id):
		errors.append("%s.%s unknown: %s" % [prefix, ref_field_id, ref_id])
		return errors
	var ref_def := _numeric_ref_def(numeric_refs.get(ref_id))
	var kind := str(ref_def.get("kind", "legacy"))
	if kind == "legacy":
		return errors
	var unit := str(ref_def.get("unit", ""))
	if kind != expected_kind:
		errors.append("%s.%s kind mismatch: %s expected %s got %s" % [prefix, ref_field_id, ref_id, expected_kind, kind])
	if not expected_unit.is_empty() and unit != expected_unit:
		errors.append("%s.%s unit mismatch: %s expected %s got %s" % [prefix, ref_field_id, ref_id, expected_unit, unit])
	return errors


static func _validate_numeric_ref_def(prefix: String, raw_ref: Variant) -> Array[String]:
	var errors: Array[String] = []
	if _is_number(raw_ref):
		return errors
	if not raw_ref is Dictionary:
		errors.append("%s should be number or object" % prefix)
		return errors
	var ref_def := raw_ref as Dictionary
	if not ref_def.has("value"):
		errors.append("%s.value missing" % prefix)
	elif not _is_number(ref_def["value"]):
		errors.append("%s.value should be number" % prefix)
	var kind := str(ref_def.get("kind", ""))
	if kind.is_empty():
		errors.append("%s.kind missing" % prefix)
	elif kind not in NUMERIC_REF_KINDS:
		errors.append("%s.kind unknown: %s" % [prefix, kind])
	var unit := str(ref_def.get("unit", ""))
	if unit.is_empty():
		errors.append("%s.unit missing" % prefix)
	return errors


static func _numeric_ref_def(raw_ref: Variant) -> Dictionary:
	if raw_ref is Dictionary:
		return raw_ref as Dictionary
	return {
		"value": raw_ref,
		"kind": "legacy",
		"unit": "",
	}


static func _matches_gem_effect_level_type(value: Variant, expected_type: String) -> bool:
	match expected_type:
		"number":
			return _is_number(value)
		"bool":
			return value is bool
		"string":
			return value is String
		"int_array":
			if not value is Array:
				return false
			for item in value:
				if not _is_number(item) or int(item) != float(item):
					return false
			return true
	return false


static func _is_number(value: Variant) -> bool:
	return value is int or value is float
