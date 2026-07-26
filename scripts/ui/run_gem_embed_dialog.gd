class_name RunGemEmbedDialog
extends CanvasLayer

signal embed_requested(slot_index: int, force_overload: bool)
signal postponed

const BattleUiTheme = preload("res://scripts/ui/battle_ui_theme.gd")

var _options_box: VBoxContainer = null
var _tip_label: Label = null
var _request_locked := false


func _init() -> void:
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func configure(options: Array[Dictionary]) -> void:
	_request_locked = false
	for child in _options_box.get_children():
		_options_box.remove_child(child)
		child.queue_free()
	var overload_available := false
	for option in options:
		if bool(option.get("overload", false)):
			overload_available = true
		_add_option(option)
	_tip_label.text = _t("gem_embed.tip_overload") if overload_available else _t("gem_embed.tip")


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

	var title := Label.new()
	title.text = _t("gem_embed.title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", BattleUiTheme.FONT_TITLE)
	title.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	box.add_child(title)

	_tip_label = Label.new()
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip_label.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
	box.add_child(_tip_label)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 180)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)

	_options_box = VBoxContainer.new()
	_options_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_options_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_options_box)

	var later := Button.new()
	later.name = "PostponeButton"
	later.custom_minimum_size = Vector2(0, 42)
	later.text = _t("gem_embed.later")
	BattleUiTheme.apply_button(later, "ghost")
	later.pressed.connect(_on_postponed)
	box.add_child(later)


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
	postponed.emit()


func _set_buttons_disabled(disabled: bool) -> void:
	for child in _options_box.get_children():
		if child is Button:
			(child as Button).disabled = disabled
			BattleUiTheme.apply_button(child as Button, "combat" if bool(child.get_meta("force_overload", false)) else "gem")


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
