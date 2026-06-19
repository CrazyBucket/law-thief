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
var _owner_mouse_inside: bool = false
var _pinned: bool = false
var _last_total_size: Vector2 = Vector2.ZERO
var _spec_sources: Dictionary = {}
var _detail_panels: Array[PanelContainer] = []
var _detail_scrolls: Array[ScrollContainer] = []
var _detail_contents: Array[VBoxContainer] = []


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 4096
	theme = BattleUiTheme.build_theme()
	set_process(false)

	_main_panel = PanelContainer.new()
	_main_panel.custom_minimum_size = Vector2(_MAIN_WIDTH, 0.0)
	_main_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_main_panel.add_theme_stylebox_override("panel", _tooltip_panel_style())
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
	_side_panel.add_theme_stylebox_override("panel", _tooltip_panel_style())
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
	_detail_panels.append(_side_panel)
	_detail_scrolls.append(_side_scroll)
	_detail_contents.append(_side_content)
	_refresh_panel_styles()

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
	if _pinned and owner != _active_owner:
		return
	_active_owner = owner
	_tooltip_mouse_inside = false
	_owner_mouse_inside = true
	_pinned = false
	_layout_serial += 1
	if _hide_timer != null:
		_hide_timer.stop()
	_clear_container(_main_content)
	_clear_detail_panels()
	_main_content.custom_minimum_size.x = _content_width(_MAIN_WIDTH)
	_side_content.custom_minimum_size.x = _content_width(_SIDE_WIDTH)
	_side_panel.visible = false
	_refresh_panel_styles()
	_build_main_content(spec)
	visible = true
	modulate.a = 1.0
	set_process(true)
	_layout_after_content.call_deferred(_layout_serial)


func hide_tooltip() -> void:
	visible = false
	_active_owner = null
	_tooltip_mouse_inside = false
	_owner_mouse_inside = false
	_pinned = false
	_last_total_size = Vector2.ZERO
	set_process(false)
	if _hide_timer != null:
		_hide_timer.stop()
	_clear_container(_main_content)
	_clear_detail_panels()


func schedule_hide(owner: Control = null) -> void:
	if _pinned:
		return
	if owner != null and _active_owner != null and owner != _active_owner:
		return
	if _hide_timer == null:
		hide_tooltip()
		return
	_hide_timer.start()


func _on_owner_mouse_entered(owner: Control) -> void:
	if owner == null or not is_instance_valid(owner):
		return
	if _pinned and owner != _active_owner:
		return
	var owner_id := owner.get_instance_id()
	_owner_mouse_inside = true
	var spec := _resolve_spec(_spec_sources.get(owner_id, {}))
	show_for_control(owner, spec)


func _on_owner_mouse_exited(owner: Control) -> void:
	_owner_mouse_inside = false
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
	if not visible or _last_total_size == Vector2.ZERO or _tooltip_mouse_inside or _pinned:
		return
	_place_near_mouse(_last_total_size)


func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if key_event.keycode != KEY_SHIFT or key_event.location == KEY_LOCATION_RIGHT:
		return
	if not key_event.pressed or key_event.echo:
		return
	_pinned = not _pinned
	_refresh_panel_styles()
	if _pinned:
		if _hide_timer != null:
			_hide_timer.stop()
	else:
		if not _owner_mouse_inside and not _tooltip_mouse_inside:
			hide_tooltip()


func _resolve_spec(spec_source: Variant) -> Dictionary:
	if spec_source is Callable:
		var result: Variant = (spec_source as Callable).call()
		return result if result is Dictionary else {}
	return spec_source if spec_source is Dictionary else {}


