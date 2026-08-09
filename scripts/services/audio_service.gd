extends Node

const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "Sfx"
const MENU_MUSIC_PATH := "res://assets/audio/menu_bgm_lawthief.ogg"
const BUS_LAYOUT := [
	{"name": BUS_MUSIC, "send": BUS_MASTER},
	{"name": BUS_SFX, "send": BUS_MASTER},
]
const TRACK_CONFIG := {
	"master": {"bus": BUS_MASTER, "enabled_setting": ""},
	"music": {"bus": BUS_MUSIC, "enabled_setting": "music_enabled"},
	"sfx": {"bus": BUS_SFX, "enabled_setting": "sfx_enabled"},
}

var _menu_music_player: AudioStreamPlayer = null
var _menu_music_requested: bool = false


func _enter_tree() -> void:
	_ensure_bus_layout()


func _ready() -> void:
	_ensure_menu_music_player()
	apply_settings()


func apply_settings() -> void:
	_ensure_bus_layout()
	for track_name in TRACK_CONFIG.keys():
		_apply_track_settings(track_name)
	_sync_menu_music_state()


func play_menu_music() -> void:
	_menu_music_requested = true
	_ensure_menu_music_player()
	_sync_menu_music_state()


func stop_menu_music() -> void:
	_menu_music_requested = false
	if _menu_music_player != null and _menu_music_player.playing:
		_menu_music_player.stop()


func get_track_volume_percent(track_name: String) -> int:
	if not TRACK_CONFIG.has(track_name):
		return 100
	if not is_instance_valid(SettingsService):
		return 100
	return SettingsService.get_track_volume_percent(track_name)


func set_track_volume_percent(track_name: String, percent: int) -> int:
	if not TRACK_CONFIG.has(track_name):
		return clampi(percent, 0, 100)
	return SettingsService.set_track_volume_percent(track_name, percent)


func set_all_track_volumes_percent(percent: int, track_names: Array = []) -> void:
	SettingsService.set_all_track_volumes_percent(percent, track_names)


func _ensure_bus_layout() -> void:
	for config in BUS_LAYOUT:
		var bus_name := str(config.get("name", ""))
		if bus_name.is_empty():
			continue
		_ensure_bus(bus_name, str(config.get("send", BUS_MASTER)))


func _ensure_bus(bus_name: String, send_bus: String) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		AudioServer.add_bus(AudioServer.bus_count)
		bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_index, bus_name)
	if bus_name != BUS_MASTER:
		AudioServer.set_bus_send(bus_index, send_bus)


func _apply_track_settings(track_name: String) -> void:
	var config: Dictionary = TRACK_CONFIG.get(track_name, {})
	var bus_name := str(config.get("bus", BUS_MASTER))
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		return
	var enabled_setting := str(config.get("enabled_setting", ""))
	var enabled := true
	if not enabled_setting.is_empty():
		enabled = bool(SettingsService.get_value(enabled_setting))
	AudioServer.set_bus_mute(bus_index, not enabled)
	AudioServer.set_bus_volume_db(bus_index, _percent_to_db(SettingsService.get_track_volume_percent(track_name)))


func _ensure_menu_music_player() -> void:
	if _menu_music_player != null:
		return
	_menu_music_player = AudioStreamPlayer.new()
	_menu_music_player.name = "MenuMusicPlayer"
	_menu_music_player.bus = BUS_MUSIC
	_menu_music_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_menu_music_player)
	if ResourceLoader.exists(MENU_MUSIC_PATH):
		var stream := load(MENU_MUSIC_PATH)
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		_menu_music_player.stream = stream


func _sync_menu_music_state() -> void:
	if _menu_music_player == null or _menu_music_player.stream == null:
		return
	var music_enabled := bool(SettingsService.get_value("music_enabled"))
	if _menu_music_requested and music_enabled:
		if not _menu_music_player.playing:
			_menu_music_player.play()
		return
	if _menu_music_player.playing:
		_menu_music_player.stop()


func _percent_to_db(percent: int) -> float:
	var clamped := clampi(percent, 0, 100)
	if clamped <= 0:
		return -80.0
	return linear_to_db(float(clamped) / 100.0)
