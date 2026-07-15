extends Node

const BoardMapGenerator = preload("res://scripts/map/board_map_generator.gd")
const AdventureConfigValidator = preload("res://scripts/services/adventure_config_validator.gd")
const BalanceConfigValidator = preload("res://scripts/services/balance_config_validator.gd")
const BehaviorRegistry = preload("res://scripts/services/behavior_registry.gd")
const CombatConfig = preload("res://scripts/core/combat_config.gd")
const AIProfiles = preload("res://scripts/rules/ai_profiles.gd")
const AdventureProgressionConfig = preload("res://scripts/core/adventure_progression_config.gd")
const NumericTextResolver = preload("res://scripts/services/numeric_text_resolver.gd")
const EncounterEnemyResolver = preload("res://scripts/services/encounter_enemy_resolver.gd")
const EncounterCatalogLoader = preload("res://scripts/services/encounter_catalog_loader.gd")
const BattleStateFactory = preload("res://scripts/battle/battle_state_factory.gd")

const ABILITY_UNIT_RED_ACTIVE := "unit_red_active"
const ABILITY_ENEMY_RED_ACTION := "enemy_red_action"
const ABILITY_BLUE_TURN_START := "blue_turn_start"
const ABILITY_BLUE_DAMAGED := "blue_damaged"
const ABILITY_BLUE_MOVE_THROUGH := "blue_move_through"
const ABILITY_BLACK_DEATH := "black_death"
const ABILITY_TILE_ACTIVE := "tile_active"
const ABILITY_TILE_TURN_START := "tile_turn_start"
const ABILITY_ATTACK_BONUS := "attack_bonus"
const ABILITY_ARMOR_BONUS := "armor_bonus"

const _GEM_EFFECT_LEVEL_PERCENT_FIELDS := {
	"deflect_chance": true,
	"rebound_chance": true,
	"damage_ratio": true,
	"reflect_damage_ratio": true,
	"stat_ratio": true,
	"followup_ratio": true,
	"redirect_ratio": true,
	"temp_clone_stat_ratio": true,
}

var _gem_effect_profiles: Dictionary = {}
var _gem_effect_levels: Dictionary = {}
var _gem_defs: Dictionary = {}
var _gem_pools: Dictionary = {}
var _gem_teaching_boosts: Dictionary = {}
var _relic_numeric_refs: Dictionary = {}
var _relic_source_weights: Dictionary = {}
var _reward_offer_config: Dictionary = {}
var _battle_reward_ui_config: Dictionary = {}
var _enemy_slot_curves: Dictionary = {}
var _unit_defs: Dictionary = {}
var _encounters: Dictionary = {}
var _relic_defs: Dictionary = {}
var _uid_counter: int = 0


func _ready() -> void:
	_register_gem_effect_profiles()
	_load_gem_effect_levels_from_json()
	_load_gem_defs_from_json()
	_load_gem_pools_from_json()
	_load_relic_numeric_refs_from_json()
	_load_relic_source_weights_from_json()
	_validate_shop_pools_source_refs()
	_load_reward_offer_config_from_json()
	_load_battle_reward_ui_config_from_json()
	_load_enemy_slot_curves_from_json()
	_load_unit_defs_from_json()
	_load_encounters_from_json()
	_validate_adventure_progression_refs()
	_load_relic_defs_from_json()


func create_battle_state(encounter_id: String, seed_value: int = 0, room_id: String = "") -> GameState:
	var encounter: Dictionary = _encounters.get(encounter_id, {})
	var current_chapter := 1
	var pending_room_type := ""
	var adventure_svc: Node = Engine.get_main_loop().root.get_node_or_null("AdventureService")
	if adventure_svc != null:
		pending_room_type = str(adventure_svc.get("pending_room_type"))
	var run_svc: Node = Engine.get_main_loop().root.get_node_or_null("RunService")
	if run_svc != null and run_svc.has_method("get_current_chapter"):
		current_chapter = int(run_svc.call("get_current_chapter"))
	if encounter.is_empty():
		push_error("Encounter not found: %s" % encounter_id)
		return null
	_uid_counter = 0
	if seed_value != 0:
		# 外部显式提供种子（如单元测试、重放）：以此初始化 master seed
		RngService.start_run(seed_value)
	# 从 master seed 确定性衍生战斗种子，保证 SL 安全
	# master seed 不存在时（首次裸启）退化为时间戳，行为与旧逻辑一致
	var combat_seed := RngService.derive_combat_seed(encounter_id, room_id)
	RngService.reset_state(combat_seed, "combat:%s" % encounter_id)
	var state := BattleStateFactory.create_base_state(
		encounter_id,
		encounter.get("player_spawn", Vector2i(3, 2)),
		_unit_defs["unit_player"],
		RngService.get_seed(),
		Callable(self, "_next_uid")
	)
	var player := state.get_player()
	_apply_run_slot_overrides(player)
	_restore_run_player_state(state, player)
	for enemy_data in _resolve_encounter_enemies(encounter, encounter_id):
		var enemy_uid := _next_uid(enemy_data.get("def_id", "enemy"))
		var def: Dictionary = _unit_defs[enemy_data.get("def_id", "unit_bomb_rat")].duplicate(true)
		var base_slots: Array = def.get("slots", [])
		var spawn_gem_slots: Array = def.get("spawn_gem_slots", [])
		var restrict_spawn_gem_slots := def.has("spawn_gem_slots")
		var enemy_slot_budget := _resolve_enemy_slot_budget(current_chapter, pending_room_type, encounter_id, enemy_data, def)
		def["slots"] = []
		for slot_data in base_slots:
			var slot_entry: Dictionary = slot_data.duplicate(true)
			var slot_type := str(slot_entry.get("slot_type", ""))
			var should_roll_gem := not slot_entry.has("gem_id")
			if should_roll_gem and restrict_spawn_gem_slots:
				should_roll_gem = slot_type in spawn_gem_slots
			if should_roll_gem and enemy_slot_budget > 0:
				enemy_slot_budget -= 1
				var enemy_pool_source := _resolve_enemy_pool_source(current_chapter, pending_room_type)
				var roll_gem_id := roll_spawnable_gem_id("enemy_spawn_%s_%s_%s" % [encounter_id, enemy_uid, slot_type], [], enemy_pool_source, current_chapter)
				if not roll_gem_id.is_empty():
					slot_entry["gem_id"] = roll_gem_id
			def["slots"].append(slot_entry)
		var enemy := BattleStateFactory.add_enemy(
			state,
			enemy_data,
			def,
			enemy_uid,
			Callable(self, "_next_uid"),
			Callable(self, "create_gem_instance")
		)
		_apply_unit_spawn_variants(enemy, def)
	BoardMapGenerator.build(state, encounter)
	TileRules.sync_all_units_standing_ground(state)
	IntentSystem.refresh_all_intents(state)
	# 所有单位就位后建立 O(1) 占格索引（多格单位 footprint 一并注册）
	state.rebuild_occupancy()
	state.log("遭遇战开始: %s" % encounter_id)
	return state


func create_battle_state_from_editor_payload(encounter_id: String, encounter: Dictionary, seed_value: int = 0) -> GameState:
	if encounter.is_empty():
		push_error("Encounter payload is empty: %s" % encounter_id)
		return null
	_uid_counter = 0
	if seed_value != 0:
		RngService.start_run(seed_value)
	var combat_seed := int(encounter.get("floor_seed", RngService.derive_combat_seed(encounter_id, "")))
	RngService.reset_state(combat_seed, "combat:%s" % encounter_id)
	var player_spawn: Vector2i = encounter.get("player_spawn", Vector2i(3, 2))
	var state := BattleStateFactory.create_base_state(
		encounter_id,
		player_spawn,
		_unit_defs["unit_player"],
		combat_seed,
		Callable(self, "_next_uid")
	)
	for enemy_data in _resolve_encounter_enemies(encounter, encounter_id):
		var enemy_uid := _next_uid(str(enemy_data.get("def_id", "enemy")))
		var def_id := str(enemy_data.get("def_id", "unit_bomb_rat"))
		var enemy_def: Dictionary = get_unit_def(def_id)
		var slot_defs: Array = enemy_data.get("slots", enemy_def.get("slots", [])).duplicate(true)
		enemy_def["slots"] = slot_defs
		BattleStateFactory.add_enemy(
			state,
			enemy_data,
			enemy_def,
			enemy_uid,
			Callable(self, "_next_uid"),
			Callable(self, "create_gem_instance")
		)
	BoardMapGenerator.build(state, encounter)
	TileRules.sync_all_units_standing_ground(state)
	IntentSystem.refresh_all_intents(state)
	state.rebuild_occupancy()
	state.log("遭遇战开始: %s" % encounter_id)
	return state


func get_encounter_ids(include_hidden: bool = false) -> Array:
	var ids: Array[String] = []
	for encounter_id in _encounters.keys():
		var encounter: Dictionary = _encounters[encounter_id]
		if include_hidden or bool(encounter.get("catalog_visible", true)):
			ids.append(str(encounter_id))
	ids.sort()
	return ids


