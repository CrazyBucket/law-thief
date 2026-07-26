extends SceneTree

const AIProfiles = preload("res://scripts/rules/ai_profiles.gd")
const AdventureConfigValidator = preload("res://scripts/services/adventure_config_validator.gd")
const BalanceConfigValidator = preload("res://scripts/services/balance_config_validator.gd")
const BehaviorRegistry = preload("res://scripts/services/behavior_registry.gd")
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
	_test_gem_pool_config()
	_test_economy_config_schema()
	_test_reward_offer_config()
	_test_battle_reward_ui_config()
	_test_adventure_progression_config()
	_test_player_copy_numeric_tokens()
	_test_enemy_slot_curves_config()
	_test_ai_profile_config()
	_test_gem_effect_level_config()
	_test_status_config()
	_test_primary_content_catalogs()
	_test_encounter_catalog_config()
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
	_expect(not shop_weights.has("boss"), "shop relic pool should exclude boss rarity")
	var normal_weights: Dictionary = reg.get_relic_source_weights("normal_chest")
	_expect(not normal_weights.has("boss"), "normal combat relic pool should exclude boss rarity")
	var elite_weights: Dictionary = reg.get_relic_source_weights("elite_combat")
	_expect(abs(float(elite_weights.get("rare", 0.0)) - 40.0) < 0.001, "elite relic rare weight should come from config")
	_expect(float(elite_weights.get("boss", 0.0)) > 0.0, "elite relic pool should allow boss rarity")
	_expect(float(reg.get_relic_source_weights("large_chest").get("boss", 0.0)) > 0.0, "boss reward relic pool should allow boss rarity")
	for source in ["shop", "normal_chest"]:
		for relic_id in reg.get_relic_pool(source):
			_expect(reg.get_relic_rarity(relic_id) != "boss", "%s should not expose boss relic %s" % [source, relic_id])
	var source_ids: Array[String] = reg.get_relic_source_ids()
	_expect("shop" in source_ids and "normal_chest" in source_ids, "relic source ids should come from config")
	_expect(reg.get_relic_source_weights("missing_relic_source").is_empty(), "unknown relic sources should not fall back to common-only weights")
	_expect(reg.get_relic_pool("missing_relic_source").is_empty(), "unknown relic sources should not produce a relic pool")
	var missing_relic_offer: Array[String] = reg.roll_relic_offer("test_missing_relic_source", "missing_relic_source", 2)
	_expect(missing_relic_offer == ["relic_placeholder", "relic_placeholder"], "unknown relic sources should produce placeholder relic offers")
	var raw := _load_json("res://resources/adventure/relic_source_weights.json")
	var errors := BalanceConfigValidator.validate_relic_source_weights(raw)
	_expect(errors.is_empty(), "relic source weights should pass strict validation")
	var invalid := raw.duplicate(true)
	invalid["shop"]["rare"] = -1.0
	invalid["shop"]["unknown_rarity"] = 1.0
	var invalid_errors := BalanceConfigValidator.validate_relic_source_weights(invalid)
	_expect(_contains_error(invalid_errors, "relic_source_weights.shop.rare should be non-negative"), "relic source validator should reject negative weights")
	_expect(_contains_error(invalid_errors, "relic_source_weights.shop.unknown_rarity is unknown"), "relic source validator should reject unknown rarity keys")
	print("  [OK] relic source weights config")


func _test_gem_pool_config() -> void:
	var reg := _registry()
	if reg == null:
		return
	var raw := _load_json("res://resources/gems/gem_pools.json")
	var known_tags: Dictionary = {}
	for gem_id in reg.get_gem_ids():
		known_tags[reg.get_gem_tag(gem_id)] = true
	var errors := BalanceConfigValidator.validate_gem_pools(raw, known_tags)
	_expect(errors.is_empty(), "gem pools should pass strict validation")
	_expect(reg.get_gem_pool_tier("gem_explosion") == 1, "explosion pool tier should remain unchanged")
	_expect(reg.get_gem_rarity("gem_explosion") == "uncommon", "explosion rarity should be upgraded")
	_expect(reg.get_gem_rarity("gem_light") == "uncommon", "light rarity should be tier 2")
	_expect(reg.get_gem_pool_tier("gem_light") == 2, "light should remain pool tier 2")
	for tier_three_rarity_gem in ["gem_split", "gem_counter", "gem_echo"]:
		_expect(reg.get_gem_rarity(tier_three_rarity_gem) == "rare", "%s rarity should be tier 3" % tier_three_rarity_gem)
	_expect(reg.get_gem_pool_tier("gem_split") == 2, "split pool tier should remain unchanged")
	_expect(reg.get_gem_pool_tier("gem_counter") == 2, "counter pool tier should remain unchanged")
	_expect(reg.get_gem_pool_tier("gem_echo") == 3, "echo pool tier should remain unchanged")
	for tier_one_gem in ["gem_poison", "gem_gravity", "gem_conductive", "gem_fire", "gem_ice"]:
		_expect(reg.get_gem_pool_tier(tier_one_gem) == 1, "%s should be pool tier 1" % tier_one_gem)
		_expect(reg.get_gem_rarity(tier_one_gem) == "common", "%s rarity should be tier 1" % tier_one_gem)
	var invalid := raw.duplicate(true)
	invalid.erase("global")
	invalid["normal_chest"]["source_tier"] = 0
	invalid["normal_chest"]["tag_weights"]["missing_tag"] = 1.0
	invalid["teaching_boosts"].erase("chapter_3")
	var invalid_errors := BalanceConfigValidator.validate_gem_pools(invalid, known_tags)
	_expect(_contains_error(invalid_errors, "gem_pools.global missing"), "gem pool validator should require the global source")
	_expect(_contains_error(invalid_errors, "normal_chest.source_tier should be a positive integer"), "gem pool validator should reject invalid source tiers")
	_expect(_contains_error(invalid_errors, "normal_chest.tag_weights.missing_tag is unknown"), "gem pool validator should reject unknown tags")
	_expect(_contains_error(invalid_errors, "teaching_boosts.chapter_3 missing"), "gem pool validator should require every teaching chapter")
	_expect(reg.get_gem_pool_source_tier("missing_gem_source") == 0, "unknown gem sources should not receive a numeric source-tier fallback")
	print("  [OK] gem pool config")


