extends Control

const BattleUiTheme = preload("res://scripts/ui/battle_ui_theme.gd")

signal slot_selected(unit_uid: String, slot_index: int)
signal dropped_gem_selected(gem_uid: String)
signal editor_unit_slot_selected(unit_uid: String, slot_index: int)
signal editor_tile_slot_selected(tile_pos: Vector2i, slot_index: int)
signal editor_unit_slot_added(unit_uid: String, slot_type: String)
signal editor_tile_slot_added(tile_pos: Vector2i, slot_type: String)
signal cancelled

var _target_uid: String = ""
var _target_tile_pos: Vector2i = Vector2i(-1, -1)
var _is_tile_mode: bool = false
var _is_dropped_mode: bool = false
var _panel: PanelContainer = null
var _content: VBoxContainer = null
var _title_label: Label = null
var _current_action: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", BattleUiTheme.tooltip_style())
	add_child(_panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(vbox)
	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 12)
	_title_label.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	vbox.add_child(_title_label)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 7)
	vbox.add_child(_content)


func show_for_unit(unit: UnitState, state: GameState, action: String, screen_pos: Vector2, check_fn: Callable) -> void:
	if visible and not _is_tile_mode and _target_uid == unit.uid and _current_action == action:
		return
	_is_tile_mode = false
	_is_dropped_mode = false
	_target_uid = unit.uid
	_current_action = action
	_title_label.text = _action_title(action)
	_clear_content()
	_add_unit_row(unit, state, action, func(i: int): return check_fn.call(unit.uid, i), func(i: int): slot_selected.emit(_target_uid, i))
	_layout_panel(screen_pos)


func show_for_dropped_gems(gem_uids: Array[String], state: GameState, screen_pos: Vector2, check_fn: Callable) -> void:
	_is_tile_mode = false
	_is_dropped_mode = true
	_target_uid = ""
	_current_action = Constants.ACTION_EXTRACT
	_title_label.text = "选择地面宝石"
	_clear_content()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	for gem_uid in gem_uids:
		var gem: GemState = state.gems.get(gem_uid, null)
		if gem == null:
			continue
		var check: Dictionary = check_fn.call(gem_uid)
		var button := Button.new()
		button.custom_minimum_size = Vector2(104, 36)
		button.text = _data_registry().get_gem_display_name(gem)
		button.disabled = not check.get("ok", false)
		BattleUiTheme.apply_button(button, "gem", false)
		var selected_uid := gem_uid
		button.pressed.connect(func() -> void: dropped_gem_selected.emit(selected_uid))
		row.add_child(button)
	_content.add_child(row)
	visible = row.get_child_count() > 0
	_layout_panel(screen_pos)


func show_for_editor_unit(unit: UnitState, state: GameState, gem_id: String, screen_pos: Vector2) -> void:
	_is_tile_mode = false
	_is_dropped_mode = false
	_target_uid = unit.uid
	_current_action = "editor_gem"
	_title_label.text = "选择宝石嵌入槽位"
	_clear_content()
	_add_editor_slot_picker(
		_data_registry().get_unit_display_name(unit.unit_def_id),
		unit.slots,
		state,
		gem_id,
		func(index: int) -> void: editor_unit_slot_selected.emit(unit.uid, index),
		func(slot_type: String) -> void: editor_unit_slot_added.emit(unit.uid, slot_type)
	)
	_layout_panel(screen_pos)


func show_for_editor_tile(tile: TileState, state: GameState, gem_id: String, screen_pos: Vector2) -> void:
	_is_tile_mode = true
	_target_uid = ""
	_target_tile_pos = tile.pos
	_current_action = "editor_gem"
	_title_label.text = "选择宝石嵌入槽位"
	_clear_content()
	_add_editor_slot_picker(
		"地块 %s" % str(tile.pos),
		tile.slots,
		state,
		gem_id,
		func(index: int) -> void: editor_tile_slot_selected.emit(tile.pos, index),
		func(slot_type: String) -> void: editor_tile_slot_added.emit(tile.pos, slot_type)
	)
	_layout_panel(screen_pos)


func _clear_content() -> void:
	for child in _content.get_children():
		child.queue_free()


func _add_unit_row(unit: UnitState, state: GameState, action: String, check_fn: Callable, emit_fn: Callable) -> bool:
	var title: String = _data_registry().get_unit_display_name(unit.unit_def_id)
	return _add_slot_row(title, unit.slots, check_fn, state, action, emit_fn)