## Resolve hand-authored encounter composition after the combat RNG context is active.
## `enemies` are always included, one weighted `enemy_groups` entry is included as a
## whole formation, and every `random_enemies` slot rolls one candidate at its preset
## position. Keeping these rolls here makes reloads deterministic for a run/room seed.
func _resolve_encounter_enemies(encounter: Dictionary, encounter_id: String) -> Array[Dictionary]:
	return EncounterEnemyResolver.resolve(encounter, encounter_id, Callable(RngService, "weighted_pick"))


func next_runtime_uid(prefix: String) -> String:
	return _next_uid(prefix)


func has_unit_def(unit_def_id: String) -> bool:
	return _unit_defs.has(unit_def_id)


func get_unit_def(unit_def_id: String) -> Dictionary:
	return _unit_defs.get(unit_def_id, {}).duplicate(true)


func get_unit_balance_value(unit_def_id: String, key: String, fallback: Variant = null) -> Variant:
	var def: Dictionary = _unit_defs.get(unit_def_id, {})
	if def.is_empty():
		return fallback
	var balance: Variant = def.get("balance", {})
	if not balance is Dictionary:
		return fallback
	return (balance as Dictionary).get(key, fallback)


func get_unit_def_ids() -> Array[String]:
	var ids: Array[String] = []
	for unit_def_id in _unit_defs.keys():
		ids.append(str(unit_def_id))
	ids.sort()
	return ids


func has_gem_def(gem_id: String) -> bool:
	return _gem_defs.has(gem_id)


func get_gem_ids() -> Array[String]:
	var ids: Array[String] = []
	for gem_id in _gem_defs.keys():
		ids.append(str(gem_id))
	ids.sort()
	return ids


func get_tile_ids() -> Array[String]:
	return [
		Constants.TILE_FLOOR,
		Constants.TILE_WATER,
		Constants.TILE_PILLAR,
		Constants.TILE_ICE,
		Constants.TILE_GRASS,
		Constants.TILE_BUSH,
	]


func has_tile_id(tile_id: String) -> bool:
	return tile_id in get_tile_ids()


func get_unit_display_name(unit_def_id: String) -> String:
	var def: Dictionary = _unit_defs.get(unit_def_id, {})
	return _translate_key(str(def.get("display_name_key", "")), {}, unit_def_id)


func get_tile_display_name(tile_id: String) -> String:
	return _translate_key(_tile_display_name_key(tile_id), {}, tile_id)


func get_entity_ids() -> Array[String]:
	return [
		Constants.ENTITY_ROCK,
		Constants.ENTITY_PROP,
		Constants.ENTITY_SPIKE,
		Constants.ENTITY_BARREL,
	]


func has_entity_id(entity_id: String) -> bool:
	return entity_id in get_entity_ids()


func get_entity_display_name(entity_id: String) -> String:
	match entity_id:
		Constants.ENTITY_ROCK:
			return "Rock"
		Constants.ENTITY_PROP:
			return "Prop"
		Constants.ENTITY_SPIKE:
			return "Spike"
		Constants.ENTITY_BARREL:
			return "Barrel"
	return entity_id


func get_overlay_ids() -> Array[String]:
	return [
		Constants.TILE_MOD_POISON_FOG,
		Constants.TILE_MOD_FIRE,
		Constants.TILE_MOD_TOXIC_SMOKE,
		Constants.TILE_MOD_POISON_PUDDLE,
	]


func get_surface_overlay_ids() -> Array[String]:
	return [
		"tile_grass_sprouts",
		"tile_grass_patch",
		"tile_grass_tall",
		"tile_grass_thicket",
		"tile_bush_tall",
		"tile_bush_thicket",
	]


func get_surface_overlay_catalog() -> Array[Dictionary]:
	return [
		{"id": "tile_grass_sprouts", "tile_id": Constants.TILE_GRASS, "surface_variant": "sprouts", "label": "Grass Sprouts"},
		{"id": "tile_grass_patch", "tile_id": Constants.TILE_GRASS, "surface_variant": "patch", "label": "Grass Patch"},
		{"id": "tile_grass_tall", "tile_id": Constants.TILE_GRASS, "surface_variant": "tall", "label": "Tall Grass"},
		{"id": "tile_grass_thicket", "tile_id": Constants.TILE_GRASS, "surface_variant": "thicket", "label": "Grass Thicket"},
		{"id": "tile_bush_tall", "tile_id": Constants.TILE_BUSH, "surface_variant": "tall", "label": "Bush Tall"},
		{"id": "tile_bush_thicket", "tile_id": Constants.TILE_BUSH, "surface_variant": "thicket", "label": "Bush Thicket"},
	]


func has_overlay_id(overlay_id: String) -> bool:
	return overlay_id in get_overlay_ids()


func has_surface_overlay_id(surface_overlay_id: String) -> bool:
	return surface_overlay_id in get_surface_overlay_ids()


func get_overlay_display_name(overlay_id: String) -> String:
	match overlay_id:
		Constants.TILE_MOD_POISON_FOG:
			return "Poison Fog"
		Constants.TILE_MOD_FIRE:
			return "Fire"
		Constants.TILE_MOD_TOXIC_SMOKE:
			return "Toxic Smoke"
		Constants.TILE_MOD_POISON_PUDDLE:
			return "Poison Puddle"
	return overlay_id


func get_surface_overlay_display_name(surface_overlay_id: String) -> String:
	for entry in get_surface_overlay_catalog():
		if str(entry.get("id", "")) == surface_overlay_id:
			return str(entry.get("label", surface_overlay_id))
	return get_tile_display_name(surface_overlay_id)


func get_overlay_default_duration(overlay_id: String) -> int:
	match overlay_id:
		Constants.TILE_MOD_POISON_FOG:
			return CombatConfig.poison_fog_duration()
		Constants.TILE_MOD_FIRE:
			return CombatConfig.fire_duration()
		Constants.TILE_MOD_TOXIC_SMOKE:
			return CombatConfig.toxic_smoke_duration()
		Constants.TILE_MOD_POISON_PUDDLE:
			return CombatConfig.poison_puddle_duration()
	return 0


func get_gem_def(gem_ref: Variant) -> Dictionary:
	return _resolve_gem_def(gem_ref)


func get_gem_display_name(gem_ref: Variant) -> String:
	var def: Dictionary = _resolve_gem_def(gem_ref)
	var fallback: String = str(def.get("symbol", _gem_id_from_ref(gem_ref)))
	return _translate_key(str(def.get("display_name_key", "")), {}, fallback)


func get_gem_symbol(gem_ref: Variant) -> String:
	var def: Dictionary = _resolve_gem_def(gem_ref)
	return _translate_key(str(def.get("symbol_key", "")), {}, str(def.get("symbol", "◆")))


func get_gem_color(gem_ref: Variant) -> Color:
	return _resolve_gem_def(gem_ref).get("color", Color.WHITE)


func get_gem_rarity(gem_ref: Variant) -> String:
	return str(_resolve_gem_def(gem_ref).get("rarity", "common"))


func get_gem_tag(gem_ref: Variant) -> String:
	var def: Dictionary = _resolve_gem_def(gem_ref)
	var tag := str(def.get("tag", ""))
	if not tag.is_empty():
		return tag
	var profile := get_gem_ability_profile(gem_ref, ABILITY_UNIT_RED_ACTIVE)
	if not profile.is_empty():
		return profile
	return _gem_id_from_ref(gem_ref)


func get_gem_element(gem_ref: Variant) -> String:
	var element := str(_resolve_gem_def(gem_ref).get("element", ""))
	return element if not element.is_empty() else get_gem_tag(gem_ref)


func get_gem_pool_tier(gem_ref: Variant) -> int:
	return int(_resolve_gem_def(gem_ref)["pool_tier"])


func get_gem_max_stack_level(gem_ref: Variant) -> int:
	return int(_resolve_gem_def(gem_ref)["max_stack_level"])


func get_gem_combo_tags(gem_ref: Variant) -> Array[String]:
	var results: Array[String] = []
	for raw in _resolve_gem_def(gem_ref).get("combos", []):
		var tag := str(raw)
		if not tag.is_empty() and not tag in results:
			results.append(tag)
	return results


func get_gem_effect_level_def(tag: String, slot_type: String, level: int) -> Dictionary:
	if tag.is_empty() or slot_type.is_empty():
		return {}
	var slot_defs: Dictionary = _gem_effect_levels.get(slot_type, {})
	if slot_defs.is_empty():
		return {}
	var tag_defs: Dictionary = slot_defs.get(tag, {})
	if tag_defs.is_empty():
		return {}
	var current_level := maxi(1, level)
	while current_level >= 1:
		var entry: Variant = tag_defs.get(str(current_level), null)
		if entry is Dictionary:
			return (entry as Dictionary).duplicate(true)
		current_level -= 1
	return {}