func _test_economy_config_schema() -> void:
	var raw := _load_json("res://resources/adventure/economy_config.json")
	var errors := AdventureConfigValidator.validate_economy_config(raw)
	_expect(errors.is_empty(), "economy config should pass strict validation")
	var invalid := raw.duplicate(true)
	invalid["combat_rewards"].erase("elite")
	invalid["shop_prices"]["gem"]["common"]["min"] = -1
	invalid["shop_prices"]["relic"]["rare"] = {"min": 60, "max": 40}
	invalid["legacy_reward"] = 9
	var invalid_errors := AdventureConfigValidator.validate_economy_config(invalid)
	_expect(_contains_error(invalid_errors, "economy_config.combat_rewards.elite missing"), "economy config validator should require every combat tier")
	_expect(_contains_error(invalid_errors, "economy_config.shop_prices.gem.common.min should be non-negative"), "economy config validator should reject negative prices")
	_expect(_contains_error(invalid_errors, "economy_config.shop_prices.relic.rare.min should not exceed max"), "economy config validator should reject inverted price ranges")
	_expect(_contains_error(invalid_errors, "economy_config.legacy_reward is unknown"), "economy config validator should reject stale fields")
	print("  [OK] economy config schema")


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


func _test_battle_reward_ui_config() -> void:
	var reg := _registry()
	if reg == null:
		return
	var raw := _load_json("res://resources/ui/battle_reward_ui_config.json")
	var errors := AdventureConfigValidator.validate_battle_reward_ui_config(raw)
	_expect(errors.is_empty(), "battle reward ui config should pass validator")
	var settlement: Dictionary = reg.get_battle_reward_ui_layout("settlement")
	_expect(float(settlement.get("panel_width", 0)) > 0.0, "settlement panel width should come from config")
	var relic_card: Dictionary = reg.get_battle_reward_card_layout("relic")
	_expect(float(relic_card.get("height", 0)) > 0.0, "relic card height should come from config")
	var invalid := {
		"settlement": {
			"canvas_layer": 78,
			"panel_width": 0,
		},
		"reward_overlay": {
			"canvas_layer": 80,
			"content_separation": 16,
			"card_separation": 20,
			"scroll_max_width": 440,
			"scroll_viewport_ratio": 1.5,
			"scroll_hover_pad": 12,
			"scroll_bar_reserve": 18,
			"scroll_edge_pad": 8,
			"action_button_width": 160,
			"action_button_height": 40,
			"fallback_viewport_width": 1280,
		},
		"cards": {},
	}
	var invalid_errors := AdventureConfigValidator.validate_battle_reward_ui_config(invalid)
	_expect(_contains_error(invalid_errors, "battle_reward_ui_config.settlement.panel_width should be positive"), "ui config should reject non-positive layout values")
	_expect(_contains_error(invalid_errors, "battle_reward_ui_config.reward_overlay.scroll_viewport_ratio should be in (0, 1]"), "ui config should reject invalid viewport ratio")
	print("  [OK] battle reward ui config")


func _test_adventure_progression_config() -> void:
	var reg := _registry()
	if reg == null:
		return
	var raw := _load_json("res://resources/adventure/adventure_progression.json")
	var event_defs := _load_json("res://resources/adventure/event_defs.json")
	var errors := AdventureConfigValidator.validate_adventure_progression(
		raw,
		_key_set(reg.get_encounter_ids()),
		_key_set(event_defs.keys())
	)
	_expect(errors.is_empty(), "adventure progression config should pass strict cross-catalog validation")
	var invalid := raw.duplicate(true)
	invalid["chapter_count"] = 0
	invalid["map"]["room_rules"]["ELITE_COMBAT"].erase("weight")
	invalid["map"]["event_pool"].append("missing_event")
	invalid["combat_encounters"]["NORMAL_COMBAT"].append("missing_encounter")
	var invalid_errors := AdventureConfigValidator.validate_adventure_progression(
		invalid,
		_key_set(reg.get_encounter_ids()),
		_key_set(event_defs.keys())
	)
	_expect(_contains_error(invalid_errors, "chapter_count should be a positive integer"), "progression config should reject invalid chapter counts")
	_expect(_contains_error(invalid_errors, "ELITE_COMBAT.weight should be a positive integer"), "progression config should require room weights")
	_expect(_contains_error(invalid_errors, "event_pool references unknown id: missing_event"), "progression config should reject unknown events")
	_expect(_contains_error(invalid_errors, "NORMAL_COMBAT references unknown id: missing_encounter"), "progression config should reject unknown encounters")
	var boss_mismatch := raw.duplicate(true)
	boss_mismatch["boss_encounters"].pop_back()
	var boss_mismatch_errors := AdventureConfigValidator.validate_adventure_progression(boss_mismatch)
	_expect(_contains_error(boss_mismatch_errors, "boss_encounters should contain one entry per chapter"), "progression config should require one boss per chapter")
	print("  [OK] adventure progression config")


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
	_expect(
		_contains_error(BalanceConfigValidator.validate_relic_numeric_refs({}), "relic_numeric_refs should not be empty"),
		"relic numeric refs should reject an empty catalog"
	)
	var raw_relic_defs := _load_json("res://resources/relics/relic_defs.json")
	var relic_errors := BalanceConfigValidator.validate_relic_defs(raw_relic_defs, raw_refs)
	_expect(relic_errors.is_empty(), "relic defs should pass amount-ref validator")
	_expect(
		_contains_error(BalanceConfigValidator.validate_relic_defs({}, raw_refs), "relic_defs should not be empty"),
		"relic defs should reject an empty catalog"
	)
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
				{"modifier": "arc_damage_bonus", "value": 1},
				{"modifier": "attack_miss_chance", "value_ref": "relic_crowbar_armor_break_bonus"},
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
	var incomplete_defs := raw_relic_defs.duplicate(true)
	incomplete_defs["relic_prism"].erase("base_weight")
	incomplete_defs["relic_phase_wrench"]["rarity"] = "legendary"
	incomplete_defs["relic_chaos_launcher"]["pool_types"] = ["missing_pool"]
	var incomplete_def_errors := BalanceConfigValidator.validate_relic_defs(incomplete_defs, raw_refs)
	_expect(_contains_error(incomplete_def_errors, "relic_defs.relic_prism.base_weight missing"), "relic defs should require authored base weights")
	_expect(_contains_error(incomplete_def_errors, "relic_defs.relic_phase_wrench.rarity is unknown"), "relic defs should reject unknown rarity")
	_expect(_contains_error(incomplete_def_errors, "relic_defs.relic_chaos_launcher.pool_types contains unknown value"), "relic defs should reject unknown pool types")
	_expect(_contains_error(invalid_def_errors, "relic_defs.broken_relic.effects[1].amount_ref unit mismatch: relic_cracked_amulet_shield expected hp got shield"), "relic defs should reject wrong amount-ref units")
	_expect(_contains_error(invalid_def_errors, "relic_defs.broken_relic.effects[2].amount_ref unknown: missing_ref"), "relic defs should reject unknown amount refs")
	_expect(_contains_error(invalid_def_errors, "relic_defs.broken_relic.effects[3].value should use value_ref in authored config"), "relic defs should reject authored inline modifier values")
	_expect(_contains_error(invalid_def_errors, "relic_defs.broken_relic.effects[4].value_ref kind mismatch: relic_crowbar_armor_break_bonus expected ratio got flat"), "relic defs should reject wrong modifier ref kinds")
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
	var raw := _load_json("res://resources/adventure/enemy_slot_curves.json")
	var invalid := raw.duplicate(true)
	invalid["UNKNOWN_ROOM"] = invalid["NORMAL_COMBAT"].duplicate(true)
	invalid["NORMAL_COMBAT"]["1"][0] = -1.0
	invalid["ELITE_COMBAT"]["bad_chapter"] = [1.0, 1.0, 1.0, 1.0]
	var invalid_errors := BalanceConfigValidator.validate_enemy_slot_curves(invalid)
	_expect(_contains_error(invalid_errors, "enemy_slot_curves.UNKNOWN_ROOM is unknown"), "enemy slot curve validator should reject unknown room types")
	_expect(_contains_error(invalid_errors, "NORMAL_COMBAT.1[0] should be non-negative"), "enemy slot curve validator should reject negative weights")
	_expect(_contains_error(invalid_errors, "ELITE_COMBAT.bad_chapter should be a positive chapter or default"), "enemy slot curve validator should reject malformed chapter keys")
	print("  [OK] enemy slot curves config")


