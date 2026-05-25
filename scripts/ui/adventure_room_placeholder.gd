extends Control

const BattleUiTheme = preload("res://scripts/ui/battle_ui_theme.gd")

@onready var _title: Label = $Content/Title
@onready var _body: Label = $Content/Body
@onready var _continue_btn: Button = $Content/ContinueBtn


func _ready() -> void:
	_apply_theme()
	_title.text = AdventureService.pending_room_label
	_body.text = _placeholder_body(AdventureService.pending_room_type)
	BattleUiTheme.apply_button(_continue_btn, "end")


func _apply_theme() -> void:
	$Content.add_theme_stylebox_override("panel", BattleUiTheme.panel_style())
	_title.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	_body.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)


func _placeholder_body(room_type: String) -> String:
	match room_type:
		"REST_SITE":
			return "营地场景占位\n恢复生命、移除负面状态等功能待实现。"
		"SHOP":
			return "商店场景占位\n购买宝石、规则卡等功能待实现。"
		"EVENT":
			return "随机事件场景占位\n抉择分支与奖励待实现。"
		"END":
			return "终点 / Boss 场景占位\n通关演出与结算待实现。"
		_:
			return "房间场景占位，内容待实现。"


func _on_continue_pressed() -> void:
	AdventureService.finish_room_and_return()


func _on_back_pressed() -> void:
	AdventureService.finish_room_and_return()