func get_gem_effect_level_summary(tag: String, slot_type: String, level: int) -> String:
	if tag.is_empty() or slot_type.is_empty():
		return ""
	var slot_defs: Dictionary = _gem_effect_levels.get(slot_type, {})
	var tag_defs: Dictionary = slot_defs.get(tag, {})
	if tag_defs.is_empty():
		return ""
	var resolved_level := maxi(1, level)
	var level_def: Dictionary = {}
	while resolved_level >= 1:
		var entry: Variant = tag_defs.get(str(resolved_level), null)
		if entry is Dictionary:
			level_def = entry as Dictionary
			break
		resolved_level -= 1
	if level_def.is_empty():
		return ""
	return _translate_key(
		"gem.level.%s.%s" % [slot_type, tag],
		_gem_effect_level_summary_params(level_def, resolved_level),
		""
	)


func get_gem_rarity_label(gem_ref: Variant) -> String:
	var rarity: String = get_gem_rarity(gem_ref)
	return _translate_key("gem.rarity.%s" % rarity, {}, rarity.capitalize())


func get_gem_spawn_weight(gem_ref: Variant) -> float:
	var def: Dictionary = _resolve_gem_def(gem_ref)
	if def.has("spawn_weight"):
		return float(def.get("spawn_weight", 0.0))
	var global_pool := get_gem_pool_def("global")
	var rarity_weights: Dictionary = global_pool.get("rarity_weights", {})
	return float(rarity_weights.get(get_gem_rarity(gem_ref), 0.0))


func get_spawnable_gem_ids(allowed_rarities: Array = []) -> Array[String]:
	return get_spawnable_gem_ids_for_source("global", 99, allowed_rarities)


func get_gem_pool_def(source: String) -> Dictionary:
	if _gem_pools.has(source):
		return _gem_pools[source].duplicate(true)
	return {}


func has_gem_pool_source(source: String) -> bool:
	return _gem_pools.has(source)


func get_gem_pool_source_ids() -> Array[String]:
	var ids: Array[String] = []
	for source_id in _gem_pools.keys():
		ids.append(str(source_id))
	ids.sort()
	return ids


func get_gem_pool_source_tier(source: String) -> int:
	var pool := get_gem_pool_def(source)
	return int(pool.get("source_tier", 0))


func get_relic_source_weights(source: String) -> Dictionary:
	if _relic_source_weights.has(source):
		return (_relic_source_weights[source] as Dictionary).duplicate(true)
	return {}


func has_relic_source(source: String) -> bool:
	return _relic_source_weights.has(source)


func get_relic_source_ids() -> Array[String]:
	var ids: Array[String] = []
	for source_id in _relic_source_weights.keys():
		ids.append(str(source_id))
	ids.sort()
	return ids


func get_battle_reward_offer_config(room_type: String) -> Dictionary:
	var rewards: Dictionary = _reward_offer_config.get("battle_rewards", {})
	var key := room_type.to_upper()
	var raw_entry: Variant = rewards.get(key, rewards.get("default", {}))
	return (raw_entry as Dictionary).duplicate(true) if raw_entry is Dictionary else {}


func get_battle_relic_offer_source(room_type: String) -> String:
	return str(get_battle_reward_offer_config(room_type).get("relic_source", ""))


func get_battle_relic_offer_count(room_type: String) -> int:
	return maxi(0, int(get_battle_reward_offer_config(room_type).get("relic_offer_count", 0)))


func get_battle_reward_ui_layout(section: String) -> Dictionary:
	var section_value: Variant = _battle_reward_ui_config.get(section, {})
	return section_value if section_value is Dictionary else {}


func get_battle_reward_ui_number(section: String, key: String) -> float:
	return float(get_battle_reward_ui_layout(section).get(key, 0))


func get_battle_reward_card_layout(card_kind: String) -> Dictionary:
	var card_value: Variant = get_battle_reward_ui_layout("cards").get(card_kind, {})
	return card_value if card_value is Dictionary else {}


func get_enemy_total_slot_weights(room_type: String, chapter: int) -> Array[float]:
	var normalized_room_type := room_type.to_upper()
	var curve_key := normalized_room_type
	if curve_key in ["BOSS", "END"]:
		curve_key = "BOSS_COMBAT"
	elif curve_key.is_empty():
		curve_key = "NORMAL_COMBAT"
	var curve: Dictionary = _enemy_slot_curves.get(curve_key, {})
	if curve.is_empty():
		push_error("DataRegistry: enemy slot curve missing: %s" % curve_key)
		return []
	var chapter_key := str(maxi(1, chapter))
	var raw_weights: Variant = curve.get(chapter_key, curve.get("default", []))
	var weights: Array[float] = []
	if raw_weights is Array:
		for raw in raw_weights:
			weights.append(float(raw))
	return weights


func get_spawnable_gem_ids_for_source(source: String, chapter_tier: int = 99, allowed_rarities: Array = []) -> Array[String]:
	var results: Array[String] = []
	if not has_gem_pool_source(source):
		return results
	var pool_def := get_gem_pool_def(source)
	var source_tier := int(pool_def["source_tier"])
	var max_tier := mini(source_tier, maxi(1, chapter_tier))
	for gem_id in _gem_defs.keys():
		var def: Dictionary = _gem_defs[gem_id]
		if not def.get("allow_random_pool", true):
			continue
		if get_gem_pool_tier(gem_id) > max_tier:
			continue
		var rarity := str(def.get("rarity", "common"))
		if not allowed_rarities.is_empty() and not rarity in allowed_rarities:
			continue
		results.append(gem_id)
	results.sort()
	return results


func roll_spawnable_gem_id(domain: String = "gem_drop", allowed_rarities: Array = [], source: String = "global", chapter_tier: int = 99) -> String:
	if not has_gem_pool_source(source):
		return ""
	var pool_def := get_gem_pool_def(source)
	var rarity_weights: Dictionary = pool_def.get("rarity_weights", {})
	var allowed: Array = allowed_rarities.duplicate()
	if allowed.is_empty() and not rarity_weights.is_empty():
		for rarity in rarity_weights.keys():
			if float(rarity_weights[rarity]) > 0.0:
				allowed.append(str(rarity))
	var candidates := get_spawnable_gem_ids_for_source(source, chapter_tier, allowed)
	if candidates.is_empty():
		return ""
	var total_weight := 0.0
	var weighted: Array[Dictionary] = []
	var tag_weights: Dictionary = pool_def.get("tag_weights", {}).duplicate(true)
	_apply_teaching_boosts(tag_weights, chapter_tier)
	for gem_id in candidates:
		var weight := _gem_pool_weight(gem_id, rarity_weights, tag_weights)
		if weight <= 0.0:
			continue
		total_weight += weight
		weighted.append({"gem_id": gem_id, "limit": total_weight})
	if weighted.is_empty():
		return ""
	var roll := (float(RngService.roll_int(domain, 0, 1000000)) / 1000000.0) * total_weight
	for entry in weighted:
		if roll < float(entry.get("limit", 0.0)):
			return str(entry.get("gem_id", ""))
	return str(weighted.back().get("gem_id", ""))


# ═══════════════════════════════════════════════════════════════════════════
# 遗物定义查询
# ═══════════════════════════════════════════════════════════════════════════

func get_relic_def(relic_id: String) -> Dictionary:
	var raw_def: Variant = _relic_defs.get(relic_id, {})
	return (raw_def as Dictionary).duplicate(true) if raw_def is Dictionary else {}


func get_relic_rarity(relic_id: String) -> String:
	var def: Dictionary = _relic_defs.get(relic_id, {})
	return str(def["rarity"]) if not def.is_empty() else ""


func has_relic_def(relic_id: String) -> bool:
	return _relic_defs.has(relic_id)


func get_relic_ids() -> Array[String]:
	var ids: Array[String] = []
	for k in _relic_defs.keys():
		ids.append(str(k))
	return ids


func has_relic_numeric_ref(ref_id: String) -> bool:
	return _relic_numeric_refs.has(ref_id)


func get_relic_numeric_ref(ref_id: String, fallback: float = 0.0) -> float:
	if not _relic_numeric_refs.has(ref_id):
		return fallback
	return _numeric_ref_value(_relic_numeric_refs.get(ref_id), fallback)


func get_relic_numeric_ref_def(ref_id: String) -> Dictionary:
	if not _relic_numeric_refs.has(ref_id):
		return {}
	var raw_ref: Variant = _relic_numeric_refs.get(ref_id)
	if raw_ref is Dictionary:
		var ref_def := (raw_ref as Dictionary).duplicate(true)
		ref_def["value"] = _numeric_ref_value(raw_ref)
		return ref_def
	return {
		"value": _numeric_ref_value(raw_ref),
		"kind": "legacy",
		"unit": "",
	}


func get_relic_numeric_refs() -> Dictionary:
	return _relic_numeric_refs.duplicate(true)




func get_relic_unlock_condition_ids() -> Array[String]:
	var seen: Dictionary = {}
	var result: Array[String] = []
	for relic_id in _relic_defs.keys():
		var cond := str(_relic_defs[relic_id].get("unlock_condition", ""))
		if cond.is_empty() or seen.has(cond):
			continue
		seen[cond] = true
		result.append(cond)
	result.sort()
	return result


