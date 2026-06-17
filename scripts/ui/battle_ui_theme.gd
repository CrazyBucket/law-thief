class_name BattleUiTheme
extends RefCounted

## 像素风 UI 主题工厂：颜色一律取自 UiPalette；风格约定为
## 无圆角、不透明面板、外深内亮双层硬边、像素字体。

const BG_DEEP := UiPalette.BG_DEEP
const BG_PANEL := UiPalette.BG_PANEL
const BG_DOCK := UiPalette.BG_DOCK
const BG_INSET := UiPalette.BG_INSET
const BORDER := UiPalette.EDGE_LIGHT
const BORDER_ACCENT := UiPalette.EDGE_ACCENT
const TEXT := UiPalette.TEXT_BRIGHT
const TEXT_MUTED := UiPalette.TEXT_MUTED
const TEXT_GOLD := UiPalette.TEXT_GOLD
const TEXT_HINT := UiPalette.TEXT_HINT
const HP_HIGH := UiPalette.HP_HIGH
const HP_MID := UiPalette.HP_MID
const HP_LOW := UiPalette.HP_LOW
const SHIELD_FILL := UiPalette.SHIELD_FILL
const SHIELD_FILL_HI := UiPalette.SHIELD_FILL_HI
const SHIELD_BG := UiPalette.SHIELD_BG
const SHIELD_BORDER := UiPalette.SHIELD_BORDER
const PHASE_PLAYER := UiPalette.PHASE_PLAYER
const PHASE_ENEMY := UiPalette.PHASE_ENEMY
const PHASE_END := UiPalette.PHASE_END

const FONT_SMALL := 12
const FONT_BODY := 12
const FONT_TITLE := 24

const _PIXEL_FONT_PATH := "res://assets/ui/fusion-pixel-12px-zh_hans.ttf"

static var _pixel_font_cache: FontFile = null
static var _theme_cache: Theme = null


static func pixel_font() -> Font:
	if _pixel_font_cache != null:
		return _pixel_font_cache
	var font := FontFile.new()
	var err := font.load_dynamic_font(_PIXEL_FONT_PATH)
	if err != OK:
		return ThemeDB.fallback_font
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	font.hinting = TextServer.HINTING_NONE
	font.generate_mipmaps = false
	_pixel_font_cache = font
	return _pixel_font_cache


static func build_theme() -> Theme:
	if _theme_cache != null:
		return _theme_cache
	var theme := Theme.new()
	theme.default_font = pixel_font()
	theme.default_font_size = FONT_BODY
	theme.set_stylebox("panel", "TooltipPanel", tooltip_style())
	theme.set_color("font_color", "TooltipLabel", TEXT)
	_theme_cache = theme
	return _theme_cache


static func apply_root_theme(root: Control) -> void:
	root.theme = build_theme()


