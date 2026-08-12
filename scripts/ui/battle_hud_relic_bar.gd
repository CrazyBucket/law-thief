class_name BattleHudRelicBar
extends RefCounted

const _ICON_MAX := 30.0
const _ICON_MIN := 24.0
const _ROW_GAP := 6.0
const _COLUMN_GAP := 12.0
const _ICON_PAD := 3.0
const _MAX_COLUMNS := 3

var _root: Control = null
var _scroll: ScrollContainer = null
var _grid: Container = null
var _owned_relics_cb: Callable = Callable()
var _texture_for_relic_cb: Callable = Callable()
var _show_detail_cb: Callable = Callable()
var _badge_state_cb: Callable = Callable()
var _ids: Array[String] = []
var _layout_key := ""
var _texture_cache: Dictionary = {}


func setup(deps: Dictionary) -> void:
	_root = deps.get("root", null)
	_scroll = deps.get("scroll", null)
	_grid = deps.get("grid", null)
	_owned_relics_cb = deps.get("owned_relics_cb", Callable())
	_texture_for_relic_cb = deps.get("texture_for_relic_cb", Callable())
	_show_detail_cb = deps.get("show_detail_cb", Callable())
	_badge_state_cb = deps.get("badge_state_cb", Callable())


func refresh(available_height: float = 320.0) -> void:
	if _grid == null or _scroll == null:
		return
	var owned := _owned_relics()
	var has_relics := not owned.is_empty()
	if _root != null:
		_root.visible = has_relics
	_scroll.visible = has_relics
	if not has_relics:
		_ids = owned.duplicate()
		_layout_key = ""
		_clear_grid()
		_scroll.custom_minimum_size = Vector2.ZERO
		return

	var layout := layout_for(owned.size(), available_height)
	var icon_size := float(layout.get("icon_size", _ICON_MAX))
	var columns := int(layout.get("columns", 1))
	var content_size: Vector2 = layout.get("content_size", Vector2.ZERO)
	var viewport_size: Vector2 = layout.get("viewport_size", Vector2.ZERO)
	var allow_scroll := bool(layout.get("scroll", false))
	var layout_key := "%d:%d:%0.1f:%d" % [owned.size(), columns, icon_size, int(allow_scroll)]
	if owned != _ids or layout_key != _layout_key:
		_ids = owned.duplicate()
		_layout_key = layout_key
		_clear_grid()
		if _grid is GridContainer:
			(_grid as GridContainer).columns = columns
		_grid.add_theme_constant_override("h_separation", int(_COLUMN_GAP))
		_grid.add_theme_constant_override("v_separation", int(_ROW_GAP))
		for relic_id in ids_for_grid(owned, columns):
			_grid.add_child(create_badge(relic_id, icon_size))
	_grid.custom_minimum_size = content_size
	_scroll.custom_minimum_size = viewport_size
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if allow_scroll else ScrollContainer.SCROLL_MODE_DISABLED
	_refresh_badge_states()


static func layout_for(count: int, available_height: float = 320.0) -> Dictionary:
	var bar_height := maxf(_ICON_MIN + _ICON_PAD * 2.0, available_height)
	var padded_max := _ICON_MAX + _ICON_PAD * 2.0
	var padded_min := _ICON_MIN + _ICON_PAD * 2.0
	var single_column_height := float(count) * padded_max + float(maxi(count - 1, 0)) * _ROW_GAP
	if single_column_height <= bar_height:
		return _layout_result(1, _ICON_MAX, single_column_height, padded_max, false, bar_height)
	var shrink_total_gap := float(maxi(count - 1, 0)) * _ROW_GAP
	var shrink_icon := floorf((bar_height - shrink_total_gap) / float(count)) - _ICON_PAD * 2.0
	if shrink_icon >= _ICON_MIN:
		var padded_icon := shrink_icon + _ICON_PAD * 2.0
		return _layout_result(1, shrink_icon, bar_height, padded_icon, false, bar_height)
	var rows_at_min := maxi(1, int(floorf((bar_height + _ROW_GAP) / (padded_min + _ROW_GAP))))
	var columns := mini(_MAX_COLUMNS, maxi(1, int(ceili(float(count) / float(rows_at_min)))))
	var rows := int(ceili(float(count) / float(columns)))
	var content_height := float(rows) * padded_min + float(maxi(rows - 1, 0)) * _ROW_GAP
	var content_width := float(columns) * padded_min + float(maxi(columns - 1, 0)) * _COLUMN_GAP
	return _layout_result(columns, _ICON_MIN, content_height, content_width, content_height > bar_height, bar_height)


static func ids_for_grid(ids: Array[String], columns: int) -> Array[String]:
	if columns <= 1:
		return ids.duplicate()
	var ordered: Array[String] = []
	var rows := int(ceili(float(ids.size()) / float(columns)))
	for row in range(rows):
		for column in range(columns):
			var index := column * rows + row
			if index < ids.size():
				ordered.append(ids[index])
	return ordered


