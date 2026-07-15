class_name BattlePreviewPanel
extends RefCounted

var _panel: PanelContainer
var _title: Label
var _body: RichTextLabel
var _tween: Tween = null
var _visible_target := false
var _fade_serial := 0


func _init(panel: PanelContainer, title: Label, body: RichTextLabel) -> void:
	_panel = panel
	_title = title
	_body = body


func show_at(mouse: Vector2, clamp_position: Callable) -> void:
	if _title.text.strip_edges().is_empty() and _body.text.strip_edges().is_empty():
		hide(true)
		return
	_panel.position = mouse + Vector2(18, 18)
	clamp_position.call()
	set_visible(true)


func hide(immediate: bool = false) -> void:
	_clear_content()
	set_visible(false, immediate)


func set_visible(shown: bool, immediate: bool = false) -> void:
	if _visible_target == shown:
		if shown and not _panel.visible: _panel.visible = true
		elif not shown and immediate:
			_panel.visible = false
			_panel.modulate.a = 0.0
		return
	_visible_target = shown
	_fade_serial += 1
	var serial := _fade_serial
	if _tween != null: _tween.kill()
	if immediate and not shown:
		_panel.visible = false
		_panel.modulate.a = 0.0
		return
	_tween = _panel.create_tween()
	_tween.set_trans(Tween.TRANS_QUAD)
	_tween.set_ease(Tween.EASE_OUT)
	if shown:
		_panel.visible = true
		_tween.tween_property(_panel, "modulate:a", 1.0, 0.12)
	else:
		_tween.tween_property(_panel, "modulate:a", 0.0, 0.24)
		_tween.tween_callback(_finish_hide.bind(serial))


func _finish_hide(serial: int) -> void:
	if serial != _fade_serial or _visible_target: return
	_panel.visible = false
	_clear_content()


func _clear_content() -> void:
	_title.text = ""
	_body.text = ""