func _build_main_content(spec: Dictionary) -> void:
	var terms: Array = spec.get("terms", [])
	var summary := str(spec.get("summary", ""))
	if not summary.is_empty():
		_add_body_label(_main_content, summary, BattleUiTheme.TEXT, _MAIN_WIDTH, terms, 0)
	var stats: Array = spec.get("stats", [])
	if not stats.is_empty():
		_add_stats(_main_content, stats, _MAIN_WIDTH)
	var components: Array = spec.get("components", [])
	for component in components:
		if component is Dictionary:
			_add_component(_main_content, component, _MAIN_WIDTH, terms, 0)
	var sections: Array = spec.get("sections", [])
	for section in sections:
		if section is Dictionary:
			_add_section(_main_content, section, _MAIN_WIDTH, terms, 0)


func _add_component(container: VBoxContainer, component: Dictionary, width: float, terms: Array = [], depth: int = 0) -> void:
	match str(component.get("type", "text")):
		"divider":
			_add_pixel_rule(container, _color_from(component.get("color", BattleUiTheme.BORDER)), width)
		"section":
			_add_section(container, component, width, terms, depth)
		"stats":
			_add_stats(container, component.get("items", []), width)
		"text":
			_add_body_label(container, str(component.get("text", "")), _color_from(component.get("color", BattleUiTheme.TEXT)), width, terms, depth)
		"terms":
			pass


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


func _add_section(container: VBoxContainer, section: Dictionary, width: float, terms: Array = [], depth: int = 0) -> void:
	var title := str(section.get("title", ""))
	if not title.is_empty():
		var title_label := Label.new()
		title_label.text = title
		title_label.add_theme_font_size_override("font_size", 10)
		title_label.add_theme_color_override("font_color", _color_from(section.get("accent", BattleUiTheme.TEXT_HINT)))
		container.add_child(title_label)
	_add_body_label(container, str(section.get("body", "")), _color_from(section.get("color", BattleUiTheme.TEXT)), width, terms, depth)


func _add_body_label(container: VBoxContainer, text: String, color: Color, width: float, terms: Array = [], depth: int = 0) -> void:
	if text.is_empty():
		return
	var label := RichTextLabel.new()
	label.custom_minimum_size.x = _content_width(width)
	label.fit_content = true
	label.scroll_active = false
	label.bbcode_enabled = true
	label.meta_underlined = true
	label.mouse_filter = Control.MOUSE_FILTER_STOP if not terms.is_empty() else Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("normal_font_size", 12)
	label.add_theme_color_override("default_color", color)
	if not terms.is_empty():
		label.mouse_entered.connect(_on_term_label_mouse_entered.bind(depth), CONNECT_DEFERRED)
	label.meta_hover_started.connect(_on_term_hover_started.bind(terms, depth), CONNECT_DEFERRED)
	label.meta_clicked.connect(_on_term_hover_started.bind(terms, depth), CONNECT_DEFERRED)
	container.add_child(label)
	_append_highlighted_text(label, text, terms)


func _append_highlighted_text(label: RichTextLabel, text: String, terms: Array) -> void:
	var cursor := 0
	while cursor < text.length():
		var match_pos := -1
		var match_index := -1
		var match_text := ""
		for index in range(terms.size()):
			if not terms[index] is Dictionary:
				continue
			var candidate := str(terms[index].get("label", terms[index].get("title", "")))
			if candidate.is_empty():
				continue
			var candidate_pos := text.find(candidate, cursor)
			if candidate_pos >= 0 and (match_pos < 0 or candidate_pos < match_pos or (candidate_pos == match_pos and candidate.length() > match_text.length())):
				match_pos = candidate_pos
				match_index = index
				match_text = candidate
		if match_index < 0:
			label.add_text(text.substr(cursor))
			break
		if match_pos > cursor:
			label.add_text(text.substr(cursor, match_pos - cursor))
		var term: Dictionary = terms[match_index]
		label.push_meta(match_index)
		label.push_color(_color_from(term.get("accent", BattleUiTheme.TEXT_GOLD)).lightened(0.18))
		label.add_text(match_text)
		label.pop()
		label.pop()
		cursor = match_pos + match_text.length()


func _on_term_hover_started(meta: Variant, terms: Array, depth: int) -> void:
	var index := int(meta)
	if index < 0 or index >= terms.size() or not terms[index] is Dictionary:
		return
	_show_term_detail(terms[index], depth + 1)