func _test_ai_profile_config() -> void:
	AIProfiles.reload()
	var melee: Dictionary = AIProfiles.get_profile("patrol_guard")
	_expect(abs(float(melee.get("w_damage", 0.0)) - 10.0) < 0.001, "patrol guard alias should resolve to melee chase profile")
	var stone_bow: Dictionary = AIProfiles.get_profile("stone_bow")
	_expect(bool(stone_bow.get("can_ranged_attack", false)), "stone bow ranged flag should come from config")
	_expect(abs(float(stone_bow.get("w_deploy_bonus", 0.0)) - 14.0) < 0.001, "stone bow deploy bonus should come from config")
	_expect(abs(float(AIProfiles.get_tuning_value("pull_base_bonus")) - 8.0) < 0.001, "ai tuning should load global pull base bonus from config")
	_expect(abs(float(AIProfiles.get_tuning_value("approach_progress_floor")) - 0.25) < 0.001, "ai tuning should load approach progress floor from config")
	var path_defaults := AIProfiles.get_path_defaults()
	_expect(abs(float(path_defaults["spike_damage_weight"]) - 0.4) < 0.001, "generic path weights should come from config")
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
	var incomplete := raw.duplicate(true)
	incomplete["profile_defaults"].erase("w_status")
	incomplete["tuning"].erase("pull_base_bonus")
	incomplete["path_defaults"].erase("base_step_cost")
	incomplete["profiles"]["melee_chase"]["misspelled_weight"] = 1.0
	var incomplete_errors := BalanceConfigValidator.validate_ai_profiles(incomplete)
	_expect(_contains_error(incomplete_errors, "ai_profiles.profile_defaults.w_status missing"), "ai profile defaults should define every profile field")
	_expect(_contains_error(incomplete_errors, "ai_profiles.tuning.pull_base_bonus missing"), "ai tuning should define every global field")
	_expect(_contains_error(incomplete_errors, "ai_profiles.path_defaults.base_step_cost missing"), "generic path defaults should define every path field")
	_expect(_contains_error(incomplete_errors, "misspelled_weight is unknown"), "ai profile overrides should reject unknown fields")
	print("  [OK] ai profile config")


