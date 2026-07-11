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
	"trample_collision_damage": true,
}

const GEM_DEF_FIELDS := {
	"display_name_key": true,
	"symbol_key": true,
	"symbol": true,
	"color": true,
	"tag": true,
	"element": true,
	"pool_tier": true,
	"max_stack_level": true,
	"combos": true,
	"rarity": true,
	"allow_random_pool": true,
	"ability_profiles": true,
}

const GEM_DEF_REQUIRED_FIELDS := [
	"display_name_key",
	"symbol_key",
	"symbol",
	"color",
	"tag",
	"element",
	"pool_tier",
	"max_stack_level",
	"combos",
	"rarity",
	"ability_profiles",
]

const GEM_ABILITY_PROFILE_KEYS := [
	"player_skill",
	"unit_red_active",
	"enemy_red_action",
	"blue_turn_start",
	"blue_damaged",
	"blue_move_through",
	"black_death",
	"tile_active",
	"tile_turn_start",
	"attack_bonus",
	"armor_bonus",
]

const GEM_RARITIES := [
	"common",
	"uncommon",
	"rare",
	"epic",
	"legendary",
	"boss",
]

const UNIT_DEF_FIELDS := {
	"display_name_key": true,
	"max_hp": true,
	"hp_roll_max": true,
	"move_points": true,
	"speed": true,
	"base_attack": true,
	"armor": true,
	"ai_profile_id": true,
	"behavior_id": true,
	"spawn_gem_slots": true,
	"balance": true,
	"footprint_size": true,
	"tags": true,
	"slots": true,
}

const UNIT_DEF_REQUIRED_FIELDS := [
	"display_name_key",
	"max_hp",
	"move_points",
	"speed",
	"base_attack",
	"armor",
	"ai_profile_id",
	"tags",
	"slots",
]

const UNIT_BALANCE_REQUIRED_BY_BEHAVIOR := {
	"patrol_guard": [
		"rampage_move_bonus",
		"charge_bonus",
		"charge_min_steps",
	],
	"stone_bow_guard": [
		"attack_range",
		"deploy_range_bonus",
		"faulty_miss_chance",
		"faulty_damage_bonus",
		"kite_ideal_range",
		"kite_min_range",
		"ranged_damage_score_mult",
		"kill_bonus",
		"move_step_cost",
		"ideal_range_penalty",
		"too_close_extra_penalty",
		"max_range_bonus",
		"hold_position_bonus",
		"deploy_hold_bonus",
		"move_when_shooting_penalty",
		"closer_when_shooting_penalty",
		"emergency_retreat_bonus_per_tile",
		"extra_distance_penalty_per_tile",
		"closer_to_gain_shot_bonus_per_tile",
		"setup_deploy_bonus",
		"approach_progress_score",
		"approach_distance_cost",
		"approach_too_close_penalty",
		"approach_ideal_band_bonus",
		"retreat_bonus_per_tile",
		"retreat_ideal_range_penalty",
		"retreat_too_close_penalty",
		"line_unreachable_penalty",
		"line_setup_bonus",
		"line_setup_distance_cost",
		"line_progress_bonus_per_step",
		"line_no_progress_penalty",
		"wait_score",
	],
	"fission_slime": [
		"split_stat_ratio",
		"slam_push_steps",
		"trample_damage",
		"trample_collision_damage",
	],
}

const COMBAT_CONFIG_NUMERIC_KEYS := {
	"attack_range": true,
	"extract_range": true,
	"insert_range": true,
	"trigger_range": true,
	"split_attack_range": true,
	"explosion_damage": true,
	"explosion_radius": true,
	"explosion_cross_damage": true,
	"explosion_death_radius": true,
	"charge_explode_dash_range": true,
	"knockback_collision_damage": true,
	"star_relocation_max_distance": true,
	"star_relocation_squeeze_damage_per_tile": true,
	"spike_damage": true,
	"spike_collision_damage": true,
	"barrel_hp": true,
	"barrel_explosion_damage": true,
	"barrel_explosion_radius": true,
	"gravity_collision_damage": true,
	"enemy_gravity_pull_range": true,
	"poison_fog_damage": true,
	"poison_fog_duration": true,
	"toxic_smoke_duration": true,
	"poison_puddle_duration": true,
	"water_move_cost_extra": true,
	"arc_proc_chance": true,
	"arc_paralysis_chance": true,
	"arc_chain_damage_ratio": true,
	"arc_chain_range": true,
	"lightning_death_damage": true,
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
	"disarmed": true,
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
	"damage_taken_mult": true,
	"attack_damage_mult": true,
	"min_move_points": true,
	"firelike_stack_mult": true,
	"attack_bonus": true,
}

const GEM_EFFECT_LEVEL_SLOT_KEYS := [
	Constants.SLOT_RED,
	Constants.SLOT_BLUE,
	Constants.SLOT_BLACK,
]

const GEM_EFFECT_LEVEL_TAG_KEYS := [
	"explosion",
	"poison",
	"fire",
	"gravity",
	"arc",
	"split",
	"light",
	"ice",
	"counter",
	"echo",
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
	"slowed_min_move_points": "number",
	"freeze_if_target_slowed": "bool",
	"mark_duration": "number",
	"retaliation_with_tags": "bool",
	"grant_extra_attack_on_kill": "bool",
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
	"turn_start_damage": "number",
	"deflect_chance": "number",
	"redirect_enemy_only": "bool",
	"slow_on_damaged": "bool",
	"root_on_damaged": "bool",
	"pillar_pull_radius": "number",
	"pillar_pull_steps": "number",
	"rebound_chance": "number",
	"redirect_mode": "string",
	"redirect_ratio": "number",
	"redirect_radius": "number",
	"temp_clone_count": "number",
	"temp_clone_hp": "number",
	"temp_clone_stat_ratio": "number",
	"temp_clone_duration": "number",
	"temp_clone_per_turn_limit": "number",
	"clone_count": "number",
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
	"echo_tag_count": "number",
	"chain_followup": "bool",
	"spawn_fog": "bool",
	"fog_radius": "number",
	"debuff_copies": "number",
	"debuff_spread_radius": "number",
	"apply_slow": "bool",
	"apply_root": "bool",
	"strike_count": "number",
	"strike_radius": "number",
	"strike_all_targets": "bool",
	"prefer_occupied_cells": "bool",
	"death_fire_radius": "number",
	"death_fire_count": "number",
	"death_fire_duration": "number",
	"death_radius": "number",
	"slowed_stacks": "number",
	"freeze_duration": "number",
	"stat_ratio": "number",
	"impact_size": "number",
	"blind_on_survive": "bool",
	"first_tag_repeat_count": "number",
	"vulnerable_duration": "number",
	"disarm_stacks": "number",
}