func _show_term_detail(term: Dictionary, depth: int) -> void:
	var panel_index := depth - 1
	_ensure_detail_panel(panel_index)
	_hide_detail_panels_after(panel_index)
	var content := _detail_contents[panel_index]
	_clear_container(content)
	var nested_terms: Array = term.get("terms", [])
	var stats: Array = term.get("stats", [])
	if not stats.is_empty():
		_add_stats(content, stats, _SIDE_WIDTH)
	_add_body_label(content, str(term.get("body", "")), BattleUiTheme.TEXT, _SIDE_WIDTH, nested_terms, depth)
	var sections: Array = term.get("sections", [])
	for section in sections:
		if section is Dictionary:
			_add_section(content, section, _SIDE_WIDTH, nested_terms, depth)
	_detail_panels[panel_index].visible = true
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

	var viewport_width := maxf(_MAIN_WIDTH, get_viewport_rect().size.x - _SCREEN_PAD * 2.0)
	var next_x := main_size.x + _PANEL_GAP
	var next_y := 0.0
	var row_height := main_size.y
	var total_size := main_size
	for index in range(_detail_panels.size()):
		var panel := _detail_panels[index]
		if not panel.visible:
			continue
		var panel_size := _panel_size_for(panel, _detail_scrolls[index], _SIDE_WIDTH, max_panel_h)
		if next_x + panel_size.x > viewport_width:
			next_x = 0.0
			next_y += row_height + _PANEL_GAP
			row_height = 0.0
		panel.position = Vector2(next_x, next_y)
		panel.size = panel_size
		next_x += panel_size.x + _PANEL_GAP
		row_height = maxf(row_height, panel_size.y)
		total_size.x = maxf(total_size.x, next_x - _PANEL_GAP)
		total_size.y = maxf(total_size.y, next_y + row_height)
	size = total_size
	_last_total_size = total_size
	if _tooltip_mouse_inside or _pinned:
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


func _tooltip_panel_style() -> StyleBoxFlat:
	var style := BattleUiTheme.tooltip_style()
	if _pinned:
		style.border_color = BattleUiTheme.BORDER_ACCENT.lightened(0.16)
		style.shadow_color = BattleUiTheme.BORDER_ACCENT.darkened(0.45)
	return style


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


func _ensure_detail_panel(index: int) -> void:
	while _detail_panels.size() <= index:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(_SIDE_WIDTH, 0.0)
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.visible = false
		panel.add_theme_stylebox_override("panel", _tooltip_panel_style())
		add_child(panel)
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		scroll.mouse_filter = Control.MOUSE_FILTER_PASS
		scroll.clip_contents = true
		panel.add_child(scroll)
		var content := VBoxContainer.new()
		content.custom_minimum_size.x = _content_width(_SIDE_WIDTH)
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.add_theme_constant_override("separation", 6)
		scroll.add_child(content)
		_detail_panels.append(panel)
		_detail_scrolls.append(scroll)
		_detail_contents.append(content)
	_refresh_panel_styles()


func _hide_detail_panels_after(index: int) -> void:
	for detail_index in range(index + 1, _detail_panels.size()):
		_clear_container(_detail_contents[detail_index])
		_detail_panels[detail_index].visible = false


func _clear_detail_panels() -> void:
	for index in range(_detail_panels.size()):
		_clear_container(_detail_contents[index])
		_detail_panels[index].visible = false


func _on_term_label_mouse_entered(depth: int) -> void:
	_hide_detail_panels_after(depth - 1)


func _refresh_panel_styles() -> void:
	if _main_panel != null:
		_main_panel.add_theme_stylebox_override("panel", _tooltip_panel_style())
	for panel in _detail_panels:
		if panel != null:
			panel.add_theme_stylebox_override("panel", _tooltip_panel_style())


func _color_from(value: Variant) -> Color:
	return value if value is Color else BattleUiTheme.TEXT