## 计算单个遗物在当前上下文下的最终权重
## weight_ctx 字段（均可选，缺省视为空/0）：
##   owned_gems    Array[String]  当前持有宝石 gem_id 列表
##   owned_relics  Array[String]  当前持有遗物 relic_id 列表
##   gem_colors    Array[String]  当前持有宝石颜色集合（"red"/"blue"/"black"）
##   total_slots   int            总槽位数
##   empty_slots   int            空置槽位数
##
## weight_rules 支持的 type：
##   has_gem            value=gem_id       持有指定宝石时乘 multiplier
##   has_gem_color      value="red/blue/black"  持有该颜色任意宝石时乘
##   has_relic          value=relic_id     持有指定遗物时乘
##   slot_count_gte     value=int          总槽位数 >= value 时乘
##   empty_slot_count_gte value=int        空置槽位数 >= value 时乘
func compute_relic_weight(relic_id: String, weight_ctx: Dictionary = {}) -> float:
	var def: Dictionary = _relic_defs.get(relic_id, {})
	if def.is_empty():
		return 0.0
	var weight := float(def["base_weight"])
	var rules: Array = def.get("weight_rules", [])
	if rules.is_empty() or weight_ctx.is_empty():
		return weight
	var owned_gems: Array = weight_ctx.get("owned_gems", [])
	var owned_relics: Array = weight_ctx.get("owned_relics", [])
	var gem_colors: Array = weight_ctx.get("gem_colors", [])
	var total_slots: int = int(weight_ctx.get("total_slots", 0))
	var empty_slots: int = int(weight_ctx.get("empty_slots", 0))
	for rule in rules:
		var rule_type := str(rule.get("type", ""))
		var multiplier := maxf(0.0, _resolve_relic_numeric_field(rule, "multiplier", 1.0))
		var matched := false
		match rule_type:
			"has_gem":
				matched = str(rule.get("value", "")) in owned_gems
			"has_gem_color":
				matched = str(rule.get("value", "")) in gem_colors
			"has_relic":
				matched = str(rule.get("value", "")) in owned_relics
			"slot_count_gte":
				matched = total_slots >= int(_resolve_relic_numeric_field(rule, "value", 0.0))
			"empty_slot_count_gte":
				matched = empty_slots >= int(_resolve_relic_numeric_field(rule, "value", 0.0))
		if matched:
			weight *= multiplier
	return weight


## 返回满足筛选条件的遗物 id 列表
## source: 来源标识（"normal_chest" / "elite_combat" / "large_chest" / "shop"）
## owned_ids: 当前局内已持有的遗物 id 集合（用于过滤 unique 遗物重复）
## unlock_flags: 当前已解锁的 flag 集合（String 数组）
func _relic_matches_source(def: Dictionary, source: String, source_weights: Dictionary) -> bool:
	var pool_types: Array = def["pool_types"]
	var allows_boss := source_weights.has("boss") and float(source_weights.get("boss", 0.0)) > 0.0
	if "global" in pool_types:
		match source:
			"shop":
				return true
			"normal_chest", "elite_combat", "large_chest":
				return true
			_:
				return true
	if source == "shop" and "shop_only" in pool_types:
		return true
	if allows_boss and "boss_drop" in pool_types:
		return true
	return false


func get_relic_pool(source: String, owned_ids: Array = [], unlock_flags: Array = []) -> Array[String]:
	var results: Array[String] = []
	var source_weights := get_relic_source_weights(source)
	if source_weights.is_empty():
		return results
	for relic_id in _relic_defs.keys():
		var def: Dictionary = _relic_defs[relic_id]
		if not _relic_matches_source(def, source, source_weights):
			continue
		# boss 遗物只在 source_weights 允许时出现
		var rarity := str(def["rarity"])
		if rarity == "boss" and not source_weights.has("boss"):
			continue
		if rarity == "boss" and float(source_weights.get("boss", 0.0)) <= 0.0:
			continue
		# 每局每种遗物只能拥有一次
		if relic_id in owned_ids:
			continue
		# 解锁条件检查
		var unlock_cond: String = str(def.get("unlock_condition", ""))
		if not unlock_cond.is_empty() and not unlock_cond in unlock_flags:
			continue
		results.append(relic_id)
	results.sort()
	return results


## 按来源概率表抽一个遗物 id；返回空串表示无可用候选
## owned_ids / unlock_flags 同 get_relic_pool
## weight_ctx: 动态权重上下文，传入空 Dict 则退化为等权，见 compute_relic_weight 注释
func roll_relic_for_source(
	domain: String,
	source: String,
	owned_ids: Array = [],
	unlock_flags: Array = [],
	weight_ctx: Dictionary = {}
) -> String:
	var source_rarity_weights := get_relic_source_weights(source)
	# 阶段一：按来源权重 roll 出稀有度
	var rarity_order: Array[String] = []
	var rarity_ws: Array[float] = []
	for rarity in source_rarity_weights.keys():
		var w := float(source_rarity_weights[rarity])
		if w > 0.0:
			rarity_order.append(str(rarity))
			rarity_ws.append(w)
	if rarity_order.is_empty():
		return ""
	var rolled_rarity: String = str(
		RngService.weighted_pick(domain + "_rarity", rarity_order, rarity_ws)
	)
	# 阶段二：从该稀有度的候选池里按动态权重选一个
	var pool := get_relic_pool(source, owned_ids, unlock_flags)
	var candidates: Array[String] = []
	var candidate_weights: Array[float] = []
	for rid in pool:
		if get_relic_rarity(rid) == rolled_rarity:
			candidates.append(rid)
			candidate_weights.append(compute_relic_weight(rid, weight_ctx))
	if candidates.is_empty():
		# 指定稀有度无货，降级到整个候选池按动态权重选
		if pool.is_empty():
			return ""
		var fallback_weights: Array[float] = []
		for rid in pool:
			fallback_weights.append(compute_relic_weight(rid, weight_ctx))
		return str(RngService.weighted_pick(domain + "_fallback", pool, fallback_weights))
	return str(RngService.weighted_pick(domain + "_pick", candidates, candidate_weights))


## 一次生成 count 个不重复的遗物 id（三选一 UI 用）
## 可用遗物不足时，剩余位置填充占位遗物；全部为占位时上层 UI 应给出提示
## weight_ctx 同 roll_relic_for_source
func roll_relic_offer(
	domain: String,
	source: String,
	count: int,
	owned_ids: Array = [],
	unlock_flags: Array = [],
	weight_ctx: Dictionary = {}
) -> Array[String]:
	var result: Array[String] = []
	var excluded: Array = owned_ids.duplicate()
	for i in range(count):
		var picked := roll_relic_for_source(
			domain + "_%d" % i, source, excluded, unlock_flags, weight_ctx
		)
		if picked.is_empty():
			result.append("relic_placeholder")
		else:
			result.append(picked)
			excluded.append(picked)
	return result


## 从指定来源 pool 抽出 count 个不重复的宝石 id（三选一奖励 UI 使用）
## source:        pool key，例如 "normal_chest" / "elite_combat" / "boss_reward"
## chapter_tier:  当前章节，用于过滤 pool_tier 上限
## exclude_ids:   本次排除的 gem_id（不重复约束）
## 返回 gem_id 数组；不足时以 "" 填充
func roll_gem_offer(
	domain: String,
	source: String,
	count: int,
	chapter_tier: int = 99,
	exclude_ids: Array = []
) -> Array[String]:
	var result: Array[String] = []
	if not has_gem_pool_source(source):
		for i in range(count):
			result.append("")
		return result
	var used_ids: Array = exclude_ids.duplicate()
	for i in range(count):
		var pool_def := get_gem_pool_def(source)
		var rarity_weights: Dictionary = pool_def.get("rarity_weights", {})
		var tag_weights: Dictionary = pool_def.get("tag_weights", {}).duplicate(true)
		_apply_teaching_boosts(tag_weights, chapter_tier)
		var allowed: Array = []
		if not rarity_weights.is_empty():
			for rarity in rarity_weights.keys():
				if float(rarity_weights[rarity]) > 0.0:
					allowed.append(str(rarity))
		var candidates := get_spawnable_gem_ids_for_source(source, chapter_tier, allowed)
		var filtered: Array[String] = []
		for gem_id in candidates:
			if not gem_id in used_ids:
				filtered.append(gem_id)
		if filtered.is_empty():
			result.append("")
			continue
		var total_weight := 0.0
		var weighted: Array[Dictionary] = []
		for gem_id in filtered:
			var weight := _gem_pool_weight(gem_id, rarity_weights, tag_weights)
			if weight <= 0.0:
				continue
			total_weight += weight
			weighted.append({"gem_id": gem_id, "limit": total_weight})
		if weighted.is_empty():
			result.append("")
			continue
		var roll := (float(RngService.roll_int("%s_%d" % [domain, i], 0, 1000000)) / 1000000.0) * total_weight
		var picked := str(weighted.back().get("gem_id", ""))
		for entry in weighted:
			if roll < float(entry.get("limit", 0.0)):
				picked = str(entry.get("gem_id", ""))
				break
		result.append(picked)
		if not picked.is_empty():
			used_ids.append(picked)
	return result


func create_gem_instance(uid: String, gem_id: String, gem_overrides: Dictionary = {}) -> GemState:
	return GemState.create(uid, gem_id, gem_overrides.duplicate(true))