func _test_gem_effect_level_config() -> void:
	var raw := _load_json("res://resources/gems/gem_effect_levels.json")
	var errors := BalanceConfigValidator.validate_gem_effect_levels(raw)
	_expect(errors.is_empty(), "gem effect levels config should pass validator")
	var missing_group: Dictionary = raw.duplicate(true)
	(missing_group[Constants.SLOT_BLACK] as Dictionary).erase("counter")
	var missing_group_errors := BalanceConfigValidator.validate_gem_effect_levels(missing_group)
	_expect(_contains_error(missing_group_errors, "gem_effect_levels.black.counter missing"), "gem effect levels validator should require every slot/tag group")
	var missing_level: Dictionary = raw.duplicate(true)
	var blue_light: Dictionary = (missing_level[Constants.SLOT_BLUE] as Dictionary)["light"]
	blue_light.erase("2")
	var missing_level_errors := BalanceConfigValidator.validate_gem_effect_levels(missing_level)
	_expect(_contains_error(missing_level_errors, "gem_effect_levels.blue.light.2 missing"), "gem effect levels validator should require levels 1 through 3")
	var missing_field: Dictionary = raw.duplicate(true)
	var blue_light_level_three: Dictionary = ((missing_field[Constants.SLOT_BLUE] as Dictionary)["light"] as Dictionary)["3"]
	blue_light_level_three.erase("reflect_power")
	var missing_field_errors := BalanceConfigValidator.validate_gem_effect_levels(missing_field)
	_expect(_contains_error(missing_field_errors, "gem_effect_levels.blue.light.3.reflect_power missing"), "gem effect levels validator should require complete rows for every group")
	var missing_blue_runtime_fields: Dictionary = raw.duplicate(true)
	(((missing_blue_runtime_fields[Constants.SLOT_BLUE] as Dictionary)["gravity"] as Dictionary)["1"] as Dictionary).erase("redirect_radius")
	var missing_blue_runtime_errors := BalanceConfigValidator.validate_gem_effect_levels(missing_blue_runtime_fields)
	_expect(_contains_error(missing_blue_runtime_errors, "gem_effect_levels.blue.gravity.1.redirect_radius missing"), "blue gravity should author its redirect radius")
	var foreign_field: Dictionary = raw.duplicate(true)
	var red_explosion_level_one: Dictionary = ((foreign_field[Constants.SLOT_RED] as Dictionary)["explosion"] as Dictionary)["1"]
	red_explosion_level_one["fog_radius"] = 1
	var foreign_field_errors := BalanceConfigValidator.validate_gem_effect_levels(foreign_field)
	_expect(_contains_error(foreign_field_errors, "gem_effect_levels.red.explosion.1.fog_radius is not allowed for red:explosion"), "gem effect levels validator should reject fields from another group")
	var extra_level: Dictionary = raw.duplicate(true)
	var red_counter: Dictionary = (extra_level[Constants.SLOT_RED] as Dictionary)["counter"]
	red_counter["4"] = (red_counter["3"] as Dictionary).duplicate(true)
	var extra_level_errors := BalanceConfigValidator.validate_gem_effect_levels(extra_level)
	_expect(_contains_error(extra_level_errors, "gem_effect_levels.red.counter.4 is unknown; expected levels 1, 2, 3"), "gem effect levels validator should reject undeclared stack levels")
	var missing_counter_semantic: Dictionary = raw.duplicate(true)
	var red_counter_level_two: Dictionary = (((missing_counter_semantic[Constants.SLOT_RED] as Dictionary)["counter"] as Dictionary)["2"] as Dictionary)
	red_counter_level_two.erase("retaliation_with_tags")
	var missing_counter_semantic_errors := BalanceConfigValidator.validate_gem_effect_levels(missing_counter_semantic)
	_expect(_contains_error(missing_counter_semantic_errors, "gem_effect_levels.red.counter.2.retaliation_with_tags missing"), "red counter should require direct retaliation semantics")
	var legacy_counter_sentinel: Dictionary = raw.duplicate(true)
	var legacy_counter_level: Dictionary = (((legacy_counter_sentinel[Constants.SLOT_RED] as Dictionary)["counter"] as Dictionary)["2"] as Dictionary)
	legacy_counter_level["mark_stacks"] = 2
	var legacy_counter_sentinel_errors := BalanceConfigValidator.validate_gem_effect_levels(legacy_counter_sentinel)
	_expect(_contains_error(legacy_counter_sentinel_errors, "gem_effect_levels.red.counter.2.mark_stacks is unknown"), "red counter should reject the obsolete level sentinel")
	var invalid_counter_duration: Dictionary = raw.duplicate(true)
	var invalid_counter_level: Dictionary = (((invalid_counter_duration[Constants.SLOT_RED] as Dictionary)["counter"] as Dictionary)["1"] as Dictionary)
	invalid_counter_level["mark_duration"] = 0
	var invalid_counter_duration_errors := BalanceConfigValidator.validate_gem_effect_levels(invalid_counter_duration)
	_expect(_contains_error(invalid_counter_duration_errors, "gem_effect_levels.red.counter.1.mark_duration should be positive"), "red counter mark duration should be positive")
	var missing_split_semantic: Dictionary = raw.duplicate(true)
	var blue_split_level_two: Dictionary = (((missing_split_semantic[Constants.SLOT_BLUE] as Dictionary)["split"] as Dictionary)["2"] as Dictionary)
	blue_split_level_two.erase("redirect_mode")
	var missing_split_semantic_errors := BalanceConfigValidator.validate_gem_effect_levels(missing_split_semantic)
	_expect(_contains_error(missing_split_semantic_errors, "gem_effect_levels.blue.split.2.redirect_mode missing"), "blue split should require an explicit redirect mode")
	var legacy_split_sentinel: Dictionary = raw.duplicate(true)
	var legacy_blue_split_level: Dictionary = (((legacy_split_sentinel[Constants.SLOT_BLUE] as Dictionary)["split"] as Dictionary)["3"] as Dictionary)
	legacy_blue_split_level["spawn_temp_clone"] = true
	var legacy_split_sentinel_errors := BalanceConfigValidator.validate_gem_effect_levels(legacy_split_sentinel)
	_expect(_contains_error(legacy_split_sentinel_errors, "gem_effect_levels.blue.split.3.spawn_temp_clone is unknown"), "blue split should reject the obsolete spawn sentinel")
	var invalid_split_ratio: Dictionary = raw.duplicate(true)
	var invalid_split_ratio_level: Dictionary = (((invalid_split_ratio[Constants.SLOT_BLUE] as Dictionary)["split"] as Dictionary)["1"] as Dictionary)
	invalid_split_ratio_level["redirect_ratio"] = 0.0
	var invalid_split_ratio_errors := BalanceConfigValidator.validate_gem_effect_levels(invalid_split_ratio)
	_expect(_contains_error(invalid_split_ratio_errors, "gem_effect_levels.blue.split.1.redirect_ratio should be positive"), "blue split redirect ratio should be positive")
	var inactive_split_knob: Dictionary = raw.duplicate(true)
	var inactive_split_level: Dictionary = (((inactive_split_knob[Constants.SLOT_BLUE] as Dictionary)["split"] as Dictionary)["1"] as Dictionary)
	inactive_split_level["temp_clone_duration"] = 1
	var inactive_split_knob_errors := BalanceConfigValidator.validate_gem_effect_levels(inactive_split_knob)
	_expect(_contains_error(inactive_split_knob_errors, "gem_effect_levels.blue.split.1.temp_clone_duration should be zero when temp_clone_count is zero"), "inactive blue split temp-clone knobs should stay zero")
	var invalid_active_split_knob: Dictionary = raw.duplicate(true)
	var invalid_active_split_level: Dictionary = (((invalid_active_split_knob[Constants.SLOT_BLUE] as Dictionary)["split"] as Dictionary)["3"] as Dictionary)
	invalid_active_split_level["temp_clone_hp"] = 0
	var invalid_active_split_knob_errors := BalanceConfigValidator.validate_gem_effect_levels(invalid_active_split_knob)
	_expect(_contains_error(invalid_active_split_knob_errors, "gem_effect_levels.blue.split.3.temp_clone_hp should be positive when temp_clone_count is positive"), "active blue split temp-clone knobs should be positive")
	var invalid_clone_count: Dictionary = raw.duplicate(true)
	var invalid_clone_count_level: Dictionary = (((invalid_clone_count[Constants.SLOT_BLACK] as Dictionary)["split"] as Dictionary)["1"] as Dictionary)
	invalid_clone_count_level["clone_count"] = 0
	var invalid_clone_count_errors := BalanceConfigValidator.validate_gem_effect_levels(invalid_clone_count)
	_expect(_contains_error(invalid_clone_count_errors, "gem_effect_levels.black.split.1.clone_count should be positive"), "black split clone count should be positive")
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
	var invalid_values := {
		Constants.SLOT_RED: {
			"explosion": {
				"1": {"blast_pattern": "circle", "center_damage_ratio": -0.1, "splash_base_attack_ratio": 1.1},
			},
			"split": {
				"1": {"damage_ratio": 1.1, "light_direction_offsets": [0, 0]},
			},
			"ice": {
				"1": {"hit_slowed_stacks": 1, "slowed_min_move_points": -1},
			},
		},
		Constants.SLOT_BLUE: {
			"gravity": {
				"1": {"deflect_chance": -0.1, "pillar_pull_steps": 1.5},
			},
			"echo": {
				"1": {"echo_tag_count": 0, "first_tag_strength": 0},
			},
			"unknown_tag": {"1": {}},
		},
		Constants.SLOT_BLACK: {
			"arc": {
				"1": {"strike_radius": 1.5, "strike_count": 0, "strike_all_targets": false},
				"2": {"strike_radius": 1, "strike_count": 3, "strike_all_targets": true},
				"3": {"strike_radius": 1, "strike_all_targets": false},
			},
			"fire": {
				"1": {"death_fire_radius": 1.5, "death_fire_count": 0, "death_fire_duration": 0},
			},
			"ice": {
				"1": {"death_radius": 1.5, "slowed_stacks": 0, "slowed_min_move_points": -1, "freeze_duration": -1},
			},
			"echo": {
				"1": {"echo_tag_count": 1, "first_tag_repeat_count": 0},
			},
		},
		"unknown_slot": {},
	}
	var invalid_value_errors := BalanceConfigValidator.validate_gem_effect_levels(invalid_values)
	_expect(_contains_error(invalid_value_errors, "blast_pattern should be one of cross, square"), "gem effect levels validator should reject invalid enum values")
	_expect(_contains_error(invalid_value_errors, "center_damage_ratio should be in [0, 1]"), "gem effect levels validator should reject non-positive explosion ratios")
	_expect(_contains_error(invalid_value_errors, "splash_base_attack_ratio should be in [0, 1]"), "gem effect levels validator should reject explosion ratios above one")
	_expect(_contains_error(invalid_value_errors, "damage_ratio should be in [0, 1]"), "gem effect levels validator should reject out-of-range ratios")
	_expect(_contains_error(invalid_value_errors, "light_direction_offsets should not contain duplicate offsets"), "gem effect levels validator should reject duplicate split directions")
	_expect(_contains_error(invalid_value_errors, "deflect_chance should be in [0, 1]"), "gem effect levels validator should reject out-of-range chances")
	_expect(_contains_error(invalid_value_errors, "pillar_pull_steps should be an integer"), "gem effect levels validator should reject fractional discrete values")
	_expect(_contains_error(invalid_value_errors, "echo_tag_count should be positive"), "gem effect levels validator should reject zero echo pick counts")
	_expect(_contains_error(invalid_value_errors, "first_tag_strength should be positive"), "gem effect levels validator should reject zero blue echo strength")
	_expect(_contains_error(invalid_value_errors, "first_tag_repeat_count should be positive"), "gem effect levels validator should reject zero black echo repeat counts")
	_expect(_contains_error(invalid_value_errors, "slowed_min_move_points should be non-negative"), "gem effect levels validator should reject negative movement floors")
	_expect(_contains_error(invalid_value_errors, "strike_radius should be an integer"), "gem effect levels validator should reject fractional strike radii")
	_expect(_contains_error(invalid_value_errors, "strike_count should be positive"), "gem effect levels validator should reject zero strike counts")
	_expect(_contains_error(invalid_value_errors, "strike_count should be omitted for all-target targeting"), "gem effect levels validator should reject all-target count sentinels")
	_expect(_contains_error(invalid_value_errors, "strike_count missing for counted targeting"), "gem effect levels validator should require counted-target strike counts")
	_expect(_contains_error(invalid_value_errors, "death_radius should be an integer"), "gem effect levels validator should reject fractional death radii")
	_expect(_contains_error(invalid_value_errors, "freeze_duration should be non-negative"), "gem effect levels validator should reject negative freeze durations")
	_expect(_contains_error(invalid_value_errors, "gem_effect_levels.red.ice.1.freeze_if_target_slowed missing"), "gem effect levels validator should require complete red-ice rows")
	_expect(_contains_error(invalid_value_errors, "death_fire_radius should be an integer"), "gem effect levels validator should reject fractional fire radii")
	_expect(_contains_error(invalid_value_errors, "death_fire_count should be positive"), "gem effect levels validator should reject zero death-fire counts")
	_expect(_contains_error(invalid_value_errors, "death_fire_duration should be positive"), "gem effect levels validator should reject zero death-fire durations")
	_expect(_contains_error(invalid_value_errors, "gem_effect_levels.black.fire.1.prefer_occupied_cells missing"), "gem effect levels validator should require complete black-fire rows")
	_expect(_contains_error(invalid_value_errors, "gem_effect_levels.blue.unknown_tag is unknown"), "gem effect levels validator should reject unknown tags")
	_expect(_contains_error(invalid_value_errors, "gem_effect_levels.unknown_slot is unknown"), "gem effect levels validator should reject unknown slots")
	print("  [OK] gem effect levels config")