const GEM_EFFECT_LEVEL_FIELDS := {
	"red:explosion": ["blast_pattern", "damage_multiplier"],
	"red:poison": ["fog_pattern", "duration_bonus", "hit_poison_stacks", "hit_poison_duration"],
	"red:fire": ["spread_count", "burning_bonus_spread_count"],
	"red:gravity": ["pull_steps", "range_bonus"],
	"red:arc": ["bounce_hops", "range"],
	"red:split": ["damage_ratio", "light_direction_offsets"],
	"red:light": ["damage_ratio", "exposed_stacks", "pierce_blockers", "beam_power", "beam_width"],
	"red:ice": ["hit_slowed_stacks", "slowed_min_move_points", "freeze_if_target_slowed"],
	"red:counter": ["mark_duration", "retaliation_with_tags", "grant_extra_attack_on_kill"],
	"red:echo": ["echo_tag_count", "followup_ratio"],
	"blue:explosion": ["detonate_on_any_damage", "detonate_on_burning", "blast_pattern", "pillar_radius", "pillar_damage", "turn_start_damage"],
	"blue:poison": ["turn_end_spread", "copy_debuff_on_contact", "copy_debuff_on_damaged", "contact_poison_stacks", "contact_poison_duration", "turn_end_poison_stacks", "turn_end_poison_duration", "pillar_radius", "pillar_poison_stacks", "pillar_poison_duration"],
	"blue:fire": ["create_fire_on_contact", "double_burning_on_already_burning", "contact_burning_stacks"],
	"blue:gravity": ["deflect_chance", "redirect_enemy_only", "redirect_radius", "slow_on_damaged", "root_on_damaged", "pillar_pull_radius", "pillar_pull_steps"],
	"blue:arc": ["rebound_chance"],
	"blue:split": ["redirect_mode", "redirect_ratio", "redirect_radius", "temp_clone_count", "temp_clone_hp", "temp_clone_stat_ratio", "temp_clone_duration", "temp_clone_per_turn_limit"],
	"blue:light": ["reflect_beams", "reflect_damage_ratio", "reflect_exposed_stacks", "reflect_power", "reflect_impact_size"],
	"blue:ice": ["contact_slowed_stacks", "slowed_min_move_points", "upgrade_slowed_to_sluggish"],
	"blue:counter": ["use_ranged_counter", "grant_extra_move_on_kill"],
	"blue:echo": ["echo_tag_count", "first_tag_strength"],
	"black:explosion": ["chain_followup", "damage_multiplier"],
	"black:poison": ["spawn_fog", "fog_radius", "debuff_copies", "debuff_spread_radius"],
	"black:fire": ["prefer_occupied_cells", "death_fire_radius", "death_fire_count", "death_fire_duration"],
	"black:gravity": ["pull_steps", "apply_slow", "apply_root"],
	"black:arc": ["strike_radius", "strike_count", "strike_all_targets"],
	"black:split": ["clone_count", "stat_ratio"],
	"black:light": ["beam_width", "beam_power", "impact_size", "blind_on_survive"],
	"black:ice": ["death_radius", "slowed_stacks", "slowed_min_move_points", "freeze_duration"],
	"black:counter": ["damage_multiplier", "vulnerable_duration", "disarm_stacks"],
	"black:echo": ["echo_tag_count", "first_tag_repeat_count"],
}

const GEM_EFFECT_LEVEL_OPTIONAL_FIELDS := {
	"black:arc": ["strike_count"],
}

const GEM_EFFECT_LEVEL_KEYS := ["1", "2", "3"]

const GEM_EFFECT_LEVEL_ENUM_VALUES := {
	"blast_pattern": ["cross", "square"],
	"fog_pattern": ["single", "cross"],
	"redirect_mode": ["random_ratio", "equal_all"],
}

const GEM_EFFECT_LEVEL_INTEGER_NON_NEGATIVE_FIELDS := {
	"duration_bonus": true,
	"hit_poison_stacks": true,
	"hit_poison_duration": true,
	"spread_count": true,
	"burning_bonus_spread_count": true,
	"pull_steps": true,
	"range_bonus": true,
	"bounce_hops": true,
	"range": true,
	"exposed_stacks": true,
	"hit_slowed_stacks": true,
	"slowed_min_move_points": true,
	"mark_duration": true,
	"redirect_radius": true,
	"temp_clone_count": true,
	"temp_clone_hp": true,
	"temp_clone_duration": true,
	"temp_clone_per_turn_limit": true,
	"clone_count": true,
	"contact_poison_stacks": true,
	"contact_poison_duration": true,
	"turn_end_poison_stacks": true,
	"turn_end_poison_duration": true,
	"pillar_radius": true,
	"pillar_poison_stacks": true,
	"pillar_poison_duration": true,
	"pillar_damage": true,
	"turn_start_damage": true,
	"pillar_pull_radius": true,
	"pillar_pull_steps": true,
	"reflect_beams": true,
	"reflect_exposed_stacks": true,
	"contact_burning_stacks": true,
	"contact_slowed_stacks": true,
	"first_tag_strength": true,
	"echo_tag_count": true,
	"fog_radius": true,
	"debuff_copies": true,
	"debuff_spread_radius": true,
	"strike_count": true,
	"strike_radius": true,
	"death_fire_radius": true,
	"death_fire_count": true,
	"death_fire_duration": true,
	"death_radius": true,
	"slowed_stacks": true,
	"freeze_duration": true,
	"first_tag_repeat_count": true,
	"vulnerable_duration": true,
	"disarm_stacks": true,
}

