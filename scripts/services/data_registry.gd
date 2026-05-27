extends Node

const BoardMapGenerator = preload("res://scripts/map/board_map_generator.gd")

const ABILITY_PLAYER_SKILL := "player_skill"
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

const _RARITY_WEIGHTS := {
	"common": 100.0,
	"uncommon": 55.0,
	"rare": 25.0,
	"epic": 10.0,
	"legendary": 4.0,
}

var _gem_effect_profiles: Dictionary = {}
var _gem_defs: Dictionary = {}
var _unit_defs: Dictionary = {}
var _encounters: Dictionary = {}
var _uid_counter: int = 0


func _ready() -> void:
	_register_gem_effect_profiles()
	_register_gem_defs()
	_register_unit_defs()
	_register_encounters()
	# JSON 覆盖：若外部文件存在则合并/替换硬编码数据
	_load_gem_defs_from_json()
	_load_unit_defs_from_json()
	_load_encounters_from_json()


func create_battle_state(encounter_id: String, seed_value: int = 0) -> GameState:
	var encounter: Dictionary = _encounters.get(encounter_id, {})
	if encounter.is_empty():
		push_error("Encounter not found: %s" % encounter_id)
		return null
	_uid_counter = 0
	RngService.set_seed(seed_value if seed_value != 0 else int(Time.get_unix_time_from_system()))
	var state := GameState.new()
	state.run_seed = RngService.get_seed()
	state.encounter_id = encounter_id
	state.player_uid = _next_uid("player")
	var player := UnitState.from_def(
		state.player_uid,
		"unit_player",
		Constants.TEAM_PLAYER,
		encounter.get("player_spawn", Vector2i(3, 2)),
		_unit_defs["unit_player"]
	)
	state.units[state.player_uid] = player
	for enemy_data in encounter.get("enemies", []):
		var enemy_uid := _next_uid(enemy_data.get("def_id", "enemy"))
		var def: Dictionary = _unit_defs[enemy_data.get("def_id", "unit_grunt")].duplicate(true)
		var base_slots: Array = def.get("slots", [])
		def["slots"] = []
		for slot_data in base_slots:
			var slot_entry: Dictionary = slot_data.duplicate(true)
			# 若遭遇模板未指定宝石，则随机分配一个
			if not slot_entry.has("gem_id"):
				var roll_gem_id := roll_spawnable_gem_id("enemy_spawn_" + str(slot_entry.get("slot_type", "")))
				if not roll_gem_id.is_empty():
					slot_entry["gem_id"] = roll_gem_id
			if slot_entry.has("gem_id"):
				var gem_uid := _next_uid("gem")
				var gem := create_gem_instance(gem_uid, slot_entry.get("gem_id", ""), slot_entry.get("gem_overrides", {}))
				state.gems[gem_uid] = gem
				slot_entry["gem_uid"] = gem_uid
				slot_entry.erase("gem_id")
				slot_entry.erase("gem_overrides")
			def["slots"].append(slot_entry)
		var enemy := UnitState.from_def(
			enemy_uid,
			enemy_data.get("def_id", "unit_grunt"),
			Constants.TEAM_ENEMY,
			enemy_data.get("pos", Vector2i.ZERO),
			def
		)
		for i in range(enemy.slots.size()):
			var slot: SlotState = enemy.slots[i]
			if not slot.gem_uid.is_empty():
				var gem: GemState = state.gems[slot.gem_uid]
				gem.owner_uid = enemy.uid
				gem.slot_index = i
		state.units[enemy_uid] = enemy
	BoardMapGenerator.build(state, encounter)
	TileRules.sync_all_units_standing_ground(state)
	IntentSystem.refresh_all_intents(state)
	state.log("遭遇战开始: %s" % encounter_id)
	return state


func get_encounter_ids() -> Array:
	return _encounters.keys()


func next_runtime_uid(prefix: String) -> String:
	return _next_uid(prefix)


func has_unit_def(unit_def_id: String) -> bool:
	return _unit_defs.has(unit_def_id)


