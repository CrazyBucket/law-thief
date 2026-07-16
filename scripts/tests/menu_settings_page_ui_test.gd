extends SceneTree

const MAIN_SCENE_PATH := "res://scenes/main/main.tscn"


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var main_scene := load(MAIN_SCENE_PATH) as PackedScene
	assert(main_scene != null, "main scene should load")
	var main_root := main_scene.instantiate()
	root.add_child(main_root)
	await process_frame
	await process_frame

	main_root.call("_show_settings_page")
	await process_frame

	var page_layer := main_root.get_node_or_null("PageLayer") as Control
	assert(page_layer != null and page_layer.visible, "settings should open as a page")
	var switches := page_layer.find_children("*", "CheckButton", true, false)
	assert(switches.size() >= 3, "settings page should use switches for common toggles")
	var sliders := page_layer.find_children("*", "HSlider", true, false)
	assert(sliders.size() >= 3, "settings page should expose master, music, and sfx volume sliders")

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
	print("MENU_SETTINGS_PAGE_UI_TEST_PASS")
	quit()