const GEM_EFFECT_LEVEL_UNIT_INTERVAL_FIELDS := {
	"deflect_chance": true,
	"rebound_chance": true,
	"damage_ratio": true,
	"reflect_damage_ratio": true,
	"stat_ratio": true,
	"followup_ratio": true,
	"redirect_ratio": true,
	"temp_clone_stat_ratio": true,
}

const GEM_EFFECT_LEVEL_POSITIVE_FIELDS := {
	"damage_multiplier": true,
	"redirect_ratio": true,
	"beam_power": true,
	"beam_width": true,
	"reflect_power": true,
	"reflect_impact_size": true,
	"impact_size": true,
}

const GEM_EFFECT_LEVEL_POSITIVE_INTEGER_FIELDS := {
	"echo_tag_count": true,
	"first_tag_strength": true,
	"first_tag_repeat_count": true,
	"strike_count": true,
	"death_fire_count": true,
	"death_fire_duration": true,
	"mark_duration": true,
	"redirect_radius": true,
	"clone_count": true,
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
	if config.is_empty():
		errors.append("relic_source_weights should not be empty")
		return errors
	for source in config.keys():
		var weights: Variant = config[source]
		if not weights is Dictionary or (weights as Dictionary).is_empty():
			errors.append("relic_source_weights.%s should be a non-empty object" % source)
			continue
		var total_weight := 0.0
		for rarity in (weights as Dictionary).keys():
			if str(rarity) not in ["common", "rare", "boss"]:
				errors.append("relic_source_weights.%s.%s is unknown" % [source, rarity])
			elif not _is_number(weights[rarity]):
				errors.append("relic_source_weights.%s.%s should be number" % [source, rarity])
			elif float(weights[rarity]) < 0.0:
				errors.append("relic_source_weights.%s.%s should be non-negative" % [source, rarity])
			else:
				total_weight += float(weights[rarity])
		if total_weight <= 0.0:
			errors.append("relic_source_weights.%s should have positive total weight" % source)
	return errors


static func validate_gem_pools(config: Dictionary, known_tags: Dictionary = {}) -> Array[String]:
	var errors: Array[String] = []
	if not config.has("global"):
		errors.append("gem_pools.global missing")
	if not config.has("teaching_boosts"):
		errors.append("gem_pools.teaching_boosts missing")
	for source_id in config.keys():
		if str(source_id) == "teaching_boosts":
			continue
		var prefix := "gem_pools.%s" % source_id
		var raw_pool: Variant = config[source_id]
		if not raw_pool is Dictionary:
			errors.append("%s should be object" % prefix)
			continue
		var pool := raw_pool as Dictionary
		for field_id in pool.keys():
			if str(field_id) not in ["source_tier", "rarity_weights", "tag_weights"]:
				errors.append("%s.%s is unknown" % [prefix, field_id])
		if not _is_positive_integer(pool.get("source_tier", null)):
			errors.append("%s.source_tier should be a positive integer" % prefix)
		var rarity_weights: Variant = pool.get("rarity_weights", null)
		if not rarity_weights is Dictionary or (rarity_weights as Dictionary).is_empty():
			errors.append("%s.rarity_weights should be a non-empty object" % prefix)
		else:
			errors.append_array(_validate_weight_map(
				"%s.rarity_weights" % prefix,
				rarity_weights as Dictionary,
				_key_dictionary(GEM_RARITIES)
			))
		var tag_weights: Variant = pool.get("tag_weights", {})
		if not tag_weights is Dictionary:
			errors.append("%s.tag_weights should be object" % prefix)
		elif not (tag_weights as Dictionary).is_empty():
			errors.append_array(_validate_weight_map(
				"%s.tag_weights" % prefix,
				tag_weights as Dictionary,
				known_tags
			))
	var teaching_boosts: Variant = config.get("teaching_boosts", null)
	if not teaching_boosts is Dictionary:
		errors.append("gem_pools.teaching_boosts should be object")
	else:
		for chapter_id in ["chapter_1", "chapter_2", "chapter_3"]:
			if not (teaching_boosts as Dictionary).has(chapter_id):
				errors.append("gem_pools.teaching_boosts.%s missing" % chapter_id)
		for chapter_id in (teaching_boosts as Dictionary).keys():
			if str(chapter_id) not in ["chapter_1", "chapter_2", "chapter_3"]:
				errors.append("gem_pools.teaching_boosts.%s is unknown" % chapter_id)
				continue
			var boosts: Variant = (teaching_boosts as Dictionary)[chapter_id]
			if not boosts is Dictionary or (boosts as Dictionary).is_empty():
				errors.append("gem_pools.teaching_boosts.%s should be a non-empty object" % chapter_id)
				continue
			for tag in (boosts as Dictionary).keys():
				var value: Variant = (boosts as Dictionary)[tag]
				if not known_tags.is_empty() and not known_tags.has(str(tag)):
					errors.append("gem_pools.teaching_boosts.%s.%s references unknown tag" % [chapter_id, tag])
				elif not _is_number(value) or float(value) <= 0.0:
					errors.append("gem_pools.teaching_boosts.%s.%s should be positive" % [chapter_id, tag])
	return errors


static func validate_relic_numeric_refs(config: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if config.is_empty():
		errors.append("relic_numeric_refs should not be empty")
		return errors
	for ref_id in config.keys():
		errors.append_array(_validate_numeric_ref_def("relic_numeric_refs.%s" % str(ref_id), config[ref_id]))
	return errors


static func validate_relic_defs(defs: Dictionary, numeric_refs: Dictionary = {}) -> Array[String]:
	var errors: Array[String] = []
	if defs.is_empty():
		errors.append("relic_defs should not be empty")
		return errors
	for relic_id in defs.keys():
		var prefix := "relic_defs.%s" % relic_id
		var raw_def: Variant = defs[relic_id]
		if not raw_def is Dictionary:
			errors.append("%s should be object" % prefix)
			continue
		var relic_def := raw_def as Dictionary
		var allowed_fields := ["name", "desc", "rarity", "pool_types", "base_weight", "unique", "effects", "weight_rules", "unlock_condition", "placeholder"]
		var required_fields := ["name", "desc", "rarity", "pool_types", "base_weight", "unique", "effects"]
		for field_id in relic_def.keys():
			if str(field_id) not in allowed_fields:
				errors.append("%s.%s is unknown" % [prefix, field_id])
		for field_id in required_fields:
			if not relic_def.has(field_id):
				errors.append("%s.%s missing" % [prefix, field_id])
		for field_id in ["name", "desc"]:
			if relic_def.has(field_id) and (not relic_def[field_id] is String or str(relic_def[field_id]).is_empty()):
				errors.append("%s.%s should be a non-empty string" % [prefix, field_id])
		var rarity := str(relic_def.get("rarity", ""))
		if rarity not in ["common", "rare", "boss"]:
			errors.append("%s.rarity is unknown: %s" % [prefix, rarity])
		var pool_types: Variant = relic_def.get("pool_types", null)
		if not pool_types is Array:
			errors.append("%s.pool_types should be array" % prefix)
		elif (pool_types as Array).is_empty() and not bool(relic_def.get("placeholder", false)):
			errors.append("%s.pool_types should be non-empty for selectable relics" % prefix)
		else:
			for pool_type in pool_types as Array:
				if str(pool_type) not in ["global", "shop_only", "boss_drop"]:
					errors.append("%s.pool_types contains unknown value: %s" % [prefix, pool_type])
		var base_weight: Variant = relic_def.get("base_weight", null)
		if not _is_number(base_weight) or float(base_weight) < 0.0:
			errors.append("%s.base_weight should be non-negative number" % prefix)
		if not relic_def.get("unique", null) is bool:
			errors.append("%s.unique should be bool" % prefix)
		if relic_def.has("placeholder") and not relic_def["placeholder"] is bool:
			errors.append("%s.placeholder should be bool" % prefix)
		if relic_def.has("desc"):
			if not relic_def["desc"] is String:
				errors.append("%s.desc should be string" % prefix)
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
		if str(room_type) not in ROOM_TYPE_KEYS:
			errors.append("enemy_slot_curves.%s is unknown" % room_type)
			continue
		var curve: Variant = config[room_type]
		if not curve is Dictionary:
			errors.append("enemy_slot_curves.%s should be object" % room_type)
			continue
		var curve_dict := curve as Dictionary
		if not curve_dict.has("default"):
			errors.append("enemy_slot_curves.%s.default missing" % room_type)
		for chapter_key in curve_dict.keys():
			if str(chapter_key) != "default" and (not str(chapter_key).is_valid_int() or int(chapter_key) <= 0):
				errors.append("enemy_slot_curves.%s.%s should be a positive chapter or default" % [room_type, chapter_key])
				continue
			var weights: Variant = curve_dict[chapter_key]
			if not weights is Array:
				errors.append("enemy_slot_curves.%s.%s should be array" % [room_type, chapter_key])
				continue
			if (weights as Array).size() != 4:
				errors.append("enemy_slot_curves.%s.%s should have 4 weights" % [room_type, chapter_key])
				continue
			var total_weight := 0.0
			for i in range((weights as Array).size()):
				if not _is_number((weights as Array)[i]):
					errors.append("enemy_slot_curves.%s.%s[%d] should be number" % [room_type, chapter_key, i])
				elif float((weights as Array)[i]) < 0.0:
					errors.append("enemy_slot_curves.%s.%s[%d] should be non-negative" % [room_type, chapter_key, i])
				else:
					total_weight += float((weights as Array)[i])
			if total_weight <= 0.0:
				errors.append("enemy_slot_curves.%s.%s should have positive total weight" % [room_type, chapter_key])
	return errors


static func validate_ai_profiles(config: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var top_level_fields := ["default_profile", "profile_defaults", "path_defaults", "aliases", "tuning", "profiles"]
	for field_id in config.keys():
		if str(field_id) not in top_level_fields:
			errors.append("ai_profiles.%s is unknown" % field_id)
	for field_id in top_level_fields:
		if not config.has(field_id):
			errors.append("ai_profiles.%s missing" % field_id)
	var default_profile := str(config.get("default_profile", ""))
	if default_profile.is_empty():
		errors.append("ai_profiles.default_profile should be a non-empty string")
	var defaults: Variant = config.get("profile_defaults", {})
	if not defaults is Dictionary:
		errors.append("ai_profiles.profile_defaults should be object")
	else:
		errors.append_array(_validate_ai_profile_fields(
			"ai_profiles.profile_defaults",
			defaults as Dictionary,
			true
		))
	var path_defaults: Variant = config.get("path_defaults", {})
	if not path_defaults is Dictionary:
		errors.append("ai_profiles.path_defaults should be object")
	else:
		var required_path_fields := ["base_step_cost", "spike_damage_weight", "water_cost_bias", "allow_partial_path"]
		for key in (path_defaults as Dictionary).keys():
			if str(key) not in required_path_fields:
				errors.append("ai_profiles.path_defaults.%s is unknown" % key)
		for key in required_path_fields:
			if not (path_defaults as Dictionary).has(key):
				errors.append("ai_profiles.path_defaults.%s missing" % key)
			elif str(key) == "allow_partial_path":
				if not (path_defaults as Dictionary)[key] is bool:
					errors.append("ai_profiles.path_defaults.%s should be bool" % key)
			elif not _is_number((path_defaults as Dictionary)[key]):
				errors.append("ai_profiles.path_defaults.%s should be number" % key)
		if _is_number((path_defaults as Dictionary).get("base_step_cost", null)) and float((path_defaults as Dictionary)["base_step_cost"]) <= 0.0:
			errors.append("ai_profiles.path_defaults.base_step_cost should be positive")
		for key in ["spike_damage_weight", "water_cost_bias"]:
			if _is_number((path_defaults as Dictionary).get(key, null)) and float((path_defaults as Dictionary)[key]) < 0.0:
				errors.append("ai_profiles.path_defaults.%s should be non-negative" % key)
	var tuning: Variant = config.get("tuning", {})
	if not tuning is Dictionary:
		errors.append("ai_profiles.tuning should be object")
	else:
		for key in (tuning as Dictionary).keys():
			if not AI_TUNING_NUMERIC_KEYS.has(str(key)):
				errors.append("ai_profiles.tuning.%s is unknown" % key)
			elif not _is_number((tuning as Dictionary)[key]):
				errors.append("ai_profiles.tuning.%s should be number" % key)
		for key in AI_TUNING_NUMERIC_KEYS.keys():
			if not (tuning as Dictionary).has(key):
				errors.append("ai_profiles.tuning.%s missing" % key)
	var profiles: Variant = config.get("profiles", {})
	if not profiles is Dictionary or (profiles as Dictionary).is_empty():
		errors.append("ai_profiles.profiles should be a non-empty object")
		return errors
	if not default_profile.is_empty() and not (profiles as Dictionary).has(default_profile):
		errors.append("ai_profiles.default_profile references missing profile: %s" % default_profile)
	for profile_id in (profiles as Dictionary).keys():
		var raw_profile: Variant = (profiles as Dictionary)[profile_id]
		if not raw_profile is Dictionary:
			errors.append("ai_profiles.profiles.%s should be object" % profile_id)
			continue
		errors.append_array(_validate_ai_profile_fields(
			"ai_profiles.profiles.%s" % profile_id,
			raw_profile as Dictionary,
			false
		))
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


static func _validate_ai_profile_fields(prefix: String, profile: Dictionary, require_complete: bool) -> Array[String]:
	var errors: Array[String] = []
	for key in profile.keys():
		var key_id := str(key)
		if AI_PROFILE_NUMERIC_KEYS.has(key_id):
			if not _is_number(profile[key]):
				errors.append("%s.%s should be number" % [prefix, key_id])
		elif AI_PROFILE_BOOL_KEYS.has(key_id):
			if not profile[key] is bool:
				errors.append("%s.%s should be bool" % [prefix, key_id])
		else:
			errors.append("%s.%s is unknown" % [prefix, key_id])
	if require_complete:
		for key in AI_PROFILE_NUMERIC_KEYS.keys():
			if not profile.has(key):
				errors.append("%s.%s missing" % [prefix, key])
		for key in AI_PROFILE_BOOL_KEYS.keys():
			if not profile.has(key):
				errors.append("%s.%s missing" % [prefix, key])
	return errors

static func validate_gem_defs(defs: Dictionary, known_profiles: Dictionary = {}) -> Array[String]:
	var errors: Array[String] = []
	if defs.is_empty():
		errors.append("gem_defs should not be empty")
		return errors
	var known_tags: Dictionary = {}
	for gem_id in defs.keys():
		var raw_def: Variant = defs[gem_id]
		if not raw_def is Dictionary:
			continue
		var tag := str((raw_def as Dictionary).get("tag", ""))
		if tag.is_empty():
			continue
		if known_tags.has(tag):
			errors.append("gem_defs.%s.tag duplicates %s" % [gem_id, known_tags[tag]])
		else:
			known_tags[tag] = str(gem_id)
	for gem_id in defs.keys():
		var prefix := "gem_defs.%s" % gem_id
		var raw_def: Variant = defs[gem_id]
		if not raw_def is Dictionary:
			errors.append("%s should be object" % prefix)
			continue
		var gem_def := raw_def as Dictionary
		for field_id in gem_def.keys():
			if not GEM_DEF_FIELDS.has(str(field_id)):
				errors.append("%s.%s is unknown" % [prefix, field_id])
		for field_id in GEM_DEF_REQUIRED_FIELDS:
			if not gem_def.has(field_id):
				errors.append("%s.%s missing" % [prefix, field_id])
		for field_id in ["display_name_key", "symbol_key", "symbol", "tag", "element"]:
			if gem_def.has(field_id) and (not gem_def[field_id] is String or str(gem_def[field_id]).is_empty()):
				errors.append("%s.%s should be a non-empty string" % [prefix, field_id])
		var color: Variant = gem_def.get("color", null)
		if not color is Array or (color as Array).size() not in [3, 4]:
			errors.append("%s.color should contain 3 or 4 numbers" % prefix)
		else:
			for component in color as Array:
				if not _is_number(component) or float(component) < 0.0 or float(component) > 1.0:
					errors.append("%s.color components should be numbers in [0, 1]" % prefix)
					break
		for field_id in ["pool_tier", "max_stack_level"]:
			var value: Variant = gem_def.get(field_id, null)
			if not _is_positive_integer(value):
				errors.append("%s.%s should be a positive integer" % [prefix, field_id])
		var rarity := str(gem_def.get("rarity", ""))
		if rarity not in GEM_RARITIES:
			errors.append("%s.rarity unknown: %s" % [prefix, rarity])
		if gem_def.has("allow_random_pool") and not gem_def["allow_random_pool"] is bool:
			errors.append("%s.allow_random_pool should be bool" % prefix)
		var combos: Variant = gem_def.get("combos", null)
		if not combos is Array:
			errors.append("%s.combos should be array" % prefix)
		else:
			var seen_combos: Dictionary = {}
			for combo in combos as Array:
				var combo_id := str(combo)
				if not combo is String or combo_id.is_empty():
					errors.append("%s.combos should contain non-empty strings" % prefix)
				elif not known_tags.has(combo_id):
					errors.append("%s.combos references unknown tag: %s" % [prefix, combo_id])
				elif seen_combos.has(combo_id):
					errors.append("%s.combos contains duplicate tag: %s" % [prefix, combo_id])
				seen_combos[combo_id] = true
		var profiles: Variant = gem_def.get("ability_profiles", null)
		if not profiles is Dictionary or (profiles as Dictionary).is_empty():
			errors.append("%s.ability_profiles should be a non-empty object" % prefix)
		else:
			for ability_slot in (profiles as Dictionary).keys():
				var ability_slot_id := str(ability_slot)
				var profile_id := str((profiles as Dictionary)[ability_slot])
				if ability_slot_id not in GEM_ABILITY_PROFILE_KEYS:
					errors.append("%s.ability_profiles.%s is unknown" % [prefix, ability_slot_id])
				elif profile_id.is_empty():
					errors.append("%s.ability_profiles.%s should be a non-empty string" % [prefix, ability_slot_id])
				elif not known_profiles.is_empty() and not known_profiles.has(profile_id):
					errors.append("%s.ability_profiles.%s references unknown profile: %s" % [prefix, ability_slot_id, profile_id])
	return errors


static func validate_unit_defs(
	defs: Dictionary,
	known_gem_ids: Dictionary = {},
	known_behavior_ids: Dictionary = {},
	known_ai_profile_ids: Dictionary = {}
) -> Array[String]:
	var errors: Array[String] = []
	if defs.is_empty():
		errors.append("unit_defs should not be empty")
		return errors
	if not defs.has("unit_player"):
		errors.append("unit_defs.unit_player missing")
	for unit_id in defs.keys():
		var prefix := "unit_defs.%s" % unit_id
		var raw_def: Variant = defs[unit_id]
		if not raw_def is Dictionary:
			errors.append("%s should be object" % prefix)
			continue
		var unit_def := raw_def as Dictionary
		for field_id in unit_def.keys():
			if not UNIT_DEF_FIELDS.has(str(field_id)):
				errors.append("%s.%s is unknown" % [prefix, field_id])
		for field_id in UNIT_DEF_REQUIRED_FIELDS:
			if not unit_def.has(field_id):
				errors.append("%s.%s missing" % [prefix, field_id])
		for field_id in ["display_name_key", "ai_profile_id"]:
			if unit_def.has(field_id) and (not unit_def[field_id] is String or str(unit_def[field_id]).is_empty()):
				errors.append("%s.%s should be a non-empty string" % [prefix, field_id])
		var ai_profile_id := str(unit_def.get("ai_profile_id", ""))
		if not ai_profile_id.is_empty() and not known_ai_profile_ids.is_empty() and not known_ai_profile_ids.has(ai_profile_id):
			errors.append("%s.ai_profile_id references unknown profile: %s" % [prefix, ai_profile_id])
		var behavior_id := str(unit_def.get("behavior_id", ""))
		if str(unit_id) != "unit_player" and not unit_def.has("behavior_id"):
			errors.append("%s.behavior_id missing" % prefix)
		elif unit_def.has("behavior_id") and (not unit_def["behavior_id"] is String or behavior_id.is_empty()):
			errors.append("%s.behavior_id should be a non-empty string" % prefix)
		elif not behavior_id.is_empty() and not known_behavior_ids.is_empty() and not known_behavior_ids.has(behavior_id):
			errors.append("%s.behavior_id references unknown behavior: %s" % [prefix, behavior_id])
		for field_id in ["max_hp", "move_points", "speed", "base_attack", "armor"]:
			var value: Variant = unit_def.get(field_id, null)
			if not _is_non_negative_integer(value):
				errors.append("%s.%s should be a non-negative integer" % [prefix, field_id])
		if _is_number(unit_def.get("max_hp", null)) and int(unit_def.get("max_hp", 0)) <= 0:
			errors.append("%s.max_hp should be positive" % prefix)
		if unit_def.has("hp_roll_max") and not _is_non_negative_integer(unit_def["hp_roll_max"]):
			errors.append("%s.hp_roll_max should be a non-negative integer" % prefix)
		errors.append_array(_validate_string_array("%s.tags" % prefix, unit_def.get("tags", null)))
		var slots: Variant = unit_def.get("slots", null)
		if not slots is Array or (slots as Array).is_empty():
			errors.append("%s.slots should be a non-empty array" % prefix)
		else:
			var seen_slot_types: Dictionary = {}
			for index in range((slots as Array).size()):
				errors.append_array(_validate_unit_slot("%s.slots[%d]" % [prefix, index], (slots as Array)[index], known_gem_ids))
				var raw_slot: Variant = (slots as Array)[index]
				if raw_slot is Dictionary:
					var slot_type := str((raw_slot as Dictionary).get("slot_type", ""))
					if seen_slot_types.has(slot_type):
						errors.append("%s.slots contains duplicate slot_type: %s" % [prefix, slot_type])
					seen_slot_types[slot_type] = true
		if unit_def.has("spawn_gem_slots"):
			var spawn_slots: Variant = unit_def["spawn_gem_slots"]
			if not spawn_slots is Array:
				errors.append("%s.spawn_gem_slots should be array" % prefix)
			else:
				for slot_type in spawn_slots as Array:
					if not slot_type is String or str(slot_type) not in [Constants.SLOT_RED, Constants.SLOT_BLUE, Constants.SLOT_BLACK]:
						errors.append("%s.spawn_gem_slots contains unknown slot: %s" % [prefix, slot_type])
		if unit_def.has("footprint_size"):
			var footprint: Variant = unit_def["footprint_size"]
			if not footprint is Array or (footprint as Array).size() != 2:
				errors.append("%s.footprint_size should contain 2 positive integers" % prefix)
			else:
				for value in footprint as Array:
					if not _is_positive_integer(value):
						errors.append("%s.footprint_size should contain 2 positive integers" % prefix)
						break
		var balance: Variant = unit_def.get("balance", {})
		if not balance is Dictionary:
			errors.append("%s.balance should be object" % prefix)
			continue
		for key in (balance as Dictionary).keys():
			if not UNIT_BALANCE_NUMERIC_KEYS.has(str(key)):
				errors.append("%s.balance.%s is unknown" % [prefix, key])
				continue
			if not _is_number((balance as Dictionary)[key]):
				errors.append("%s.balance.%s should be number" % [prefix, key])
		for required_key in UNIT_BALANCE_REQUIRED_BY_BEHAVIOR.get(behavior_id, []):
			if not (balance as Dictionary).has(required_key):
				errors.append("%s.balance.%s missing" % [prefix, required_key])
	return errors


static func validate_combat_config(config: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for key in config.keys():
		if not COMBAT_CONFIG_NUMERIC_KEYS.has(str(key)):
			errors.append("combat_config.%s is unknown" % str(key))
	for key in COMBAT_CONFIG_NUMERIC_KEYS.keys():
		if not config.has(key):
			errors.append("combat_config.%s missing" % key)
			continue
		if not _is_number(config[key]):
			errors.append("combat_config.%s should be number" % key)
	if config.has("star_relocation_max_distance"):
		var max_distance: Variant = config["star_relocation_max_distance"]
		if _is_number(max_distance) and (
			float(max_distance) != floor(float(max_distance)) or int(max_distance) <= 0
		):
			errors.append("combat_config.star_relocation_max_distance should be a positive integer")
	if config.has("star_relocation_squeeze_damage_per_tile"):
		var squeeze_per_tile: Variant = config["star_relocation_squeeze_damage_per_tile"]
		if _is_number(squeeze_per_tile) and (
			float(squeeze_per_tile) != floor(float(squeeze_per_tile)) or int(squeeze_per_tile) < 0
		):
			errors.append("combat_config.star_relocation_squeeze_damage_per_tile should be a non-negative integer")
	if config.has("water_move_cost_extra") and _is_number(config["water_move_cost_extra"]):
		if float(config["water_move_cost_extra"]) < 0.0:
			errors.append("combat_config.water_move_cost_extra should be non-negative")
	return errors


static func validate_gem_effect_levels(config: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for slot_type in GEM_EFFECT_LEVEL_SLOT_KEYS:
		if not config.has(slot_type):
			errors.append("gem_effect_levels.%s missing" % slot_type)
	for slot_type in config.keys():
		if slot_type not in GEM_EFFECT_LEVEL_SLOT_KEYS:
			errors.append("gem_effect_levels.%s is unknown" % str(slot_type))
			continue
		var slot_defs: Variant = config[slot_type]
		if not slot_defs is Dictionary:
			errors.append("gem_effect_levels.%s should be object" % slot_type)
			continue
		for required_tag in GEM_EFFECT_LEVEL_TAG_KEYS:
			if not (slot_defs as Dictionary).has(required_tag):
				errors.append("gem_effect_levels.%s.%s missing" % [slot_type, required_tag])
		for tag in (slot_defs as Dictionary).keys():
			if tag not in GEM_EFFECT_LEVEL_TAG_KEYS:
				errors.append("gem_effect_levels.%s.%s is unknown" % [str(slot_type), str(tag)])
				continue
			var tag_defs: Variant = (slot_defs as Dictionary)[tag]
			if not tag_defs is Dictionary:
				errors.append("gem_effect_levels.%s.%s should be object" % [slot_type, tag])
				continue
			for required_level in GEM_EFFECT_LEVEL_KEYS:
				if not (tag_defs as Dictionary).has(required_level):
					errors.append("gem_effect_levels.%s.%s.%s missing" % [slot_type, tag, required_level])
			for level_key in (tag_defs as Dictionary).keys():
				var level_id := str(level_key)
				if level_id not in GEM_EFFECT_LEVEL_KEYS:
					errors.append("gem_effect_levels.%s.%s.%s is unknown; expected levels 1, 2, 3" % [slot_type, tag, level_id])
					continue
				var entry: Variant = (tag_defs as Dictionary)[level_key]
				if not entry is Dictionary:
					errors.append("gem_effect_levels.%s.%s.%s should be object" % [slot_type, tag, level_id])
					continue
				var schema_key := "%s:%s" % [slot_type, tag]
				var allowed_fields: Array = GEM_EFFECT_LEVEL_FIELDS.get(schema_key, [])
				var optional_fields: Array = GEM_EFFECT_LEVEL_OPTIONAL_FIELDS.get(schema_key, [])
				for required_field in allowed_fields:
					if required_field in optional_fields:
						continue
					if not (entry as Dictionary).has(required_field):
						errors.append("gem_effect_levels.%s.%s.%s.%s missing" % [slot_type, tag, level_id, required_field])
				if schema_key == "black:arc" and (entry as Dictionary).get("strike_all_targets", null) is bool:
					var strikes_all := bool((entry as Dictionary).get("strike_all_targets", false))
					if not strikes_all and not (entry as Dictionary).has("strike_count"):
						errors.append("gem_effect_levels.%s.%s.%s.strike_count missing for counted targeting" % [slot_type, tag, level_id])
					elif strikes_all and (entry as Dictionary).has("strike_count"):
						errors.append("gem_effect_levels.%s.%s.%s.strike_count should be omitted for all-target targeting" % [slot_type, tag, level_id])
				if schema_key == "blue:split" and _is_number((entry as Dictionary).get("temp_clone_count", null)):
					var temp_clone_count := int((entry as Dictionary).get("temp_clone_count", 0))
					var temp_fields := [
						"temp_clone_hp",
						"temp_clone_stat_ratio",
						"temp_clone_duration",
						"temp_clone_per_turn_limit",
					]
					for temp_field in temp_fields:
						var temp_value: Variant = (entry as Dictionary).get(temp_field, null)
						if not _is_number(temp_value):
							continue
						if temp_clone_count > 0 and float(temp_value) <= 0.0:
							errors.append("gem_effect_levels.%s.%s.%s.%s should be positive when temp_clone_count is positive" % [slot_type, tag, level_id, temp_field])
						elif temp_clone_count == 0 and float(temp_value) != 0.0:
							errors.append("gem_effect_levels.%s.%s.%s.%s should be zero when temp_clone_count is zero" % [slot_type, tag, level_id, temp_field])
					var per_turn_limit: Variant = (entry as Dictionary).get("temp_clone_per_turn_limit", null)
					if temp_clone_count > 0 and _is_number(per_turn_limit) and int(per_turn_limit) < temp_clone_count:
						errors.append("gem_effect_levels.%s.%s.%s.temp_clone_per_turn_limit should be at least temp_clone_count" % [slot_type, tag, level_id])
				for field_key in (entry as Dictionary).keys():
					var field_id := str(field_key)
					if not GEM_EFFECT_LEVEL_VALUE_TYPES.has(field_id):
						errors.append("gem_effect_levels.%s.%s.%s.%s is unknown" % [slot_type, tag, level_id, field_id])
						continue
					if field_id not in allowed_fields:
						errors.append("gem_effect_levels.%s.%s.%s.%s is not allowed for %s" % [slot_type, tag, level_id, field_id, schema_key])
						continue
					var expected_type := str(GEM_EFFECT_LEVEL_VALUE_TYPES[field_id])
					if not _matches_gem_effect_level_type((entry as Dictionary)[field_key], expected_type):
						errors.append("gem_effect_levels.%s.%s.%s.%s should be %s" % [slot_type, tag, level_id, field_id, expected_type])
						continue
					errors.append_array(_validate_gem_effect_level_value(
						"gem_effect_levels.%s.%s.%s.%s" % [slot_type, tag, level_id, field_id],
						field_id,
						(entry as Dictionary)[field_key]
					))
	return errors


static func validate_status_config(config: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for required_entry_id in STATUS_CONFIG_ENTRY_KEYS.keys():
		if not config.has(required_entry_id):
			errors.append("status_config.%s missing" % required_entry_id)
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
		for required_field_id in ["default_stacks", "default_duration"]:
			if not (entry as Dictionary).has(required_field_id):
				errors.append("status_config.%s.%s missing" % [str(entry_id), required_field_id])
		var extra_required_fields: Array = []
		match str(entry_id):
			"burning":
				extra_required_fields = ["firelike_stack_mult"]
			"slowed":
				extra_required_fields = ["min_move_points"]
			"vulnerable":
				extra_required_fields = ["damage_taken_mult"]
			"weak":
				extra_required_fields = ["attack_damage_mult"]
			"lawless":
				extra_required_fields = ["attack_bonus"]
		for required_field_id in extra_required_fields:
			if not (entry as Dictionary).has(required_field_id):
				errors.append("status_config.%s.%s missing" % [str(entry_id), required_field_id])
		for integer_field_id in ["default_stacks", "default_duration", "min_move_points", "attack_bonus"]:
			if not (entry as Dictionary).has(integer_field_id):
				continue
			var integer_value: Variant = (entry as Dictionary)[integer_field_id]
			if _is_number(integer_value) and not _is_non_negative_integer(integer_value):
				errors.append("status_config.%s.%s should be a non-negative integer" % [str(entry_id), integer_field_id])
		for multiplier_field_id in ["firelike_stack_mult", "damage_taken_mult", "attack_damage_mult"]:
			if not (entry as Dictionary).has(multiplier_field_id):
				continue
			var multiplier: Variant = (entry as Dictionary)[multiplier_field_id]
			if _is_number(multiplier) and float(multiplier) <= 0.0:
				errors.append("status_config.%s.%s should be positive" % [str(entry_id), multiplier_field_id])
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


static func _validate_gem_effect_level_value(prefix: String, field_id: String, value: Variant) -> Array[String]:
	var errors: Array[String] = []
	if GEM_EFFECT_LEVEL_ENUM_VALUES.has(field_id) and str(value) not in GEM_EFFECT_LEVEL_ENUM_VALUES[field_id]:
		errors.append("%s should be one of %s" % [prefix, ", ".join(GEM_EFFECT_LEVEL_ENUM_VALUES[field_id])])
	if GEM_EFFECT_LEVEL_INTEGER_NON_NEGATIVE_FIELDS.has(field_id):
		if int(value) != float(value):
			errors.append("%s should be an integer" % prefix)
		elif float(value) < 0.0:
			errors.append("%s should be non-negative" % prefix)
	if GEM_EFFECT_LEVEL_POSITIVE_INTEGER_FIELDS.has(field_id) and float(value) <= 0.0:
		errors.append("%s should be positive" % prefix)
	if GEM_EFFECT_LEVEL_UNIT_INTERVAL_FIELDS.has(field_id) and (float(value) < 0.0 or float(value) > 1.0):
		errors.append("%s should be in [0, 1]" % prefix)
	if GEM_EFFECT_LEVEL_POSITIVE_FIELDS.has(field_id) and float(value) <= 0.0:
		errors.append("%s should be positive" % prefix)
	if field_id == "light_direction_offsets":
		var offsets := value as Array
		if offsets.is_empty():
			errors.append("%s should not be empty" % prefix)
		elif offsets.size() != _unique_int_count(offsets):
			errors.append("%s should not contain duplicate offsets" % prefix)
	return errors


static func _unique_int_count(values: Array) -> int:
	var seen := {}
	for value in values:
		seen[int(value)] = true
	return seen.size()


static func _validate_string_array(prefix: String, value: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not value is Array:
		errors.append("%s should be array" % prefix)
		return errors
	var seen: Dictionary = {}
	for item in value as Array:
		var item_id := str(item)
		if not item is String or item_id.is_empty():
			errors.append("%s should contain non-empty strings" % prefix)
		elif seen.has(item_id):
			errors.append("%s contains duplicate value: %s" % [prefix, item_id])
		seen[item_id] = true
	return errors


static func _validate_unit_slot(prefix: String, raw_slot: Variant, known_gem_ids: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not raw_slot is Dictionary:
		errors.append("%s should be object" % prefix)
		return errors
	var slot := raw_slot as Dictionary
	for field_id in slot.keys():
		if str(field_id) not in ["slot_type", "gem_id"]:
			errors.append("%s.%s is unknown" % [prefix, field_id])
	var slot_type := str(slot.get("slot_type", ""))
	if slot_type not in [Constants.SLOT_RED, Constants.SLOT_BLUE, Constants.SLOT_BLACK]:
		errors.append("%s.slot_type unknown: %s" % [prefix, slot_type])
	if slot.has("gem_id"):
		var gem_id := str(slot.get("gem_id", ""))
		if not slot["gem_id"] is String or gem_id.is_empty():
			errors.append("%s.gem_id should be a non-empty string" % prefix)
		elif not known_gem_ids.is_empty() and not known_gem_ids.has(gem_id):
			errors.append("%s.gem_id references unknown gem: %s" % [prefix, gem_id])
	return errors


static func _is_non_negative_integer(value: Variant) -> bool:
	return _is_number(value) and int(value) == float(value) and int(value) >= 0


static func _is_positive_integer(value: Variant) -> bool:
	return _is_non_negative_integer(value) and int(value) > 0


static func _validate_weight_map(prefix: String, weights: Dictionary, known_ids: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var total_weight := 0.0
	for raw_id in weights.keys():
		var id := str(raw_id)
		var value: Variant = weights[raw_id]
		if not known_ids.is_empty() and not known_ids.has(id):
			errors.append("%s.%s is unknown" % [prefix, id])
		elif not _is_number(value):
			errors.append("%s.%s should be number" % [prefix, id])
		elif float(value) < 0.0:
			errors.append("%s.%s should be non-negative" % [prefix, id])
		else:
			total_weight += float(value)
	if total_weight <= 0.0:
		errors.append("%s should have positive total weight" % prefix)
	return errors


static func _key_dictionary(ids: Array) -> Dictionary:
	var result: Dictionary = {}
	for id in ids:
		result[str(id)] = true
	return result


static func _is_number(value: Variant) -> bool:
	return value is int or value is float