func get_gem_ability_profile(gem_ref: Variant, ability_slot: String) -> String:
	var ability_profiles: Dictionary = _resolve_gem_def(gem_ref).get("ability_profiles", {})
	return str(ability_profiles.get(ability_slot, ""))


func get_gem_effect_description(gem_ref: Variant, slot_type: String, context: String) -> String:
	var parts: Array[String] = []
	for ability_slot in _ability_slots_for_display(slot_type, context):
		var profile_id := get_gem_ability_profile(gem_ref, ability_slot)
		if profile_id.is_empty():
			continue
		var text := _translate_ability_description(profile_id, ability_slot)
		if text.is_empty() or text in parts:
			continue
		parts.append(text)
	return "；".join(parts)


func get_enemy_red_intent_meta(gem_ref: Variant, damage: int) -> Dictionary:
	var profile: Dictionary = _effect_profile(get_gem_ability_profile(gem_ref, ABILITY_ENEMY_RED_ACTION))
	if profile.is_empty():
		return {"type": "wait", "preview": _translate_key("intent.wait", {}, "等待"), "damage": 0}
	var intent: Dictionary = profile.get("enemy_intent", {})
	if intent.is_empty():
		return {"type": "wait", "preview": _translate_key("intent.wait", {}, "等待"), "damage": 0}
	var params: Dictionary = intent.get("params", {}).duplicate(true)
	if not params.has("hits"):
		params["hits"] = 1
	var resolved_damage := int(intent.get("damage", 0))
	match str(intent.get("damage_mode", "fixed")):
		"base_attack":
			resolved_damage = damage
			params["damage"] = damage
		"cross_burst":
			resolved_damage = CombatConfig.explosion_cross_damage()
			params["damage"] = resolved_damage
		_:
			if resolved_damage != 0 and not params.has("damage"):
				params["damage"] = resolved_damage
	if not params.has("damage") and resolved_damage != 0:
		params["damage"] = resolved_damage
	return {
		"type": str(intent.get("type", "wait")),
		"preview": _translate_key(str(intent.get("preview_key", "")), params, "等待"),
		"damage": resolved_damage,
	}


func _gem_pool_weight(gem_id: String, rarity_weights: Dictionary, tag_weights: Dictionary) -> float:
	var rarity := get_gem_rarity(gem_id)
	var weight := get_gem_spawn_weight(gem_id)
	if not rarity_weights.is_empty():
		weight = float(rarity_weights.get(rarity, 0.0))
	if weight <= 0.0:
		return 0.0
	var tag := get_gem_tag(gem_id)
	if tag_weights.has(tag):
		weight *= maxf(0.0, float(tag_weights.get(tag, 1.0)))
	return weight


func _next_uid(prefix: String) -> String:
	_uid_counter += 1
	return "%s_%d" % [prefix, _uid_counter]


func _apply_unit_spawn_variants(unit: UnitState, def: Dictionary) -> void:
	if not def.has("hp_roll_max"):
		return
	var bonus := RngService.roll_int("unit_spawn_hp_%s" % unit.unit_def_id, 0, int(def.get("hp_roll_max", 0)))
	unit.hp = int(def["max_hp"]) + bonus
	unit.max_hp = unit.hp


func _register_gem_effect_profiles() -> void:
	_gem_effect_profiles = {
		"explosion": {
			"enemy_intent": {
				"type": "explosion_attack",
				"preview_key": "gem.intent.explosion_attack",
				"damage_mode": "cross_burst",
				"damage": 0,
			},
			"ability_descriptions": {
					ABILITY_UNIT_RED_ACTIVE: {"key": "gem.effect.explosion.unit_red_active", "params": {"damage": CombatConfig.explosion_damage()}},
					ABILITY_ENEMY_RED_ACTION: {"key": "gem.effect.explosion.enemy_red_action", "params": {"damage": CombatConfig.explosion_damage()}},
				ABILITY_BLUE_TURN_START: {"key": "gem.effect.explosion.blue_turn_start"},
				ABILITY_BLACK_DEATH: {"key": "gem.effect.explosion.black_death"},
				ABILITY_TILE_ACTIVE: {"key": "gem.effect.explosion.tile_active"},
				ABILITY_TILE_TURN_START: {"key": "gem.effect.explosion.tile_turn_start"},
			},
		},
		"poison": {
			"enemy_intent": {
				"type": "poison_attack",
				"damage_mode": "base_attack",
				"preview_key": "gem.intent.poison_attack",
				"damage": 0,
			},
			"ability_descriptions": {
				ABILITY_UNIT_RED_ACTIVE: {"key": "gem.effect.poison.unit_red_active"},
				ABILITY_ENEMY_RED_ACTION: {"key": "gem.effect.poison.enemy_red_action"},
				ABILITY_BLUE_DAMAGED: {"key": "gem.effect.poison.blue_damaged"},
				ABILITY_BLACK_DEATH: {"key": "gem.effect.poison.black_death"},
				ABILITY_TILE_ACTIVE: {"key": "gem.effect.poison.tile_active"},
				ABILITY_TILE_TURN_START: {"key": "gem.effect.poison.tile_turn_start"},
			},
		},
		"gravity": {
			"enemy_intent": {
				"type": "pull",
				"preview_key": "gem.intent.pull",
				"params": {"damage": CombatConfig.gravity_collision_damage()},
				"damage": 0,
			},
			"ability_descriptions": {
				ABILITY_UNIT_RED_ACTIVE: {"key": "gem.effect.gravity.unit_red_active"},
				ABILITY_ENEMY_RED_ACTION: {"key": "gem.effect.gravity.enemy_red_action", "params": {"damage": CombatConfig.gravity_collision_damage()}},
				ABILITY_BLACK_DEATH: {"key": "gem.effect.gravity.black_death"},
				ABILITY_TILE_ACTIVE: {"key": "gem.effect.gravity.tile_active"},
				ABILITY_TILE_TURN_START: {"key": "gem.effect.gravity.tile_turn_start"},
			},
		},
		"arc": {
			"enemy_intent": {
				"type": "arc_attack",
				"preview_key": "gem.intent.arc_attack",
				"damage_mode": "base_attack",
				"damage": 0,
			},
			"ability_descriptions": {
				ABILITY_UNIT_RED_ACTIVE: {"key": "gem.effect.arc.unit_red_active"},
				ABILITY_ENEMY_RED_ACTION: {"key": "gem.effect.arc.enemy_red_action"},
				ABILITY_BLUE_DAMAGED: {"key": "gem.effect.arc.blue_damaged"},
				ABILITY_BLACK_DEATH: {"key": "gem.effect.arc.black_death"},
			},
		},
		"fire_gem": {
			"enemy_intent": {
				"type": "fire_attack",
				"preview_key": "gem.intent.fire_attack",
				"damage_mode": "base_attack",
				"damage": 0,
			},
			"ability_descriptions": {
				ABILITY_UNIT_RED_ACTIVE: {"key": "gem.effect.fire_gem.unit_red_active"},
				ABILITY_ENEMY_RED_ACTION: {"key": "gem.effect.fire_gem.enemy_red_action"},
				ABILITY_BLUE_DAMAGED: {"key": "gem.effect.fire_gem.blue_damaged"},
				ABILITY_BLACK_DEATH: {"key": "gem.effect.fire_gem.black_death"},
			},
		},
		"ice": {
			"enemy_intent": {
				"type": "ice_attack",
				"preview_key": "gem.intent.ice_attack",
				"damage_mode": "base_attack",
				"damage": 0,
			},
			"ability_descriptions": {
				ABILITY_UNIT_RED_ACTIVE: {"key": "gem.effect.ice.unit_red_active"},
				ABILITY_ENEMY_RED_ACTION: {"key": "gem.effect.ice.enemy_red_action"},
				ABILITY_BLUE_DAMAGED: {"key": "gem.effect.ice.blue_damaged"},
				ABILITY_BLACK_DEATH: {"key": "gem.effect.ice.black_death"},
			},
		},
		"split": {
			"enemy_intent": {
				"type": "split_attack",
				"preview_key": "gem.intent.split_attack",
				"damage_mode": "base_attack",
				"damage": 0,
			},
			"ability_descriptions": {
				ABILITY_UNIT_RED_ACTIVE: {"key": "gem.effect.split.unit_red_active"},
				ABILITY_ENEMY_RED_ACTION: {"key": "gem.effect.split.enemy_red_action"},
				ABILITY_BLUE_DAMAGED: {"key": "gem.effect.split.blue_damaged"},
				ABILITY_BLACK_DEATH: {"key": "gem.effect.split.black_death"},
			},
		},
		"light": {
			"enemy_intent": {
				"type": "light_beam",
				"preview_key": "gem.intent.light_beam",
				"damage_mode": "base_attack",
				"damage": 0,
			},
			"ability_descriptions": {
				ABILITY_UNIT_RED_ACTIVE: {"key": "gem.effect.light.unit_red_active"},
				ABILITY_ENEMY_RED_ACTION: {"key": "gem.effect.light.enemy_red_action"},
				ABILITY_BLUE_DAMAGED: {"key": "gem.effect.light.blue_damaged"},
				ABILITY_BLACK_DEATH: {"key": "gem.effect.light.black_death"},
			},
		},
		"counter": {
			"enemy_intent": {
				"type": "counter_attack",
				"preview_key": "gem.intent.counter_attack",
				"damage_mode": "base_attack",
				"damage": 0,
			},
			"ability_descriptions": {
				ABILITY_UNIT_RED_ACTIVE: {"key": "gem.effect.counter.unit_red_active"},
				ABILITY_ENEMY_RED_ACTION: {"key": "gem.effect.counter.enemy_red_action"},
				ABILITY_BLUE_DAMAGED: {"key": "gem.effect.counter.blue_damaged"},
				ABILITY_BLACK_DEATH: {"key": "gem.effect.counter.black_death"},
			},
		},
		"echo": {
			"enemy_intent": {
				"type": "echo_attack",
				"preview_key": "gem.intent.echo_attack",
				"damage_mode": "base_attack",
				"damage": 0,
			},
			"ability_descriptions": {
				ABILITY_UNIT_RED_ACTIVE: {"key": "gem.effect.echo.unit_red_active"},
				ABILITY_ENEMY_RED_ACTION: {"key": "gem.effect.echo.enemy_red_action"},
				ABILITY_BLUE_DAMAGED: {"key": "gem.effect.echo.blue_damaged"},
				ABILITY_BLACK_DEATH: {"key": "gem.effect.echo.black_death"},
			},
		},
	}


