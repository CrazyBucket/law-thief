class_name CombatConfig
extends RefCounted

const CONFIG_PATH := "res://resources/combat/combat_config.json"

static var _loaded := false
static var _config: Dictionary = {}


static func reload() -> void:
	_loaded = false
	_config = {}
	_ensure_loaded()


static func split_attack_damage_ratio() -> float:
	return float_value("split_attack_damage_ratio", Constants.SPLIT_ATTACK_DAMAGE_RATIO)


static func explosion_cross_damage() -> int:
	return int_value("explosion_cross_damage", Constants.EXPLOSION_CROSS_DAMAGE)


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


static func fire_duration() -> int:
	return int_value("fire_duration", Constants.FIRE_DURATION)


static func fire_spread_chance() -> float:
	return float_value("fire_spread_chance", Constants.FIRE_SPREAD_CHANCE)


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
