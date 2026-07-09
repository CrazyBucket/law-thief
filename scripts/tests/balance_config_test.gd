extends SceneTree

const AIProfiles = preload("res://scripts/rules/ai_profiles.gd")
const AdventureConfigValidator = preload("res://scripts/services/adventure_config_validator.gd")
const BalanceConfigValidator = preload("res://scripts/services/balance_config_validator.gd")
const CombatConfig = preload("res://scripts/core/combat_config.gd")
const FissionSlimeRules = preload("res://scripts/rules/fission_slime_rules.gd")
const PatrolGuardRules = preload("res://scripts/rules/patrol_guard_rules.gd")
const StatusConfig = preload("res://scripts/core/status_config.gd")
const StoneBowGuardRules = preload("res://scripts/rules/stone_bow_guard_rules.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("=== Balance Config Test ===")
	_test_relic_numeric_refs_config()
	_test_relic_source_weights_config()
	_test_reward_offer_config()
	_test_player_copy_numeric_tokens()
	_test_enemy_slot_curves_config()
	_test_ai_profile_config()
	_test_gem_effect_level_config()
	_test_status_config()
	_test_unit_and_hazard_balance_config()
	if _failed:
		push_error("BALANCE_CONFIG_TEST_FAIL")
		quit(1)
		return
	print("BALANCE_CONFIG_TEST_PASS")
	quit(0)


func _test_relic_source_weights_config() -> void:
	var reg := _registry()
	if reg == null:
		return
	var shop_weights: Dictionary = reg.get_relic_source_weights("shop")
	_expect(abs(float(shop_weights.get("boss", 0.0)) - 15.0) < 0.001, "shop relic boss weight should come from config")
	var elite_weights: Dictionary = reg.get_relic_source_weights("elite_combat")
	_expect(abs(float(elite_weights.get("rare", 0.0)) - 40.0) < 0.001, "elite relic rare weight should come from config")
	var source_ids: Array[String] = reg.get_relic_source_ids()
	_expect("shop" in source_ids and "normal_chest" in source_ids, "relic source ids should come from config")
	_expect(reg.get_relic_source_weights("missing_relic_source").is_empty(), "unknown relic sources should not fall back to common-only weights")
	_expect(reg.get_relic_pool("missing_relic_source").is_empty(), "unknown relic sources should not produce a relic pool")
	var missing_relic_offer: Array[String] = reg.roll_relic_offer("test_missing_relic_source", "missing_relic_source", 2)
	_expect(missing_relic_offer == ["relic_placeholder", "relic_placeholder"], "unknown relic sources should produce placeholder relic offers")
	print("  [OK] relic source weights config")


func _test_reward_offer_config() -> void:
	var reg := _registry()
	if reg == null:
		return
	var raw := _load_json("res://resources/adventure/reward_offer_config.json")
	var source_set := _key_set(reg.get_relic_source_ids())
	var errors := AdventureConfigValidator.validate_reward_offer_config(raw, source_set)
	_expect(errors.is_empty(), "reward offer config should pass validator")
	var elite_reward: Dictionary = reg.get_battle_reward_offer_config("ELITE_COMBAT")
	_expect(str(elite_reward.get("relic_source", "")) == "elite_combat", "elite reward relic source should come from config")
	_expect(int(elite_reward.get("relic_offer_count", 0)) == 3, "elite reward relic offer count should come from config")
	var end_reward: Dictionary = reg.get_battle_reward_offer_config("END")
	_expect(str(end_reward.get("relic_source", "")) == "large_chest", "end reward relic source should come from config")
	var fallback_reward: Dictionary = reg.get_battle_reward_offer_config("UNKNOWN_ROOM")
	_expect(str(fallback_reward.get("relic_source", "")) == "normal_chest", "unknown reward room should use configured default")
	_expect(reg.get_battle_relic_offer_source("UNKNOWN_ROOM") == "normal_chest", "battle reward source helper should use configured default")
	_expect(reg.get_battle_relic_offer_count("UNKNOWN_ROOM") == 3, "battle reward count helper should use configured default")
	var missing_default := {
		"battle_rewards": {
			"NORMAL_COMBAT": {
				"relic_source": "normal_chest",
				"relic_offer_count": 3,
			},
		},
	}
	var missing_default_errors := AdventureConfigValidator.validate_reward_offer_config(missing_default, source_set)
	_expect(_contains_error(missing_default_errors, "reward_offer_config.battle_rewards.default missing"), "reward config should require an authored default")
	var invalid := {
		"battle_rewards": {
			"default": {
				"relic_source": "",
				"relic_offer_count": 1.5,
			},
			"NORMAL_COMBAT": {
				"relic_source": "missing_relic_source",
				"relic_offer_count": -1,
			},
		},
	}
	var invalid_errors := AdventureConfigValidator.validate_reward_offer_config(invalid, source_set)
	_expect(_contains_error(invalid_errors, "reward_offer_config.battle_rewards.default.relic_source should not be empty"), "reward config should reject empty relic source")
	_expect(_contains_error(invalid_errors, "reward_offer_config.battle_rewards.default.relic_offer_count should be integer"), "reward config should reject fractional counts")
	_expect(_contains_error(invalid_errors, "reward_offer_config.battle_rewards.NORMAL_COMBAT.relic_offer_count should be non-negative"), "reward config should reject negative counts")
	_expect(_contains_error(invalid_errors, "reward_offer_config.battle_rewards.NORMAL_COMBAT.relic_source unknown: missing_relic_source"), "reward config should reject unknown relic sources")
	var shop_errors := AdventureConfigValidator.validate_shop_pools(
		{
			"default": {
				"gem_offer_count": 1,
				"relic_offer_count": 1,
				"gem_source": "missing_gem_source",
				"relic_source": "missing_relic_source",
			},
		},
		_key_set(reg.get_gem_pool_source_ids()),
		source_set
	)
	_expect(_contains_error(shop_errors, "shop_pools.default.gem_source unknown: missing_gem_source"), "shop pool config should reject unknown gem sources")
	_expect(_contains_error(shop_errors, "shop_pools.default.relic_source unknown: missing_relic_source"), "shop pool config should reject unknown relic sources")
	_expect(reg.get_gem_pool_def("missing_gem_source").is_empty(), "unknown gem sources should not fall back to global pool")
	_expect(reg.get_spawnable_gem_ids_for_source("missing_gem_source", 1).is_empty(), "unknown gem sources should not produce spawnable gem ids")
	var missing_gem_offer: Array[String] = reg.roll_gem_offer("test_missing_gem_source", "missing_gem_source", 2, 1)
	_expect(missing_gem_offer == ["", ""], "unknown gem sources should produce empty gem offer slots")
	print("  [OK] reward offer config")


func _test_player_copy_numeric_tokens() -> void:
	var amount_refs := {
		"event_1_gold": {"value": 3, "kind": "flat", "unit": "gold"},
	}
	var valid_event_errors := AdventureConfigValidator.validate_event_defs({
		"token_number_event": {
			"title": "token",
			"body": "拿 {amount_ref:event_1_gold} 金币",
			"options": [
				{
					"id": "take_gold",
					"label": "拿 {amount_ref:event_1_gold} 金币",
					"conditions": [],
					"effects": [
						{"action": "grant_resource", "resource_id": "gold", "amount_ref": "event_1_gold"},
					],
				},
			],
		},
	}, amount_refs)
	_expect(valid_event_errors.is_empty(), "event text should allow numbers inside numeric tokens")
	var invalid_event_errors := AdventureConfigValidator.validate_event_defs({
		"literal_number_event": {
			"title": "literal",
			"body": "拿 3 金币",
			"options": [
				{
					"id": "take_gold",
					"label": "拿 3 金币",
					"conditions": [],
					"effects": [
						{"action": "grant_resource", "resource_id": "gold", "amount_ref": "event_1_gold"},
					],
				},
			],
		},
	}, amount_refs)
	_expect(_contains_error(invalid_event_errors, "event_defs.literal_number_event.body should use numeric text tokens instead of literal numbers"), "event body should reject literal numbers")
	_expect(_contains_error(invalid_event_errors, "event_defs.literal_number_event.options[0].label should use numeric text tokens instead of literal numbers"), "event option label should reject literal numbers")
	var invalid_rule_errors := AdventureConfigValidator.validate_map_rule_defs({
		"literal_number_rule": {
			"name": "金币增益",
			"desc": "后续金币 +10%",
			"default_scope": "run",
			"effects": [
				{"modifier": "gold_gain_mult", "value": 1.1},
			],
		},
	})
	_expect(_contains_error(invalid_rule_errors, "map_rule_defs.literal_number_rule.desc should use numeric text tokens instead of literal numbers"), "map rule desc should reject literal numbers")
	print("  [OK] player copy numeric tokens")


func _test_relic_numeric_refs_config() -> void:
	var reg := _registry()
	if reg == null:
		return
	_expect(reg.has_relic_numeric_ref("relic_cracked_amulet_shield"), "relic numeric ref should be loaded")
	_expect(reg.get_relic_numeric_ref("relic_reinforced_base_shield") == 4.0, "relic shield amount should come from ref config")
	_expect(abs(float(reg.get_relic_numeric_ref("relic_broken_rib_collision_damage_mult")) - 1.5) < 0.001, "relic modifier value should come from ref config")
	_expect(abs(float(reg.get_relic_numeric_ref("relic_empty_coffin_empty_slot_weight_mult")) - 3.0) < 0.001, "relic weight multiplier should come from ref config")
	var shield_ref: Dictionary = reg.get_relic_numeric_ref_def("relic_cracked_amulet_shield")
	_expect(str(shield_ref.get("kind", "")) == "flat", "relic shield amount ref should declare flat kind")
	_expect(str(shield_ref.get("unit", "")) == "shield", "relic shield amount ref should declare shield unit")
	var amulet_desc := str(reg.get_relic_def("relic_cracked_amulet").get("desc", ""))
	_expect(amulet_desc == "战斗开始时获得 3 点护盾。", "relic desc should render numeric refs")
	var goggles_desc := str(reg.get_relic_def("relic_cracked_goggles").get("desc", ""))
	_expect(goggles_desc.find("10%") >= 0 and goggles_desc.find("+2") >= 0, "relic desc should render percent and signed numeric refs")
	var painkiller_desc := str(reg.get_relic_def("relic_painkiller").get("desc", ""))
	_expect(painkiller_desc.find("1 点伤害") >= 0, "relic desc should render painkiller damage cap ref")
	var raw_refs := _load_json("res://resources/relics/relic_numeric_refs.json")
	var ref_errors := BalanceConfigValidator.validate_relic_numeric_refs(raw_refs)
	_expect(ref_errors.is_empty(), "relic numeric refs should pass validator")
	var raw_relic_defs := _load_json("res://resources/relics/relic_defs.json")
	var relic_errors := BalanceConfigValidator.validate_relic_defs(raw_relic_defs, raw_refs)
	_expect(relic_errors.is_empty(), "relic defs should pass amount-ref validator")
	var invalid_refs := {
		"broken": {"value": 1, "kind": "flat"}
	}
	var invalid_ref_errors := BalanceConfigValidator.validate_relic_numeric_refs(invalid_refs)
	_expect(_contains_error(invalid_ref_errors, "relic_numeric_refs.broken.unit missing"), "relic numeric ref validator should require units")
	var invalid_defs := {
		"broken_relic": {
			"desc": "bad 3 {relic_numeric_ref:missing_desc_ref}",
			"effects": [
				{"on": "battle_start", "action": "add_armor", "target": "player", "amount": 3},
				{"on": "battle_start", "action": "heal", "target": "player", "amount_ref": "relic_cracked_amulet_shield"},
				{"on": "battle_start", "action": "add_temp_move", "amount_ref": "missing_ref"},
				{"modifier": "arc_damage_mult", "value": 1.2},
				{"modifier": "attack_miss_chance", "value_ref": "relic_crowbar_armor_lock_break_bonus"},
				{"modifier": "first_damage_cap", "value_ref": "relic_cracked_amulet_shield"},
				{"on": "battle_start", "action": "apply_max_hp_reduction", "ratio_ref": "relic_cracked_amulet_shield"}
			],
			"weight_rules": [
				{"type": "empty_slot_count_gte", "value": 2, "multiplier_ref": "relic_empty_coffin_empty_slot_weight_mult"},
				{"type": "has_gem", "value": "gem_split", "multiplier": 5.0},
				{"type": "slot_count_gte", "value_ref": "relic_cracked_amulet_shield", "multiplier_ref": "relic_reinforced_base_slot_weight_mult"}
			]
		}
	}
	var invalid_def_errors := BalanceConfigValidator.validate_relic_defs(invalid_defs, raw_refs)
	_expect(_contains_error(invalid_def_errors, "relic_defs.broken_relic.desc unknown relic numeric token: missing_desc_ref"), "relic defs should reject unknown desc numeric tokens")
	_expect(_contains_error(invalid_def_errors, "relic_defs.broken_relic.desc should use relic numeric text tokens instead of literal numbers"), "relic defs should reject literal desc numbers")
	_expect(_contains_error(invalid_def_errors, "relic_defs.broken_relic.effects[0].amount should use amount_ref in authored config"), "relic defs should reject authored inline amounts")
	_expect(_contains_error(invalid_def_errors, "relic_defs.broken_relic.effects[1].amount_ref unit mismatch: relic_cracked_amulet_shield expected hp got shield"), "relic defs should reject wrong amount-ref units")
	_expect(_contains_error(invalid_def_errors, "relic_defs.broken_relic.effects[2].amount_ref unknown: missing_ref"), "relic defs should reject unknown amount refs")
	_expect(_contains_error(invalid_def_errors, "relic_defs.broken_relic.effects[3].value should use value_ref in authored config"), "relic defs should reject authored inline modifier values")
	_expect(_contains_error(invalid_def_errors, "relic_defs.broken_relic.effects[4].value_ref kind mismatch: relic_crowbar_armor_lock_break_bonus expected ratio got flat"), "relic defs should reject wrong modifier ref kinds")
	_expect(_contains_error(invalid_def_errors, "relic_defs.broken_relic.effects[5].value_ref unit mismatch: relic_cracked_amulet_shield expected damage got shield"), "relic defs should reject wrong first-damage-cap ref units")
	_expect(_contains_error(invalid_def_errors, "relic_defs.broken_relic.effects[6].ratio_ref kind mismatch: relic_cracked_amulet_shield expected ratio got flat"), "relic defs should reject wrong ratio ref kinds")
	_expect(_contains_error(invalid_def_errors, "relic_defs.broken_relic.weight_rules[0].value should use value_ref in authored config"), "relic defs should reject authored inline weight thresholds")
	_expect(_contains_error(invalid_def_errors, "relic_defs.broken_relic.weight_rules[1].multiplier should use multiplier_ref in authored config"), "relic defs should reject authored inline weight multipliers")
	_expect(_contains_error(invalid_def_errors, "relic_defs.broken_relic.weight_rules[2].value_ref unit mismatch: relic_cracked_amulet_shield expected slot_count got shield"), "relic defs should reject wrong weight threshold units")
	var coffin_weight: float = float(reg.compute_relic_weight("relic_empty_coffin", {"empty_slots": 2}))
	_expect(abs(coffin_weight - 3.0) < 0.001, "relic weight refs should resolve during weight computation")
	var shell_weight: float = float(reg.compute_relic_weight("relic_empty_shell", {"empty_slots": 1}))
	_expect(abs(shell_weight - 2.0) < 0.001, "relic threshold refs should resolve during weight computation")
	print("  [OK] relic numeric refs config")


func _test_enemy_slot_curves_config() -> void:
	var reg := _registry()
	if reg == null:
		return
	var elite_ch2: Array[float] = reg.get_enemy_total_slot_weights("ELITE_COMBAT", 2)
	_expect(elite_ch2.size() == 4, "enemy slot curve should provide four weights")
	_expect(abs(elite_ch2[3] - 30.0) < 0.001, "elite chapter 2 slot curve should come from config")
	var boss_ch5: Array[float] = reg.get_enemy_total_slot_weights("BOSS", 5)
	_expect(abs(boss_ch5[2] - 25.0) < 0.001 and abs(boss_ch5[3] - 75.0) < 0.001, "boss slot curve should normalize room type and use default config")
	print("  [OK] enemy slot curves config")


func _test_ai_profile_config() -> void:
	AIProfiles.reload()
	var melee: Dictionary = AIProfiles.get_profile("patrol_guard")
	_expect(abs(float(melee.get("w_damage", 0.0)) - 10.0) < 0.001, "patrol guard alias should resolve to melee chase profile")
	var stone_bow: Dictionary = AIProfiles.get_profile("stone_bow")
	_expect(bool(stone_bow.get("can_ranged_attack", false)), "stone bow ranged flag should come from config")
	_expect(abs(float(stone_bow.get("w_deploy_bonus", 0.0)) - 14.0) < 0.001, "stone bow deploy bonus should come from config")
	_expect(abs(float(AIProfiles.get_tuning_value("pull_base_bonus", 0.0)) - 8.0) < 0.001, "ai tuning should load global pull base bonus from config")
	_expect(abs(float(AIProfiles.get_tuning_value("approach_progress_floor", 0.0)) - 0.25) < 0.001, "ai tuning should load approach progress floor from config")
	var fallback: Dictionary = AIProfiles.get_profile("unknown_profile")
	_expect(abs(float(fallback.get("wait_score", 0.0)) - (-10.0)) < 0.001, "unknown ai profile should fall back to default config profile")
	var raw := _load_json("res://resources/combat/ai_profiles.json")
	var errors := BalanceConfigValidator.validate_ai_profiles(raw)
	_expect(errors.is_empty(), "ai profile config should pass validator")
	var invalid := {
		"default_profile": "melee_chase",
		"aliases": {"patrol_guard": "melee_chase"},
		"tuning": {"pull_base_bonus": "bad"},
		"profiles": {
			"melee_chase": {"w_damage": 10.0}
		}
	}
	var invalid_errors := BalanceConfigValidator.validate_ai_profiles(invalid)
	_expect(_contains_error(invalid_errors, "ai_profiles.tuning.pull_base_bonus should be number"), "ai profile validator should reject bad tuning types")
	print("  [OK] ai profile config")


func _test_gem_effect_level_config() -> void:
	var raw := _load_json("res://resources/gems/gem_effect_levels.json")
	var errors := BalanceConfigValidator.validate_gem_effect_levels(raw)
	_expect(errors.is_empty(), "gem effect levels config should pass validator")
	var invalid := {
		Constants.SLOT_RED: {
			"poison": {
				"1": {"hit_poison_stacks": "bad"},
			},
		},
		Constants.SLOT_BLUE: {},
		Constants.SLOT_BLACK: {},
	}
	var invalid_errors := BalanceConfigValidator.validate_gem_effect_levels(invalid)
	_expect(_contains_error(invalid_errors, "hit_poison_stacks should be number"), "gem effect levels validator should reject wrong field types")
	print("  [OK] gem effect levels config")


func _test_status_config() -> void:
	StatusConfig.reload()
	_expect(StatusConfig.default_stacks("poison", 0) == 1, "status config should load poison default stacks")
	_expect(StatusConfig.default_duration("poison", 0) == 2, "status config should load poison default duration")
	_expect(StatusConfig.default_duration("rooted", 0) == 2, "status config should load rooted default duration")
	_expect(StatusConfig.default_level("counter_mark", 0) == 1, "status config should load counter mark default level")
	_expect(abs(StatusConfig.float_value("vulnerable", "damage_taken_mult", 0.0) - 1.5) < 0.001, "status config should load vulnerable damage multiplier")
	_expect(abs(StatusConfig.float_value("weak", "attack_damage_mult", 0.0) - 0.75) < 0.001, "status config should load weak attack multiplier")
	_expect(StatusConfig.int_value("slowed", "min_move_points", 0) == 1, "status config should load slowed min move points")
	var raw := _load_json("res://resources/combat/status_config.json")
	var errors := BalanceConfigValidator.validate_status_config(raw)
	_expect(errors.is_empty(), "status config should pass validator")
	var invalid := {
		"poison": {"default_stacks": "bad"},
		"weak": {"attack_damage_mult": "bad"},
	}
	var invalid_errors := BalanceConfigValidator.validate_status_config(invalid)
	_expect(_contains_error(invalid_errors, "status_config.poison.default_stacks should be number"), "status config validator should reject wrong field types")
	_expect(_contains_error(invalid_errors, "status_config.weak.attack_damage_mult should be number"), "status config validator should reject wrong multiplier field types")
	print("  [OK] status config")


func _test_unit_and_hazard_balance_config() -> void:
	var reg := _registry()
	if reg == null:
		return
	var raw_combat_config := _load_json("res://resources/combat/combat_config.json")
	var combat_config_errors := BalanceConfigValidator.validate_combat_config(raw_combat_config)
	_expect(combat_config_errors.is_empty(), "combat config should pass validator")
	var invalid_combat_config := raw_combat_config.duplicate(true)
	invalid_combat_config["overload_ai_control_base_percent"] = "bad"
	var invalid_combat_config_errors := BalanceConfigValidator.validate_combat_config(invalid_combat_config)
	_expect(_contains_error(invalid_combat_config_errors, "combat_config.overload_ai_control_base_percent should be number"), "combat config validator should reject bad overload ai percent types")
	var raw_unit_defs := _load_json("res://resources/units/unit_defs.json")
	var unit_def_errors := BalanceConfigValidator.validate_unit_balance_defs(raw_unit_defs)
	_expect(unit_def_errors.is_empty(), "unit defs balance config should pass validator")
	var invalid_unit_defs := {
		"unit_stone_bow_guard": {
			"balance": {
				"hold_position_bonus": "bad",
			},
		},
	}
	var invalid_unit_def_errors := BalanceConfigValidator.validate_unit_balance_defs(invalid_unit_defs)
	_expect(_contains_error(invalid_unit_def_errors, "unit_defs.unit_stone_bow_guard.balance.hold_position_bonus should be number"), "unit balance validator should reject bad stone bow score types")
	var patrol := UnitState.from_def("patrol_test", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i.ZERO, reg.get_unit_def("unit_patrol_guard"))
	_expect(PatrolGuardRules.rampage_move_points(patrol) == 4, "patrol guard rampage move bonus should come from unit config")
	var stone_bow_range := StoneBowGuardRules.attack_range_for(Vector2i.ZERO, [])
	_expect(stone_bow_range == 4, "stone bow deployed range should come from unit config")
	_expect(abs(float(reg.get_unit_balance_value("unit_stone_bow_guard", "hold_position_bonus", 0.0)) - 120.0) < 0.001, "stone bow hold-position score should come from unit config")
	_expect(abs(float(reg.get_unit_balance_value("unit_stone_bow_guard", "line_progress_bonus_per_step", 0.0)) - 28.0) < 0.001, "stone bow line-progress score should come from unit config")
	var fission := UnitState.from_def("fission_test", "unit_fission_slime", Constants.TEAM_ENEMY, Vector2i.ZERO, reg.get_unit_def("unit_fission_slime"))
	_expect(abs(FissionSlimeRules.split_stat_ratio(fission) - 0.5) < 0.001, "fission slime split ratio should come from unit config")
	_expect(CombatConfig.spike_damage() == 5, "spike damage should come from combat config")
	_expect(CombatConfig.attack_range() == 3, "attack range should come from combat config")
	_expect(CombatConfig.extract_range() == 3, "extract range should come from combat config")
	_expect(CombatConfig.insert_range() == 3, "insert range should come from combat config")
	_expect(CombatConfig.trigger_range() == 3, "trigger range should come from combat config")
	_expect(CombatConfig.split_attack_range() == 1, "split attack range should come from combat config")
	_expect(abs(CombatConfig.split_damage_redirect_ratio() - 0.5) < 0.001, "split redirect ratio should come from combat config")
	_expect(CombatConfig.split_surround_radius() == 1, "split surround radius should come from combat config")
	_expect(abs(CombatConfig.split_black_stat_ratio() - 0.3) < 0.001, "split black stat ratio should come from combat config")
	_expect(CombatConfig.explosion_damage() == 12, "explosion damage should come from combat config")
	_expect(CombatConfig.explosion_radius() == 1, "explosion radius should come from combat config")
	_expect(CombatConfig.charge_explode_dash_range() == 2, "charge explode dash range should come from combat config")
	_expect(CombatConfig.knockback_collision_damage() == -1, "knockback collision damage should come from combat config")
	_expect(CombatConfig.barrel_hp() == 3, "barrel hp should come from combat config")
	_expect(CombatConfig.barrel_explosion_damage() == 10, "barrel explosion damage should come from combat config")
	_expect(CombatConfig.overload_gem_op_damage_amount() == 3, "overload gem backlash should come from combat config")
	_expect(CombatConfig.overload_ai_control_min_chapter() == 1, "overload ai min chapter should come from combat config")
	_expect(CombatConfig.overload_ai_control_max_chapter() == 45, "overload ai max chapter should come from combat config")
	_expect(abs(CombatConfig.overload_ai_control_base_percent() - 75.0) < 0.001, "overload ai base percent should come from combat config")
	_expect(CombatConfig.overload_ai_control_chapter_baseline() == 3, "overload ai chapter baseline should come from combat config")
	_expect(abs(CombatConfig.overload_ai_control_chapter_penalty() - 1.0) < 0.001, "overload ai chapter penalty should come from combat config")
	_expect(CombatConfig.overload_ai_control_gem_baseline() == 9, "overload ai gem baseline should come from combat config")
	_expect(abs(CombatConfig.overload_ai_control_gem_penalty() - 7.0) < 0.001, "overload ai gem penalty should come from combat config")
	_expect(abs(CombatConfig.overload_ai_control_min_probability() - 0.0) < 0.001, "overload ai min probability should come from combat config")
	_expect(abs(CombatConfig.overload_ai_control_max_probability() - 0.95) < 0.001, "overload ai max probability should come from combat config")
	_expect(abs(CombatConfig.grass_grow_chance() - 0.2) < 0.001, "grass grow chance should come from combat config")
	print("  [OK] unit and hazard balance config")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)


func _registry() -> Node:
	var reg: Node = Engine.get_main_loop().root.get_node_or_null("DataRegistry")
	_expect(reg != null, "DataRegistry autoload should be available during balance config test")
	return reg


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


func _key_set(ids: Array[String]) -> Dictionary:
	var result := {}
	for id in ids:
		result[str(id)] = true
	return result


func _contains_error(errors: Array[String], snippet: String) -> bool:
	for err in errors:
		if err.find(snippet) >= 0:
			return true
	return false