func get_unit_def(unit_def_id: String) -> Dictionary:
	return _unit_defs.get(unit_def_id, {}).duplicate(true)


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
		Constants.TILE_SPIKE,
		Constants.TILE_WATER,
		Constants.TILE_PILLAR,
	]


func has_tile_id(tile_id: String) -> bool:
	return tile_id in get_tile_ids()


func get_unit_display_name(unit_def_id: String) -> String:
	var def: Dictionary = _unit_defs.get(unit_def_id, {})
	return _translate_key(str(def.get("display_name_key", "")), {}, unit_def_id)


func get_tile_display_name(tile_id: String) -> String:
	return _translate_key(_tile_display_name_key(tile_id), {}, tile_id)


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


func get_gem_rarity_label(gem_ref: Variant) -> String:
	var rarity: String = get_gem_rarity(gem_ref)
	return _translate_key("gem.rarity.%s" % rarity, {}, rarity.capitalize())


func get_gem_spawn_weight(gem_ref: Variant) -> float:
	var def: Dictionary = _resolve_gem_def(gem_ref)
	if def.has("spawn_weight"):
		return float(def.get("spawn_weight", 0.0))
	return float(_RARITY_WEIGHTS.get(get_gem_rarity(gem_ref), 1.0))


func get_spawnable_gem_ids(allowed_rarities: Array = []) -> Array[String]:
	var results: Array[String] = []
	for gem_id in _gem_defs.keys():
		var def: Dictionary = _gem_defs[gem_id]
		if not def.get("allow_random_pool", true):
			continue
		var rarity := str(def.get("rarity", "common"))
		if not allowed_rarities.is_empty() and not rarity in allowed_rarities:
			continue
		results.append(gem_id)
	results.sort()
	return results


func roll_spawnable_gem_id(domain: String = "gem_drop", allowed_rarities: Array = []) -> String:
	var candidates := get_spawnable_gem_ids(allowed_rarities)
	if candidates.is_empty():
		return ""
	var total_weight := 0.0
	var weighted: Array[Dictionary] = []
	for gem_id in candidates:
		var weight := get_gem_spawn_weight(gem_id)
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


func create_gem_instance(uid: String, gem_id: String, gem_overrides: Dictionary = {}) -> GemState:
	return GemState.create(uid, gem_id, gem_overrides.duplicate(true))


func get_gem_ability_profile(gem_ref: Variant, ability_slot: String) -> String:
	var ability_profiles: Dictionary = _resolve_gem_def(gem_ref).get("ability_profiles", {})
	return str(ability_profiles.get(ability_slot, ""))


func get_player_skill_target_mode(gem_ref: Variant) -> String:
	var profile: Dictionary = _effect_profile(get_gem_ability_profile(gem_ref, ABILITY_PLAYER_SKILL))
	return str(profile.get("player_skill_target_mode", "any_cell"))


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
	var resolved_damage := int(intent.get("damage", 0))
	match str(intent.get("damage_mode", "fixed")):
		"base_attack":
			resolved_damage = damage
			params["damage"] = damage
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


func _next_uid(prefix: String) -> String:
	_uid_counter += 1
	return "%s_%d" % [prefix, _uid_counter]


