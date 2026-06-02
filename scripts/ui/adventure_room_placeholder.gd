extends Control

const BattleUiTheme = preload("res://scripts/ui/battle_ui_theme.gd")

@onready var _title: Label = $Content/VBox/Title
@onready var _body: Label = $Content/VBox/Body
@onready var _continue_btn: Button = $Content/VBox/ContinueBtn
@onready var _back_btn: Button = $BackBtn


func _ready() -> void:
	_apply_theme()
	var room_result := AdventureService.resolve_pending_room()
	_title.text = "%s · %s" % [SaveService.get_active_slot_label(), AdventureService.pending_room_label]
	_body.text = _placeholder_body(AdventureService.pending_room_type, room_result)
	BattleUiTheme.apply_button(_continue_btn, "end")
	BattleUiTheme.apply_button(_back_btn, "ghost")


func _apply_theme() -> void:
	$Content.add_theme_stylebox_override("panel", BattleUiTheme.panel_style())
	_title.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	_body.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)


func _placeholder_body(room_type: String, room_result: Dictionary = {}) -> String:
	var summary := str(room_result.get("summary", ""))
	if not summary.is_empty():
		return summary
	match room_type:
		"REST_SITE":
			return "营地可用于恢复生命，当前先实现固定回血。"
		"SHOP":
			return "商店节点暂时保留占位，后续再接商品与购买流程。"
		"EVENT":
			return "问号节点已改为直接发放遗物。"
		"END":
			return "大关终点：结算后进入下一关或通关回主菜单。"
		_:
			return "房间场景占位，当前用于承接整体流程跳转。"


func _on_continue_pressed() -> void:
	AdventureService.finish_room_and_return()


func _on_back_pressed() -> void:
	AdventureService.finish_room_and_return()