func _resolve_gem_def(gem_ref: Variant) -> Dictionary:
	var gem_id := _gem_id_from_ref(gem_ref)
	var base: Dictionary = _gem_defs.get(gem_id, {}).duplicate(true)
	if gem_ref is GemState:
		var gem := gem_ref as GemState
		if not gem.def_overrides.is_empty():
			base = _deep_merge_dict(base, gem.def_overrides)
	return base


func _effect_profile(profile_id: String) -> Dictionary:
	return _gem_effect_profiles.get(profile_id, {})


func _translate_ability_description(profile_id: String, ability_slot: String) -> String:
	var profile: Dictionary = _effect_profile(profile_id)
	if profile.is_empty():
		return ""
	var descriptions: Dictionary = profile.get("ability_descriptions", {})
	var entry: Variant = descriptions.get(ability_slot, {})
	if entry is Dictionary:
		var payload := entry as Dictionary
		return _translate_key(str(payload.get("key", "")), payload.get("params", {}), "")
	if entry is String:
		return _translate_key(str(entry), {}, "")
	return ""


func _ability_slots_for_display(slot_type: String, context: String) -> Array[String]:
	match slot_type:
		Constants.SLOT_RED:
			match context:
				"player_trigger":
					return [ABILITY_UNIT_RED_ACTIVE]
				"enemy_active":
					return [ABILITY_ENEMY_RED_ACTION]
		Constants.SLOT_BLUE:
			match context:
				"unit_blue":
					return [
						ABILITY_BLUE_TURN_START,
						ABILITY_BLUE_DAMAGED,
						ABILITY_BLUE_MOVE_THROUGH,
						ABILITY_ATTACK_BONUS,
						ABILITY_ARMOR_BONUS,
					]
				"pillar":
					return [ABILITY_TILE_TURN_START]
		Constants.SLOT_BLACK:
			return [ABILITY_BLACK_DEATH]
	return []


func _rarity_rank(rarity: String) -> int:
	match rarity:
		"common":
			return 0
		"uncommon":
			return 1
		"rare":
			return 2
		"epic":
			return 3
		"legendary":
			return 4
	return -1


func _tile_display_name_key(tile_id: String) -> String:
	match tile_id:
		Constants.TILE_WATER:
			return "tile.water.name"
		Constants.TILE_PILLAR:
			return "tile.pillar.name"
		Constants.TILE_ICE:
			return "tile.ice.name"
		Constants.TILE_GRASS:
			return "tile.grass.name"
		Constants.TILE_BUSH:
			return "tile.bush.name"
		_:
			return "tile.floor.name"


func _translate_key(key: String, params: Dictionary = {}, fallback: String = "") -> String:
	if key.is_empty():
		return fallback
	var translated := I18nService.tr_key(key, params)
	if translated == key:
		return fallback
	return translated


func _gem_effect_level_summary_params(level_def: Dictionary, level: int) -> Dictionary:
	var params: Dictionary = {"level": level}
	for raw_field_id in level_def.keys():
		var field_id := str(raw_field_id)
		params[field_id] = _format_gem_effect_level_summary_value(field_id, level_def[raw_field_id])
	var offsets: Variant = level_def.get("light_direction_offsets", [])
	if offsets is Array:
		params["shot_count"] = (offsets as Array).size()
	if bool(level_def.get("strike_all_targets", false)):
		params["strike_targets"] = _translate_key("gem.level.target.all", {}, "all")
	elif level_def.has("strike_count"):
		params["strike_targets"] = _format_gem_effect_level_summary_value("strike_count", level_def["strike_count"])
	return params


func _format_gem_effect_level_summary_value(field_id: String, value: Variant) -> String:
	if value is bool:
		return _translate_key("gem.level.bool.%s" % ("true" if value else "false"), {}, "yes" if value else "no")
	if field_id == "blast_pattern" or field_id == "fog_pattern":
		return _translate_key("gem.level.pattern.%s" % str(value), {}, str(value))
	if field_id == "redirect_mode":
		return _translate_key("gem.level.split.redirect.%s" % str(value), {}, str(value))
	if _GEM_EFFECT_LEVEL_PERCENT_FIELDS.has(field_id):
		return "%s%%" % _format_gem_effect_level_number(float(value) * 100.0)
	if value is int or value is float:
		return _format_gem_effect_level_number(float(value))
	return str(value)


func _format_gem_effect_level_number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.2f" % value


func _gem_id_from_ref(gem_ref: Variant) -> String:
	if gem_ref is GemState:
		return (gem_ref as GemState).gem_id
	return str(gem_ref)


func _deep_merge_dict(base: Dictionary, overrides: Dictionary) -> Dictionary:
	var merged := base.duplicate(true)
	for key in overrides.keys():
		var override_value: Variant = overrides[key]
		var base_value: Variant = merged.get(key, null)
		if base_value is Dictionary and override_value is Dictionary:
			merged[key] = _deep_merge_dict(base_value as Dictionary, override_value as Dictionary)
		elif override_value is Dictionary:
			merged[key] = (override_value as Dictionary).duplicate(true)
		elif override_value is Array:
			merged[key] = (override_value as Array).duplicate(true)
		else:
			merged[key] = override_value
	return merged


# ─── JSON 外部数据加载 ────────────────────────────────────────────────────────

func _numeric_ref_value(raw_ref: Variant, fallback: float = 0.0) -> float:
	if raw_ref is int or raw_ref is float:
		return float(raw_ref)
	if raw_ref is Dictionary:
		return float((raw_ref as Dictionary).get("value", fallback))
	return fallback


func _resolve_relic_numeric_field(payload: Dictionary, field_id: String, fallback: float = 0.0) -> float:
	var ref_key := "%s_ref" % field_id
	if payload.has(ref_key):
		return get_relic_numeric_ref(str(payload.get(ref_key, "")), fallback)
	return float(payload.get(field_id, fallback))


func _load_gem_defs_from_json() -> void:
	var path := "res://resources/gems/gem_defs.json"
	var raw := _read_json_file(path)
	var errors := BalanceConfigValidator.validate_gem_defs(raw, _key_set(_gem_effect_profiles.keys()))
	BalanceConfigValidator.ensure_valid(path, errors)
	_gem_defs = {}
	if not errors.is_empty():
		return
	for gem_id in raw.keys():
		var entry: Dictionary = (raw[gem_id] as Dictionary).duplicate(true)
		if entry.has("color"):
			var c: Array = entry["color"]
			entry["color"] = Color(float(c[0]), float(c[1]), float(c[2]), float(c[3]) if c.size() > 3 else 1.0)
		_gem_defs[gem_id] = entry


func _load_gem_effect_levels_from_json() -> void:
	var path := "res://resources/gems/gem_effect_levels.json"
	var raw := _read_json_file(path)
	var errors := BalanceConfigValidator.validate_gem_effect_levels(raw)
	BalanceConfigValidator.ensure_valid(path, errors)
	_gem_effect_levels = {}
	if not errors.is_empty():
		return
	_gem_effect_levels = raw.duplicate(true)


func _load_gem_pools_from_json() -> void:
	var path := "res://resources/gems/gem_pools.json"
	var raw := _read_json_file(path)
	var known_tags: Dictionary = {}
	for gem_id in get_gem_ids():
		known_tags[get_gem_tag(gem_id)] = true
	var errors := BalanceConfigValidator.validate_gem_pools(raw, known_tags)
	BalanceConfigValidator.ensure_valid(path, errors)
	_gem_pools = {}
	_gem_teaching_boosts = {}
	if not errors.is_empty():
		return
	_gem_teaching_boosts = (raw["teaching_boosts"] as Dictionary).duplicate(true)
	_gem_pools = raw.duplicate(true)
	_gem_pools.erase("teaching_boosts")


