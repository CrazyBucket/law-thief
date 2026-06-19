class_name RichTooltip
extends Control

const BattleUiTheme = preload("res://scripts/ui/battle_ui_theme.gd")

const _MAIN_WIDTH := 260.0
const _SIDE_WIDTH := 220.0
const _PANEL_GAP := 8.0
const _SCREEN_PAD := 8.0
const _CURSOR_OFFSET := Vector2(18.0, 18.0)
const _MAX_HEIGHT_RATIO := 0.58
const _MAX_HEIGHT_ABS := 390.0
const _MIN_SCROLL_HEIGHT := 64.0

var _main_panel: PanelContainer = null
var _main_scroll: ScrollContainer = null
var _main_content: VBoxContainer = null
var _side_panel: PanelContainer = null
var _side_scroll: ScrollContainer = null
var _side_content: VBoxContainer = null
var _hide_timer: Timer = null
var _active_owner: Control = null
var _layout_serial: int = 0
var _tooltip_mouse_inside: bool = false
var _last_total_size: Vector2 = Vector2.ZERO
var _spec_sources: Dictionary = {}


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 4096
	theme = BattleUiTheme.build_theme()
	set_process(false)

	_main_panel = PanelContainer.new()
	_main_panel.custom_minimum_size = Vector2(_MAIN_WIDTH, 0.0)
	_main_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_main_panel.add_theme_stylebox_override("panel", _tooltip_panel_style(BattleUiTheme.TEXT_GOLD, false))
	add_child(_main_panel)

	_main_scroll = ScrollContainer.new()
	_main_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_main_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_main_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_main_scroll.clip_contents = true
	_main_panel.add_child(_main_scroll)

	_main_content = VBoxContainer.new()
	_main_content.custom_minimum_size.x = _content_width(_MAIN_WIDTH)
	_main_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_content.add_theme_constant_override("separation", 7)
	_main_scroll.add_child(_main_content)

	_side_panel = PanelContainer.new()
	_side_panel.custom_minimum_size = Vector2(_SIDE_WIDTH, 0.0)
	_side_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_side_panel.visible = false
	_side_panel.add_theme_stylebox_override("panel", _tooltip_panel_style(BattleUiTheme.TEXT_GOLD, true))
	add_child(_side_panel)

	_side_scroll = ScrollContainer.new()
	_side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_side_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_side_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_side_scroll.clip_contents = true
	_side_panel.add_child(_side_scroll)

	_side_content = VBoxContainer.new()
	_side_content.custom_minimum_size.x = _content_width(_SIDE_WIDTH)
	_side_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_side_content.add_theme_constant_override("separation", 6)
	_side_scroll.add_child(_side_content)

	_hide_timer = Timer.new()
	_hide_timer.one_shot = true
	_hide_timer.wait_time = 0.22
	_hide_timer.timeout.connect(_on_hide_timer_timeout)
	add_child(_hide_timer)

	mouse_entered.connect(_on_tooltip_mouse_entered)
	mouse_exited.connect(_on_tooltip_mouse_exited)


func attach(owner: Control, spec_source: Variant) -> void:
	if owner == null:
		return
	var owner_id := owner.get_instance_id()
	_spec_sources[owner_id] = spec_source
	var meta_key := "_rich_tooltip_attached_%d" % get_instance_id()
	if bool(owner.get_meta(meta_key, false)):
		return
	owner.set_meta(meta_key, true)
	owner.mouse_entered.connect(_on_owner_mouse_entered.bind(owner), CONNECT_DEFERRED)
	owner.mouse_exited.connect(_on_owner_mouse_exited.bind(owner), CONNECT_DEFERRED)
	owner.tree_exiting.connect(_on_owner_tree_exiting.bind(owner_id), CONNECT_ONE_SHOT)


func show_for_control(owner: Control, spec: Dictionary) -> void:
	if owner == null or spec.is_empty():
		hide_tooltip()
		return
	_active_owner = owner
	_tooltip_mouse_inside = false
	_layout_serial += 1
	if _hide_timer != null:
		_hide_timer.stop()
	_clear_container(_main_content)
	_clear_container(_side_content)
	_main_content.custom_minimum_size.x = _content_width(_MAIN_WIDTH)
	_side_content.custom_minimum_size.x = _content_width(_SIDE_WIDTH)
	_side_panel.visible = false
	var accent := _color_from(spec.get("accent", BattleUiTheme.TEXT_GOLD))
	_main_panel.add_theme_stylebox_override("panel", _tooltip_panel_style(accent, false))
	_build_main_content(spec)
	visible = true
	modulate.a = 1.0
	set_process(true)
	_layout_after_content.call_deferred(_layout_serial)