func _register_gem_effect_profiles() -> void:
	_gem_effect_profiles = {
		"explosion": {
			"player_skill_target_mode": "any_cell",
			"enemy_intent": {
				"type": "charge_explode",
				"preview_key": "gem.intent.charge_explode",
				"params": {"damage": Constants.EXPLOSION_DAMAGE},
				"damage": Constants.EXPLOSION_DAMAGE,
			},
			"ability_descriptions": {
				ABILITY_PLAYER_SKILL: {"key": "gem.effect.explosion.player_skill", "params": {"damage": Constants.EXPLOSION_DAMAGE}},
				ABILITY_UNIT_RED_ACTIVE: {"key": "gem.effect.explosion.unit_red_active", "params": {"damage": Constants.EXPLOSION_DAMAGE}},
				ABILITY_ENEMY_RED_ACTION: {"key": "gem.effect.explosion.enemy_red_action", "params": {"damage": Constants.EXPLOSION_DAMAGE}},
				ABILITY_BLUE_TURN_START: {"key": "gem.effect.explosion.blue_turn_start"},
				ABILITY_BLACK_DEATH: {"key": "gem.effect.explosion.black_death"},
				ABILITY_TILE_ACTIVE: {"key": "gem.effect.explosion.tile_active"},
				ABILITY_TILE_TURN_START: {"key": "gem.effect.explosion.tile_turn_start"},
			},
		},
		"poison": {
			"player_skill_target_mode": "any_cell",
			"enemy_intent": {
				"type": "poison_attack",
				"damage_mode": "base_attack",
				"preview_key": "gem.intent.poison_attack",
				"damage": 0,
			},
			"ability_descriptions": {
				ABILITY_PLAYER_SKILL: {"key": "gem.effect.poison.player_skill"},
				ABILITY_UNIT_RED_ACTIVE: {"key": "gem.effect.poison.unit_red_active"},
				ABILITY_ENEMY_RED_ACTION: {"key": "gem.effect.poison.enemy_red_action"},
				ABILITY_BLUE_DAMAGED: {"key": "gem.effect.poison.blue_damaged"},
				ABILITY_BLACK_DEATH: {"key": "gem.effect.poison.black_death"},
				ABILITY_TILE_ACTIVE: {"key": "gem.effect.poison.tile_active"},
				ABILITY_TILE_TURN_START: {"key": "gem.effect.poison.tile_turn_start"},
			},
		},
		"gravity": {
			"player_skill_target_mode": "enemy_unit",
			"enemy_intent": {
				"type": "pull",
				"preview_key": "gem.intent.pull",
				"params": {"damage": Constants.GRAVITY_COLLISION_DAMAGE},
				"damage": 0,
			},
			"ability_descriptions": {
				ABILITY_PLAYER_SKILL: {"key": "gem.effect.gravity.player_skill", "params": {"damage": Constants.GRAVITY_COLLISION_DAMAGE}},
				ABILITY_UNIT_RED_ACTIVE: {"key": "gem.effect.gravity.unit_red_active"},
				ABILITY_ENEMY_RED_ACTION: {"key": "gem.effect.gravity.enemy_red_action", "params": {"damage": Constants.GRAVITY_COLLISION_DAMAGE}},
				ABILITY_BLUE_TURN_START: {"key": "gem.effect.gravity.blue_turn_start"},
				ABILITY_BLACK_DEATH: {"key": "gem.effect.gravity.black_death"},
				ABILITY_TILE_ACTIVE: {"key": "gem.effect.gravity.tile_active"},
				ABILITY_TILE_TURN_START: {"key": "gem.effect.gravity.tile_turn_start"},
			},
		},
		"arc": {
			"player_skill_target_mode": "water_tile",
			"enemy_intent": {
				"type": "arc_attack",
				"preview_key": "gem.intent.arc_attack",
				"damage_mode": "base_attack",
				"damage": 0,
			},
			"ability_descriptions": {
				ABILITY_PLAYER_SKILL: {"key": "gem.effect.arc.player_skill"},
				ABILITY_UNIT_RED_ACTIVE: {"key": "gem.effect.arc.unit_red_active"},
				ABILITY_ENEMY_RED_ACTION: {"key": "gem.effect.arc.enemy_red_action"},
				ABILITY_BLUE_DAMAGED: {"key": "gem.effect.arc.blue_damaged"},
				ABILITY_BLACK_DEATH: {"key": "gem.effect.arc.black_death"},
			},
		},
		"fire_gem": {
			"player_skill_target_mode": "any_cell",
			"enemy_intent": {
				"type": "fire_attack",
				"preview_key": "gem.intent.fire_attack",
				"damage_mode": "base_attack",
				"damage": 0,
			},
			"ability_descriptions": {
				ABILITY_PLAYER_SKILL: {"key": "gem.effect.fire_gem.player_skill"},
				ABILITY_UNIT_RED_ACTIVE: {"key": "gem.effect.fire_gem.unit_red_active"},
				ABILITY_ENEMY_RED_ACTION: {"key": "gem.effect.fire_gem.enemy_red_action"},
				ABILITY_BLUE_DAMAGED: {"key": "gem.effect.fire_gem.blue_damaged"},
				ABILITY_BLACK_DEATH: {"key": "gem.effect.fire_gem.black_death"},
			},
		},
		"ice": {
			"player_skill_target_mode": "enemy_unit",
			"enemy_intent": {
				"type": "ice_attack",
				"preview_key": "gem.intent.ice_attack",
				"damage_mode": "base_attack",
				"damage": 0,
			},
			"ability_descriptions": {
				ABILITY_PLAYER_SKILL: {"key": "gem.effect.ice.player_skill"},
				ABILITY_UNIT_RED_ACTIVE: {"key": "gem.effect.ice.unit_red_active"},
				ABILITY_ENEMY_RED_ACTION: {"key": "gem.effect.ice.enemy_red_action"},
				ABILITY_BLUE_DAMAGED: {"key": "gem.effect.ice.blue_damaged"},
				ABILITY_BLACK_DEATH: {"key": "gem.effect.ice.black_death"},
			},
		},
	}


