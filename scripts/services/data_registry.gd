extends Node

const BoardMapGenerator = preload("res://scripts/map/board_map_generator.gd")

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
	"boss": 0.0,
}

# 来源 → 每个稀有度的权重（决定 roll 时各等级的抽出概率）
const _SOURCE_RARITY_WEIGHTS := {
	"normal_chest": {"common": 65.0, "rare": 25.0, "boss": 10.0},
	"elite_combat": {"common": 40.0, "rare": 40.0, "boss": 20.0},
	"large_chest": {"common": 10.0, "rare": 60.0, "boss": 30.0},
	"shop": {"common": 50.0, "rare": 35.0, "boss": 15.0},
}

var _gem_effect_profiles: Dictionary = {}
var _gem_defs: Dictionary = {}
var _unit_defs: Dictionary = {}
var _encounters: Dictionary = {}
var _relic_defs: Dictionary = {}
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
	_load_relic_defs_from_json()


func create_battle_state(encounter_id: String, seed_value: int = 0, room_id: String = "") -> GameState:
	var encounter: Dictionary = _encounters.get(encounter_id, {})
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
	_apply_run_slot_overrides(player)
	_restore_run_player_state(state, player)
	for enemy_data in encounter.get("enemies", []):
		var enemy_uid := _next_uid(enemy_data.get("def_id", "enemy"))
		var def: Dictionary = _unit_defs[enemy_data.get("def_id", "unit_bomb_rat")].duplicate(true)
		var base_slots: Array = def.get("slots", [])
		def["slots"] = []
		var spawn_gem_slots: Array = def.get("spawn_gem_slots", [])
		for slot_data in base_slots:
			var slot_entry: Dictionary = slot_data.duplicate(true)
			var slot_type := str(slot_entry.get("slot_type", ""))
			var should_roll_gem := not slot_entry.has("gem_id")
			if should_roll_gem and not spawn_gem_slots.is_empty():
				should_roll_gem = slot_type in spawn_gem_slots
			if should_roll_gem:
				var roll_gem_id := roll_spawnable_gem_id("enemy_spawn_" + slot_type)
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
			enemy_data.get("def_id", "unit_bomb_rat"),
			Constants.TEAM_ENEMY,
			enemy_data.get("pos", Vector2i.ZERO),
			def
		)
		_apply_unit_spawn_variants(enemy, def)
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
	# 所有单位就位后建立 O(1) 占格索引（多格单位 footprint 一并注册）
	state.rebuild_occupancy()
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


# ═══════════════════════════════════════════════════════════════════════════
# 遗物定义查询
# ═══════════════════════════════════════════════════════════════════════════

func get_relic_def(relic_id: String) -> Dictionary:
	return _relic_defs.get(relic_id, {})


func get_relic_rarity(relic_id: String) -> String:
	return str(_relic_defs.get(relic_id, {}).get("rarity", "common"))


func get_relic_ids() -> Array[String]:
	var ids: Array[String] = []
	for k in _relic_defs.keys():
		ids.append(str(k))
	return ids


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
	var weight := maxf(0.0, float(def.get("base_weight", 1.0)))
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
		var multiplier := maxf(0.0, float(rule.get("multiplier", 1.0)))
		var matched := false
		match rule_type:
			"has_gem":
				matched = str(rule.get("value", "")) in owned_gems
			"has_gem_color":
				matched = str(rule.get("value", "")) in gem_colors
			"has_relic":
				matched = str(rule.get("value", "")) in owned_relics
			"slot_count_gte":
				matched = total_slots >= int(rule.get("value", 0))
			"empty_slot_count_gte":
				matched = empty_slots >= int(rule.get("value", 0))
		if matched:
			weight *= multiplier
	return weight


## 返回满足筛选条件的遗物 id 列表
## source: 来源标识（"normal_chest" / "elite_combat" / "large_chest" / "shop"）
## owned_ids: 当前局内已持有的遗物 id 集合（用于过滤 unique 遗物重复）
## unlock_flags: 当前已解锁的 flag 集合（String 数组）
func _relic_matches_source(def: Dictionary, source: String, source_weights: Dictionary) -> bool:
	var pool_types: Array = def.get("pool_types", ["global"])
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
	var source_weights: Dictionary = _SOURCE_RARITY_WEIGHTS.get(source, {})
	for relic_id in _relic_defs.keys():
		var def: Dictionary = _relic_defs[relic_id]
		if not _relic_matches_source(def, source, source_weights):
			continue
		# boss 遗物只在 source_weights 允许时出现
		var rarity := str(def.get("rarity", "common"))
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
	var source_rarity_weights: Dictionary = _SOURCE_RARITY_WEIGHTS.get(source, {"common": 100.0})
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


