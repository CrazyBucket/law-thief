class_name AIProfiles
extends RefCounted
## AI 鎬ф牸閰嶇疆 鈥斺€?鏁版嵁椹卞姩鐨勬潈閲嶇郴缁?

const BalanceConfigValidator = preload("res://scripts/services/balance_config_validator.gd")
const CONFIG_PATH := "res://resources/combat/ai_profiles.json"

static var _loaded := false
static var _default_profile_id := "melee_chase"
static var _aliases: Dictionary = {
	"bomb_rat": "bomb_rat",
	"stone_bow": "stone_bow",
	"patrol_guard": "melee_chase",
	"fission_slime": "melee_chase",
}
static var _tuning: Dictionary = {
	"ranged_keep_distance_scale": 0.3,
	"explosion_adjacent_bonus_mult": 2.0,
	"pull_base_bonus": 8.0,
	"pull_damage_bonus_mult": 0.5,
	"pull_distance_score_mult": 1.2,
	"arc_chain_bonus_mult": 0.5,
	"approach_progress_floor": 0.25,
	"path_self_damage_ratio": 0.25,
}
static var _profiles: Dictionary = {
	"melee_chase": {
		"w_damage": 10.0,
		"w_kill_player": 150.0,
		"w_self_sacrifice": -20.0,
		"w_self_damage": 8.0,
		"w_friendly_fire": 30.0,
		"w_approach": 6.0,
		"w_move_cost": 0.5,
		"w_pull": 0.0,
		"w_poison": 0.0,
		"wait_score": -10.0,
		"can_extract": false,
		"prefer_distance": false,
		"guard_ally": false,
	},
	"stone_bow": {
		"w_damage": 10.0,
		"w_kill_player": 150.0,
		"w_self_sacrifice": -25.0,
		"w_self_damage": 8.0,
		"w_friendly_fire": 25.0,
		"w_approach": 2.0,
		"w_move_cost": 0.4,
		"w_deploy_bonus": 14.0,
		"w_keep_distance": 5.0,
		"wait_score": 2.0,
		"can_ranged_attack": true,
		"prefer_distance": true,
		"can_extract": false,
		"guard_ally": false,
	},
	"bomb_rat": {
		"w_approach": 10.0,
		"wait_score": -50.0,
		"can_extract": false,
	},
}


static func reload() -> void:
	_loaded = false
	_ensure_loaded()


static func get_profile(ai_profile_id: String) -> Dictionary:
	_ensure_loaded()
	var resolved_id := str(_aliases.get(ai_profile_id, ai_profile_id))
	if _profiles.has(resolved_id):
		return (_profiles[resolved_id] as Dictionary).duplicate(true)
	return (_profiles.get(_default_profile_id, {}) as Dictionary).duplicate(true)


static func get_tuning() -> Dictionary:
	_ensure_loaded()
	return _tuning.duplicate(true)


static func get_tuning_value(key: String, fallback: Variant = null) -> Variant:
	_ensure_loaded()
	if _tuning.has(key):
		return _tuning.get(key)
	return fallback


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var raw := _load_json(CONFIG_PATH)
	if raw.is_empty():
		return
	BalanceConfigValidator.ensure_valid(CONFIG_PATH, BalanceConfigValidator.validate_ai_profiles(raw))
	_default_profile_id = str(raw.get("default_profile", _default_profile_id))
	var aliases: Variant = raw.get("aliases", {})
	if aliases is Dictionary:
		_aliases = (aliases as Dictionary).duplicate(true)
	var tuning: Variant = raw.get("tuning", {})
	if tuning is Dictionary:
		_tuning = _merge_dict(_tuning, tuning as Dictionary)
	var profiles: Variant = raw.get("profiles", {})
	if profiles is Dictionary:
		_profiles = (profiles as Dictionary).duplicate(true)


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
		push_warning("AIProfiles: JSON parse error in %s - %s" % [path, json.get_error_message()])
		return {}
	var data: Variant = json.get_data()
	if data is Dictionary:
		return (data as Dictionary).duplicate(true)
	push_warning("AIProfiles: expected JSON object in %s" % path)
	return {}


static func _merge_dict(base: Dictionary, overrides: Dictionary) -> Dictionary:
	var merged := base.duplicate(true)
	for key in overrides.keys():
		merged[key] = overrides[key]
	return merged