func _register_gem_defs() -> void:
	_gem_defs = {
		Constants.GEM_EXPLOSION: {
			"display_name_key": "gem.explosion.name",
			"symbol_key": "gem.explosion.symbol",
			"symbol": "爆",
			"color": Color(1.0, 0.45, 0.2),
			"rarity": "common",
			"ability_profiles": {
				ABILITY_PLAYER_SKILL: "explosion",
				ABILITY_UNIT_RED_ACTIVE: "explosion",
				ABILITY_ENEMY_RED_ACTION: "explosion",
				ABILITY_BLUE_TURN_START: "explosion",
				ABILITY_BLUE_DAMAGED: "explosion",
				ABILITY_BLACK_DEATH: "explosion",
				ABILITY_TILE_ACTIVE: "explosion",
				ABILITY_TILE_TURN_START: "explosion",
			},
		},
		Constants.GEM_POISON: {
			"display_name_key": "gem.poison.name",
			"symbol_key": "gem.poison.symbol",
			"symbol": "毒",
			"color": Color(0.55, 0.9, 0.35),
			"rarity": "common",
			"ability_profiles": {
				ABILITY_PLAYER_SKILL: "poison",
				ABILITY_UNIT_RED_ACTIVE: "poison",
				ABILITY_ENEMY_RED_ACTION: "poison",
				ABILITY_BLUE_DAMAGED: "poison",
				ABILITY_BLACK_DEATH: "poison",
				ABILITY_TILE_ACTIVE: "poison",
				ABILITY_TILE_TURN_START: "poison",
			},
		},
		Constants.GEM_GRAVITY: {
			"display_name_key": "gem.gravity.name",
			"symbol_key": "gem.gravity.symbol",
			"symbol": "引",
			"color": Color(0.35, 0.65, 1.0),
			"rarity": "rare",
			"ability_profiles": {
				ABILITY_PLAYER_SKILL: "gravity",
				ABILITY_UNIT_RED_ACTIVE: "gravity",
				ABILITY_ENEMY_RED_ACTION: "gravity",
				ABILITY_BLUE_TURN_START: "gravity",
				ABILITY_BLUE_DAMAGED: "gravity",
				ABILITY_BLACK_DEATH: "gravity",
				ABILITY_TILE_ACTIVE: "gravity",
				ABILITY_TILE_TURN_START: "gravity",
			},
		},
		Constants.GEM_CONDUCTIVE: {
			"display_name_key": "gem.conductive.name",
			"symbol_key": "gem.conductive.symbol",
			"symbol": "电",
			"color": Color(0.95, 0.9, 0.3),
			"rarity": "uncommon",
			"ability_profiles": {
				ABILITY_PLAYER_SKILL: "arc",
				ABILITY_UNIT_RED_ACTIVE: "arc",
				ABILITY_ENEMY_RED_ACTION: "arc",
				ABILITY_BLUE_DAMAGED: "arc",
				ABILITY_BLACK_DEATH: "arc",
			},
		},
		Constants.GEM_FIRE: {
			"display_name_key": "gem.fire.name",
			"symbol_key": "gem.fire.symbol",
			"symbol": "炎",
			"color": Color(1.0, 0.35, 0.1),
			"rarity": "uncommon",
			"ability_profiles": {
				ABILITY_PLAYER_SKILL: "fire_gem",
				ABILITY_UNIT_RED_ACTIVE: "fire_gem",
				ABILITY_ENEMY_RED_ACTION: "fire_gem",
				ABILITY_BLUE_DAMAGED: "fire_gem",
				ABILITY_BLACK_DEATH: "fire_gem",
			},
		},
		Constants.GEM_ICE: {
			"display_name_key": "gem.ice.name",
			"symbol_key": "gem.ice.symbol",
			"symbol": "冰",
			"color": Color(0.6, 0.9, 1.0),
			"rarity": "uncommon",
			"ability_profiles": {
				ABILITY_PLAYER_SKILL: "ice",
				ABILITY_UNIT_RED_ACTIVE: "ice",
				ABILITY_ENEMY_RED_ACTION: "ice",
				ABILITY_BLUE_DAMAGED: "ice",
				ABILITY_BLACK_DEATH: "ice",
			},
		},
	}


