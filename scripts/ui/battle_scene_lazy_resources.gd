extends RefCounted

const EDITOR_CONSOLE_SCENE_PATH := "res://scenes/ui/editor_console.tscn"
const BATTLE_EDITOR_PANEL_SCRIPT_PATH := "res://scripts/ui/battle_editor_panel.gd"
const BATTLE_EDITOR_VIEW_SCRIPT_PATH := "res://scripts/ui/battle_editor_view.gd"
const GENERATED_EXPORT_BUTTON_SCRIPT_PATH := "res://scripts/ui/generated_encounter_export_button.gd"
const BATTLE_REWARD_OVERLAY_SCRIPT_PATH := "res://scripts/ui/battle_reward_overlay.gd"
const BATTLE_REWARD_CARD_FACTORY_SCRIPT_PATH := "res://scripts/ui/battle_reward_card_factory.gd"
const BATTLE_SETTLEMENT_SERVICE_SCRIPT_PATH := "res://scripts/battle/battle_settlement_service.gd"
const BATTLE_REWARD_VIEW_SCRIPT_PATH := "res://scripts/ui/battle_reward_view.gd"
const SYSTEM_PAUSE_MENU_SCRIPT_PATH := "res://scripts/ui/system_pause_menu.gd"
const GAME_CONFIRM_DIALOG_SCRIPT_PATH := "res://scripts/ui/game_confirm_dialog.gd"

var _cache: Dictionary = {}
var _battle_reward_view_instance: RefCounted = null


func editor_console_scene() -> PackedScene:
	return _load(EDITOR_CONSOLE_SCENE_PATH) as PackedScene


func editor_panel_script() -> Script:
	return _load(BATTLE_EDITOR_PANEL_SCRIPT_PATH) as Script


func editor_view_script() -> Script:
	return _load(BATTLE_EDITOR_VIEW_SCRIPT_PATH) as Script


func generated_export_button_script() -> Script:
	return _load(GENERATED_EXPORT_BUTTON_SCRIPT_PATH) as Script


func battle_reward_overlay() -> Script:
	return _load(BATTLE_REWARD_OVERLAY_SCRIPT_PATH) as Script


func battle_reward_card_factory() -> Script:
	return _load(BATTLE_REWARD_CARD_FACTORY_SCRIPT_PATH) as Script


func battle_settlement_service() -> Script:
	return _load(BATTLE_SETTLEMENT_SERVICE_SCRIPT_PATH) as Script


func battle_reward_view() -> RefCounted:
	if _battle_reward_view_instance == null:
		var script := _load(BATTLE_REWARD_VIEW_SCRIPT_PATH) as Script
		if script != null:
			_battle_reward_view_instance = script.new()
	return _battle_reward_view_instance


func system_pause_menu_script() -> Script:
	return _load(SYSTEM_PAUSE_MENU_SCRIPT_PATH) as Script


func game_confirm_dialog_script() -> Script:
	return _load(GAME_CONFIRM_DIALOG_SCRIPT_PATH) as Script


func _load(path: String) -> Resource:
	var cached := _cache.get(path, null) as Resource
	if cached != null:
		return cached
	var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	if resource != null:
		_cache[path] = resource
	return resource