func _test_status_config() -> void:
	StatusConfig.reload()
	_expect(StatusConfig.default_stacks("poison") == 1, "status config should load poison default stacks")
	_expect(StatusConfig.default_duration("poison") == 2, "status config should load poison default duration")
	_expect(StatusConfig.default_duration("rooted") == 2, "status config should load rooted default duration")
	_expect(StatusConfig.default_duration("counter_mark") == 1, "status config should load counter mark duration")
	_expect(abs(StatusConfig.float_value("vulnerable", "damage_taken_mult") - 1.5) < 0.001, "status config should load vulnerable damage multiplier")
	_expect(abs(StatusConfig.float_value("weak", "attack_damage_mult") - 0.75) < 0.001, "status config should load weak attack multiplier")
	_expect(StatusConfig.int_value("slowed", "min_move_points") == 1, "status config should load slowed min move points")
	_expect(StatusConfig.int_value("lawless", "attack_bonus") == 1, "status config should load lawless attack bonus")
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
	var incomplete := raw.duplicate(true)
	incomplete.erase("rooted")
	incomplete["armor"].erase("default_duration")
	incomplete["slowed"]["min_move_points"] = -1
	incomplete["lawless"].erase("attack_bonus")
	var incomplete_errors := BalanceConfigValidator.validate_status_config(incomplete)
	_expect(_contains_error(incomplete_errors, "status_config.rooted missing"), "status config validator should require every registered status")
	_expect(_contains_error(incomplete_errors, "status_config.armor.default_duration missing"), "status config validator should require explicit default fields")
	_expect(_contains_error(incomplete_errors, "status_config.slowed.min_move_points should be a non-negative integer"), "status config validator should reject negative movement floors")
	_expect(_contains_error(incomplete_errors, "status_config.lawless.attack_bonus missing"), "status config should require the lawless attack bonus")
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
	invalid_combat_config["legacy_fire_death_count"] = 5
	invalid_combat_config["ice_death_radius"] = 1
	invalid_combat_config["arc_hit_damage"] = 8
	invalid_combat_config["star_relocation_max_distance"] = 1.5
	invalid_combat_config["star_relocation_squeeze_damage_per_tile"] = -1
	invalid_combat_config["water_move_cost_extra"] = -0.5
	var invalid_combat_config_errors := BalanceConfigValidator.validate_combat_config(invalid_combat_config)
	_expect(_contains_error(invalid_combat_config_errors, "combat_config.overload_ai_control_base_percent should be number"), "combat config validator should reject bad overload ai percent types")
	_expect(_contains_error(invalid_combat_config_errors, "combat_config.legacy_fire_death_count is unknown"), "combat config validator should reject stale or misspelled keys")
	_expect(_contains_error(invalid_combat_config_errors, "combat_config.ice_death_radius is unknown"), "combat config validator should reject the removed shared ice radius")
	_expect(_contains_error(invalid_combat_config_errors, "combat_config.arc_hit_damage is unknown"), "combat config validator should reject the unused fixed arc-hit value")
	_expect(_contains_error(invalid_combat_config_errors, "star_relocation_max_distance should be a positive integer"), "combat config validator should reject fractional relocation radii")
	_expect(_contains_error(invalid_combat_config_errors, "star_relocation_squeeze_damage_per_tile should be a non-negative integer"), "combat config validator should reject negative squeeze damage")
	_expect(_contains_error(invalid_combat_config_errors, "water_move_cost_extra should be non-negative"), "combat config validator should reject negative water movement cost")
	var raw_unit_defs := _load_json("res://resources/units/unit_defs.json")
	var unit_def_errors := BalanceConfigValidator.validate_unit_defs(raw_unit_defs)
	_expect(unit_def_errors.is_empty(), "unit defs balance config should pass validator")
	var invalid_unit_defs := {
		"unit_stone_bow_guard": {
			"balance": {
				"hold_position_bonus": "bad",
				"misspelled_score": 1,
			},
		},
		"unit_fission_slime": {
			"behavior_id": "fission_slime",
			"balance": {
				"split_stat_ratio": 0.5,
				"slam_push_steps": 1,
				"trample_damage": 3,
			},
		},
	}
	var invalid_unit_def_errors := BalanceConfigValidator.validate_unit_defs(invalid_unit_defs)
	_expect(_contains_error(invalid_unit_def_errors, "unit_defs.unit_stone_bow_guard.balance.hold_position_bonus should be number"), "unit balance validator should reject bad stone bow score types")
	_expect(_contains_error(invalid_unit_def_errors, "unit_defs.unit_stone_bow_guard.balance.misspelled_score is unknown"), "unit balance validator should reject unknown numeric knobs")
	_expect(_contains_error(invalid_unit_def_errors, "unit_defs.unit_fission_slime.balance.trample_collision_damage missing"), "fission balance schema should require collision damage")
	var patrol := UnitState.from_def("patrol_test", "unit_patrol_guard", Constants.TEAM_ENEMY, Vector2i.ZERO, reg.get_unit_def("unit_patrol_guard"))
	_expect(PatrolGuardRules.rampage_move_points(patrol) == 3, "patrol guard rampage move bonus should come from unit config")
	var stone_bow_range := StoneBowGuardRules.attack_range_for(Vector2i.ZERO, [])
	_expect(stone_bow_range == 4, "stone bow deployed range should come from unit config")
	_expect(abs(float(reg.get_unit_balance_value("unit_stone_bow_guard", "hold_position_bonus", 0.0)) - 120.0) < 0.001, "stone bow hold-position score should come from unit config")
	_expect(abs(float(reg.get_unit_balance_value("unit_stone_bow_guard", "line_progress_bonus_per_step", 0.0)) - 28.0) < 0.001, "stone bow line-progress score should come from unit config")
	var fission := UnitState.from_def("fission_test", "unit_fission_slime", Constants.TEAM_ENEMY, Vector2i.ZERO, reg.get_unit_def("unit_fission_slime"))
	_expect(abs(FissionSlimeRules.split_stat_ratio(fission) - 0.5) < 0.001, "fission slime split ratio should come from unit config")
	_expect(FissionSlimeRules.trample_damage(fission) == 3, "fission trample skill damage should come from unit config")
	_expect(FissionSlimeRules.trample_collision_damage(fission) == 1, "fission trample collision damage should come from unit config")
	_expect(FissionSlimeRules.trample_total_damage(fission) == 4, "fission trample total should compose configured damage components")
	_expect(CombatConfig.spike_damage() == 5, "spike damage should come from combat config")
	_expect(CombatConfig.attack_range() == 3, "attack range should come from combat config")
	_expect(CombatConfig.extract_range() == 3, "extract range should come from combat config")
	_expect(CombatConfig.insert_range() == 3, "insert range should come from combat config")
	_expect(CombatConfig.trigger_range() == 3, "trigger range should come from combat config")
	_expect(CombatConfig.split_attack_range() == 1, "split attack range should come from combat config")
	var split_blue_lv1: Dictionary = reg.get_gem_effect_level_def("split", Constants.SLOT_BLUE, 1)
	var split_black_lv1: Dictionary = reg.get_gem_effect_level_def("split", Constants.SLOT_BLACK, 1)
	_expect(abs(float(split_blue_lv1.get("redirect_ratio", 0.0)) - 0.5) < 0.001, "split redirect ratio should come from blue split level data")
	_expect(int(split_blue_lv1.get("redirect_radius", 0)) == 1, "split redirect radius should come from blue split level data")
	_expect(abs(float(split_black_lv1.get("stat_ratio", 0.0)) - 0.3) < 0.001, "split clone ratio should come from black split level data")
	_expect(CombatConfig.explosion_damage() == 12, "explosion damage should come from combat config")
	_expect(CombatConfig.explosion_radius() == 1, "explosion radius should come from combat config")
	_expect(CombatConfig.charge_explode_dash_range() == 2, "charge explode dash range should come from combat config")
	_expect(CombatConfig.knockback_collision_damage() == -1, "knockback collision damage should come from combat config")
	_expect(CombatConfig.star_relocation_max_distance() == 2, "star relocation radius should come from combat config")
	_expect(CombatConfig.star_relocation_squeeze_damage_per_tile() == 1, "squeeze damage per tile should come from combat config")
	_expect(CombatConfig.barrel_hp() == 3, "barrel hp should come from combat config")
	_expect(CombatConfig.barrel_explosion_damage() == 10, "barrel explosion damage should come from combat config")
	_expect(CombatConfig.barrel_explosion_radius() == 1, "barrel explosion radius should come from combat config")
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
	_expect(CombatConfig.toxic_smoke_duration() == 1, "toxic smoke duration should come from combat config")
	_expect(CombatConfig.poison_puddle_duration() == 2, "poison puddle duration should come from combat config")
	_expect(abs(CombatConfig.water_move_cost_extra() - 1.0) < 0.001, "water movement cost should come from combat config")
	print("  [OK] unit and hazard balance config")


