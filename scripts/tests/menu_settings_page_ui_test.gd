extends SceneTree

const MAIN_SCENE_PATH := "res://scenes/main/main.tscn"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var main_scene := load(MAIN_SCENE_PATH) as PackedScene
	_check(main_scene != null, "main scene should load")
	if main_scene == null:
		_finish()
		return
	var main_root := main_scene.instantiate()
	root.add_child(main_root)
	await process_frame
	await process_frame

	main_root.call("_show_settings_page")
	await process_frame

	var page_layer := main_root.get_node_or_null("PageLayer") as Control
	_check(page_layer != null and page_layer.visible, "settings should open as a page")
	if page_layer == null:
		main_root.free()
		_finish()
		return
	var switches := page_layer.find_children("*", "CheckButton", true, false)
	_check(switches.size() >= 3, "settings page should use switches for common toggles")
	var sliders := page_layer.find_children("*", "HSlider", true, false)
	_check(sliders.size() >= 3, "settings page should expose master, music, and sfx volume sliders")

	var settings_service: Node = root.get_node("SettingsService")
	var original_settings: Dictionary = settings_service.call("get_all")
	var tutorial_toggle := _control_for_row(page_layer, "教学提示", "CheckButton") as CheckButton
	_check(tutorial_toggle != null, "tutorial setting should expose an actionable switch")
	if tutorial_toggle != null:
		var tutorial_before := bool(settings_service.call("get_value", "show_tutorial"))
		tutorial_toggle.toggled.emit(not tutorial_before)
		await process_frame
		var tutorial_after := bool(settings_service.call("get_value", "show_tutorial"))
		settings_service.call("set_value", "show_tutorial", tutorial_before)
		_check(tutorial_after == not tutorial_before, "tutorial switch should update persisted settings")

	var master_slider := _control_for_row(page_layer, "主音量", "HSlider") as HSlider
	_check(master_slider != null and master_slider.editable, "master volume should expose an editable slider")
	if master_slider != null:
		var master_before := int(settings_service.call("get_track_volume_percent", "master"))
		var requested_master := 37 if master_before != 37 else 63
		master_slider.value = requested_master
		await process_frame
		var master_after := int(settings_service.call("get_track_volume_percent", "master"))
		settings_service.call("set_track_volume_percent", "master", master_before)
		_check(master_after == requested_master, "master slider should persist the selected volume")

	var reset_button := _control_for_row(page_layer, "恢复默认设置", "Button") as Button
	_check(reset_button != null, "settings page should expose the reset-to-defaults action")
	if reset_button != null:
		reset_button.pressed.emit()
		await process_frame
		await process_frame
		_check(bool(settings_service.call("get_value", "show_tutorial")), "reset should restore tutorial hints")
		_check(int(settings_service.call("get_track_volume_percent", "master")) == 100, "reset should restore master volume")
	settings_service.call("reset_to_defaults")
	for key in original_settings.keys():
		settings_service.call("set_value", str(key), original_settings[key])
	_check(settings_service.call("get_all") == original_settings, "test should restore the original persisted settings")

	var menu_music := main_root.get_node_or_null("MenuMusic") as AudioStreamPlayer
	if menu_music != null:
		menu_music.stop()
		await process_frame
		await create_timer(0.1).timeout
		menu_music.stream = null
		await process_frame
		menu_music.free()
	menu_music = null
	main_root.free()
	await process_frame
	await create_timer(0.1).timeout
	page_layer = null
	main_root = null
	main_scene = null
	_finish()


func _finish() -> void:
	if not _failures.is_empty():
		for failure in _failures:
			push_error(failure)
		quit(1)
		return
	print("MENU_SETTINGS_PAGE_UI_TEST_PASS")
	quit()


func _control_for_row(page: Control, title: String, control_type: String) -> Control:
	for row in page.find_children("*", "HBoxContainer", true, false):
		var has_title := false
		for label in row.find_children("*", "Label", true, false):
			if (label as Label).text == title:
				has_title = true
				break
		if not has_title:
			continue
		var controls := row.find_children("*", control_type, true, false)
		if not controls.is_empty():
			return controls[0] as Control
	return null


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