func _register_unit_defs() -> void:
	_unit_defs = {
		"unit_player": {
			"display_name_key": "unit.player.name",
			"max_hp": 60,
			"move_points": 3,
			"speed": 12,
			"base_attack": 10,
			"ai_profile_id": "player",
			"slots": [
				{"slot_type": Constants.SLOT_RED},
				{"slot_type": Constants.SLOT_BLUE},
				{"slot_type": Constants.SLOT_BLACK},
			],
		},
		"unit_bomber": {
			"display_name_key": "unit.bomber.name",
			"max_hp": 20,
			"move_points": 3,
			"speed": 11,
			"base_attack": 6,
			"ai_profile_id": "bomber",
			"tags": [Constants.TAG_UNIT_BOMBER, Constants.TAG_UNIT_MOBILE],
			"slots": [
				{"slot_type": Constants.SLOT_RED},
				{"slot_type": Constants.SLOT_BLUE},
				{"slot_type": Constants.SLOT_BLACK},
			],
		},
		"unit_training_guard": {
			"display_name_key": "unit.training_guard.name",
			"max_hp": 20,
			"move_points": 1,
			"speed": 8,
			"base_attack": 6,
			"ai_profile_id": "melee_chase",
			"tags": [Constants.TAG_UNIT_TRAINING],
			"slots": [
				{"slot_type": Constants.SLOT_RED},
				{"slot_type": Constants.SLOT_BLUE},
				{"slot_type": Constants.SLOT_BLACK},
			],
		},
		"unit_heavy_guard": {
			"display_name_key": "unit.heavy_guard.name",
			"max_hp": 30,
			"move_points": 1,
			"speed": 7,
			"base_attack": 8,
			"ai_profile_id": "guard",
			"tags": [Constants.TAG_UNIT_HEAVY],
			"slots": [
				{"slot_type": Constants.SLOT_RED},
				{"slot_type": Constants.SLOT_BLUE},
				{"slot_type": Constants.SLOT_BLACK},
			],
		},
		"unit_poison_bug": {
			"display_name_key": "unit.poison_bug.name",
			"max_hp": 20,
			"move_points": 2,
			"speed": 10,
			"base_attack": 6,
			"ai_profile_id": "poison_roamer",
			"tags": [Constants.TAG_UNIT_MOBILE],
			"slots": [
				{"slot_type": Constants.SLOT_RED},
				{"slot_type": Constants.SLOT_BLUE},
				{"slot_type": Constants.SLOT_BLACK},
			],
		},
		"unit_gravity_eye": {
			"display_name_key": "unit.gravity_eye.name",
			"max_hp": 25,
			"move_points": 0,
			"speed": 9,
			"base_attack": 0,
			"ai_profile_id": "puller",
			"tags": [Constants.TAG_UNIT_PULLER, Constants.TAG_UNIT_TURRET],
			"slots": [
				{"slot_type": Constants.SLOT_RED},
				{"slot_type": Constants.SLOT_BLUE},
				{"slot_type": Constants.SLOT_BLACK},
			],
		},
		"unit_grunt": {
			"display_name_key": "unit.grunt.name",
			"max_hp": 20,
			"move_points": 2,
			"speed": 9,
			"base_attack": 6,
			"ai_profile_id": "melee_chase",
			"tags": [],
			"slots": [
				{"slot_type": Constants.SLOT_RED},
				{"slot_type": Constants.SLOT_BLUE},
				{"slot_type": Constants.SLOT_BLACK},
			],
		},
		"unit_thief": {
			"display_name_key": "unit.thief.name",
			"max_hp": 20,
			"move_points": 3,
			"speed": 13,
			"base_attack": 6,
			"ai_profile_id": "thief",
			"tags": [Constants.TAG_UNIT_THIEF, Constants.TAG_UNIT_MOBILE],
			"slots": [
				{"slot_type": Constants.SLOT_RED},
				{"slot_type": Constants.SLOT_BLUE},
				{"slot_type": Constants.SLOT_BLACK},
			],
		},
		"unit_shock_tower": {
			"display_name_key": "unit.shock_tower.name",
			"max_hp": 30,
			"move_points": 0,
			"speed": 6,
			"base_attack": 0,
			"ai_profile_id": "turret",
			"tags": [Constants.TAG_UNIT_TURRET],
			"slots": [
				{"slot_type": Constants.SLOT_RED},
				{"slot_type": Constants.SLOT_BLUE},
				{"slot_type": Constants.SLOT_BLACK},
			],
		},
	}