func _test_primary_content_catalogs() -> void:
	var reg := _registry()
	if reg == null:
		return
	var raw_gem_defs := _load_json("res://resources/gems/gem_defs.json")
	var known_profiles := _profile_id_set(raw_gem_defs)
	var gem_errors := BalanceConfigValidator.validate_gem_defs(raw_gem_defs, known_profiles)
	_expect(gem_errors.is_empty(), "gem definition catalog should pass complete schema validation")
	_expect(reg.get_gem_ids() == _sorted_string_keys(raw_gem_defs), "runtime gem catalog ids should exactly match gem_defs.json")
	var invalid_gem_defs := raw_gem_defs.duplicate(true)
	invalid_gem_defs["gem_explosion"].erase("symbol")
	invalid_gem_defs["gem_explosion"]["legacy_damage"] = 9
	invalid_gem_defs["gem_explosion"]["ability_profiles"]["unit_red_active"] = "missing_profile"
	invalid_gem_defs["gem_poison"]["tag"] = "explosion"
	var invalid_gem_errors := BalanceConfigValidator.validate_gem_defs(invalid_gem_defs, known_profiles)
	_expect(_contains_error(invalid_gem_errors, "gem_defs.gem_explosion.symbol missing"), "gem catalog validator should reject missing authored fields")
	_expect(_contains_error(invalid_gem_errors, "gem_defs.gem_explosion.legacy_damage is unknown"), "gem catalog validator should reject stale fields")
	_expect(_contains_error(invalid_gem_errors, "references unknown profile: missing_profile"), "gem catalog validator should reject unknown effect profiles")
	_expect(_contains_error(invalid_gem_errors, "tag duplicates"), "gem catalog validator should reject duplicate semantic tags")
	var raw_unit_defs := _load_json("res://resources/units/unit_defs.json")
	var unit_errors := BalanceConfigValidator.validate_unit_defs(
		raw_unit_defs,
		_key_set(reg.get_gem_ids()),
		_key_set(BehaviorRegistry.get_behavior_ids()),
		_known_unit_ai_profile_ids()
	)
	_expect(unit_errors.is_empty(), "unit definition catalog should pass complete schema validation")
	_expect(reg.get_unit_def_ids() == _sorted_string_keys(raw_unit_defs), "runtime unit catalog ids should exactly match unit_defs.json")
	var allowed_empty_unit_defs := raw_unit_defs.duplicate(true)
	allowed_empty_unit_defs["unit_patrol_guard"]["allow_empty_gems"] = true
	var allowed_empty_unit_errors := BalanceConfigValidator.validate_unit_defs(
		allowed_empty_unit_defs,
		_key_set(reg.get_gem_ids()),
		_key_set(BehaviorRegistry.get_behavior_ids()),
		_known_unit_ai_profile_ids()
	)
	_expect(allowed_empty_unit_errors.is_empty(), "unit definitions should accept a boolean allow_empty_gems marker")
	for unit_id in raw_unit_defs.keys():
		_expect(
			_sorted_string_keys(reg.get_unit_def(str(unit_id))) == _sorted_string_keys(raw_unit_defs[unit_id]),
			"runtime unit %s should not inherit hidden catalog fields" % unit_id
		)
	var invalid_unit_defs := raw_unit_defs.duplicate(true)
	invalid_unit_defs["unit_player"].erase("armor")
	invalid_unit_defs["unit_patrol_guard"]["balance"].erase("charge_bonus")
	invalid_unit_defs["unit_stone_bow_guard"]["behavior_id"] = "missing_behavior"
	invalid_unit_defs["unit_bomb_rat"]["ai_profile_id"] = "missing_ai_profile"
	invalid_unit_defs["unit_fission_slime"]["slots"][2]["gem_id"] = "missing_gem"
	invalid_unit_defs["unit_patrol_guard"]["allow_empty_gems"] = "yes"
	var invalid_unit_errors := BalanceConfigValidator.validate_unit_defs(
		invalid_unit_defs,
		_key_set(reg.get_gem_ids()),
		_key_set(BehaviorRegistry.get_behavior_ids()),
		_known_unit_ai_profile_ids()
	)
	_expect(_contains_error(invalid_unit_errors, "unit_defs.unit_player.armor missing"), "unit catalog validator should reject missing base stats")
	_expect(_contains_error(invalid_unit_errors, "unit_defs.unit_patrol_guard.balance.charge_bonus missing"), "unit catalog validator should require behavior-owned balance fields")
	_expect(_contains_error(invalid_unit_errors, "references unknown behavior: missing_behavior"), "unit catalog validator should reject unknown behavior ids")
	_expect(_contains_error(invalid_unit_errors, "references unknown profile: missing_ai_profile"), "unit catalog validator should reject unknown AI profile ids")
	_expect(_contains_error(invalid_unit_errors, "references unknown gem: missing_gem"), "unit catalog validator should reject unknown initial gems")
	_expect(_contains_error(invalid_unit_errors, "allow_empty_gems should be bool"), "unit catalog validator should reject non-boolean empty-gem markers")
	print("  [OK] primary content catalogs")


