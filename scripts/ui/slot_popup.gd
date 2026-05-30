extends Control

const BattleUiTheme = preload("res://scripts/ui/battle_ui_theme.gd")

signal slot_selected(unit_uid: String, slot_index: int)
signal tile_slot_selected(tile_pos: Vector2i, slot_index: int)
signal cancelled

var _target_uid: String = ""
var _target_tile_pos: Vector2i = Vector2i(-1, -1)
var _is_tile_mode: bool = false
var _panel: PanelContainer = null
var _button_row: HBoxContainer = null
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
	_button_row = HBoxContainer.new()
	_button_row.add_theme_constant_override("separation", 6)
	vbox.add_child(_button_row)


func show_for_unit(unit: UnitState, state: GameState, action: String, screen_pos: Vector2, check_fn: Callable) -> void:
	if visible and not _is_tile_mode and _target_uid == unit.uid and _current_action == action:
		return
	_is_tile_mode = false
	_target_uid = unit.uid
	_current_action = action
	_title_label.text = _action_title(action)
	_build_buttons(unit.slots, func(i: int): return check_fn.call(unit.uid, i), state, action, func(i: int): slot_selected.emit(_target_uid, i))
	_layout_panel(screen_pos)


func show_for_tile(tile: TileState, state: GameState, action: String, screen_pos: Vector2, check_fn: Callable) -> void:
	if visible and _is_tile_mode and _target_tile_pos == tile.pos and _current_action == action:
		return
	_is_tile_mode = true
	_target_uid = ""
	_target_tile_pos = tile.pos
	_current_action = action
	_title_label.text = "%s · 地块" % _action_title(action)
	_build_buttons(tile.slots, func(i: int): return check_fn.call(tile.pos, i), state, action, func(i: int): tile_slot_selected.emit(tile.pos, i))
	_layout_panel(screen_pos)


func _build_buttons(slots: Array, check_fn: Callable, state: GameState, action: String, emit_fn: Callable) -> void:
	for child in _button_row.get_children():
		child.queue_free()
	var valid_count := 0
	for i in range(slots.size()):
		var slot: SlotState = slots[i]
		var check: Dictionary = check_fn.call(i)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(76, 40)
		btn.add_theme_font_size_override("font_size", 12)
		var slot_label: String = _slot_label_for(slot)
		var gem_text := ""
		if not slot.gem_uid.is_empty():
			var gem: GemState = state.gems.get(slot.gem_uid, null)
			if gem != null:
				gem_text = _data_registry().get_gem_display_name(gem)
		match action:
			"extract":
				btn.text = "%s %s" % [slot_label, gem_text] if not gem_text.is_empty() else "%s 空" % slot_label
			"insert":
				btn.text = "%s 嵌入" % slot_label if slot.gem_uid.is_empty() else "%s %s" % [slot_label, gem_text]
			"trigger":
				btn.text = "%s %s" % [slot_label, gem_text] if not gem_text.is_empty() else "%s 空" % slot_label
		if slot.locked:
			btn.text = "%s 锁" % slot_label
		var is_valid: bool = check.get("ok", false)
		btn.disabled = not is_valid
		var kind := "gem" if is_valid else "ghost"
		BattleUiTheme.apply_button(btn, kind, is_valid)
		if is_valid:
			valid_count += 1
		var idx := i
		btn.pressed.connect(func(): emit_fn.call(idx))
		_button_row.add_child(btn)
	if valid_count == 0:
		hide_popup()
	else:
		visible = true


func _layout_panel(screen_pos: Vector2) -> void:
	await get_tree().process_frame
	var panel_size := _panel.get_combined_minimum_size() + Vector2(20, 16)
	_panel.custom_minimum_size = panel_size
	_panel.size = panel_size
	position = screen_pos - Vector2(panel_size.x * 0.5, panel_size.y + 12.0)
	_clamp_to_screen()


func hide_popup() -> void:
	visible = false
	for child in _button_row.get_children():
		child.queue_free()
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
		"trigger": return "选择要触发的槽位"
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


func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node("DataRegistry")


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		hide_popup()