func hide_tooltip() -> void:
	visible = false
	_active_owner = null
	_tooltip_mouse_inside = false
	_last_total_size = Vector2.ZERO
	set_process(false)
	if _hide_timer != null:
		_hide_timer.stop()
	_clear_container(_main_content)
	_clear_container(_side_content)
	if _side_panel != null:
		_side_panel.visible = false


func schedule_hide(owner: Control = null) -> void:
	if owner != null and _active_owner != null and owner != _active_owner:
		return
	if _hide_timer == null:
		hide_tooltip()
		return
	_hide_timer.start()


func _on_owner_mouse_entered(owner: Control) -> void:
	if owner == null or not is_instance_valid(owner):
		return
	var owner_id := owner.get_instance_id()
	var spec := _resolve_spec(_spec_sources.get(owner_id, {}))
	show_for_control(owner, spec)


func _on_owner_mouse_exited(owner: Control) -> void:
	schedule_hide(owner)


func _on_owner_tree_exiting(owner_id: int) -> void:
	_spec_sources.erase(owner_id)
	if _active_owner != null and _active_owner.get_instance_id() == owner_id:
		hide_tooltip()


func _on_tooltip_mouse_entered() -> void:
	_tooltip_mouse_inside = true
	if _hide_timer != null:
		_hide_timer.stop()


func _on_tooltip_mouse_exited() -> void:
	_tooltip_mouse_inside = false
	schedule_hide(_active_owner)


func _on_hide_timer_timeout() -> void:
	if _tooltip_mouse_inside:
		return
	hide_tooltip()


func _process(_delta: float) -> void:
	if not visible or _last_total_size == Vector2.ZERO or _tooltip_mouse_inside:
		return
	_place_near_mouse(_last_total_size)


func _resolve_spec(spec_source: Variant) -> Dictionary:
	if spec_source is Callable:
		var result: Variant = (spec_source as Callable).call()
		return result if result is Dictionary else {}
	return spec_source if spec_source is Dictionary else {}


func _build_main_content(spec: Dictionary) -> void:
	_add_header(_main_content, spec, _MAIN_WIDTH)
	var summary := str(spec.get("summary", ""))
	if not summary.is_empty():
		_add_body_label(_main_content, summary, BattleUiTheme.TEXT, _MAIN_WIDTH)
	var stats: Array = spec.get("stats", [])
	if not stats.is_empty():
		_add_stats(_main_content, stats, _MAIN_WIDTH)
	var components: Array = spec.get("components", [])
	for component in components:
		if component is Dictionary:
			_add_component(_main_content, component, _MAIN_WIDTH)
	var sections: Array = spec.get("sections", [])
	for section in sections:
		if section is Dictionary:
			_add_section(_main_content, section, _MAIN_WIDTH)
	var terms: Array = spec.get("terms", [])
	if not terms.is_empty():
		_add_terms(_main_content, terms, _MAIN_WIDTH)


func _add_component(container: VBoxContainer, component: Dictionary, width: float) -> void:
	match str(component.get("type", "text")):
		"divider":
			_add_pixel_rule(container, _color_from(component.get("color", BattleUiTheme.BORDER)), width)
		"section":
			_add_section(container, component, width)
		"stats":
			_add_stats(container, component.get("items", []), width)
		"text":
			_add_body_label(container, str(component.get("text", "")), _color_from(component.get("color", BattleUiTheme.TEXT)), width)
		"terms":
			_add_terms(container, component.get("items", []), width)


func _add_header(container: VBoxContainer, spec: Dictionary, width: float) -> void:
	var accent := _color_from(spec.get("accent", BattleUiTheme.TEXT_GOLD))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.custom_minimum_size.x = _content_width(width)
	container.add_child(row)

	var icon: Variant = spec.get("icon", null)
	if icon is Texture2D:
		var icon_wrap := Control.new()
		icon_wrap.custom_minimum_size = Vector2(24, 24)
		row.add_child(icon_wrap)
		var icon_rect := TextureRect.new()
		icon_rect.texture = icon
		icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.self_modulate = _color_from(spec.get("icon_tint", Color.WHITE))
		icon_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon_wrap.add_child(icon_rect)

	var title_col := VBoxContainer.new()
	title_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_col.add_theme_constant_override("separation", 2)
	row.add_child(title_col)

	var title := Label.new()
	title.text = str(spec.get("title", ""))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_override("font", BattleUiTheme.pixel_font())
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", accent)
	title_col.add_child(title)

	var subtitle := str(spec.get("subtitle", ""))
	if not subtitle.is_empty():
		var sub := Label.new()
		sub.text = subtitle
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub.add_theme_font_size_override("font_size", 11)
		sub.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
		title_col.add_child(sub)
	_add_pixel_rule(container, accent, width)