func _test_encounter_catalog_config() -> void:
	var reg := _registry()
	if reg == null:
		return
	var visible_ids: Array = reg.get_encounter_ids()
	var authored_ids := _json_basenames("res://resources/encounters/")
	_expect(visible_ids == authored_ids, "visible encounter catalog should exactly match production JSON files")
	var all_ids: Array = reg.get_encounter_ids(true)
	for fixture_id in ["bomb_rat_test", "patrol_guard_test", "stone_bow_test", "fission_slime_test"]:
		_expect(fixture_id in all_ids, "debug encounter catalog should load %s fixture" % fixture_id)
		_expect(fixture_id not in visible_ids, "%s fixture should stay hidden from production catalog" % fixture_id)
	var raw := _load_json("res://resources/encounters/tutorial_001.json")
	var errors := AdventureConfigValidator.validate_encounter_def(
		"tutorial_001",
		raw,
		_unit_def_map(reg),
		_key_set(reg.get_tile_ids()),
		_key_set(reg.get_entity_ids()),
		_key_set(reg.get_overlay_ids()),
		_key_set(reg.get_gem_ids()),
		Constants.BOARD_SIZE
	)
	_expect(errors.is_empty(), "tutorial encounter should pass catalog validation")
	var allowed_empty := raw.duplicate(true)
	allowed_empty["enemies"][0]["allow_empty_gems"] = true
	allowed_empty["random_enemies"] = [{
		"pos": [7, 7],
		"candidates": [{"def_id": "unit_patrol_guard", "weight": 1, "allow_empty_gems": true}],
	}]
	var allowed_empty_errors := AdventureConfigValidator.validate_encounter_def(
		"tutorial_001",
		allowed_empty,
		_unit_def_map(reg),
		_key_set(reg.get_tile_ids()),
		_key_set(reg.get_entity_ids()),
		_key_set(reg.get_overlay_ids()),
		_key_set(reg.get_gem_ids()),
		Constants.BOARD_SIZE
	)
	_expect(allowed_empty_errors.is_empty(), "encounter enemies and random candidates should accept boolean allow_empty_gems markers")
	var invalid := raw.duplicate(true)
	invalid["legacy_enemy_damage"] = 3
	invalid["enemies"][0]["def_id"] = "missing_unit"
	invalid["enemies"][0]["allow_empty_gems"] = "yes"
	invalid["random_enemies"] = [{
		"pos": [7, 7],
		"candidates": [{"def_id": "unit_patrol_guard", "allow_empty_gems": 1}],
	}]
	invalid["entities"][0]["pos"] = [99, 99]
	var invalid_errors := AdventureConfigValidator.validate_encounter_def(
		"tutorial_001",
		invalid,
		_unit_def_map(reg),
		_key_set(reg.get_tile_ids()),
		_key_set(reg.get_entity_ids()),
		_key_set(reg.get_overlay_ids()),
		_key_set(reg.get_gem_ids()),
		Constants.BOARD_SIZE
	)
	_expect(_contains_error(invalid_errors, "legacy_enemy_damage is unknown"), "encounter validator should reject stale fields")
	_expect(_contains_error(invalid_errors, "references unknown unit: missing_unit"), "encounter validator should reject unknown unit ids")
	_expect(_contains_error(invalid_errors, "outside 8x8 board"), "encounter validator should reject out-of-bounds positions")
	_expect(_contains_error(invalid_errors, "allow_empty_gems should be bool"), "encounter validator should reject non-boolean empty-gem markers")
	_expect(reg.create_battle_state("bomb_rat_test", 3801) != null, "hidden encounter fixtures should remain directly loadable by tests")
	print("  [OK] encounter catalog config")


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


