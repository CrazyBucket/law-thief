extends Control

const BattleUiTheme = preload("res://scripts/ui/battle_ui_theme.gd")

const REST_PANEL := Color("#201810")
const REST_INSET := Color("#130f0d")
const EMBER := Color("#e38a32")
const EMBER_LIGHT := Color("#ffd17a")
const MOSS_EDGE := Color("#756342")

@onready var _top_bar: PanelContainer = $SafeArea/Layout/TopBar
@onready var _flame_mark: Label = $SafeArea/Layout/TopBar/Row/FlameMark
@onready var _title: Label = $SafeArea/Layout/TopBar/Row/TitleGroup/Title
@onready var _subtitle: Label = $SafeArea/Layout/TopBar/Row/TitleGroup/Subtitle
@onready var _safety_label: Label = $SafeArea/Layout/TopBar/Row/SafetyLabel
@onready var _rest_card: PanelContainer = $SafeArea/Layout/Main/RestCard
@onready var _eyebrow: Label = $SafeArea/Layout/Main/RestCard/Margin/VBox/Eyebrow
@onready var _heading: Label = $SafeArea/Layout/Main/RestCard/Margin/VBox/Heading
@onready var _description: Label = $SafeArea/Layout/Main/RestCard/Margin/VBox/Description
@onready var _recovery_panel: PanelContainer = $SafeArea/Layout/Main/RestCard/Margin/VBox/RecoveryPanel
@onready var _recovery_mark: Label = $SafeArea/Layout/Main/RestCard/Margin/VBox/RecoveryPanel/RecoveryRow/RecoveryMark
@onready var _recovery_title: Label = $SafeArea/Layout/Main/RestCard/Margin/VBox/RecoveryPanel/RecoveryRow/Copy/RecoveryTitle
@onready var _recovery_value: Label = $SafeArea/Layout/Main/RestCard/Margin/VBox/RecoveryPanel/RecoveryRow/Copy/RecoveryValue
@onready var _result_label: Label = $SafeArea/Layout/Main/RestCard/Margin/VBox/ResultLabel
@onready var _rest_button: Button = $SafeArea/Layout/Main/RestCard/Margin/VBox/RestButton
@onready var _leave_button: Button = $SafeArea/Layout/Main/RestCard/Margin/VBox/LeaveButton

var _room_id := ""


func _ready() -> void:
	theme = BattleUiTheme.build_theme()
	_apply_theme()
	_apply_copy()
	_room_id = AdventureService.current_room_id()
	_refresh_room_view(RoomFlowService.enter_room(_room_id))


func _apply_theme() -> void:
	_top_bar.add_theme_stylebox_override("panel", _panel_style(REST_PANEL, EMBER.darkened(0.2), 10, 1))
	_rest_card.add_theme_stylebox_override("panel", _panel_style(REST_PANEL, MOSS_EDGE, 12, 2))
	_recovery_panel.add_theme_stylebox_override("panel", _panel_style(REST_INSET, EMBER.darkened(0.25), 12, 1))
	_flame_mark.add_theme_color_override("font_color", EMBER_LIGHT)
	_title.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	_subtitle.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
	_safety_label.add_theme_color_override("font_color", Color("#a7c690"))
	_eyebrow.add_theme_color_override("font_color", EMBER_LIGHT)
	_heading.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	_description.add_theme_color_override("font_color", BattleUiTheme.TEXT_HINT)
	_recovery_mark.add_theme_color_override("font_color", EMBER_LIGHT)
	_recovery_title.add_theme_color_override("font_color", BattleUiTheme.TEXT)
	_recovery_value.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
	_result_label.add_theme_color_override("font_color", Color("#b8dc96"))
	BattleUiTheme.apply_button(_rest_button, "end")
	BattleUiTheme.apply_button(_leave_button, "ghost")


func _apply_copy() -> void:
	_title.text = _t("rest.ui.title")
	_subtitle.text = _t("rest.ui.subtitle")
	_safety_label.text = _t("rest.ui.safe")
	_eyebrow.text = _t("rest.ui.eyebrow")
	_heading.text = _t("rest.ui.heading")
	_description.text = _t("rest.ui.description")
	_recovery_title.text = _t("rest.ui.recovery.title")
	_recovery_value.text = _t("rest.ui.recovery.value")
	_rest_button.text = _t("rest.ui.action")
	_leave_button.text = _t("rest.ui.leave")


func _refresh_room_view(room_view: Dictionary) -> void:
	var resolved := str(room_view.get("state", "")) == "RESOLVED"
	var result: Dictionary = room_view.get("result", {})
	_result_label.visible = resolved
	_leave_button.visible = not resolved
	if not resolved:
		_rest_button.disabled = false
		_rest_button.text = _t("rest.ui.action")
		BattleUiTheme.apply_button(_rest_button, "end")
		return
	var heal: Dictionary = result.get("heal", {})
	_result_label.text = _t("rest.ui.result", {
		"amount": int(heal.get("amount", 0)),
		"current": int(heal.get("after_hp", 0)),
		"max": int(heal.get("max_hp", 0)),
	})
	_rest_button.disabled = false
	_rest_button.text = _t("rest.ui.continue")
	BattleUiTheme.apply_button(_rest_button, "end")


func _on_rest_pressed() -> void:
	var room_view := RoomFlowService.get_room_view(_room_id)
	if str(room_view.get("state", "")) == "RESOLVED":
		AdventureService.finish_room_and_return()
		return
	_rest_button.disabled = true
	BattleUiTheme.apply_button(_rest_button, "end")
	_refresh_room_view(RoomFlowService.submit_room_command(_room_id, {}))


func _on_leave_pressed() -> void:
	AdventureService.finish_room_and_return()


func _panel_style(bg: Color, edge: Color, margin: int, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = edge
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(0)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	style.shadow_color = Color(0, 0, 0, 0.7)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0, 3)
	return style


func _t(key: String, values: Dictionary = {}) -> String:
	var translated := tr(key)
	return (translated if translated != key else key).format(values)
