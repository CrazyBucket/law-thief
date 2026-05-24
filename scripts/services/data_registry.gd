extends Node

const BoardMapGenerator = preload("res://scripts/map/board_map_generator.gd")

var _unit_defs: Dictionary = {}
var _encounters: Dictionary = {}
var _uid_counter: int = 0


func _ready() -> void:
	_register_unit_defs()
	_register_encounters()


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
		# 始终使用 unit_def 的槽位结构，遭遇模板只负责预装宝石
		var base_slots: Array = def.get("slots", [])
		var gem_overrides: Array = enemy_data.get("slots", []).duplicate(true)
		def["slots"] = []
		for slot_data in base_slots:
			var slot_entry: Dictionary = slot_data.duplicate(true)
			# 查找遭遇模板中是否为该类型槽位预装了宝石
			for override in gem_overrides:
				if override.get("slot_type", -1) == slot_entry.get("slot_type", -1) and override.has("gem_id"):
					slot_entry["gem_id"] = override["gem_id"]
					gem_overrides.erase(override)
					break
			if slot_entry.has("gem_id"):
				var gem_uid := _next_uid("gem")
				var gem := GemState.create(gem_uid, slot_entry.get("gem_id", ""))
				state.gems[gem_uid] = gem
				slot_entry["gem_uid"] = gem_uid
				slot_entry.erase("gem_id")
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
	IntentSystem.refresh_all_intents(state)
	state.log("遭遇战开始: %s" % encounter_id)
	return state


func get_encounter_ids() -> Array:
	return _encounters.keys()


func get_unit_display_name(unit_def_id: String) -> String:
	return _unit_defs.get(unit_def_id, {}).get("display_name", unit_def_id)


func get_tile_display_name(tile_id: String) -> String:
	match tile_id:
		Constants.TILE_SPIKE:
			return "尖刺"
		Constants.TILE_WATER:
			return "水洼"
		Constants.TILE_ALTAR:
			return "祭坛"
		Constants.TILE_PILLAR:
			return "机关柱"
		_:
			return "地面"


func get_gem_display_name(gem_id: String) -> String:
	match gem_id:
		Constants.GEM_EXPLOSION:
			return "爆炸"
		Constants.GEM_POISON:
			return "剧毒"
		Constants.GEM_GRAVITY:
			return "引力"
		Constants.GEM_HEAVY_ARMOR:
			return "重甲"
		Constants.GEM_CONDUCTIVE:
			return "导电"
		Constants.GEM_FRAGILE:
			return "易碎"
	return gem_id


func _next_uid(prefix: String) -> String:
	_uid_counter += 1
	return "%s_%d" % [prefix, _uid_counter]


