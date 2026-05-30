extends Node

const SETTINGS_PATH := "user://settings.json"
const SETTINGS_VERSION := 1
const DEFAULTS := {
	"fullscreen": false,
	"show_tutorial": true,
	"music_enabled": true,
	"sfx_enabled": true,
	"battle_animation_speed": 1.0,
}

var _settings: Dictionary = DEFAULTS.duplicate(true)


func _ready() -> void:
	load_settings()
	apply_runtime_settings()


func get_value(key: String):
	if _settings.has(key):
		return _settings[key]
	return DEFAULTS.get(key)


func get_all() -> Dictionary:
	return _settings.duplicate(true)


func set_value(key: String, value) -> void:
	_settings[key] = value
	save_settings()
	apply_runtime_settings()


func toggle_bool(key: String) -> bool:
	var next_value := not bool(get_value(key))
	set_value(key, next_value)
	return next_value


func get_animation_speed_scale() -> float:
	return float(get_value("battle_animation_speed"))


func set_animation_speed_scale(speed_scale: float) -> void:
	set_value("battle_animation_speed", clampf(speed_scale, 0.5, 2.0))


func cycle_animation_speed(step: int) -> float:
	var options := [0.75, 1.0, 1.5, 2.0]
	var current := get_animation_speed_scale()
	var index := options.find(current)
	if index < 0:
		index = 1
	index = clampi(index + step, 0, options.size() - 1)
	set_animation_speed_scale(float(options[index]))
	return get_animation_speed_scale()


func load_settings() -> void:
	_settings = DEFAULTS.duplicate(true)
	if not FileAccess.file_exists(SETTINGS_PATH):
		save_settings()
		return
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return
	var data: Variant = json.get_data()
	if not data is Dictionary:
		return
	var dict := data as Dictionary
	var payload: Variant = dict.get("settings", {})
	if payload is Dictionary:
		for key in (payload as Dictionary).keys():
			_settings[key] = (payload as Dictionary)[key]


func save_settings() -> void:
	var payload := {
		"version": SETTINGS_VERSION,
		"settings": _settings,
	}
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()


func apply_runtime_settings() -> void:
	var fullscreen := bool(get_value("fullscreen"))
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)