func _add_stats(container: VBoxContainer, stats: Array, width: float) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.custom_minimum_size.x = _content_width(width)
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 2)
	container.add_child(grid)
	for raw_stat in stats:
		if not raw_stat is Dictionary:
			continue
		var stat: Dictionary = raw_stat
		var label := Label.new()
		label.text = str(stat.get("label", ""))
		label.add_theme_font_size_override("font_size", 10)
		label.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
		grid.add_child(label)
		var value := Label.new()
		value.text = str(stat.get("value", ""))
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.add_theme_font_size_override("font_size", 10)
		value.add_theme_color_override("font_color", _color_from(stat.get("color", BattleUiTheme.TEXT)))
		grid.add_child(value)


func _add_section(container: VBoxContainer, section: Dictionary, width: float) -> void:
	var title := str(section.get("title", ""))
	if not title.is_empty():
		var title_label := Label.new()
		title_label.text = title
		title_label.add_theme_font_size_override("font_size", 10)
		title_label.add_theme_color_override("font_color", _color_from(section.get("accent", BattleUiTheme.TEXT_HINT)))
		container.add_child(title_label)
	_add_body_label(container, str(section.get("body", "")), _color_from(section.get("color", BattleUiTheme.TEXT)), width)


func _add_body_label(container: VBoxContainer, text: String, color: Color, width: float) -> void:
	if text.is_empty():
		return
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = _content_width(width)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", color)
	container.add_child(label)


func _add_terms(container: VBoxContainer, terms: Array, width: float) -> void:
	var label := Label.new()
	label.text = "词条"
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", BattleUiTheme.TEXT_HINT)
	container.add_child(label)
	var row := HFlowContainer.new()
	row.custom_minimum_size.x = _content_width(width)
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 5)
	container.add_child(row)
	for raw_term in terms:
		if not raw_term is Dictionary:
			continue
		var term: Dictionary = raw_term
		var btn := Button.new()
		btn.text = str(term.get("label", term.get("title", "")))
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(54, 24)
		BattleUiTheme.apply_button(btn, "ghost")
		btn.add_theme_color_override("font_color", _color_from(term.get("accent", BattleUiTheme.TEXT_GOLD)))
		btn.mouse_entered.connect(_show_term_detail.bind(term), CONNECT_DEFERRED)
		btn.pressed.connect(_show_term_detail.bind(term), CONNECT_DEFERRED)
		row.add_child(btn)


func _show_term_detail(term: Dictionary) -> void:
	_clear_container(_side_content)
	var accent := _color_from(term.get("accent", BattleUiTheme.TEXT_GOLD))
	_side_panel.add_theme_stylebox_override("panel", _tooltip_panel_style(accent, true))
	_add_header(_side_content, {
		"title": str(term.get("title", term.get("label", ""))),
		"subtitle": str(term.get("subtitle", "")),
		"icon": term.get("icon", null),
		"icon_tint": term.get("icon_tint", Color.WHITE),
		"accent": accent,
	}, _SIDE_WIDTH)
	var stats: Array = term.get("stats", [])
	if not stats.is_empty():
		_add_stats(_side_content, stats, _SIDE_WIDTH)
	_add_body_label(_side_content, str(term.get("body", "")), BattleUiTheme.TEXT, _SIDE_WIDTH)
	var sections: Array = term.get("sections", [])
	for section in sections:
		if section is Dictionary:
			_add_section(_side_content, section, _SIDE_WIDTH)
	_side_panel.visible = true
	_layout_serial += 1
	_layout_after_content.call_deferred(_layout_serial)


func _layout_after_content(serial: int) -> void:
	await get_tree().process_frame
	if serial != _layout_serial or not visible:
		return
	_sync_panel_layout()


