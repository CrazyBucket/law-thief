extends SceneTree

const BATTLE_SCENE_PATH := "res://scenes/battle/battle_scene.tscn"

class EndTurnShortcutController:
	extends BattleController
	var begin_enemy_phase_calls: int = 0

	func begin_enemy_phase() -> Dictionary:
		begin_enemy_phase_calls += 1
		state.phase = Constants.PHASE_ENDED
		return {}


var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var settings: Node = root.get_node("SettingsService")
	var game_service: Node = root.get_node("GameService")
	var original_settings: Dictionary = settings.call("get_all")
	var previous_mode := str(game_service.get("pending_battle_mode"))
	var previous_encounter := str(game_service.get("pending_encounter_id"))
	settings.call("set_value", "show_tutorial", false)
	game_service.set("pending_battle_mode", "normal")
	game_service.set("pending_encounter_id", "tutorial_001")

	var packed := load(BATTLE_SCENE_PATH) as PackedScene
	_check(packed != null, "battle scene should load")
	if packed == null:
		_restore(settings, original_settings, game_service, previous_mode, previous_encounter)
		_finish()
		return
	var battle := packed.instantiate()
	root.add_child(battle)
	await process_frame
	await process_frame

	var menu_button := battle.get_node_or_null(
		"SystemMenuHud/Root/MenuBtn"
	) as Button
	_check(menu_button != null, "battle HUD should expose a top-corner menu entry")
	if menu_button != null:
		_check(menu_button.anchor_left == 1.0 and menu_button.offset_top <= 8.0, "menu entry should stay in the upper-right corner")
		_check(menu_button.text.is_empty(), "battle menu entry should not use a text glyph as its icon")
		_check(menu_button.icon != null, "battle menu entry should use a dedicated texture icon")
		_check(menu_button.flat, "battle menu icon should not have a button frame")
		if menu_button.icon != null:
			_check(
				menu_button.icon.resource_path == "res://assets/ui/system_menu_gear.png",
				"battle menu entry should use the shared system gear"
			)
	_check(
		battle.get_node_or_null("HudLayer/BottomDock/BottomBar/TurnGroup/VBox/Row/MenuBtn") == null,
		"battle menu entry should not occupy the command dock"
	)
	_check(InputMap.has_action("pause_menu"), "pause_menu input action should exist")
	_check(_action_has_physical_key("pause_menu", KEY_ESCAPE), "Esc should map to pause_menu")
	_check(_action_has_physical_key("end_turn", KEY_E), "E should map to end_turn")

	var escape_event := InputEventKey.new()
	escape_event.physical_keycode = KEY_ESCAPE
	escape_event.pressed = true
	battle.call("_input", escape_event)
	var menu = battle.get("_battle_menu")
	_check(menu != null and menu.is_open(), "Esc should open the battle menu")
	if menu != null:
		_check(
			menu.get_script() != null
				and str(menu.get_script().resource_path) == "res://scripts/ui/system_pause_menu.gd",
			"battle should use the shared system menu"
		)
		var settings_button := menu.find_child("SettingsButton", true, false) as Button
		var save_button := menu.find_child("SaveAndExitButton", true, false) as Button
		var title_art := menu.find_child("TitleArt", true, false) as TextureRect
		_check(settings_button != null, "battle menu should expose settings")
		_check(save_button != null, "battle menu should expose save and return")
		_check(title_art != null and title_art.visible and title_art.texture != null, "battle menu should reuse the title treatment from the opening menu")
		if settings_button != null:
			_check(
				settings_button.get_script() != null
				and str(settings_button.get_script().resource_path) == "res://scripts/ui/pixel_menu_button.gd",
				"battle menu actions should use the opening menu button style"
			)
		if settings_button != null:
			settings_button.pressed.emit()
			await process_frame
			_check(menu.is_settings_page(), "settings should open as a second-level page")
			_check(menu.find_children("*", "HSlider", true, false).size() >= 3, "battle settings should expose audio sliders")
			_check(menu.find_children("*", "CheckButton", true, false).size() >= 4, "battle settings should expose common toggles")
			menu.handle_cancel()
			_check(menu.is_open() and not menu.is_settings_page(), "Esc from settings should return to the battle menu")

		battle.call("_input", escape_event)
		_check(not menu.is_open(), "Esc from the battle menu should resume battle")

	var controller: BattleController = battle.get("_controller")
	var phase_before := str(controller.state.phase)
	menu.open_menu()
	var end_turn_event := InputEventKey.new()
	end_turn_event.physical_keycode = KEY_E
	end_turn_event.unicode = 101
	end_turn_event.pressed = true
	battle.call("_unhandled_input", end_turn_event)
	_check(str(controller.state.phase) == phase_before, "E should not end the turn while the menu is open")
	menu.close_menu()
	var shortcut_controller := EndTurnShortcutController.new()
	shortcut_controller.state = controller.state.clone()
	shortcut_controller.state.phase = Constants.PHASE_PLAYER
	battle.set("_controller", shortcut_controller)
	var tutorial_guard := Control.new()
	battle.add_child(tutorial_guard)
	battle.set("_tutorial_overlay", tutorial_guard)
	battle.call("_unhandled_input", end_turn_event)
	_check(shortcut_controller.begin_enemy_phase_calls == 0, "E should not end the turn behind the tutorial")
	battle.set("_tutorial_overlay", null)
	tutorial_guard.queue_free()
	battle.call("_unhandled_input", end_turn_event)
	_check(
		shortcut_controller.begin_enemy_phase_calls == 1,
		"E should end the player turn during battle"
	)

	var map_packed := load("res://scenes/map/adventure_map.tscn") as PackedScene
	_check(map_packed != null, "adventure map scene should load")
	if map_packed != null:
		var map_scene := map_packed.instantiate()
		var map_menu_button := map_scene.get_node_or_null("SystemMenuHud/Root/MenuBtn") as Button
		_check(map_menu_button != null, "adventure map should expose the same top-corner menu entry")
		if map_menu_button != null and menu_button != null:
			_check(map_menu_button.flat, "adventure map menu icon should not have a button frame")
			_check(map_menu_button.icon != null, "adventure map should use the shared system gear")
			if map_menu_button.icon != null:
				_check(
					map_menu_button.icon.resource_path == "res://assets/ui/system_menu_gear.png",
					"adventure map menu entry should use the shared system gear"
				)
			_check(
				map_menu_button.anchor_left == menu_button.anchor_left
					and map_menu_button.offset_left == menu_button.offset_left
					and map_menu_button.offset_top == menu_button.offset_top
					and map_menu_button.offset_right == menu_button.offset_right
					and map_menu_button.offset_bottom == menu_button.offset_bottom,
				"map and battle menu entries should occupy the same screen position"
			)
		var old_map_back := map_scene.get_node_or_null("HudLayer/ActionPanel/ActionRow/BackBtn") as Button
		_check(old_map_back == null or not old_map_back.visible, "map should not expose a separate main-menu button")
		map_scene.free()

	battle.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	_restore(settings, original_settings, game_service, previous_mode, previous_encounter)
	_finish()


func _action_has_physical_key(action: StringName, keycode: Key) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == keycode:
			return true
	return false


func _restore(
	settings: Node,
	original_settings: Dictionary,
	game_service: Node,
	previous_mode: String,
	previous_encounter: String
) -> void:
	settings.call("reset_to_defaults")
	for key in original_settings.keys():
		settings.call("set_value", str(key), original_settings[key])
	game_service.set("pending_battle_mode", previous_mode)
	game_service.set("pending_encounter_id", previous_encounter)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if not _failures.is_empty():
		for failure in _failures:
			push_error(failure)
		quit(1)
		return
	print("BATTLE_PAUSE_MENU_UI_TEST_PASS")
	quit()
