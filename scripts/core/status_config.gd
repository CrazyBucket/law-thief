class_name StatusConfig
extends RefCounted

const BalanceConfigValidator = preload("res://scripts/services/balance_config_validator.gd")
const CONFIG_PATH := "res://resources/combat/status_config.json"

static var _loaded := false
static var _config: Dictionary = {}


static func reload() -> void:
	_loaded = false
	_config = {}
	_ensure_loaded()


static func default_stacks(entry_id: String) -> int:
	return int_value(entry_id, "default_stacks")


static func default_duration(entry_id: String) -> int:
	return int_value(entry_id, "default_duration")


static func float_value(entry_id: String, field_id: String) -> float:
	return float(_required_value(entry_id, field_id))


static func int_value(entry_id: String, field_id: String) -> int:
	return int(_required_value(entry_id, field_id))


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var raw := _load_json(CONFIG_PATH)
	var errors := BalanceConfigValidator.validate_status_config(raw)
	BalanceConfigValidator.ensure_valid(CONFIG_PATH, errors)
	_config = raw.duplicate(true) if errors.is_empty() else {}


static func _required_value(entry_id: String, field_id: String) -> Variant:
	_ensure_loaded()
	var entry: Variant = _config.get(entry_id, null)
	if entry is Dictionary and (entry as Dictionary).has(field_id):
		return (entry as Dictionary)[field_id]
	push_error("StatusConfig: required value missing: %s.%s" % [entry_id, field_id])
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
		push_warning("StatusConfig: JSON parse error in %s - %s" % [path, json.get_error_message()])
		return {}
	var data: Variant = json.get_data()
	if data is Dictionary:
		return (data as Dictionary).duplicate(true)
	push_warning("StatusConfig: expected JSON object in %s" % path)
	return {}
