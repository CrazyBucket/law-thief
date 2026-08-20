class_name RunGemEmbedDialog
extends CanvasLayer

signal embed_requested(slot_index: int, force_overload: bool)
signal postponed
signal abandoned

const BattleUiTheme = preload("res://scripts/ui/battle_ui_theme.gd")

var _options_box: VBoxContainer = null
var _options_scroll: ScrollContainer = null
var _title_label: Label = null
var _tip_label: Label = null
var _postpone_button: Button = null
var _abandon_button: Button = null
var _request_locked := false


func _init() -> void:
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func configure(options: Array[Dictionary], title_text: String = "", allow_hold: bool = true, allow_abandon: bool = false) -> void:
	_request_locked = false
	for child in _options_box.get_children():
		_options_box.remove_child(child)
		child.queue_free()
	_title_label.text = title_text if not title_text.is_empty() else _t("gem_embed.title")
	var overload_available := false
	for option in options:
		if bool(option.get("overload", false)):
			overload_available = true
		_add_option(option)
	_tip_label.text = _t("gem_embed.tip_overload") if overload_available else _t("gem_embed.tip")
	_options_scroll.visible = not options.is_empty()
	_postpone_button.visible = allow_hold
	_abandon_button.visible = allow_abandon


func dismiss() -> void:
	visible = false
	queue_free()


func _build() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = BattleUiTheme.build_theme()
	add_child(root)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.015, 0.016, 0.03, 0.88)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(480, 0)
	var panel_style := BattleUiTheme.panel_style(BattleUiTheme.BORDER_ACCENT)
	panel_style.bg_color = Color(0.035, 0.04, 0.065, 0.98)
	panel_style.content_margin_left = 24
	panel_style.content_margin_right = 24
	panel_style.content_margin_top = 22
	panel_style.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	_title_label = Label.new()
	_title_label.text = _t("gem_embed.title")
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", BattleUiTheme.FONT_TITLE)
	_title_label.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	box.add_child(_title_label)

	_tip_label = Label.new()
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip_label.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
	box.add_child(_tip_label)

	_options_scroll = ScrollContainer.new()
	_options_scroll.custom_minimum_size = Vector2(0, 180)
	_options_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_options_scroll)

	_options_box = VBoxContainer.new()
	_options_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_options_box.add_theme_constant_override("separation", 8)
	_options_scroll.add_child(_options_box)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	box.add_child(action_row)

	_postpone_button = Button.new()
	_postpone_button.name = "PostponeButton"
	_postpone_button.custom_minimum_size = Vector2(0, 42)
	_postpone_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_postpone_button.text = _t("gem_embed.later")
	BattleUiTheme.apply_button(_postpone_button, "ghost")
	_postpone_button.pressed.connect(_on_postponed)
	action_row.add_child(_postpone_button)

	_abandon_button = Button.new()
	_abandon_button.name = "AbandonButton"
	_abandon_button.custom_minimum_size = Vector2(0, 42)
	_abandon_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_abandon_button.text = _t("gem_embed.abandon")
	BattleUiTheme.apply_button(_abandon_button, "combat")
	_abandon_button.pressed.connect(_on_abandoned)
	action_row.add_child(_abandon_button)


func _add_option(option: Dictionary) -> void:
	var slot: Dictionary = option.get("slot", {})
	var slot_index := int(option.get("index", -1))
	var force_overload := bool(option.get("overload", false))
	var slot_name := _slot_label(str(slot.get("slot_type", "")))
	var button := Button.new()
	button.name = "SlotButton_%d" % slot_index
	button.custom_minimum_size = Vector2(0, 46)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.set_meta("slot_index", slot_index)
	button.set_meta("force_overload", force_overload)
	if force_overload:
		var gem_id := str(slot.get("gem_id", ""))
		button.text = _t("gem_embed.slot_overload", {
			"slot": slot_name,
			"gem": DataRegistry.get_gem_display_name(gem_id),
		})
	else:
		button.text = _t("gem_embed.slot", {"slot": slot_name})
	BattleUiTheme.apply_button(button, "combat" if force_overload else "gem")
	button.pressed.connect(_on_option_pressed.bind(slot_index, force_overload))
	_options_box.add_child(button)


func _on_option_pressed(slot_index: int, force_overload: bool) -> void:
	if _request_locked:
		return
	_request_locked = true
	_set_buttons_disabled(true)
	embed_requested.emit(slot_index, force_overload)


func unlock_after_failure() -> void:
	_request_locked = false
	_set_buttons_disabled(false)


func _on_postponed() -> void:
	if _request_locked:
		return
	_request_locked = true
	_set_buttons_disabled(true)
	postponed.emit()


func _on_abandoned() -> void:
	if _request_locked:
		return
	_request_locked = true
	_set_buttons_disabled(true)
	abandoned.emit()


func _set_buttons_disabled(disabled: bool) -> void:
	for child in _options_box.get_children():
		if child is Button:
			(child as Button).disabled = disabled
			BattleUiTheme.apply_button(child as Button, "combat" if bool(child.get_meta("force_overload", false)) else "gem")
	_postpone_button.disabled = disabled
	_abandon_button.disabled = disabled
	BattleUiTheme.apply_button(_postpone_button, "ghost")
	BattleUiTheme.apply_button(_abandon_button, "combat")


func _slot_label(slot_type: String) -> String:
	match slot_type:
		Constants.SLOT_RED:
			return _t("gem_embed.slot.red")
		Constants.SLOT_BLUE:
			return _t("gem_embed.slot.blue")
		Constants.SLOT_BLACK:
			return _t("gem_embed.slot.black")
	return _t("gem_embed.slot.unknown")


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_on_postponed()
		get_viewport().set_input_as_handled()


func _t(key: String, values: Dictionary = {}) -> String:
	return tr(key).format(values)
