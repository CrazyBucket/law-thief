extends PanelContainer

const BattleUiTheme = preload("res://scripts/ui/battle_ui_theme.gd")
const BattleEditorItemButtonScript = preload("res://scripts/ui/battle_editor_item_button.gd")

signal tool_selected(tool: Dictionary)
signal tool_drag_started(tool: Dictionary)
signal tool_cleared()
signal relic_requested(relic_id: String)
signal encounter_requested(encounter_id: String)
signal clear_enemies_requested()
signal close_requested()
signal panel_moved()

const _CATEGORY_ORDER := ["units", "tiles", "entities", "overlays", "gems", "relics"]
const _CATEGORY_LABELS := {
	"units": "怪物",
	"tiles": "地块",
	"entities": "实体",
	"overlays": "Overlay",
	"gems": "宝石",
	"relics": "遗物",
}

var _registry: Node = null
var _catalog: Dictionary = {}
var _selected_category: String = "units"
var _selected_tool: Dictionary = {}

var _close_btn: Button = null
var _status_label: Label = null
var _search_input: LineEdit = null
var _category_row: GridContainer = null
var _encounter_option: OptionButton = null
var _list_vbox: VBoxContainer = null
var _list_scroll: ScrollContainer = null
var _content_box: VBoxContainer = null
var _item_buttons: Dictionary = {}
var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(340, 0)
	add_theme_stylebox_override("panel", BattleUiTheme.panel_style(BattleUiTheme.BORDER_ACCENT))
	_build_ui()
	if not _catalog.is_empty():
		_refresh_category_buttons()
		_refresh_tool_list()


func setup(registry: Node) -> void:
	_registry = registry
	_rebuild_catalog()
	if _category_row == null:
		return
	_rebuild_encounter_options()
	_refresh_category_buttons()
	_refresh_tool_list()


func _rebuild_encounter_options() -> void:
	if _encounter_option == null or _registry == null:
		return
	_encounter_option.clear()
	var ids: Array[String] = _registry.get_encounter_ids(true)
	if not "procedural_normal" in ids:
		ids.push_front("procedural_normal")
	var current_id := ""
	var game_service: Node = Engine.get_main_loop().root.get_node_or_null("GameService")
	if game_service != null:
		current_id = str(game_service.get("pending_encounter_id"))
	for encounter_id in ids:
		_encounter_option.add_item(encounter_id)
		_encounter_option.set_item_tooltip(_encounter_option.item_count - 1, encounter_id)
		if encounter_id == current_id:
			_encounter_option.select(_encounter_option.item_count - 1)
	if _encounter_option.selected < 0 and _encounter_option.item_count > 0:
		_encounter_option.select(0)


func _on_encounter_selected(index: int) -> void:
	if _encounter_option == null or index < 0 or index >= _encounter_option.item_count:
		return
	_update_status_label("已选择场景，点击重载后应用")


func _on_reload_pressed() -> void:
	if _encounter_option == null or _encounter_option.selected < 0:
		return
	encounter_requested.emit(_encounter_option.get_item_text(_encounter_option.selected))


func set_selected_tool(tool: Dictionary) -> void:
	_selected_tool = tool.duplicate(true)
	_refresh_item_button_states()
	_update_status_label("")


