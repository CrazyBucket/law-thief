extends Control
## 战斗内 Editor CLI（场景布局，避免代码动态 UI 尺寸为 0）

signal command_submitted(command: String)

@onready var _output: RichTextLabel = %Output
@onready var _input: LineEdit = %Input

var _log_lines: Array[String] = []
var _cmd_history: Array[String] = []
var _cmd_nav: int = -1
var _cmd_draft: String = ""


func _ready() -> void:
	visible = false
	_apply_theme()
	_input.text_submitted.connect(_on_input_submitted)
	_input.gui_input.connect(_on_input_gui_input)
	append_log("> /help", "#6bdc8e")
	append_log("资源 id 为字符串（如 unit_bomb_rat、gem_poison），不是数字。", "#7a9a82")


func open() -> void:
	visible = true
	_reset_cmd_nav()
	_input.grab_focus()
	_input.caret_column = _input.text.length()


func close() -> void:
	visible = false
	_reset_cmd_nav()
	_input.release_focus()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func is_open() -> bool:
	return visible


func append_log(text: String, color: String = "#b8d4bc") -> void:
	_log_lines.append("[color=%s]%s[/color]" % [color, text])
	while _log_lines.size() > 80:
		_log_lines.remove_at(0)
	_output.text = "\n".join(_log_lines)
	await get_tree().process_frame
	_output.scroll_to_line(maxi(0, _output.get_line_count() - 1))


func clear_input() -> void:
	_input.clear()
	_input.grab_focus()


func _apply_theme() -> void:
	var term_text := Color(0.72, 0.95, 0.78)
	var term_muted := Color(0.45, 0.62, 0.5, 0.9)
	var term_prompt := Color(0.55, 0.92, 0.62)
	%Title.add_theme_color_override("font_color", term_muted)
	_output.add_theme_color_override("default_color", term_text)
	_output.add_theme_stylebox_override("normal", _surface_style(Color(0.02, 0.05, 0.03, 0.42), Color(0.28, 0.55, 0.34, 0.35)))
	%Frame.add_theme_stylebox_override("panel", _surface_style(Color(0.02, 0.05, 0.03, 0.72), Color(0.28, 0.55, 0.34, 0.55)))
	_input.add_theme_color_override("font_color", term_prompt)
	_input.add_theme_color_override("font_placeholder_color", term_muted)
	_input.add_theme_color_override("caret_color", term_prompt)
	_input.add_theme_stylebox_override("normal", _surface_style(Color(0.01, 0.03, 0.02, 0.72), Color(0.45, 0.85, 0.5, 0.9)))
	_input.add_theme_stylebox_override("focus", _surface_style(Color(0.02, 0.06, 0.03, 0.82), Color(0.55, 0.95, 0.6, 1.0)))


func _surface_style(bg: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(2)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	return box


func _on_input_submitted(raw_text: String) -> void:
	var command := raw_text.strip_edges()
	if command.is_empty():
		return
	_remember_command(command)
	command_submitted.emit(command)
	clear_input()


func _on_input_gui_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_UP:
		_recall_command(-1)
		_input.accept_event()
	elif event.keycode == KEY_DOWN:
		_recall_command(1)
		_input.accept_event()


func _remember_command(command: String) -> void:
	if _cmd_history.is_empty() or _cmd_history[-1] != command:
		_cmd_history.append(command)
	while _cmd_history.size() > 50:
		_cmd_history.remove_at(0)
	_reset_cmd_nav()


func _reset_cmd_nav() -> void:
	_cmd_nav = -1
	_cmd_draft = ""


func _recall_command(step: int) -> void:
	if _cmd_history.is_empty():
		return
	if _cmd_nav < 0 and step < 0:
		_cmd_draft = _input.text
	var next_nav := _cmd_nav + step
	if next_nav < -1:
		next_nav = -1
	elif next_nav >= _cmd_history.size():
		next_nav = -1
	_cmd_nav = next_nav
	if _cmd_nav < 0:
		_input.text = _cmd_draft
	else:
		_input.text = _cmd_history[_cmd_nav]
	_input.caret_column = _input.text.length()