static func _pixel_box(bg: Color, edge: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = edge
	box.set_border_width_all(1)
	box.set_corner_radius_all(0)
	box.shadow_color = UiPalette.EDGE_DARK
	box.shadow_size = 2
	box.shadow_offset = Vector2.ZERO
	return box


static func panel_style(accent: Color = BORDER) -> StyleBoxFlat:
	var box := _pixel_box(BG_PANEL, accent)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box


static func dock_style() -> StyleBoxFlat:
	var box := _pixel_box(BG_DOCK.darkened(0.08), BORDER_ACCENT.darkened(0.25))
	box.border_width_top = 2
	box.border_width_left = 0
	box.border_width_right = 0
	box.border_width_bottom = 0
	box.shadow_size = 3
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box


static func command_group_style(kind: String, active: bool = false) -> StyleBoxFlat:
	var accent := _action_base_color(kind)
	if accent == Color.TRANSPARENT:
		accent = BORDER
	var bg := BG_INSET
	if active:
		bg = accent.darkened(0.72)
	var box := _pixel_box(bg, accent.darkened(0.24) if not active else accent.lightened(0.1))
	box.shadow_size = 1
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 5
	box.content_margin_bottom = 7
	return box


static func tooltip_style() -> StyleBoxFlat:
	var box := _pixel_box(UiPalette.BG_RAISED, BORDER_ACCENT)
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
	box.set_corner_radius_all(0)
	box.set_border_width_all(2)
	box.shadow_color = UiPalette.EDGE_DARK
	box.shadow_size = 1
	box.shadow_offset = Vector2(0, 1)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	if disabled:
		box.bg_color = UiPalette.BG_RAISED.darkened(0.3)
		box.border_color = UiPalette.EDGE_MID
		box.shadow_size = 0
		return box
	var base := _action_base_color(kind)
	if kind == "ghost":
		box.bg_color = UiPalette.BG_RAISED
		box.border_color = UiPalette.EDGE_MID
		return box
	if base == Color.TRANSPARENT:
		box.bg_color = UiPalette.BG_RAISED
		box.border_color = BORDER
		return box
	box.bg_color = base.darkened(0.35) if active else base.darkened(0.68)
	box.border_color = base.lightened(0.25) if active else base.darkened(0.3)
	return box


static func _action_base_color(kind: String) -> Color:
	match kind:
		"move":
			return UiPalette.ACTION_MOVE
		"combat":
			return UiPalette.ACTION_COMBAT
		"skill":
			return UiPalette.ACTION_SKILL
		"gem":
			return UiPalette.ACTION_GEM
		"end":
			return UiPalette.ACTION_END
	return Color.TRANSPARENT


static func apply_button(button: Button, kind: String, active: bool = false) -> void:
	var disabled := button.disabled
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := button_style(kind, active and not disabled, disabled)
		if state == "hover" and not disabled:
			style.bg_color = style.bg_color.lightened(0.1)
			style.border_color = style.border_color.lightened(0.15)
		if state == "pressed" and not disabled:
			style.bg_color = style.bg_color.darkened(0.12)
			style.shadow_size = 0
		button.add_theme_stylebox_override(state, style)
	button.add_theme_font_override("font", pixel_font())
	button.add_theme_color_override("font_color", TEXT if not disabled else TEXT_MUTED)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_font_size_override("font_size", FONT_BODY)


static func chip_style(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color.darkened(0.62)
	box.border_color = color.lightened(0.1)
	box.set_border_width_all(1)
	box.set_corner_radius_all(0)
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
	return bar_bg_style(SHIELD_BORDER)


static func shield_fill_style() -> StyleBoxFlat:
	return bar_fill_style(SHIELD_FILL)


static func bar_bg_style(edge: Color = UiPalette.EDGE_MID) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = UiPalette.BG_INSET
	box.border_color = edge
	box.set_border_width_all(1)
	box.set_corner_radius_all(0)
	return box


static func bar_fill_style(fill: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = fill.lightened(0.22)
	box.border_width_top = 1
	box.set_corner_radius_all(0)
	return box


## 棋盘世界空间的分段像素条；面板内 ProgressBar 走 bar_*_style。
static func draw_pixel_bar(canvas: CanvasItem, rect: Rect2, ratio: float, fill: Color) -> void:
	var clamped: float = clampf(ratio, 0.0, 1.0)
	canvas.draw_rect(rect.grow(1), UiPalette.EDGE_DARK, true)
	canvas.draw_rect(rect, UiPalette.BG_INSET, true)
	var seg_w := 3.0
	var gap := 1.0
	var inner := rect.grow(-1)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return
	var total_segs: int = maxi(1, int(floor((inner.size.x + gap) / (seg_w + gap))))
	var lit_segs: int = int(round(clamped * float(total_segs)))
	if clamped > 0.0:
		lit_segs = maxi(lit_segs, 1)
	for i in range(lit_segs):
		var x := inner.position.x + float(i) * (seg_w + gap)
		var w := minf(seg_w, inner.position.x + inner.size.x - x)
		if w <= 0.0:
			break
		canvas.draw_rect(Rect2(x, inner.position.y, w, inner.size.y), fill, true)
	var hi := Rect2(inner.position, Vector2(inner.size.x * clamped, 1))
	if hi.size.x >= 1.0:
		canvas.draw_rect(hi, fill.lightened(0.3), true)


static func section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", pixel_font())
	label.add_theme_font_size_override("font_size", FONT_SMALL)
	label.add_theme_color_override("font_color", TEXT_MUTED)
	return label


static func separator() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 8)
	return sep
