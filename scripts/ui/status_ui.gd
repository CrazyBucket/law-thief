class_name StatusUi
extends RefCounted

const _StatusRegistry = preload("res://scripts/rules/status_registry.gd")
const _StatusIcons = preload("res://scripts/ui/status_icons.gd")


static func build_status_row(unit: UnitState, compact: bool = false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4 if compact else 6)
	for status in _StatusRegistry.sort_statuses(unit.statuses):
		row.add_child(build_status_chip(status, compact))
	return row


static func populate_status_row(
	container: HBoxContainer,
	unit: UnitState,
	compact: bool = false,
	exclude_status_ids: Array[String] = []
) -> void:
	while container.get_child_count() > 0:
		container.get_child(0).free()
	for status in _StatusRegistry.sort_statuses(unit.statuses):
		if status.status_id in exclude_status_ids:
			continue
		container.add_child(build_status_chip(status, compact))


static func build_status_chip(status: StatusInstance, compact: bool = false) -> Control:
	var chip := PanelContainer.new()
	var color := _StatusRegistry.status_color(status.status_id)
	chip.add_theme_stylebox_override("panel", _chip_style(color))
	chip.tooltip_text = _StatusRegistry.tooltip(status)
	var icon_tex := _StatusIcons.get_icon(status.status_id)
	if icon_tex != null:
		var icon_size: float = 16.0 if compact else 20.0
		var icon_wrap := Control.new()
		icon_wrap.custom_minimum_size = Vector2(icon_size, icon_size)
		var tex_rect := TextureRect.new()
		tex_rect.texture = icon_tex
		tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon_wrap.add_child(tex_rect)
		var badge_text: String = _StatusRegistry.icon_badge(status)
		if not badge_text.is_empty():
			var badge := Label.new()
			badge.text = badge_text
			badge.add_theme_font_override("font", BattleUiTheme.pixel_font())
			badge.add_theme_font_size_override("font_size", 8 if compact else 9)
			badge.add_theme_color_override("font_color", UiPalette.TEXT_BRIGHT)
			badge.add_theme_color_override("font_outline_color", UiPalette.TEXT_OUTLINE)
			badge.add_theme_constant_override("outline_size", 2)
			badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
			badge.offset_left = -14.0
			badge.offset_top = -11.0
			icon_wrap.add_child(badge)
		chip.add_child(icon_wrap)
		chip.custom_minimum_size = Vector2(icon_size + 6, icon_size + 4)
	else:
		var label := Label.new()
		label.text = _StatusRegistry.short_label(status)
		label.add_theme_font_override("font", BattleUiTheme.pixel_font())
		label.add_theme_font_size_override("font_size", 10 if compact else 11)
		label.add_theme_color_override("font_color", UiPalette.TEXT_BRIGHT)
		chip.add_child(label)
		chip.custom_minimum_size = Vector2(34 if compact else 40, 18 if compact else 22)
	return chip


static func format_status_bbcode(status: StatusInstance) -> String:
	var color: Color = _StatusRegistry.status_color(status.status_id)
	var hex := color.to_html(false)
	var type_label := "增益" if _StatusRegistry.status_type(status.status_id) == _StatusRegistry.TYPE_BUFF else "减益"
	if _StatusRegistry.status_type(status.status_id) == _StatusRegistry.TYPE_SYSTEM:
		type_label = "特殊"
	return "[color=#%s][%s] %s[/color] [color=#%s]%s[/color]" % [
		hex,
		type_label,
		_StatusRegistry.display_name(status.status_id),
		UiPalette.TEXT_MUTED.to_html(false),
		_StatusRegistry.tooltip(status),
	]


static func format_all_bbcode(unit: UnitState) -> String:
	if unit.statuses.is_empty():
		return "[color=#%s]无状态[/color]" % UiPalette.TEXT_FAINT.to_html(false)
	var lines: Array[String] = []
	for status in _StatusRegistry.sort_statuses(unit.statuses):
		lines.append(format_status_bbcode(status))
	return "\n".join(lines)


static func preview_lines(unit: UnitState) -> Array[String]:
	var lines: Array[String] = []
	for status in _StatusRegistry.sort_statuses(unit.statuses):
		lines.append("%s：%s" % [_StatusRegistry.display_name(status.status_id), _StatusRegistry.tooltip(status)])
	return lines


static func _chip_style(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color.darkened(0.6)
	box.border_color = color.lightened(0.08)
	box.set_border_width_all(1)
	box.set_corner_radius_all(0)
	box.content_margin_left = 6
	box.content_margin_right = 6
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	return box
