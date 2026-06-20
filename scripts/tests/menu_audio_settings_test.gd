extends SceneTree


const SETTINGS_PATH := "user://settings.json"
const MENU_MUSIC_PATH := "res://assets/audio/menu_bgm_lawthief.ogg"
const MAIN_SCENE_PATH := "res://scenes/main/main.tscn"


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var had_settings := FileAccess.file_exists(SETTINGS_PATH)
	var backup := ""
	if had_settings:
		var read_file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		if read_file != null:
			backup = read_file.get_as_text()
			read_file.close()

	assert(ResourceLoader.exists(MENU_MUSIC_PATH), "menu music asset should exist")
	assert(ResourceLoader.exists(MAIN_SCENE_PATH), "main scene should exist")
	assert(AudioServer.get_bus_index("Music") >= 0, "music bus should be available")
	assert(AudioServer.get_bus_index("Sfx") >= 0, "sfx bus should be available")
	var main_scene := load(MAIN_SCENE_PATH) as PackedScene
	assert(main_scene != null, "main scene should load")
	var main_root := main_scene.instantiate()
	var menu_music := main_root.get_node_or_null("MenuMusic") as AudioStreamPlayer
	assert(menu_music != null, "main scene should include menu music player")
	assert(menu_music.bus == "Music", "menu music should route to music bus")
	assert(menu_music.autoplay, "menu music should autoplay on main menu")
	main_root.queue_free()

	var settings: Node = root.get_node("SettingsService")
	var audio: Node = root.get_node("AudioService")
	audio.play_menu_music()
	assert(settings.get_track_volume_percent("music") >= 0, "music volume should be readable")

	settings.set_track_volume_percent("music", 37)
	assert(settings.get_track_volume_percent("music") == 37, "music volume should persist percent")
	var music_bus := AudioServer.get_bus_index("Music")
	assert(absf(AudioServer.get_bus_volume_db(music_bus) - linear_to_db(0.37)) < 0.05, "music bus volume should follow settings")

	var track_names: Array[String] = ["music", "sfx"]
	settings.set_all_track_volumes_percent(64, track_names)
	assert(audio.get_track_volume_percent("music") == 64, "audio service should expose updated music volume")
	assert(settings.get_track_volume_percent("sfx") == 64, "batch volume change should update sfx track")

	settings.set_value("music_enabled", false)
	assert(AudioServer.is_bus_mute(music_bus), "disabling music should mute music bus")
	settings.set_value("music_enabled", true)
	assert(not AudioServer.is_bus_mute(music_bus), "re-enabling music should unmute music bus")

	audio.stop_menu_music()
	_restore_settings(had_settings, backup)
	print("MENU_AUDIO_SETTINGS_TEST_PASS")
	quit()


func _restore_settings(had_settings: bool, backup: String) -> void:
	if had_settings:
		var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
		if file != null:
			file.store_string(backup)
			file.close()
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
