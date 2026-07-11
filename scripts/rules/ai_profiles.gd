class_name AIProfiles
extends RefCounted
## Data-authored utility weights and pathfinding preferences.

const BalanceConfigValidator = preload("res://scripts/services/balance_config_validator.gd")
const CONFIG_PATH := "res://resources/combat/ai_profiles.json"

static var _loaded := false
static var _default_profile_id := ""
static var _aliases: Dictionary = {}
static var _tuning: Dictionary = {}
static var _path_defaults: Dictionary = {}
static var _profiles: Dictionary = {}

static func reload() -> void:
	_loaded = false
	_default_profile_id = ""
	_aliases = {}
	_tuning = {}
	_path_defaults = {}
	_profiles = {}
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


static func get_tuning_value(key: String) -> Variant:
	_ensure_loaded()
	if _tuning.has(key):
		return _tuning[key]
	push_error("AIProfiles: required tuning value missing: %s" % key)
	return 0.0


static func get_path_defaults() -> Dictionary:
	_ensure_loaded()
	return _path_defaults.duplicate(true)


static func get_profile_ids() -> Array[String]:
	_ensure_loaded()
	var ids: Array[String] = []
	for profile_id in _profiles.keys():
		ids.append(str(profile_id))
	for alias_id in _aliases.keys():
		if str(alias_id) not in ids:
			ids.append(str(alias_id))
	ids.sort()
	return ids


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var raw := _load_json(CONFIG_PATH)
	var errors := BalanceConfigValidator.validate_ai_profiles(raw)
	BalanceConfigValidator.ensure_valid(CONFIG_PATH, errors)
	if not errors.is_empty():
		return
	_default_profile_id = str(raw["default_profile"])
	_aliases = (raw["aliases"] as Dictionary).duplicate(true)
	_tuning = (raw["tuning"] as Dictionary).duplicate(true)
	_path_defaults = (raw["path_defaults"] as Dictionary).duplicate(true)
	var profile_defaults := raw["profile_defaults"] as Dictionary
	for profile_id in (raw["profiles"] as Dictionary).keys():
		_profiles[profile_id] = _merge_dict(
			profile_defaults,
			(raw["profiles"] as Dictionary)[profile_id] as Dictionary
		)


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