func _key_set(ids: Array) -> Dictionary:
	var result := {}
	for id in ids:
		result[str(id)] = true
	return result


func _sorted_string_keys(value: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key in value.keys():
		result.append(str(key))
	result.sort()
	return result


func _profile_id_set(gem_defs: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for raw_def in gem_defs.values():
		if not raw_def is Dictionary:
			continue
		var profiles: Variant = (raw_def as Dictionary).get("ability_profiles", {})
		if not profiles is Dictionary:
			continue
		for profile_id in (profiles as Dictionary).values():
			result[str(profile_id)] = true
	return result


func _known_unit_ai_profile_ids() -> Dictionary:
	var result := _key_set(AIProfiles.get_profile_ids())
	result["player"] = true
	result["training_dummy"] = true
	return result


func _unit_def_map(reg: Node) -> Dictionary:
	var result: Dictionary = {}
	for unit_id in reg.get_unit_def_ids():
		result[str(unit_id)] = reg.get_unit_def(str(unit_id))
	return result


func _json_basenames(dir_path: String) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return result
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			result.append(file_name.get_basename())
		file_name = dir.get_next()
	dir.list_dir_end()
	result.sort()
	return result


func _contains_error(errors: Array[String], snippet: String) -> bool:
	for err in errors:
		if err.find(snippet) >= 0:
			return true
	return false
