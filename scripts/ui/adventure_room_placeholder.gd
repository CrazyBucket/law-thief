extends Control

const BattleUiTheme = preload("res://scripts/ui/battle_ui_theme.gd")

@onready var _title: Label = $Content/VBox/Title
@onready var _body: Label = $Content/VBox/Body
@onready var _continue_btn: Button = $Content/VBox/ContinueBtn
@onready var _back_btn: Button = $BackBtn


func _ready() -> void:
	_apply_theme()
	_title.text = "%s · %s" % [SaveService.get_active_slot_label(), AdventureService.pending_room_label]
	_body.text = _placeholder_body(AdventureService.pending_room_type)
	BattleUiTheme.apply_button(_continue_btn, "end")
	BattleUiTheme.apply_button(_back_btn, "ghost")


func _apply_theme() -> void:
	$Content.add_theme_stylebox_override("panel", BattleUiTheme.panel_style())
	_title.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	_body.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)


func _placeholder_body(room_type: String) -> String:
	match room_type:
		"REST_SITE":
			return "营地场景占位\n后续可在这里放入治疗、移除负面状态、整理宝石与遗物事件。"
		"SHOP":
			return "商店场景占位\n后续可接入货币、商品池、刷新与购买逻辑。"
		"EVENT":
			return "随机事件场景占位\n后续可扩展多分支文本、风险收益和局外解锁联动。"
		"END":
			return "终点 / Boss 场景占位\n后续可接入章节结算、成就判定与通关演出。"
		_:
			return "房间场景占位，当前用于承接整体流程跳转。"


func _on_continue_pressed() -> void:
	AdventureService.finish_room_and_return()


func _on_back_pressed() -> void:
	AdventureService.finish_room_and_return()
