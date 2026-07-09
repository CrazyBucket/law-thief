class_name StatusConfig
extends RefCounted

const BalanceConfigValidator = preload("res://scripts/services/balance_config_validator.gd")
const CONFIG_PATH := "res://resources/combat/status_config.json"

const _DEFAULTS := {
	"poison": {"default_stacks": 1, "default_duration": 2},
	"burning": {"default_stacks": 1, "default_duration": 0, "firelike_stack_mult": 2},
	"armor": {"default_duration": 1},
	"shield": {"default_duration": 0},
	"rooted": {"default_duration": 2},
	"exposed": {"default_duration": 1},
	"lawless": {"default_duration": 0},
	"bomb_rat_plunder": {"default_duration": 0},
	"paralyzed": {"default_duration": 1},
	"slowed": {"default_stacks": 1, "default_duration": 0, "min_move_points": 1},
	"wet": {"default_duration": 2},
	"sluggish": {"default_duration": 1},
	"vulnerable": {"default_duration": 1, "damage_taken_mult": 1.5},
	"weak": {"default_duration": 1, "attack_damage_mult": 0.75},
	"light_exposed": {"default_stacks": 1, "default_duration": 0},
	"blinded": {"default_duration": 1},
	"counter_mark": {"default_duration": 1, "default_level": 1},
	"extra_attack": {"default_stacks": 1},
	"extra_move": {"default_stacks": 1},
}

static var _loaded := false
static var _config: Dictionary = {}


static func reload() -> void:
	_loaded = false
	_config = {}
	_ensure_loaded()


static func default_stacks(entry_id: String, fallback: int = 1) -> int:
	return int_value(entry_id, "default_stacks", fallback)


static func default_duration(entry_id: String, fallback: int = 0) -> int:
	return int_value(entry_id, "default_duration", fallback)


static func default_level(entry_id: String, fallback: int = 1) -> int:
	return int_value(entry_id, "default_level", fallback)


static func float_value(entry_id: String, field_id: String, fallback: float) -> float:
	_ensure_loaded()
	var entry: Dictionary = _config.get(entry_id, {})
	return float(entry.get(field_id, fallback))


static func int_value(entry_id: String, field_id: String, fallback: int) -> int:
	_ensure_loaded()
	var entry: Dictionary = _config.get(entry_id, {})
	return int(entry.get(field_id, fallback))


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_config = _DEFAULTS.duplicate(true)
	var raw := _load_json(CONFIG_PATH)
	if raw.is_empty():
		return
	BalanceConfigValidator.ensure_valid(CONFIG_PATH, BalanceConfigValidator.validate_status_config(raw))
	_config = _merge_entries(_config, raw)


static func _merge_entries(base: Dictionary, overrides: Dictionary) -> Dictionary:
	var merged := base.duplicate(true)
	for entry_id in overrides.keys():
		var override_entry: Variant = overrides[entry_id]
		if override_entry is Dictionary:
			var base_entry: Dictionary = merged.get(entry_id, {})
			for field_id in (override_entry as Dictionary).keys():
				base_entry[field_id] = (override_entry as Dictionary)[field_id]
			merged[entry_id] = base_entry
		else:
			merged[entry_id] = override_entry
	return merged


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
		push_warning("StatusConfig: JSON parse error in %s - %s" % [path, json.get_error_message()])
		return {}
	var data: Variant = json.get_data()
	if data is Dictionary:
		return (data as Dictionary).duplicate(true)
	push_warning("StatusConfig: expected JSON object in %s" % path)
	return {}