func _sync_panel_layout() -> void:
	if _main_panel == null or _active_owner == null or not is_instance_valid(_active_owner):
		hide_tooltip()
		return
	var max_panel_h := _max_panel_height()
	var main_size := _panel_size_for(_main_panel, _main_scroll, _MAIN_WIDTH, max_panel_h)
	_main_panel.position = Vector2.ZERO
	_main_panel.size = main_size

	var total_size := main_size
	if _side_panel.visible:
		var side_size := _panel_size_for(_side_panel, _side_scroll, _SIDE_WIDTH, max_panel_h)
		_side_panel.position = Vector2(main_size.x + _PANEL_GAP, 0.0)
		_side_panel.size = side_size
		total_size.x = main_size.x + _PANEL_GAP + side_size.x
		total_size.y = maxf(main_size.y, side_size.y)
	size = total_size
	_last_total_size = total_size
	if _tooltip_mouse_inside:
		global_position = _clamp_position(global_position, total_size)
	else:
		_place_near_mouse(total_size)


func _place_near_mouse(total_size: Vector2) -> void:
	var mouse := get_viewport().get_mouse_position()
	var target := mouse + _CURSOR_OFFSET
	var viewport_size := get_viewport_rect().size
	if target.x + total_size.x > viewport_size.x - _SCREEN_PAD:
		target.x = mouse.x - total_size.x - _CURSOR_OFFSET.x
	if target.y + total_size.y > viewport_size.y - _SCREEN_PAD:
		target.y = mouse.y - total_size.y - _CURSOR_OFFSET.y
	global_position = _clamp_position(target, total_size)


func _clamp_position(target: Vector2, total_size: Vector2) -> Vector2:
	var viewport_size := get_viewport_rect().size
	target.x = clampf(target.x, _SCREEN_PAD, maxf(_SCREEN_PAD, viewport_size.x - total_size.x - _SCREEN_PAD))
	target.y = clampf(target.y, _SCREEN_PAD, maxf(_SCREEN_PAD, viewport_size.y - total_size.y - _SCREEN_PAD))
	return target


func _panel_size_for(panel: PanelContainer, scroll: ScrollContainer, width: float, max_h: float) -> Vector2:
	scroll.custom_minimum_size.y = 0.0
	var margins := _panel_margins(panel)
	var scroll_w := maxf(_content_width(width), width - margins.x)
	scroll.custom_minimum_size.x = scroll_w
	var content := scroll.get_child(0) as Control
	var content_h := 0.0
	if content != null:
		content.custom_minimum_size.x = scroll_w
		content_h = content.get_combined_minimum_size().y
	var wanted_h := maxf(_MIN_SCROLL_HEIGHT, content_h) + margins.y
	var wanted_w := maxf(width, scroll_w + margins.x)
	if wanted_h <= max_h:
		scroll.custom_minimum_size.y = maxf(_MIN_SCROLL_HEIGHT, content_h)
		return Vector2(wanted_w, wanted_h)
	var scroll_h := maxf(_MIN_SCROLL_HEIGHT, max_h - margins.y)
	scroll.custom_minimum_size.y = scroll_h
	return Vector2(wanted_w, max_h)


func _max_panel_height() -> float:
	var viewport_h := get_viewport_rect().size.y
	return minf(_MAX_HEIGHT_ABS, maxf(160.0, viewport_h * _MAX_HEIGHT_RATIO))


func _panel_margins(panel: PanelContainer) -> Vector2:
	var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
	if style == null:
		return Vector2(20.0, 18.0)
	return Vector2(
		style.content_margin_left + style.content_margin_right,
		style.content_margin_top + style.content_margin_bottom
	)


func _tooltip_panel_style(accent: Color, side: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = UiPalette.BG_PANEL if side else UiPalette.BG_RAISED.darkened(0.08)
	box.border_color = accent.lightened(0.05)
	box.set_border_width_all(2)
	box.set_corner_radius_all(0)
	box.shadow_color = UiPalette.EDGE_DARK
	box.shadow_size = 4
	box.shadow_offset = Vector2(3, 3)
	box.content_margin_left = 9
	box.content_margin_right = 9
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box


func _add_pixel_rule(container: VBoxContainer, color: Color, width: float) -> void:
	var line := ColorRect.new()
	line.color = Color(color, 0.82)
	line.custom_minimum_size = Vector2(_content_width(width), 2.0)
	container.add_child(line)


func _content_width(width: float) -> float:
	return maxf(80.0, width - 22.0)


func _clear_container(container: Container) -> void:
	if container == null:
		return
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _color_from(value: Variant) -> Color:
	return value if value is Color else BattleUiTheme.TEXT