static func _layout_result(columns: int, icon_size: float, content_height: float, content_width: float, scroll: bool, max_height: float) -> Dictionary:
	return {
		"columns": columns,
		"icon_size": icon_size,
		"content_size": Vector2(content_width, content_height),
		"viewport_size": Vector2(content_width + (12.0 if scroll else 0.0), minf(content_height, max_height)),
		"scroll": scroll,
	}


func _owned_relics() -> Array[String]:
	var owned: Array[String] = []
	if not _owned_relics_cb.is_valid():
		return owned
	for relic_id in _owned_relics_cb.call():
		owned.append(str(relic_id))
	return owned


func _clear_grid() -> void:
	for child in _grid.get_children():
		child.queue_free()


func create_badge(relic_id: String, icon_size: float) -> Control:
	var item_size := Vector2(icon_size + _ICON_PAD * 2.0, icon_size + _ICON_PAD * 2.0)
	var root := Control.new()
	root.set_meta("relic_id", relic_id)
	root.custom_minimum_size = item_size
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	root.clip_contents = false
	var source_texture: Texture2D = _texture_for_relic_cb.call(relic_id) if _texture_for_relic_cb.is_valid() else null
	if source_texture != null:
		var icon := TextureRect.new()
		icon.name = "RelicIcon"
		icon.texture = _render_texture(source_texture, icon_size, false)
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(icon)
		var outline := TextureRect.new()
		outline.name = "HoverTextureOutline"
		outline.visible = false
		outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		outline.texture = _render_texture(source_texture, icon_size, true)
		outline.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		outline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		outline.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		outline.stretch_mode = TextureRect.STRETCH_SCALE
		root.add_child(outline)
		root.mouse_entered.connect(func() -> void:
			outline.visible = true
			icon.visible = false
		)
		root.mouse_exited.connect(func() -> void:
			outline.visible = false
			icon.visible = true
		)
	var button := Button.new()
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.mouse_entered.connect(func() -> void: _set_badge_hover(root, true))
	button.mouse_exited.connect(func() -> void: _set_badge_hover(root, false))
	if _show_detail_cb.is_valid():
		button.pressed.connect(_show_detail_cb.bind(relic_id))
	root.add_child(button)
	var state_badge := Label.new()
	state_badge.name = "StateBadge"
	state_badge.visible = false
	state_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	state_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	state_badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	state_badge.add_theme_font_size_override("font_size", 9)
	state_badge.add_theme_color_override("font_color", Color(1.0, 0.9, 0.36))
	state_badge.add_theme_color_override("font_outline_color", Color(0.08, 0.07, 0.06, 1.0))
	state_badge.add_theme_constant_override("outline_size", 3)
	state_badge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(state_badge)
	return root


func _refresh_badge_states() -> void:
	if _grid == null:
		return
	for child in _grid.get_children():
		if not child is Control:
			continue
		var state_badge := (child as Control).get_node_or_null("StateBadge") as Label
		if state_badge == null:
			continue
		var relic_id := str((child as Control).get_meta("relic_id", ""))
		var text_value := ""
		if _badge_state_cb.is_valid():
			text_value = str(_badge_state_cb.call(relic_id))
		state_badge.text = text_value
		state_badge.visible = not text_value.is_empty()


func _set_badge_hover(root: Control, hovered: bool) -> void:
	var outline := root.get_node_or_null("HoverTextureOutline")
	var icon := root.get_node_or_null("RelicIcon")
	if outline != null:
		outline.visible = hovered
	if icon != null:
		icon.visible = not hovered


func _render_texture(source_texture: Texture2D, icon_size: float, with_outline: bool) -> Texture2D:
	var cache_key := "%s:%d:%d" % [source_texture.resource_path, int(icon_size), int(with_outline)]
	if _texture_cache.has(cache_key):
		return _texture_cache[cache_key]
	var source := source_texture.get_image()
	if source == null or source.is_empty():
		return source_texture
	source.convert(Image.FORMAT_RGBA8)
	var source_pad := maxi(3, int(roundf(float(source.get_width()) * _ICON_PAD / icon_size)))
	var outline_radius := maxi(2, int(ceilf(float(source.get_width()) * 1.5 / icon_size)))
	var rendered := Image.create(source.get_width() + source_pad * 2, source.get_height() + source_pad * 2, false, Image.FORMAT_RGBA8)
	rendered.fill(Color.TRANSPARENT)
	if with_outline:
		for y in range(source.get_height()):
			for x in range(source.get_width()):
				if source.get_pixel(x, y).a <= 0.01:
					continue
				for offset_y in range(-outline_radius, outline_radius + 1):
					for offset_x in range(-outline_radius, outline_radius + 1):
						rendered.set_pixel(x + source_pad + offset_x, y + source_pad + offset_y, Color.WHITE)
	rendered.blend_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), Vector2i(source_pad, source_pad))
	var texture := ImageTexture.create_from_image(rendered)
	_texture_cache[cache_key] = texture
	return texture