func set_hover_summary(text: String) -> void:
	_update_status_label(text)


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(root)

	var header_panel := PanelContainer.new()
	header_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	header_panel.add_theme_stylebox_override("panel", BattleUiTheme.button_style("ghost", true))
	root.add_child(header_panel)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	header.gui_input.connect(_on_header_gui_input)
	header_panel.add_child(header)

	var drag_handle := Label.new()
	drag_handle.text = "::::"
	drag_handle.tooltip_text = "拖动面板"
	drag_handle.add_theme_font_size_override("font_size", 16)
	drag_handle.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	header.add_child(drag_handle)

	var title := Label.new()
	title.text = "测试编辑器"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", BattleUiTheme.TEXT)
	header.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	_close_btn = Button.new()
	_close_btn.custom_minimum_size = Vector2(34, 34)
	_close_btn.text = "×"
	_close_btn.pressed.connect(func() -> void: close_requested.emit())
	BattleUiTheme.apply_button(_close_btn, "ghost")
	header.add_child(_close_btn)

	_content_box = VBoxContainer.new()
	_content_box.add_theme_constant_override("separation", 8)
	_content_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_content_box)

	var encounter_row := HBoxContainer.new()
	encounter_row.add_theme_constant_override("separation", 6)
	_content_box.add_child(encounter_row)
	var encounter_label := Label.new()
	encounter_label.text = "起始场景"
	encounter_label.custom_minimum_size.x = 64
	encounter_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	encounter_label.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
	encounter_row.add_child(encounter_label)
	_encounter_option = OptionButton.new()
	_encounter_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_encounter_option.custom_minimum_size.y = 30
	_encounter_option.item_selected.connect(_on_encounter_selected)
	encounter_row.add_child(_encounter_option)
	var reload_btn := Button.new()
	reload_btn.text = "重载"
	reload_btn.custom_minimum_size = Vector2(62, 30)
	reload_btn.pressed.connect(_on_reload_pressed)
	BattleUiTheme.apply_button(reload_btn, "ghost")
	encounter_row.add_child(reload_btn)

	var editor_action_row := HBoxContainer.new()
	editor_action_row.add_theme_constant_override("separation", 6)
	_content_box.add_child(editor_action_row)
	var clear_enemies_btn := Button.new()
	clear_enemies_btn.text = "清空敌人"
	clear_enemies_btn.custom_minimum_size.y = 30
	clear_enemies_btn.pressed.connect(func() -> void: clear_enemies_requested.emit())
	BattleUiTheme.apply_button(clear_enemies_btn, "ghost")
	editor_action_row.add_child(clear_enemies_btn)
	var editor_hint := Label.new()
	editor_hint.text = "宝石拖到格子后自动填入第一个可用槽位"
	editor_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	editor_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	editor_hint.add_theme_font_size_override("font_size", 10)
	editor_hint.add_theme_color_override("font_color", BattleUiTheme.TEXT_HINT)
	editor_action_row.add_child(editor_hint)

	_search_input = LineEdit.new()
	_search_input.placeholder_text = "搜索资源 id"
	_search_input.text_changed.connect(_on_search_changed)
	_content_box.add_child(_search_input)

	_category_row = GridContainer.new()
	_category_row.columns = 3
	_category_row.add_theme_constant_override("separation", 6)
	_category_row.add_theme_constant_override("h_separation", 6)
	_category_row.add_theme_constant_override("v_separation", 6)
	_content_box.add_child(_category_row)

	_list_scroll = ScrollContainer.new()
	_list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_scroll.custom_minimum_size.y = 180
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_scroll.resized.connect(_sync_list_width)
	_content_box.add_child(_list_scroll)

	_list_vbox = VBoxContainer.new()
	_list_vbox.add_theme_constant_override("separation", 6)
	_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_scroll.add_child(_list_vbox)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 11)
	_status_label.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
	_status_label.size_flags_vertical = Control.SIZE_SHRINK_END
	root.add_child(_status_label)


func _rebuild_catalog() -> void:
	if _registry == null:
		return
	_catalog.clear()
	_catalog["units"] = _registry.get_unit_def_ids().map(func(unit_id: String) -> Dictionary:
		return {
			"id": unit_id,
			"label": _registry.get_unit_display_name(unit_id),
			"kind": "unit",
		}
	)
	_catalog["tiles"] = _registry.get_tile_ids().map(func(tile_id: String) -> Dictionary:
		return {
			"id": tile_id,
			"label": _registry.get_tile_display_name(tile_id),
			"kind": "tile",
		}
	)
	_catalog["entities"] = _registry.get_entity_ids().map(func(entity_id: String) -> Dictionary:
		return {
			"id": entity_id,
			"label": _registry.get_entity_display_name(entity_id),
			"kind": "entity",
		}
	)
	var overlay_entries: Array = []
	for raw_surface_entry in _registry.get_surface_overlay_catalog():
		var surface_entry: Dictionary = raw_surface_entry
		overlay_entries.append({
			"id": str(surface_entry.get("id", "")),
			"label": str(surface_entry.get("label", surface_entry.get("id", ""))),
			"kind": "surface_overlay",
			"tile_id": str(surface_entry.get("tile_id", "")),
			"surface_variant": str(surface_entry.get("surface_variant", "")),
		})
	for overlay_id in _registry.get_overlay_ids():
		overlay_entries.append({
			"id": overlay_id,
			"label": _registry.get_overlay_display_name(overlay_id),
			"kind": "overlay",
		})
	_catalog["overlays"] = overlay_entries
	_catalog["gems"] = _registry.get_gem_ids().map(func(gem_id: String) -> Dictionary:
		return {
			"id": gem_id,
			"label": _registry.get_gem_display_name(gem_id),
			"kind": "gem",
		}
	)
	_catalog["relics"] = _registry.get_relic_ids().map(func(relic_id: String) -> Dictionary:
		var def: Dictionary = _registry.get_relic_def(relic_id)
		return {
			"id": relic_id,
			"label": str(def.get("name", relic_id)),
			"kind": "relic",
		}
	)