func _add_slot_row(title: String, slots: Array, check_fn: Callable, state: GameState, action: String, emit_fn: Callable) -> bool:
	var row_box := VBoxContainer.new()
	row_box.add_theme_constant_override("separation", 3)
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
	row_box.add_child(label)
	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 5)
	row_box.add_child(button_row)
	var shown := 0
	for i in range(slots.size()):
		var slot: SlotState = slots[i]
		if not _should_show_slot(slot, action):
			continue
		var check: Dictionary = check_fn.call(i)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(74, 36)
		btn.add_theme_font_size_override("font_size", 12)
		var slot_label: String = _slot_label_for(slot)
		var gem_text: String = ""
		if not slot.gem_uid.is_empty():
			var gem: GemState = state.gems.get(slot.gem_uid, null)
			if gem != null:
				gem_text = _data_registry().get_gem_display_name(gem)
		if slot.is_split_disabled():
			btn.text = "%s %s·失效" % [slot_label, gem_text] if not gem_text.is_empty() else "%s·失效" % slot_label
		elif slot.locked:
			btn.text = "%s 锁" % slot_label
		else:
			match action:
				"extract":
					btn.text = "%s %s" % [slot_label, gem_text] if not gem_text.is_empty() else "%s 空" % slot_label
				"insert":
					btn.text = "%s 嵌入" % slot_label if slot.gem_uid.is_empty() else "%s %s" % [slot_label, gem_text]
		var is_valid: bool = check.get("ok", false)
		btn.disabled = not is_valid
		BattleUiTheme.apply_button(btn, "gem", false)
		btn.add_theme_color_override("font_color", _slot_color(slot.slot_type).lightened(0.25))
		var idx := i
		btn.pressed.connect(func(): emit_fn.call(idx))
		button_row.add_child(btn)
		shown += 1
	if shown == 0:
		row_box.queue_free()
		return false
	_content.add_child(row_box)
	visible = true
	return true


func _add_editor_slot_picker(
	title: String,
	slots: Array,
	state: GameState,
	gem_id: String,
	select_fn: Callable,
	add_fn: Callable
) -> void:
	var title_label := Label.new()
	title_label.text = "%s · %s" % [title, _data_registry().get_gem_display_name(gem_id)]
	title_label.add_theme_font_size_override("font_size", 10)
	title_label.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
	_content.add_child(title_label)

	var slots_grid := GridContainer.new()
	slots_grid.columns = 3
	slots_grid.add_theme_constant_override("h_separation", 5)
	slots_grid.add_theme_constant_override("v_separation", 5)
	_content.add_child(slots_grid)
	for i in range(slots.size()):
		var slot: SlotState = slots[i]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(92, 40)
		btn.add_theme_font_size_override("font_size", 11)
		var gem_text := "空"
		if not slot.gem_uid.is_empty():
			var gem: GemState = state.gems.get(slot.gem_uid, null)
			if gem != null:
				gem_text = _data_registry().get_gem_display_name(gem)
		btn.text = "%d. %s %s" % [i + 1, _slot_label_for(slot), gem_text]
		btn.disabled = slot.locked or slot.is_split_disabled()
		BattleUiTheme.apply_button(btn, "gem", false)
		btn.add_theme_color_override("font_color", _slot_color(slot.slot_type).lightened(0.25))
		var slot_index := i
		btn.pressed.connect(func() -> void: select_fn.call(slot_index))
		slots_grid.add_child(btn)

	var add_label := Label.new()
	add_label.text = "新增槽位并嵌入"
	add_label.add_theme_font_size_override("font_size", 10)
	add_label.add_theme_color_override("font_color", BattleUiTheme.TEXT_HINT)
	_content.add_child(add_label)
	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 5)
	_content.add_child(add_row)
	for slot_type in [Constants.SLOT_RED, Constants.SLOT_BLUE, Constants.SLOT_BLACK]:
		var add_btn := Button.new()
		add_btn.custom_minimum_size = Vector2(88, 36)
		add_btn.text = "+%s槽" % _slot_label(slot_type)
		BattleUiTheme.apply_button(add_btn, "ghost")
		add_btn.add_theme_color_override("font_color", _slot_color(slot_type).lightened(0.25))
		var bound_slot_type: String = slot_type
		add_btn.pressed.connect(func() -> void: add_fn.call(bound_slot_type))
		add_row.add_child(add_btn)
	visible = true


func _should_show_slot(slot: SlotState, action: String) -> bool:
	match action:
		Constants.ACTION_INSERT:
			return true
		Constants.ACTION_EXTRACT:
			return not slot.gem_uid.is_empty()
	return true


func _layout_panel(screen_pos: Vector2) -> void:
	await get_tree().process_frame
	var panel_size := _panel.get_combined_minimum_size() + Vector2(20, 16)
	_panel.custom_minimum_size = panel_size
	_panel.size = panel_size
	position = screen_pos - Vector2(panel_size.x * 0.5, panel_size.y + 12.0)
	_clamp_to_screen()


func hide_popup() -> void:
	visible = false
	_clear_content()
	_target_uid = ""
	_target_tile_pos = Vector2i(-1, -1)
	_is_tile_mode = false
	_current_action = ""
	cancelled.emit()


func is_showing() -> bool:
	return visible


func _clamp_to_screen() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	position.x = clampf(position.x, 8.0, viewport_size.x - _panel.size.x - 8.0)
	position.y = clampf(position.y, 56.0, viewport_size.y - _panel.size.y - 80.0)


func _action_title(action: String) -> String:
	match action:
		"extract": return "选择要拔出的槽位"
		"insert": return "选择要嵌入的槽位"
	return "选择槽位"


func _slot_label(slot_type: String) -> String:
	match slot_type:
		"red": return "红"
		"blue": return "蓝"
		"black": return "黑"
	return "?"


func _slot_label_for(slot: SlotState) -> String:
	var base := _slot_label(slot.slot_type)
	if not slot.dual_type.is_empty():
		return "%s/%s" % [base, _slot_label(slot.dual_type)]
	return base


func _slot_color(slot_type: String) -> Color:
	return UiPalette.slot_color(slot_type)


func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node("DataRegistry")


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		hide_popup()
