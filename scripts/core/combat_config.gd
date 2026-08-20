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


static func attack_range() -> int:
	return int_value("attack_range")


static func extract_range() -> int:
	return int_value("extract_range")


static func insert_range() -> int:
	return int_value("insert_range")


static func trigger_range() -> int:
	return int_value("trigger_range")


static func split_attack_range() -> int:
	return int_value("split_attack_range")


static func explosion_damage() -> int:
	return int_value("explosion_damage")


static func explosion_radius() -> int:
	return int_value("explosion_radius")


static func explosion_cross_damage() -> int:
	return int_value("explosion_cross_damage")


static func explosion_death_radius() -> int:
	return int_value("explosion_death_radius")


static func charge_explode_dash_range() -> int:
	return int_value("charge_explode_dash_range")


static func knockback_collision_damage() -> int:
	return int_value("knockback_collision_damage")


static func star_relocation_max_distance() -> int:
	return maxi(1, int_value("star_relocation_max_distance"))


static func star_relocation_squeeze_damage_per_tile() -> int:
	return maxi(0, int_value("star_relocation_squeeze_damage_per_tile"))


static func spike_damage() -> int:
	return int_value("spike_damage")


static func spike_collision_damage() -> int:
	return int_value("spike_collision_damage")


static func barrel_explosion_damage() -> int:
	return int_value("barrel_explosion_damage")


static func barrel_explosion_radius() -> int:
	return int_value("barrel_explosion_radius")


static func barrel_hp() -> int:
	return int_value("barrel_hp")


static func gravity_collision_damage() -> int:
	return int_value("gravity_collision_damage")


static func poison_fog_damage() -> int:
	return int_value("poison_fog_damage")


static func poison_fog_duration() -> int:
	return int_value("poison_fog_duration")


static func toxic_smoke_duration() -> int:
	return int_value("toxic_smoke_duration")


static func poison_puddle_duration() -> int:
	return int_value("poison_puddle_duration")


static func water_move_cost_extra() -> float:
	return float_value("water_move_cost_extra")


static func arc_proc_chance() -> float:
	return float_value("arc_proc_chance")


static func arc_paralysis_chance() -> float:
	return float_value("arc_paralysis_chance")


static func arc_chain_damage_ratio() -> float:
	return float_value("arc_chain_damage_ratio")


static func arc_chain_range() -> int:
	return int_value("arc_chain_range")


static func lightning_death_damage() -> int:
	return int_value("lightning_death_damage")


static func split_death_hp_merge_divisor() -> int:
	return maxi(1, int_value("split_death_hp_merge_divisor"))


static func overload_gem_op_damage_amount() -> int:
	return int_value("overload_gem_op_damage_amount")


static func overload_ai_control_min_chapter() -> int:
	return int_value("overload_ai_control_min_chapter")


static func overload_ai_control_max_chapter() -> int:
	return int_value("overload_ai_control_max_chapter")


static func overload_ai_control_base_percent() -> float:
	return float_value("overload_ai_control_base_percent")


static func overload_ai_control_chapter_baseline() -> int:
	return int_value("overload_ai_control_chapter_baseline")


static func overload_ai_control_chapter_penalty() -> float:
	return float_value("overload_ai_control_chapter_penalty")


static func overload_ai_control_gem_baseline() -> int:
	return int_value("overload_ai_control_gem_baseline")


static func overload_ai_control_gem_penalty() -> float:
	return float_value("overload_ai_control_gem_penalty")


static func overload_ai_control_min_probability() -> float:
	return float_value("overload_ai_control_min_probability")


static func overload_ai_control_max_probability() -> float:
	return float_value("overload_ai_control_max_probability")


static func fire_duration() -> int:
	return int_value("fire_duration")


static func fire_spread_chance() -> float:
	return float_value("fire_spread_chance")


static func grass_grow_chance() -> float:
	return float_value("grass_grow_chance")


static func int_value(key: String) -> int:
	return int(_required_value(key))


static func float_value(key: String) -> float:
	return float(_required_value(key))


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var raw := _load_json(CONFIG_PATH)
	var errors := BalanceConfigValidator.validate_combat_config(raw)
	BalanceConfigValidator.ensure_valid(CONFIG_PATH, errors)
	_config = raw.duplicate(true) if errors.is_empty() else {}


static func _required_value(key: String) -> Variant:
	_ensure_loaded()
	if _config.has(key):
		return _config[key]
	push_error("CombatConfig: required value missing: %s" % key)
	return 0


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