func _register_encounters() -> void:
	_encounters = {
		"tutorial_001": {
			"player_spawn": Vector2i(3, 2),
			"enemies": [
				{"def_id": "unit_bomber", "pos": Vector2i(2, 4)},
				{"def_id": "unit_training_guard", "pos": Vector2i(3, 5)},
			],
			"tiles": [
				{"pos": Vector2i(2, 5), "tile_id": Constants.TILE_SPIKE},
			],
		},
		"template_a": {
			"player_spawn": Vector2i(1, 6),
			"enemies": [
				{"def_id": "unit_bomber", "pos": Vector2i(4, 2)},
				{"def_id": "unit_heavy_guard", "pos": Vector2i(5, 4)},
				{"def_id": "unit_poison_bug", "pos": Vector2i(6, 6)},
			],
			"tiles": [
				{"pos": Vector2i(3, 5), "tile_id": Constants.TILE_SPIKE},
				{"pos": Vector2i(6, 3), "tile_id": Constants.TILE_SPIKE},
				{"pos": Vector2i(7, 5), "tile_id": Constants.TILE_PILLAR, "slots": [{"slot_type": Constants.SLOT_BLUE}]},
			],
		},
		"template_b": {
			"player_spawn": Vector2i(1, 6),
			"enemies": [
				{"def_id": "unit_gravity_eye", "pos": Vector2i(4, 3)},
				{"def_id": "unit_heavy_guard", "pos": Vector2i(5, 5)},
				{"def_id": "unit_poison_bug", "pos": Vector2i(6, 2)},
			],
			"tiles": [
				{"pos": Vector2i(4, 4), "tile_id": Constants.TILE_SPIKE},
				{"pos": Vector2i(5, 4), "tile_id": Constants.TILE_SPIKE},
				{"pos": Vector2i(6, 4), "tile_id": Constants.TILE_SPIKE},
				{"pos": Vector2i(2, 2), "tile_id": Constants.TILE_PILLAR, "slots": [{"slot_type": Constants.SLOT_BLUE}]},
			],
		},
		"template_c": {
			"player_spawn": Vector2i(1, 6),
			"enemies": [
				{"def_id": "unit_poison_bug", "pos": Vector2i(5, 2)},
				{"def_id": "unit_gravity_eye", "pos": Vector2i(6, 4)},
				{"def_id": "unit_grunt", "pos": Vector2i(4, 6)},
				{"def_id": "unit_grunt", "pos": Vector2i(6, 6)},
			],
			"tiles": [
				{"pos": Vector2i(3, 4), "tile_id": Constants.TILE_WATER},
				{"pos": Vector2i(4, 4), "tile_id": Constants.TILE_WATER},
				{"pos": Vector2i(3, 5), "tile_id": Constants.TILE_WATER},
				{"pos": Vector2i(4, 5), "tile_id": Constants.TILE_WATER},
			],
		},
		"template_d": {
			"player_spawn": Vector2i(1, 6),
			"enemies": [
				{"def_id": "unit_shock_tower", "pos": Vector2i(6, 1)},
				{"def_id": "unit_thief", "pos": Vector2i(5, 3)},
				{"def_id": "unit_heavy_guard", "pos": Vector2i(4, 4)},
				{"def_id": "unit_grunt", "pos": Vector2i(3, 5)},
				{"def_id": "unit_grunt", "pos": Vector2i(5, 5)},
			],
			"tiles": [
				{"pos": Vector2i(2, 3), "tile_id": Constants.TILE_WATER},
				{"pos": Vector2i(3, 3), "tile_id": Constants.TILE_WATER},
				{"pos": Vector2i(2, 4), "tile_id": Constants.TILE_WATER},
				{"pos": Vector2i(5, 6), "tile_id": Constants.TILE_SPIKE},
				{"pos": Vector2i(6, 6), "tile_id": Constants.TILE_SPIKE},
				{"pos": Vector2i(7, 3), "tile_id": Constants.TILE_PILLAR, "slots": [{"slot_type": Constants.SLOT_BLUE}]},
			],
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
				"player_skill":
					return [ABILITY_PLAYER_SKILL]
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
		Constants.TILE_SPIKE:
			return "tile.spike.name"
		Constants.TILE_WATER:
			return "tile.water.name"
		Constants.TILE_PILLAR:
			return "tile.pillar.name"
		_:
			return "tile.floor.name"


func _translate_key(key: String, params: Dictionary = {}, fallback: String = "") -> String:
	if key.is_empty():
		return fallback
	var translated := I18nService.tr_key(key, params)
	if translated == key:
		return fallback
	return translated


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

func _load_gem_defs_from_json() -> void:
	var path := "res://resources/gems/gem_defs.json"
	var raw := _read_json_file(path)
	if raw.is_empty():
		return
	for gem_id in raw.keys():
		var entry: Dictionary = raw[gem_id]
		if entry.has("color"):
			var c: Array = entry["color"]
			entry["color"] = Color(float(c[0]), float(c[1]), float(c[2]), float(c[3]) if c.size() > 3 else 1.0)
		if _gem_defs.has(gem_id):
			_gem_defs[gem_id] = _deep_merge_dict(_gem_defs[gem_id], entry)
		else:
			_gem_defs[gem_id] = entry


func _load_unit_defs_from_json() -> void:
	var path := "res://resources/units/unit_defs.json"
	var raw := _read_json_file(path)
	if raw.is_empty():
		return
	for unit_id in raw.keys():
		var entry: Dictionary = raw[unit_id]
		if _unit_defs.has(unit_id):
			_unit_defs[unit_id] = _deep_merge_dict(_unit_defs[unit_id], entry)
		else:
			_unit_defs[unit_id] = entry


func _load_encounters_from_json() -> void:
	var dir := DirAccess.open("res://resources/encounters/")
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var encounter_id := file_name.get_basename()
			var path := "res://resources/encounters/" + file_name
			var raw := _read_json_file(path)
			if not raw.is_empty():
				_encounters[encounter_id] = _parse_encounter_json(raw)
		file_name = dir.get_next()
	dir.list_dir_end()


func _parse_encounter_json(raw: Dictionary) -> Dictionary:
	var result := raw.duplicate(true)
	# player_spawn: [x, y] → Vector2i
	if result.has("player_spawn"):
		var sp: Array = result["player_spawn"]
		result["player_spawn"] = Vector2i(int(sp[0]), int(sp[1]))
	# enemies: pos [x, y] → Vector2i
	if result.has("enemies"):
		var enemies: Array = result["enemies"]
		for i in range(enemies.size()):
			var e: Dictionary = enemies[i].duplicate(true)
			if e.has("pos"):
				var p: Array = e["pos"]
				e["pos"] = Vector2i(int(p[0]), int(p[1]))
			enemies[i] = e
		result["enemies"] = enemies
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