func _refresh_category_buttons() -> void:
	for child in _category_row.get_children():
		child.queue_free()
	for category in _CATEGORY_ORDER:
		var btn := Button.new()
		btn.toggle_mode = true
		btn.button_pressed = category == _selected_category
		btn.text = str(_CATEGORY_LABELS.get(category, category))
		btn.custom_minimum_size = Vector2(0, 30)
		btn.pressed.connect(_on_category_pressed.bind(category))
		BattleUiTheme.apply_button(btn, "ghost", category == _selected_category)
		_category_row.add_child(btn)


func _refresh_tool_list() -> void:
	for child in _list_vbox.get_children():
		child.queue_free()
	_item_buttons.clear()
	var needle := _search_input.text.strip_edges().to_lower()
	var entries: Array = _catalog.get(_selected_category, [])
	for entry_variant in entries:
		var entry: Dictionary = entry_variant
		var search_text := "%s %s" % [str(entry.get("id", "")), str(entry.get("label", ""))]
		if not needle.is_empty() and needle not in search_text.to_lower():
			continue
		var btn := BattleEditorItemButtonScript.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.text = "::::  %s  [%s]" % [str(entry.get("label", "")), str(entry.get("id", ""))]
		btn.tooltip_text = "拖拽到棋盘放置"
		btn.custom_minimum_size = Vector2(0, 44)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.clip_text = true
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.set_tool(entry)
		btn.pressed.connect(_on_tool_pressed.bind(entry.duplicate(true)))
		btn.drag_started.connect(_on_tool_drag_started)
		_list_vbox.add_child(btn)
		_item_buttons[str(entry.get("id", ""))] = btn
	_sync_list_width()
	_refresh_item_button_states()


func _refresh_item_button_states() -> void:
	for entry_id in _item_buttons.keys():
		var btn: Button = _item_buttons[entry_id]
		var active := str(_selected_tool.get("id", "")) == str(entry_id)
		if btn.has_method("set_drag_enabled"):
			btn.set_drag_enabled(true)
		BattleUiTheme.apply_button(btn, "ghost", active)


func _update_status_label(extra: String) -> void:
	var lines: Array[String] = []
	if not _selected_tool.is_empty():
		var kind := str(_selected_tool.get("kind", ""))
		var hint := "拖到棋盘放置"
		if kind == "relic":
			hint = "点击条目添加"
		lines.append("当前: %s（%s）" % [str(_selected_tool.get("id", "")), hint])
	if not extra.is_empty():
		lines.append(extra)
	_status_label.text = "\n".join(lines)


func _sync_list_width() -> void:
	if _list_scroll == null or _list_vbox == null:
		return
	_list_vbox.custom_minimum_size.x = maxf(_list_scroll.size.x - 12.0, 0.0)


func _on_category_pressed(category: String) -> void:
	_selected_category = category
	_refresh_category_buttons()
	_refresh_tool_list()


func _on_search_changed(_text: String) -> void:
	_refresh_tool_list()


func _on_tool_pressed(entry: Dictionary) -> void:
	_selected_tool = entry.duplicate(true)
	_refresh_item_button_states()
	_update_status_label("")
	tool_selected.emit(_selected_tool.duplicate(true))
	if str(_selected_tool.get("kind", "")) == "relic":
		relic_requested.emit(str(_selected_tool.get("id", "")))


func _on_tool_drag_started(entry: Dictionary) -> void:
	_selected_tool = entry
	_refresh_item_button_states()
	_update_status_label("正在拖拽")
	tool_drag_started.emit(_selected_tool.duplicate(true))


func _on_header_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_offset = get_global_mouse_position() - global_position
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		var viewport_rect := get_viewport_rect()
		var next_pos := get_global_mouse_position() - _drag_offset
		next_pos.x = clampf(next_pos.x, 0.0, maxf(viewport_rect.size.x - size.x, 0.0))
		next_pos.y = clampf(next_pos.y, 0.0, maxf(viewport_rect.size.y - size.y, 0.0))
		position = next_pos
		panel_moved.emit()
