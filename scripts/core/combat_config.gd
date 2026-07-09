class_name CombatConfig
extends RefCounted

const BalanceConfigValidator = preload("res://scripts/services/balance_config_validator.gd")
const CONFIG_PATH := "res://resources/combat/combat_config.json"

static var _loaded := false
static var _config: Dictionary = {}


static func reload() -> void:
	_loaded = false
	_config = {}
	_ensure_loaded()


static func split_attack_damage_ratio() -> float:
	return float_value("split_attack_damage_ratio", Constants.SPLIT_ATTACK_DAMAGE_RATIO)


static func attack_range() -> int:
	return int_value("attack_range", Constants.ATTACK_RANGE)


static func extract_range() -> int:
	return int_value("extract_range", Constants.EXTRACT_RANGE)


static func insert_range() -> int:
	return int_value("insert_range", Constants.INSERT_RANGE)


static func trigger_range() -> int:
	return int_value("trigger_range", Constants.TRIGGER_RANGE)


static func split_attack_range() -> int:
	return int_value("split_attack_range", Constants.SPLIT_ATTACK_RANGE)


static func split_damage_redirect_ratio() -> float:
	return float_value("split_damage_redirect_ratio", Constants.SPLIT_DAMAGE_REDIRECT_RATIO)


static func split_surround_radius() -> int:
	return int_value("split_surround_radius", Constants.SPLIT_SURROUND_RADIUS)


static func split_black_stat_ratio() -> float:
	return float_value("split_black_stat_ratio", Constants.SPLIT_STAT_RATIO)


static func explosion_damage() -> int:
	return int_value("explosion_damage", Constants.EXPLOSION_DAMAGE)


static func explosion_radius() -> int:
	return int_value("explosion_radius", Constants.EXPLOSION_RADIUS)


static func explosion_cross_damage() -> int:
	return int_value("explosion_cross_damage", Constants.EXPLOSION_CROSS_DAMAGE)


static func explosion_death_radius() -> int:
	return int_value("explosion_death_radius", Constants.EXPLOSION_DEATH_RADIUS)


static func charge_explode_dash_range() -> int:
	return int_value("charge_explode_dash_range", Constants.CHARGE_EXPLODE_DASH_RANGE)


static func knockback_collision_damage() -> int:
	return int_value("knockback_collision_damage", Constants.KNOCKBACK_COLLISION_DAMAGE)


static func spike_damage() -> int:
	return int_value("spike_damage", Constants.SPIKE_DAMAGE)


static func spike_collision_damage() -> int:
	return int_value("spike_collision_damage", Constants.SPIKE_COLLISION_DAMAGE)


static func barrel_explosion_damage() -> int:
	return int_value("barrel_explosion_damage", Constants.BARREL_EXPLOSION_DAMAGE)


static func barrel_hp() -> int:
	return int_value("barrel_hp", Constants.BARREL_HP)


static func gravity_collision_damage() -> int:
	return int_value("gravity_collision_damage", Constants.GRAVITY_COLLISION_DAMAGE)


static func enemy_gravity_pull_range() -> int:
	return int_value("enemy_gravity_pull_range", Constants.ENEMY_GRAVITY_PULL_RANGE)


static func poison_fog_damage() -> int:
	return int_value("poison_fog_damage", Constants.POISON_FOG_DAMAGE)


static func poison_fog_duration() -> int:
	return int_value("poison_fog_duration", Constants.POISON_FOG_DURATION)


static func arc_proc_chance() -> float:
	return float_value("arc_proc_chance", Constants.ARC_PROC_CHANCE)


static func arc_paralysis_chance() -> float:
	return float_value("arc_paralysis_chance", Constants.ARC_PARALYSIS_CHANCE)


static func arc_chain_damage_ratio() -> float:
	return float_value("arc_chain_damage_ratio", Constants.ARC_CHAIN_DAMAGE_RATIO)


static func arc_chain_range() -> int:
	return int_value("arc_chain_range", Constants.ARC_CHAIN_RANGE)


static func arc_hit_damage() -> int:
	return int_value("arc_hit_damage", Constants.ARC_HIT_DAMAGE)


static func lightning_death_damage() -> int:
	return int_value("lightning_death_damage", Constants.LIGHTNING_DEATH_DAMAGE)


static func fire_death_fire_count() -> int:
	return int_value("fire_death_fire_count", Constants.FIRE_DEATH_FIRE_COUNT)


static func fire_death_radius() -> int:
	return int_value("fire_death_radius", Constants.FIRE_DEATH_RADIUS)


static func ice_death_radius() -> int:
	return int_value("ice_death_radius", Constants.ICE_DEATH_RADIUS)


static func split_death_hp_merge_divisor() -> int:
	return maxi(1, int_value("split_death_hp_merge_divisor", Constants.SPLIT_DEATH_HP_MERGE_DIVISOR))


static func overload_gem_op_damage_amount() -> int:
	return int_value("overload_gem_op_damage_amount", Constants.OVERLOAD_GEM_OP_DAMAGE_AMOUNT)


static func overload_ai_control_min_chapter() -> int:
	return int_value("overload_ai_control_min_chapter", 1)


static func overload_ai_control_max_chapter() -> int:
	return int_value("overload_ai_control_max_chapter", 45)


static func overload_ai_control_base_percent() -> float:
	return float_value("overload_ai_control_base_percent", 75.0)


static func overload_ai_control_chapter_baseline() -> int:
	return int_value("overload_ai_control_chapter_baseline", 3)


static func overload_ai_control_chapter_penalty() -> float:
	return float_value("overload_ai_control_chapter_penalty", 1.0)


static func overload_ai_control_gem_baseline() -> int:
	return int_value("overload_ai_control_gem_baseline", 9)


static func overload_ai_control_gem_penalty() -> float:
	return float_value("overload_ai_control_gem_penalty", 7.0)


static func overload_ai_control_min_probability() -> float:
	return float_value("overload_ai_control_min_probability", 0.0)


static func overload_ai_control_max_probability() -> float:
	return float_value("overload_ai_control_max_probability", 0.95)


static func fire_duration() -> int:
	return int_value("fire_duration", Constants.FIRE_DURATION)


static func fire_spread_chance() -> float:
	return float_value("fire_spread_chance", Constants.FIRE_SPREAD_CHANCE)


static func grass_grow_chance() -> float:
	return float_value("grass_grow_chance", Constants.GRASS_GROW_CHANCE)


static func int_value(key: String, fallback: int) -> int:
	_ensure_loaded()
	return int(_config.get(key, fallback))


static func float_value(key: String, fallback: float) -> float:
	_ensure_loaded()
	return float(_config.get(key, fallback))


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_config = _load_json(CONFIG_PATH)
	if not _config.is_empty():
		BalanceConfigValidator.ensure_valid(CONFIG_PATH, BalanceConfigValidator.validate_combat_config(_config))


static func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning("CombatConfig: JSON parse error in %s - %s" % [path, json.get_error_message()])
		return {}
	var data: Variant = json.get_data()
	if data is Dictionary:
		return (data as Dictionary).duplicate(true)
	push_warning("CombatConfig: expected JSON object in %s" % path)
	return {}
