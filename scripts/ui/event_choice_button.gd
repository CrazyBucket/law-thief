class_name EventChoiceButton
extends Button

const BattleUiTheme = preload("res://scripts/ui/battle_ui_theme.gd")

const MIN_HEIGHT := 64

const TITLE_COLOR := Color("#e9e4da")
const TITLE_HOVER_COLOR := Color("#d8bd82")
const EFFECT_COLOR := Color("#bebad2")
const EFFECT_HOVER_COLOR := Color("#d4cee4")
const DISABLED_COLOR := Color("#77736f")
const MARKER_COLOR := Color("#716b65")
const MARKER_HOVER_COLOR := Color("#c9ad76")

var _choice_text := ""
var _effect_text := ""
var _content: VBoxContainer = null
var _title_label: Label = null
var _effect_label: Label = null
var _hover_amount := 0.0
var _press_amount := 0.0


func configure(choice: String, effect_text: String, disabled_reason: String, enabled: bool) -> void:
	_choice_text = choice if enabled or disabled_reason.is_empty() else "%s  ·  %s" % [choice, disabled_reason]
	_effect_text = effect_text
	disabled = not enabled
	set_meta("event_condition_disabled", not enabled)
	tooltip_text = disabled_reason if disabled else ""
	_sync_content()
	refresh_visual_state()


func _ready() -> void:
	custom_minimum_size = Vector2(0, MIN_HEIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flat = true
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not disabled else Control.CURSOR_ARROW
	text = ""
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_build_content()
	mouse_entered.connect(_wake_animation)
	mouse_exited.connect(_wake_animation)
	button_down.connect(_wake_animation)
	button_up.connect(_wake_animation)
	refresh_visual_state()
	set_process(false)


func _build_content() -> void:
	_content = VBoxContainer.new()
	_content.name = "OptionContent"
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_theme_constant_override("separation", 0)
	add_child(_content)
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.offset_left = 26.0
	_content.offset_top = 5.0
	_content.offset_right = -8.0
	_content.offset_bottom = -6.0

	_title_label = Label.new()
	_title_label.name = "ChoiceTitle"
	_title_label.custom_minimum_size = Vector2(0, 27)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.set_meta("event_choice_title", true)
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_title_label)
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_override("font", BattleUiTheme.event_semibold_font())
	_title_label.add_theme_font_size_override("font_size", 16)

	_effect_label = Label.new()
	_effect_label.name = "EffectText"
	_effect_label.custom_minimum_size = Vector2(0, 22)
	_effect_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_effect_label.set_meta("event_effect_label", true)
	_effect_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_effect_label)
	_effect_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_effect_label.add_theme_font_override("font", BattleUiTheme.event_font())
	_effect_label.add_theme_font_size_override("font_size", 13)
	_sync_content()


func _sync_content() -> void:
	if _title_label == null or _effect_label == null:
		return
	_title_label.text = _choice_text
	_effect_label.text = _effect_text
	_effect_label.visible = not _effect_text.is_empty()


func _process(delta: float) -> void:
	var hover_target := 1.0 if is_hovered() and not disabled else 0.0
	var press_target := 1.0 if button_pressed and not disabled else 0.0
	_hover_amount = move_toward(_hover_amount, hover_target, delta * 7.5)
	_press_amount = move_toward(_press_amount, press_target, delta * 14.0)
	refresh_visual_state()
	if is_equal_approx(_hover_amount, hover_target) and is_equal_approx(_press_amount, press_target):
		set_process(false)


func _draw() -> void:
	var emphasis := maxf(_hover_amount, _press_amount)
	var marker_color := Color(MARKER_COLOR, 0.26 if disabled else 0.55)
	marker_color = marker_color.lerp(Color(MARKER_HOVER_COLOR, 0.92), emphasis)
	var center_y := size.y * 0.5 if _effect_text.is_empty() else 21.0
	var center := Vector2(8.0, center_y)
	var radius := 3.2 + _hover_amount * 0.45 - _press_amount * 0.25
	var diamond := PackedVector2Array([
		center + Vector2(0.0, -radius),
		center + Vector2(radius, 0.0),
		center + Vector2(0.0, radius),
		center + Vector2(-radius, 0.0),
	])
	if emphasis > 0.001:
		draw_colored_polygon(diamond, Color(MARKER_HOVER_COLOR, 0.18 + emphasis * 0.24))
	var outline := diamond.duplicate()
	outline.append(diamond[0])
	draw_polyline(outline, marker_color, 1.0, true)


func refresh_visual_state() -> void:
	if _content == null or _title_label == null or _effect_label == null:
		return
	if disabled:
		_title_label.add_theme_color_override("font_color", Color(DISABLED_COLOR, 0.82))
		_effect_label.add_theme_color_override("font_color", Color(DISABLED_COLOR, 0.58))
	else:
		var emphasis := clampf(_hover_amount + _press_amount * 0.22, 0.0, 1.0)
		_title_label.add_theme_color_override("font_color", TITLE_COLOR.lerp(TITLE_HOVER_COLOR, emphasis))
		_effect_label.add_theme_color_override("font_color", EFFECT_COLOR.lerp(EFFECT_HOVER_COLOR, emphasis))
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not disabled else Control.CURSOR_ARROW
	queue_redraw()


func _wake_animation() -> void:
	set_process(true)