func _apply_unit_spawn_variants(unit: UnitState, def: Dictionary) -> void:
	if not def.has("hp_roll_max"):
		return
	var bonus := RngService.roll_int("unit_spawn_hp_%s" % unit.unit_def_id, 0, int(def.get("hp_roll_max", 0)))
	unit.hp = int(def.get("max_hp", 1)) + bonus
	unit.max_hp = unit.hp


func _register_gem_effect_profiles() -> void:
	_gem_effect_profiles = {
		"explosion": {
			"enemy_intent": {
				"type": "explosion_attack",
				"preview_key": "gem.intent.explosion_attack",
				"damage_mode": "base_attack",
				"damage": 0,
			},
			"ability_descriptions": {
				ABILITY_UNIT_RED_ACTIVE: {"key": "gem.effect.explosion.unit_red_active", "params": {"damage": Constants.EXPLOSION_DAMAGE}},
				ABILITY_ENEMY_RED_ACTION: {"key": "gem.effect.explosion.enemy_red_action", "params": {"damage": Constants.EXPLOSION_DAMAGE}},
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
				"params": {"damage": Constants.GRAVITY_COLLISION_DAMAGE},
				"damage": 0,
			},
			"ability_descriptions": {
				ABILITY_UNIT_RED_ACTIVE: {"key": "gem.effect.gravity.unit_red_active"},
				ABILITY_ENEMY_RED_ACTION: {"key": "gem.effect.gravity.enemy_red_action", "params": {"damage": Constants.GRAVITY_COLLISION_DAMAGE}},
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
					ABILITY_UNIT_RED_ACTIVE: "gravity",
				ABILITY_ENEMY_RED_ACTION: "gravity",
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
					ABILITY_UNIT_RED_ACTIVE: "ice",
				ABILITY_ENEMY_RED_ACTION: "ice",
				ABILITY_BLUE_DAMAGED: "ice",
				ABILITY_BLACK_DEATH: "ice",
			},
		},
		Constants.GEM_SPLIT: {
			"display_name_key": "gem.split.name",
			"symbol_key": "gem.split.symbol",
			"symbol": "裂",
			"color": Color(0.85, 0.5, 1.0),
			"rarity": "epic",
			"allow_random_pool": true,
			"ability_profiles": {
				ABILITY_UNIT_RED_ACTIVE: "split",
				ABILITY_ENEMY_RED_ACTION: "split",
				ABILITY_BLUE_DAMAGED: "split",
				ABILITY_BLACK_DEATH: "split",
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
		"unit_bomb_rat": {
			"display_name_key": "unit.bomb_rat.name",
			"max_hp": 10,
			"hp_roll_max": Constants.BOMB_RAT_HP_ROLL_MAX,
			"move_points": 4,
			"speed": 13,
			"base_attack": 4,
			"ai_profile_id": "bomb_rat",
			"behavior_id": "bomb_rat",
			"spawn_gem_slots": [Constants.SLOT_BLACK],
			"tags": [Constants.TAG_UNIT_BOMB_RAT, Constants.TAG_UNIT_MOBILE],
			"slots": [
				{"slot_type": Constants.SLOT_RED},
				{"slot_type": Constants.SLOT_BLUE},
				{"slot_type": Constants.SLOT_BLACK},
			],
		},
		"unit_patrol_guard": {
			"display_name_key": "unit.patrol_guard.name",
			"max_hp": 24,
			"hp_roll_max": Constants.PATROL_GUARD_HP_ROLL_MAX,
			"move_points": 3,
			"speed": 9,
			"base_attack": 6,
			"ai_profile_id": "melee_chase",
			"behavior_id": "patrol_guard",
			"tags": [Constants.TAG_UNIT_PATROL_GUARD],
			"slots": [
				{"slot_type": Constants.SLOT_RED},
				{"slot_type": Constants.SLOT_BLUE},
				{"slot_type": Constants.SLOT_BLACK},
			],
		},
		"unit_stone_bow_guard": {
			"display_name_key": "unit.stone_bow_guard.name",
			"max_hp": 14,
			"hp_roll_max": Constants.STONE_BOW_HP_ROLL_MAX,
			"move_points": 2,
			"speed": 8,
			"base_attack": 4,
			"ai_profile_id": "stone_bow",
			"behavior_id": "stone_bow_guard",
			"tags": [Constants.TAG_UNIT_STONE_BOW_GUARD, Constants.TAG_UNIT_RANGED],
			"slots": [
				{"slot_type": Constants.SLOT_RED},
				{"slot_type": Constants.SLOT_BLUE},
				{"slot_type": Constants.SLOT_BLACK},
			],
		},
		"unit_fission_slime": {
			"display_name_key": "unit.fission_slime.name",
			"max_hp": 22,
			"hp_roll_max": Constants.FISSION_SLIME_HP_ROLL_MAX,
			"move_points": 2,
			"speed": 7,
			"base_attack": 4,
			"ai_profile_id": "melee_chase",
			"behavior_id": "fission_slime",
			"footprint_size": Vector2i(2, 2),
			"tags": [Constants.TAG_UNIT_FISSION_SLIME],
			"slots": [
				{"slot_type": Constants.SLOT_RED},
				{"slot_type": Constants.SLOT_BLUE, "gem_id": Constants.GEM_SPLIT},
				{"slot_type": Constants.SLOT_BLACK, "gem_id": Constants.GEM_SPLIT},
			],
		},
	}


func _register_encounters() -> void:
	_encounters = {
		"tutorial_001": {
			"player_spawn": Vector2i(3, 2),
			"enemies": [
				{"def_id": "unit_bomb_rat", "pos": Vector2i(2, 4)},
				{"def_id": "unit_patrol_guard", "pos": Vector2i(3, 5)},
			],
			"entities": [
				{"pos": Vector2i(2, 5), "entity_id": Constants.ENTITY_SPIKE},
				{"pos": Vector2i(4, 3), "entity_id": Constants.ENTITY_PROP},
				{"pos": Vector2i(5, 2), "entity_id": Constants.ENTITY_PROP, "prop_sprite": "Statue1_0"},
				{"pos": Vector2i(1, 4), "entity_id": Constants.ENTITY_PROP},
			],
		},
		"bomb_rat_test": {
			"player_spawn": Vector2i(3, 2),
			"enemies": [
				{"def_id": "unit_bomb_rat", "pos": Vector2i(1, 4)},
			],
		},
		"patrol_guard_test": {
			"player_spawn": Vector2i(3, 2),
			"enemies": [
				{"def_id": "unit_patrol_guard", "pos": Vector2i(0, 2)},
			],
		},
		"stone_bow_test": {
			"player_spawn": Vector2i(1, 2),
			"enemies": [
				{"def_id": "unit_stone_bow_guard", "pos": Vector2i(5, 2)},
			],
		},
		"fission_slime_test": {
			"player_spawn": Vector2i(0, 2),
			"enemies": [
				{"def_id": "unit_fission_slime", "pos": Vector2i(4, 3)},
			],
		},
		"template_a": {
			"player_spawn": Vector2i(1, 6),
			"enemies": [
				{"def_id": "unit_bomb_rat", "pos": Vector2i(4, 2)},
				{"def_id": "unit_patrol_guard", "pos": Vector2i(5, 4)},
				{"def_id": "unit_stone_bow_guard", "pos": Vector2i(6, 6)},
			],
			"entities": [
				{"pos": Vector2i(3, 5), "entity_id": Constants.ENTITY_SPIKE},
				{"pos": Vector2i(6, 3), "entity_id": Constants.ENTITY_SPIKE},
			],
			"tiles": [
				{"pos": Vector2i(7, 5), "tile_id": Constants.TILE_PILLAR, "slots": [ {"slot_type": Constants.SLOT_BLUE}]},
			],
		},
		"template_b": {
			"player_spawn": Vector2i(1, 6),
			"enemies": [
				{"def_id": "unit_stone_bow_guard", "pos": Vector2i(6, 2)},
				{"def_id": "unit_fission_slime", "pos": Vector2i(3, 3)},
				{"def_id": "unit_patrol_guard", "pos": Vector2i(5, 5)},
			],
			"entities": [
				{"pos": Vector2i(4, 4), "entity_id": Constants.ENTITY_SPIKE},
				{"pos": Vector2i(5, 4), "entity_id": Constants.ENTITY_SPIKE},
				{"pos": Vector2i(6, 4), "entity_id": Constants.ENTITY_SPIKE},
			],
			"tiles": [
				{"pos": Vector2i(2, 2), "tile_id": Constants.TILE_PILLAR, "slots": [ {"slot_type": Constants.SLOT_BLUE}]},
			],
		},
		"template_c": {
			"player_spawn": Vector2i(1, 6),
			"enemies": [
				{"def_id": "unit_bomb_rat", "pos": Vector2i(5, 2)},
				{"def_id": "unit_patrol_guard", "pos": Vector2i(4, 6)},
				{"def_id": "unit_stone_bow_guard", "pos": Vector2i(6, 4)},
				{"def_id": "unit_fission_slime", "pos": Vector2i(3, 3)},
			],
			"tiles": [
				{"pos": Vector2i(3, 4), "tile_id": Constants.TILE_WATER},
				{"pos": Vector2i(4, 4), "tile_id": Constants.TILE_WATER},
				{"pos": Vector2i(3, 5), "tile_id": Constants.TILE_WATER},
				{"pos": Vector2i(4, 5), "tile_id": Constants.TILE_WATER},
			],
			"entities": [
				{"pos": Vector2i(2, 3), "entity_id": Constants.ENTITY_PROP},
				{"pos": Vector2i(6, 2), "entity_id": Constants.ENTITY_PROP, "prop_sprite": "LargeRock2_1"},
				{"pos": Vector2i(5, 5), "entity_id": Constants.ENTITY_PROP},
				{"pos": Vector2i(3, 6), "entity_id": Constants.ENTITY_PROP, "prop_sprite": "Post2_0"},
			],
		},
		"template_d": {
			"player_spawn": Vector2i(1, 6),
			"enemies": [
				{"def_id": "unit_stone_bow_guard", "pos": Vector2i(6, 1)},
				{"def_id": "unit_bomb_rat", "pos": Vector2i(5, 3)},
				{"def_id": "unit_patrol_guard", "pos": Vector2i(4, 4)},
				{"def_id": "unit_fission_slime", "pos": Vector2i(2, 2)},
			],
			"entities": [
				{"pos": Vector2i(5, 6), "entity_id": Constants.ENTITY_SPIKE},
				{"pos": Vector2i(6, 6), "entity_id": Constants.ENTITY_SPIKE},
			],
			"tiles": [
				{"pos": Vector2i(2, 3), "tile_id": Constants.TILE_WATER},
				{"pos": Vector2i(3, 3), "tile_id": Constants.TILE_WATER},
				{"pos": Vector2i(2, 4), "tile_id": Constants.TILE_WATER},
				{"pos": Vector2i(7, 3), "tile_id": Constants.TILE_PILLAR, "slots": [ {"slot_type": Constants.SLOT_BLUE}]},
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


func _load_relic_defs_from_json() -> void:
	var path := "res://resources/relics/relic_defs.json"
	var raw := _read_json_file(path)
	if raw.is_empty():
		return
	for relic_id in raw.keys():
		var entry: Dictionary = raw[relic_id]
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
	for i in range(mini(player.slots.size(), run.player_slot_gems.size())):
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
		if slot.dual_type.is_empty():
			var dual_type := str(slot_snapshot.get("dual_type", ""))
			if not dual_type.is_empty():
				slot.dual_type = dual_type
		gem.owner_uid = player.uid
		gem.slot_index = i
		state.gems[gem.uid] = gem
	if not run.carried_gem.is_empty():
		var carried := create_gem_instance(
			_next_uid("gem"),
			str(run.carried_gem.get("gem_id", "")),
			run.carried_gem.get("def_overrides", {}) if run.carried_gem.get("def_overrides", {}) is Dictionary else {}
		)
		if not carried.gem_id.is_empty():
			carried.owner_uid = player.uid
			carried.slot_index = -1
			state.gems[carried.uid] = carried
			state.held_gem_uid = carried.uid


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