func _register_unit_defs() -> void:
	_unit_defs = {
		"unit_player": {
			"display_name": "窃律者",
			"max_hp": 6,
			"move_points": 3,
			"base_attack": 1,
			"ai_profile_id": "player",
			"slots": [
				{"slot_type": Constants.SLOT_RED},
				{"slot_type": Constants.SLOT_BLUE},
				{"slot_type": Constants.SLOT_BLACK},
			],
		},
		"unit_bomber": {
			"display_name": "自爆工兵",
			"max_hp": 2,
			"move_points": 3,
			"base_attack": 1,
			"ai_profile_id": "bomber",
			"slots": [
				{"slot_type": Constants.SLOT_RED},
				{"slot_type": Constants.SLOT_BLUE},
				{"slot_type": Constants.SLOT_BLACK},
			],
		},
		"unit_training_guard": {
			"display_name": "训练守卫",
			"max_hp": 1,
			"move_points": 1,
			"base_attack": 1,
			"ai_profile_id": "melee_chase",
			"slots": [
				{"slot_type": Constants.SLOT_RED},
				{"slot_type": Constants.SLOT_BLUE},
				{"slot_type": Constants.SLOT_BLACK},
			],
		},
		"unit_heavy_guard": {
			"display_name": "重甲守卫",
			"max_hp": 3,
			"move_points": 1,
			"base_attack": 1,
			"ai_profile_id": "guard",
			"slots": [
				{"slot_type": Constants.SLOT_RED},
				{"slot_type": Constants.SLOT_BLUE},
				{"slot_type": Constants.SLOT_BLACK},
			],
		},
		"unit_poison_bug": {
			"display_name": "毒虫",
			"max_hp": 2,
			"move_points": 2,
			"base_attack": 1,
			"ai_profile_id": "poison_roamer",
			"slots": [
				{"slot_type": Constants.SLOT_RED},
				{"slot_type": Constants.SLOT_BLUE},
				{"slot_type": Constants.SLOT_BLACK},
			],
		},
		"unit_gravity_eye": {
			"display_name": "引力眼",
			"max_hp": 2,
			"move_points": 0,
			"base_attack": 0,
			"ai_profile_id": "puller",
			"slots": [
				{"slot_type": Constants.SLOT_RED},
				{"slot_type": Constants.SLOT_BLUE},
				{"slot_type": Constants.SLOT_BLACK},
			],
		},
		"unit_grunt": {
			"display_name": "小怪",
			"max_hp": 1,
			"move_points": 2,
			"base_attack": 1,
			"ai_profile_id": "melee_chase",
			"slots": [
				{"slot_type": Constants.SLOT_RED},
				{"slot_type": Constants.SLOT_BLUE},
				{"slot_type": Constants.SLOT_BLACK},
			],
		},
		"unit_thief": {
			"display_name": "窃贼",
			"max_hp": 2,
			"move_points": 3,
			"base_attack": 1,
			"ai_profile_id": "thief",
			"slots": [
				{"slot_type": Constants.SLOT_RED},
				{"slot_type": Constants.SLOT_BLUE},
				{"slot_type": Constants.SLOT_BLACK},
			],
		},
		"unit_shock_tower": {
			"display_name": "电塔",
			"max_hp": 3,
			"move_points": 0,
			"base_attack": 0,
			"ai_profile_id": "turret",
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
				{
					"def_id": "unit_bomber",
					"pos": Vector2i(2, 4),
					"slots": [
						{"slot_type": Constants.SLOT_RED, "gem_id": Constants.GEM_EXPLOSION},
					],
				},
				{
					"def_id": "unit_training_guard",
					"pos": Vector2i(3, 5),
					"slots": [],
				},
			],
			"tiles": [
				{"pos": Vector2i(2, 5), "tile_id": Constants.TILE_SPIKE},
				{"pos": Vector2i(5, 3), "tile_id": Constants.TILE_ALTAR, "slots": [{"slot_type": Constants.SLOT_RED}]},
			],
		},
		"template_a": {
			"player_spawn": Vector2i(1, 6),
			"enemies": [
				{"def_id": "unit_bomber", "pos": Vector2i(4, 2), "slots": [{"slot_type": Constants.SLOT_RED, "gem_id": Constants.GEM_EXPLOSION}]},
				{"def_id": "unit_heavy_guard", "pos": Vector2i(5, 4), "slots": [{"slot_type": Constants.SLOT_BLUE, "gem_id": Constants.GEM_HEAVY_ARMOR}]},
				{"def_id": "unit_poison_bug", "pos": Vector2i(6, 6), "slots": [{"slot_type": Constants.SLOT_BLUE, "gem_id": Constants.GEM_POISON}]},
			],
			"tiles": [
				{"pos": Vector2i(3, 5), "tile_id": Constants.TILE_SPIKE},
				{"pos": Vector2i(6, 3), "tile_id": Constants.TILE_SPIKE},
				{"pos": Vector2i(2, 3), "tile_id": Constants.TILE_ALTAR, "slots": [{"slot_type": Constants.SLOT_RED}]},
				{"pos": Vector2i(7, 5), "tile_id": Constants.TILE_PILLAR, "slots": [{"slot_type": Constants.SLOT_BLUE}]},
			],
		},
		"template_b": {
			"player_spawn": Vector2i(1, 6),
			"enemies": [
				{"def_id": "unit_gravity_eye", "pos": Vector2i(4, 3), "slots": [{"slot_type": Constants.SLOT_RED, "gem_id": Constants.GEM_GRAVITY}]},
				{"def_id": "unit_heavy_guard", "pos": Vector2i(5, 5), "slots": [{"slot_type": Constants.SLOT_BLUE, "gem_id": Constants.GEM_HEAVY_ARMOR, "locked": true, "lock_type": Constants.LOCK_ARMOR}]},
				{"def_id": "unit_poison_bug", "pos": Vector2i(6, 2), "slots": [{"slot_type": Constants.SLOT_BLUE, "gem_id": Constants.GEM_POISON}]},
			],
			"tiles": [
				{"pos": Vector2i(4, 4), "tile_id": Constants.TILE_SPIKE},
				{"pos": Vector2i(5, 4), "tile_id": Constants.TILE_SPIKE},
				{"pos": Vector2i(6, 4), "tile_id": Constants.TILE_SPIKE},
				{"pos": Vector2i(2, 2), "tile_id": Constants.TILE_PILLAR, "slots": [{"slot_type": Constants.SLOT_BLUE}]},
				{"pos": Vector2i(7, 6), "tile_id": Constants.TILE_ALTAR, "slots": [{"slot_type": Constants.SLOT_RED}]},
			],
		},
		"template_c": {
			"player_spawn": Vector2i(1, 6),
			"enemies": [
				{
					"def_id": "unit_poison_bug",
					"pos": Vector2i(5, 2),
					"slots": [
						{"slot_type": Constants.SLOT_RED, "gem_id": Constants.GEM_CONDUCTIVE},
						{"slot_type": Constants.SLOT_BLUE, "gem_id": Constants.GEM_POISON},
					],
				},
				{"def_id": "unit_gravity_eye", "pos": Vector2i(6, 4), "slots": [{"slot_type": Constants.SLOT_RED, "gem_id": Constants.GEM_GRAVITY}]},
				{"def_id": "unit_grunt", "pos": Vector2i(4, 6)},
				{"def_id": "unit_grunt", "pos": Vector2i(6, 6)},
			],
			"tiles": [
				{"pos": Vector2i(3, 4), "tile_id": Constants.TILE_WATER},
				{"pos": Vector2i(4, 4), "tile_id": Constants.TILE_WATER},
				{"pos": Vector2i(3, 5), "tile_id": Constants.TILE_WATER},
				{"pos": Vector2i(4, 5), "tile_id": Constants.TILE_WATER},
				{"pos": Vector2i(2, 1), "tile_id": Constants.TILE_ALTAR, "slots": [{"slot_type": Constants.SLOT_RED}]},
			],
		},
		"template_d": {
			"player_spawn": Vector2i(1, 6),
			"enemies": [
				{"def_id": "unit_shock_tower", "pos": Vector2i(6, 1), "slots": [{"slot_type": Constants.SLOT_RED, "gem_id": Constants.GEM_CONDUCTIVE}]},
				{"def_id": "unit_thief", "pos": Vector2i(5, 3)},
				{"def_id": "unit_heavy_guard", "pos": Vector2i(4, 4), "slots": [{"slot_type": Constants.SLOT_BLUE, "gem_id": Constants.GEM_HEAVY_ARMOR}]},
				{"def_id": "unit_grunt", "pos": Vector2i(3, 5)},
				{"def_id": "unit_grunt", "pos": Vector2i(5, 5)},
			],
			"tiles": [
				{"pos": Vector2i(2, 3), "tile_id": Constants.TILE_WATER},
				{"pos": Vector2i(3, 3), "tile_id": Constants.TILE_WATER},
				{"pos": Vector2i(2, 4), "tile_id": Constants.TILE_WATER},
				{"pos": Vector2i(5, 6), "tile_id": Constants.TILE_SPIKE},
				{"pos": Vector2i(6, 6), "tile_id": Constants.TILE_SPIKE},
				{"pos": Vector2i(1, 1), "tile_id": Constants.TILE_ALTAR, "slots": [{"slot_type": Constants.SLOT_RED}]},
				{"pos": Vector2i(7, 3), "tile_id": Constants.TILE_PILLAR, "slots": [{"slot_type": Constants.SLOT_BLUE}]},
			],
		},
	}
