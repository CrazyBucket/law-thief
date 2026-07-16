extends Node

const SETTINGS_VERSION := 1
const _PersistencePathPolicy = preload("res://scripts/services/persistence_path_policy.gd")
const DEFAULTS := {
	"fullscreen": false,
	"show_tutorial": true,
	"music_enabled": true,
	"sfx_enabled": true,
	"audio_volumes": {
		"master": 100,
		"music": 100,
		"sfx": 100,
	},
	"battle_animation_speed": 1.0,
}

var _settings: Dictionary = {}


func _ready() -> void:
	load_settings()
	apply_runtime_settings()


func _default_settings() -> Dictionary:
	var defaults := DEFAULTS.duplicate(true)
	defaults["battle_editor_enabled"] = OS.is_debug_build()
	return defaults


func get_value(key: String):
	if _settings.has(key):
		return _settings[key]
	return _default_settings().get(key)


func get_all() -> Dictionary:
	return _settings.duplicate(true)


func get_settings_path() -> String:
	return _PersistencePathPolicy.settings_path()


func set_value(key: String, value) -> void:
	_settings[key] = value
	save_settings()
	apply_runtime_settings()


func reset_to_defaults() -> void:
	_settings = _default_settings()
	save_settings()
	apply_runtime_settings()


func toggle_bool(key: String) -> bool:
	var next_value := not bool(get_value(key))
	set_value(key, next_value)
	return next_value


func get_track_volume_percent(track_name: String) -> int:
	var defaults: Dictionary = _default_audio_volumes()
	var volumes_variant: Variant = get_value("audio_volumes")
	if not volumes_variant is Dictionary:
		return int(defaults.get(track_name, 100))
	var volumes: Dictionary = volumes_variant
	return int(clampi(int(volumes.get(track_name, defaults.get(track_name, 100))), 0, 100))


func set_track_volume_percent(track_name: String, percent: int) -> int:
	var volumes := _get_audio_volumes()
	volumes[track_name] = clampi(percent, 0, 100)
	_settings["audio_volumes"] = volumes
	save_settings()
	apply_runtime_settings()
	return int(volumes[track_name])


func set_all_track_volumes_percent(percent: int, track_names: Array = []) -> void:
	var volumes := _get_audio_volumes()
	var target_tracks := track_names
	if target_tracks.is_empty():
		target_tracks = ["master", "music", "sfx"]
	var clamped := clampi(percent, 0, 100)
	for track_name in target_tracks:
		volumes[str(track_name)] = clamped
	_settings["audio_volumes"] = volumes
	save_settings()
	apply_runtime_settings()


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
	_settings = _default_settings()
	var settings_path := get_settings_path()
	if not FileAccess.file_exists(settings_path):
		save_settings()
		return
	var file := FileAccess.open(settings_path, FileAccess.READ)
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
	_settings["audio_volumes"] = _get_audio_volumes()


func save_settings() -> void:
	var settings_path := get_settings_path()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(settings_path).get_base_dir())
	var payload := {
		"version": SETTINGS_VERSION,
		"settings": _settings,
	}
	var file := FileAccess.open(settings_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()


func apply_runtime_settings() -> void:
	var fullscreen := bool(get_value("fullscreen"))
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)
	var root: Window = Engine.get_main_loop().root
	if root == null:
		return
	var audio_service := root.get_node_or_null("AudioService")
	if audio_service != null and audio_service.has_method("apply_settings"):
		audio_service.apply_settings()


func _default_audio_volumes() -> Dictionary:
	return (DEFAULTS.get("audio_volumes", {}) as Dictionary).duplicate(true)


func _get_audio_volumes() -> Dictionary:
	var volumes := _default_audio_volumes()
	var current: Variant = _settings.get("audio_volumes", {})
	if current is Dictionary:
		for key in (current as Dictionary).keys():
			volumes[str(key)] = clampi(int((current as Dictionary)[key]), 0, 100)
	return volumes
