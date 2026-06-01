class_name BattleUiTheme
extends RefCounted

const BG_DEEP := Color(0.05, 0.05, 0.09)
const BG_PANEL := Color(0.09, 0.1, 0.14, 0.94)
const BG_DOCK := Color(0.07, 0.08, 0.12, 0.96)
const BORDER := Color(0.28, 0.3, 0.38, 0.85)
const BORDER_ACCENT := Color(0.72, 0.58, 0.28, 0.95)
const TEXT := Color(0.92, 0.93, 0.96)
const TEXT_MUTED := Color(0.62, 0.65, 0.72)
const TEXT_GOLD := Color(0.95, 0.82, 0.42)
const TEXT_HINT := Color(0.78, 0.72, 0.48)
const HP_HIGH := Color(0.28, 0.78, 0.48)
const HP_MID := Color(0.9, 0.72, 0.22)
const HP_LOW := Color(0.9, 0.28, 0.28)
const SHIELD_FILL := Color(0.78, 0.82, 0.88)
const SHIELD_FILL_HI := Color(0.88, 0.91, 0.96)
const SHIELD_BG := Color(0.12, 0.13, 0.18)
const SHIELD_BORDER := Color(0.38, 0.4, 0.46)
const PHASE_PLAYER := Color(0.35, 0.72, 0.95)
const PHASE_ENEMY := Color(0.92, 0.38, 0.38)
const PHASE_END := Color(0.55, 0.58, 0.65)


static func panel_style(accent: Color = BORDER) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = BG_PANEL
	box.border_color = accent
	box.set_border_width_all(1)
	box.set_corner_radius_all(10)
	box.shadow_color = Color(0, 0, 0, 0.35)
	box.shadow_size = 6
	box.shadow_offset = Vector2(0, 3)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box


static func dock_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = BG_DOCK
	box.border_color = BORDER
	box.set_border_width_all(1)
	box.border_width_top = 2
	box.set_corner_radius_all(0)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box


static func tooltip_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.08, 0.09, 0.13, 0.98)
	box.border_color = BORDER_ACCENT
	box.set_border_width_all(1)
	box.set_corner_radius_all(8)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box


static func button_style(
	kind: String,
	active: bool = false,
	disabled: bool = false
) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.set_corner_radius_all(8)
	box.set_border_width_all(2)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	if disabled:
		box.bg_color = Color(0.12, 0.12, 0.16, 0.55)
		box.border_color = Color(0.25, 0.26, 0.32, 0.5)
		return box
	match kind:
		"move":
			box.bg_color = Color(0.14, 0.34, 0.52, 0.95) if active else Color(0.1, 0.18, 0.28, 0.92)
			box.border_color = Color(0.45, 0.78, 1.0) if active else Color(0.28, 0.45, 0.62)
		"combat":
			box.bg_color = Color(0.52, 0.18, 0.18, 0.95) if active else Color(0.22, 0.12, 0.14, 0.92)
			var combat_border_active := Color(1.0, 0.45, 0.38)
			var combat_border_idle := Color(0.48, 0.28, 0.28)
			box.border_color = combat_border_active if active else combat_border_idle
		"skill":
			box.bg_color = Color(0.42, 0.22, 0.62, 0.95) if active else Color(0.18, 0.12, 0.28, 0.92)
			box.border_color = Color(0.82, 0.55, 1.0) if active else Color(0.42, 0.32, 0.58)
		"gem":
			box.bg_color = Color(0.16, 0.38, 0.28, 0.95) if active else Color(0.1, 0.2, 0.16, 0.92)
			box.border_color = Color(0.45, 0.92, 0.62) if active else Color(0.28, 0.52, 0.38)
		"end":
			box.bg_color = Color(0.58, 0.42, 0.12, 0.95) if active else Color(0.22, 0.18, 0.1, 0.92)
			box.border_color = Color(1.0, 0.82, 0.35) if active else Color(0.52, 0.42, 0.22)
		"ghost":
			box.bg_color = Color(0.12, 0.12, 0.16, 0.75)
			box.border_color = Color(0.32, 0.34, 0.4, 0.65)
		_:
			box.bg_color = Color(0.16, 0.16, 0.22, 0.92)
			box.border_color = BORDER
	return box


static func apply_button(button: Button, kind: String, active: bool = false) -> void:
	var disabled := button.disabled
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := button_style(kind, active and not disabled, disabled)
		if state == "hover" and not disabled:
			style.bg_color = style.bg_color.lightened(0.08)
		if state == "pressed" and not disabled:
			style.bg_color = style.bg_color.darkened(0.06)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", TEXT if not disabled else TEXT_MUTED)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_font_size_override("font_size", 14)


static func chip_style(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color.darkened(0.55)
	box.bg_color.a = 0.88
	box.border_color = color.lightened(0.1)
	box.set_border_width_all(1)
	box.set_corner_radius_all(12)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 3
	box.content_margin_bottom = 3
	return box


static func hp_fill_color(ratio: float) -> Color:
	if ratio <= 0.3:
		return HP_LOW
	if ratio <= 0.6:
		return HP_MID
	return HP_HIGH


static func shield_bar_styles() -> Dictionary:
	return {
		"background": shield_bg_style(),
		"fill": shield_fill_style(),
	}


static func shield_bg_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = SHIELD_BG
	box.border_color = SHIELD_BORDER
	box.set_border_width_all(1)
	box.set_corner_radius_all(3)
	return box


static func shield_fill_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = SHIELD_FILL
	box.border_color = SHIELD_FILL_HI
	box.set_border_width_all(1)
	box.set_corner_radius_all(3)
	return box


static func section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", TEXT_MUTED)
	return label


static func separator() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 8)
	return sep