func _load_relic_numeric_refs_from_json() -> void:
	var path := "res://resources/relics/relic_numeric_refs.json"
	var raw := _read_json_file(path)
	var errors := BalanceConfigValidator.validate_relic_numeric_refs(raw)
	BalanceConfigValidator.ensure_valid(path, errors)
	_relic_numeric_refs = {}
	if not errors.is_empty():
		return
	_relic_numeric_refs = raw.duplicate(true)


func _load_relic_source_weights_from_json() -> void:
	var path := "res://resources/adventure/relic_source_weights.json"
	var raw := _read_json_file(path)
	var errors := BalanceConfigValidator.validate_relic_source_weights(raw)
	BalanceConfigValidator.ensure_valid(path, errors)
	_relic_source_weights = {}
	if not errors.is_empty():
		return
	_relic_source_weights = raw.duplicate(true)


func _load_reward_offer_config_from_json() -> void:
	var path := "res://resources/adventure/reward_offer_config.json"
	var raw := _read_json_file(path)
	var errors := AdventureConfigValidator.validate_reward_offer_config(
		raw,
		_key_set(get_relic_source_ids())
	)
	AdventureConfigValidator.ensure_valid(path, errors)
	_reward_offer_config = {}
	if not errors.is_empty():
		return
	_reward_offer_config = raw.duplicate(true)


func _load_battle_reward_ui_config_from_json() -> void:
	var path := "res://resources/ui/battle_reward_ui_config.json"
	var raw := _read_json_file(path)
	var errors := AdventureConfigValidator.validate_battle_reward_ui_config(raw)
	AdventureConfigValidator.ensure_valid(path, errors)
	_battle_reward_ui_config = {}
	if not errors.is_empty():
		return
	_battle_reward_ui_config = raw.duplicate(true)


func _validate_shop_pools_source_refs() -> void:
	var path := "res://resources/adventure/shop_pools.json"
	var raw := _read_json_file(path)
	if raw.is_empty():
		return
	AdventureConfigValidator.ensure_valid(
		path,
		AdventureConfigValidator.validate_shop_pools(
			raw,
			_key_set(get_gem_pool_source_ids()),
			_key_set(get_relic_source_ids())
		)
	)


func _load_enemy_slot_curves_from_json() -> void:
	var path := "res://resources/adventure/enemy_slot_curves.json"
	var raw := _read_json_file(path)
	var errors := BalanceConfigValidator.validate_enemy_slot_curves(raw)
	BalanceConfigValidator.ensure_valid(path, errors)
	_enemy_slot_curves = {}
	if not errors.is_empty():
		return
	_enemy_slot_curves = raw.duplicate(true)


func _validate_adventure_progression_refs() -> void:
	var path := AdventureProgressionConfig.CONFIG_PATH
	var event_defs := _read_json_file("res://resources/adventure/event_defs.json")
	AdventureConfigValidator.ensure_valid(
		path,
		AdventureConfigValidator.validate_adventure_progression(
			AdventureProgressionConfig.get_config(),
			_key_set(get_encounter_ids()),
			_key_set(event_defs.keys())
		)
	)


func _load_unit_defs_from_json() -> void:
	var path := "res://resources/units/unit_defs.json"
	var raw := _read_json_file(path)
	var known_ai_profile_ids := _key_set(AIProfiles.get_profile_ids())
	known_ai_profile_ids["player"] = true
	known_ai_profile_ids["training_dummy"] = true
	var errors := BalanceConfigValidator.validate_unit_defs(
		raw,
		_key_set(get_gem_ids()),
		_key_set(BehaviorRegistry.get_behavior_ids()),
		known_ai_profile_ids
	)
	BalanceConfigValidator.ensure_valid(path, errors)
	_unit_defs = {}
	if not errors.is_empty():
		return
	_unit_defs = raw.duplicate(true)


func _load_encounters_from_json() -> void:
	_encounters = {}
	var production_dir := "res://resources/encounters/"
	var loaded_count := _load_encounters_from_dir(production_dir)
	if loaded_count <= 0:
		AdventureConfigValidator.ensure_valid(production_dir, ["no valid encounter definitions loaded"])
	if OS.is_debug_build():
		_load_encounters_from_dir("res://tests/fixtures/encounters/")


func _load_encounters_from_dir(dir_path: String) -> int:
	var raw_entries := EncounterCatalogLoader.load_raw_entries(
		dir_path,
		_encounters,
		Callable(self, "_read_json_file"),
		Callable(self, "_validate_encounter_def"),
		Callable(self, "_report_encounter_errors")
	)
	for encounter_id in raw_entries:
		_encounters[encounter_id] = _parse_encounter_json(raw_entries[encounter_id])
	return raw_entries.size()


func _validate_encounter_def(encounter_id: String, raw: Dictionary) -> Array[String]:
	return AdventureConfigValidator.validate_encounter_def(
		encounter_id,
		raw,
		_unit_defs,
		_key_set(get_tile_ids()),
		_key_set(get_entity_ids()),
		_key_set(get_overlay_ids()),
		_key_set(get_gem_ids()),
		Constants.BOARD_SIZE
	)


func _report_encounter_errors(path: String, errors: Array[String]) -> void:
	AdventureConfigValidator.ensure_valid(path, errors)


func _parse_encounter_json(raw: Dictionary) -> Dictionary:
	var result := raw.duplicate(true)
	# player_spawn: [x, y] → Vector2i
	if result.has("player_spawn"):
		var sp: Array = result["player_spawn"]
		result["player_spawn"] = Vector2i(int(sp[0]), int(sp[1]))
	# enemies: pos [x, y] → Vector2i
	if result.has("enemies"):
		result["enemies"] = _parse_enemy_positions(result["enemies"])
	if result.has("enemy_groups"):
		var groups: Array = result["enemy_groups"]
		for i in range(groups.size()):
			var group: Dictionary = groups[i].duplicate(true)
			group["enemies"] = _parse_enemy_positions(group.get("enemies", []))
			groups[i] = group
		result["enemy_groups"] = groups
	if result.has("random_enemies"):
		var random_enemies: Array = result["random_enemies"]
		for i in range(random_enemies.size()):
			var slot: Dictionary = random_enemies[i].duplicate(true)
			if slot.has("pos"):
				var p: Array = slot["pos"]
				slot["pos"] = Vector2i(int(p[0]), int(p[1]))
			random_enemies[i] = slot
		result["random_enemies"] = random_enemies
	# tiles: pos [x, y] → Vector2i
	if result.has("tiles"):
		var tiles: Array = result["tiles"]
		for i in range(tiles.size()):
			var t: Dictionary = tiles[i].duplicate(true)
			if t.has("pos"):
				var p: Array = t["pos"]
				t["pos"] = Vector2i(int(p[0]), int(p[1]))
			tiles[i] = t
		result["tiles"] = tiles
	if result.has("entities"):
		var entities: Array = result["entities"]
		for i in range(entities.size()):
			var entry: Dictionary = entities[i].duplicate(true)
			if entry.has("pos"):
				var p: Variant = entry["pos"]
				if p is Array and p.size() >= 2:
					entry["pos"] = Vector2i(int(p[0]), int(p[1]))
			entities[i] = entry
		result["entities"] = entities
	return result


func _parse_enemy_positions(raw_enemies: Array) -> Array:
	var enemies := raw_enemies.duplicate(true)
	for i in range(enemies.size()):
		var enemy: Dictionary = enemies[i].duplicate(true)
		if enemy.has("pos"):
			var p: Array = enemy["pos"]
			enemy["pos"] = Vector2i(int(p[0]), int(p[1]))
		enemies[i] = enemy
	return enemies


func _resolve_enemy_slot_budget(
	chapter: int,
	room_type: String,
	encounter_id: String,
	enemy_data: Dictionary,
	def: Dictionary
) -> int:
	var fixed_count := 0
	var random_slot_defs: Array[Dictionary] = []
	var spawn_gem_slots: Array = def.get("spawn_gem_slots", [])
	var restrict_spawn_gem_slots := def.has("spawn_gem_slots")
	for raw_slot in def.get("slots", []):
		if not raw_slot is Dictionary:
			continue
		var slot_def := raw_slot as Dictionary
		if slot_def.has("gem_id"):
			fixed_count += 1
			continue
		if restrict_spawn_gem_slots and not str(slot_def.get("slot_type", "")) in spawn_gem_slots:
			continue
		random_slot_defs.append(slot_def)
	if random_slot_defs.is_empty():
		return 0
	var target_total := _roll_enemy_total_gem_slots(chapter, room_type, encounter_id, enemy_data, def)
	return clampi(target_total - fixed_count, 0, random_slot_defs.size())


