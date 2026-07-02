class_name GameConfirmDialog
extends CanvasLayer

signal confirmed
signal cancelled

const BattleUiTheme = preload("res://scripts/ui/battle_ui_theme.gd")

var _title_label: Label
var _body_label: Label
var _ok_btn: Button
var _cancel_btn: Button


func _init() -> void:
	layer = 80
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func configure(title: String, body: String, ok_text: String, cancel_text: String) -> void:
	_title_label.text = title
	_body_label.text = body
	_ok_btn.text = ok_text
	_cancel_btn.text = cancel_text


func popup_centered(_size: Vector2i = Vector2i.ZERO) -> void:
	visible = true


func _build() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = BattleUiTheme.build_theme()
	add_child(root)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.03, 0.05, 0.78)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 0)
	var panel_style := BattleUiTheme.panel_style(BattleUiTheme.BORDER_ACCENT)
	panel_style.bg_color = Color(0.03, 0.05, 0.08, 0.96)
	panel_style.border_color = Color(0.2, 0.82, 0.64, 0.42)
	panel_style.shadow_size = 0
	panel_style.content_margin_left = 28
	panel_style.content_margin_right = 28
	panel_style.content_margin_top = 24
	panel_style.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", BattleUiTheme.FONT_TITLE)
	_title_label.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	vbox.add_child(_title_label)

	_body_label = Label.new()
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body_label.add_theme_font_size_override("font_size", 14)
	_body_label.add_theme_color_override("font_color", BattleUiTheme.TEXT)
	vbox.add_child(_body_label)

	var separator := HSeparator.new()
	separator.modulate = Color(0.35, 0.75, 0.62, 0.25)
	vbox.add_child(separator)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_row)

	_cancel_btn = Button.new()
	_cancel_btn.custom_minimum_size = Vector2(148, 44)
	BattleUiTheme.apply_button(_cancel_btn, "ghost")
	_cancel_btn.pressed.connect(_on_cancel_pressed)
	btn_row.add_child(_cancel_btn)

	_ok_btn = Button.new()
	_ok_btn.custom_minimum_size = Vector2(148, 44)
	BattleUiTheme.apply_button(_ok_btn, "end")
	_ok_btn.pressed.connect(_on_ok_pressed)
	btn_row.add_child(_ok_btn)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_cancel_pressed()
		get_viewport().set_input_as_handled()


func _on_ok_pressed() -> void:
	visible = false
	confirmed.emit()


func _on_cancel_pressed() -> void:
	visible = false
	cancelled.emit()
