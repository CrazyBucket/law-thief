class_name BattleEditorItemButton
extends Button

const BattleUiTheme = preload("res://scripts/ui/battle_ui_theme.gd")

signal drag_started(tool: Dictionary)

var tool: Dictionary = {}
var drag_enabled: bool = true


func set_tool(value: Dictionary) -> void:
	tool = value.duplicate(true)


func set_drag_enabled(enabled: bool) -> void:
	drag_enabled = enabled


func _get_drag_data(_at_position: Vector2) -> Variant:
	if not drag_enabled or tool.is_empty() or str(tool.get("kind", "")) == "relic":
		return null
	drag_started.emit(tool.duplicate(true))
	var preview := Label.new()
	preview.text = "%s  [%s]" % [str(tool.get("label", "")), str(tool.get("id", ""))]
	preview.add_theme_font_size_override("font_size", 13)
	preview.add_theme_color_override("font_color", BattleUiTheme.TEXT)
	preview.add_theme_stylebox_override("normal", BattleUiTheme.tooltip_style())
	set_drag_preview(preview)
	return {
		"battle_editor_tool": tool.duplicate(true),
	}