func _roll_enemy_total_gem_slots(
	chapter: int,
	room_type: String,
	encounter_id: String,
	enemy_data: Dictionary,
	def: Dictionary
) -> int:
	var def_id := str(enemy_data.get("def_id", ""))
	if def_id == "unit_bomb_rat":
		return 1
	var slots: Array = def.get("slots", [])
	var max_slots := slots.size()
	if max_slots <= 0:
		return 0
	var normalized_room_type := room_type.to_upper()
	var weights := get_enemy_total_slot_weights(normalized_room_type, chapter)
	var items: Array = []
	var item_weights: Array[float] = []
	for slot_count in range(weights.size()):
		if slot_count > max_slots:
			continue
		items.append(slot_count)
		item_weights.append(float(weights[slot_count]))
	var picked: Variant = RngService.weighted_pick(
		"enemy_slot_budget_%s_%s_%s" % [encounter_id, def_id, str(enemy_data.get("pos", Vector2i.ZERO))],
		items,
		item_weights
	)
	var picked_count := int(picked) if picked != null else mini(1, max_slots)
	if _enemy_requires_initial_gem(enemy_data, def):
		picked_count = maxi(1, picked_count)
	return clampi(picked_count, 0, max_slots)


func _enemy_requires_initial_gem(enemy_data: Dictionary, def: Dictionary) -> bool:
	if bool(enemy_data.get("allow_empty_gems", false)) or bool(def.get("allow_empty_gems", false)):
		return false
	for raw_tag in def.get("tags", []):
		if str(raw_tag) == "unit:test_fixture":
			return false
	return not def.get("slots", []).is_empty()


func _enemy_total_slot_weights(chapter: int, room_type: String) -> Array[float]:
	return get_enemy_total_slot_weights(room_type, chapter)


func _load_relic_defs_from_json() -> void:
	var path := "res://resources/relics/relic_defs.json"
	var raw := _read_json_file(path)
	var errors := BalanceConfigValidator.validate_relic_defs(raw, _relic_numeric_refs)
	BalanceConfigValidator.ensure_valid(path, errors)
	_relic_defs = {}
	if not errors.is_empty():
		return
	for relic_id in raw.keys():
		var entry: Dictionary = (raw[relic_id] as Dictionary).duplicate(true)
		if entry.has("desc"):
			entry["desc"] = NumericTextResolver.format_text(str(entry.get("desc", "")), {
				"relic_numeric_refs": _relic_numeric_refs,
			})
		if _relic_defs.has(relic_id):
			_relic_defs[relic_id] = _deep_merge_dict(_relic_defs[relic_id], entry)
		else:
			_relic_defs[relic_id] = entry


## 将 RunState 记录的持久槽位变更应用到刚创建的玩家单位上
func _apply_run_slot_overrides(player: UnitState) -> void:
	var run_svc: Node = Engine.get_main_loop().root.get_node_or_null("RunService")
	if run_svc == null:
		return
	var run: RunState = run_svc.get_run()
	if run == null:
		return
	for entry in run.extra_slots:
		var slot_type: String = str(entry.get("slot_type", ""))
		if not slot_type.is_empty():
			player.slots.append(SlotState.create(slot_type))
	var upgrades_applied: int = 0
	for entry in run.upgraded_slots:
		var from_type: String = str(entry.get("from_type", ""))
		var to_dual: String = str(entry.get("to_dual_type", ""))
		if from_type.is_empty() or to_dual.is_empty():
			continue
		var applied := false
		for i in range(upgrades_applied, player.slots.size()):
			var slot: SlotState = player.slots[i]
			if slot.slot_type == from_type and slot.dual_type.is_empty():
				slot.dual_type = to_dual
				applied = true
				upgrades_applied += 1
				break
		if not applied:
			upgrades_applied += 1


func _restore_run_player_state(state: GameState, player: UnitState) -> void:
	var run_svc: Node = Engine.get_main_loop().root.get_node_or_null("RunService")
	if run_svc == null:
		return
	var run: RunState = run_svc.get_run()
	if run == null:
		return
	if run.player_max_hp > 0:
		player.max_hp = run.player_max_hp
	if run.player_hp >= 0:
		player.hp = mini(player.max_hp, maxi(0, run.player_hp))
	_ensure_player_slots_for_restore(player, run.player_slot_gems)
	for i in range(run.player_slot_gems.size()):
		var raw_slot: Variant = run.player_slot_gems[i]
		if not raw_slot is Dictionary:
			continue
		var slot_snapshot := raw_slot as Dictionary
		if slot_snapshot.is_empty():
			continue
		var gem := create_gem_instance(
			_next_uid("gem"),
			str(slot_snapshot.get("gem_id", "")),
			slot_snapshot.get("def_overrides", {}) if slot_snapshot.get("def_overrides", {}) is Dictionary else {}
		)
		if gem.gem_id.is_empty():
			continue
			
		var slot: SlotState = player.slots[i]
		slot.gem_uid = gem.uid
		var lock_type := str(slot_snapshot.get("lock_type", ""))
		if not lock_type.is_empty():
			slot.lock_type = lock_type
		if slot.dual_type.is_empty():
			var dual_type := str(slot_snapshot.get("dual_type", ""))
			if not dual_type.is_empty():
				slot.dual_type = dual_type
		gem.mark_slotted(player.uid, i)
		state.gems[gem.uid] = gem
	if not run.carried_gem.is_empty():
		var carried := create_gem_instance(
			_next_uid("gem"),
			str(run.carried_gem.get("gem_id", "")),
			run.carried_gem.get("def_overrides", {}) if run.carried_gem.get("def_overrides", {}) is Dictionary else {}
		)
		if not carried.gem_id.is_empty():
			carried.mark_held(player.uid)
			state.gems[carried.uid] = carried
			state.held_gem_uid = carried.uid
	state.overload_active_mutations = run.overload_active_mutations.duplicate()


## 过载等战斗内追加的槽位只写入 player_slot_gems，不会进入 extra_slots
func _ensure_player_slots_for_restore(player: UnitState, slot_gems: Array) -> void:
	while player.slots.size() < slot_gems.size():
		var i := player.slots.size()
		var raw_slot: Variant = slot_gems[i]
		var slot_type := Constants.SLOT_RED
		var dual_type := ""
		var lock_type := ""
		if raw_slot is Dictionary:
			var snapshot := raw_slot as Dictionary
			slot_type = str(snapshot.get("slot_type", Constants.SLOT_RED))
			if slot_type.is_empty():
				slot_type = Constants.SLOT_RED
			dual_type = str(snapshot.get("dual_type", ""))
			lock_type = str(snapshot.get("lock_type", ""))
		var slot := SlotState.create(slot_type)
		if not dual_type.is_empty():
			slot.dual_type = dual_type
		if not lock_type.is_empty():
			slot.lock_type = lock_type
		player.slots.append(slot)


## 根据章节和房间类型映射到对应的敌人宝石 pool key
func _resolve_enemy_pool_source(chapter: int, room_type: String) -> String:
	var normalized := room_type.to_upper()
	match normalized:
		"BOSS", "BOSS_COMBAT", "END":
			return "enemy_boss"
		"ELITE_COMBAT":
			if chapter >= 3:
				return "enemy_boss"
			return "enemy_elite"
		_:
			if chapter >= 2:
				return "enemy_elite"
			return "enemy_normal"


## 将教学加权叠加到已有 tag_weights（就地修改）
func _apply_teaching_boosts(tag_weights: Dictionary, chapter_tier: int) -> void:
	if _gem_teaching_boosts.is_empty():
		return
	var chapter := clampi(chapter_tier, 1, 3)
	var boost_key := "chapter_%d" % chapter
	var boosts: Dictionary = _gem_teaching_boosts.get(boost_key, {})
	for tag in boosts.keys():
		var multiplier := maxf(0.0, float(boosts[tag]))
		if tag_weights.has(tag):
			tag_weights[tag] = float(tag_weights[tag]) * multiplier
		else:
			tag_weights[tag] = multiplier


## 返回当前 source pool 的候选列表，附带每项权重，供 debug 工具查看
func get_gem_pool_candidates(source: String, chapter_tier: int = 99) -> Array[Dictionary]:
	var pool_def := get_gem_pool_def(source)
	var rarity_weights: Dictionary = pool_def.get("rarity_weights", {})
	var tag_weights: Dictionary = pool_def.get("tag_weights", {}).duplicate(true)
	_apply_teaching_boosts(tag_weights, chapter_tier)
	var allowed: Array = []
	if not rarity_weights.is_empty():
		for rarity in rarity_weights.keys():
			if float(rarity_weights[rarity]) > 0.0:
				allowed.append(str(rarity))
	var candidates := get_spawnable_gem_ids_for_source(source, chapter_tier, allowed)
	var result: Array[Dictionary] = []
	for gem_id in candidates:
		var weight := _gem_pool_weight(gem_id, rarity_weights, tag_weights)
		result.append({
			"gem_id": gem_id,
			"tag": get_gem_tag(gem_id),
			"rarity": get_gem_rarity(gem_id),
			"pool_tier": get_gem_pool_tier(gem_id),
			"weight": weight,
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(b.get("weight", 0.0)) > float(a.get("weight", 0.0))
	)
	return result


func _read_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("DataRegistry: cannot open %s" % path)
		return {}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_warning("DataRegistry: JSON parse error in %s — %s" % [path, json.get_error_message()])
		return {}
	var data: Variant = json.get_data()
	if data is Dictionary:
		return data as Dictionary
	push_warning("DataRegistry: expected JSON object in %s" % path)
	return {}


func _key_set(ids: Array) -> Dictionary:
	var result := {}
	for id in ids:
		result[str(id)] = true
	return result
