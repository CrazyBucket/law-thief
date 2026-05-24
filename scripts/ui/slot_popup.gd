extends Control
## 棋盘上方弹出式槽位选择器
## hover 到可操作单位时自动显示在头顶，点击槽位直接执行

const UnitVisuals = preload("res://scripts/ui/unit_visuals.gd")

signal slot_selected(unit_uid: String, slot_index: int)
signal tile_slot_selected(tile_pos: Vector2i, slot_index: int)
signal cancelled

var _target_uid: String = ""
var _target_tile_pos: Vector2i = Vector2i(-1, -1)
var _is_tile_mode: bool = false
var _buttons: Array[Button] = []
var _current_action: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func show_for_unit(unit: UnitState, state: GameState, action: String, screen_pos: Vector2, check_fn: Callable) -> void:
	# 如果已经在显示同一个单位的同一个操作，不重复创建
	if visible and not _is_tile_mode and _target_uid == unit.uid and _current_action == action:
		return
	_is_tile_mode = false

	_clear_buttons()
	_target_uid = unit.uid
	_current_action = action
	visible = true

	var valid_count: int = 0
	for i in range(unit.slots.size()):
		var slot: SlotState = unit.slots[i]
		var check: Dictionary = check_fn.call(unit.uid, i)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(64, 32)
		btn.add_theme_font_size_override("font_size", 12)

		var slot_label: String = _slot_label(slot.slot_type)
		var gem_text: String = ""
		if not slot.gem_uid.is_empty():
			var gem: GemState = state.gems.get(slot.gem_uid, null)
			if gem != null:
				gem_text = _gem_name(gem.gem_id)

		match action:
			"extract":
				btn.text = "%s◆%s" % [slot_label, gem_text] if not gem_text.is_empty() else "%s空" % slot_label
			"insert":
				btn.text = "%s嵌入" % slot_label if slot.gem_uid.is_empty() else "%s◆%s" % [slot_label, gem_text]
			"trigger":
				btn.text = "%s◆%s" % [slot_label, gem_text] if not gem_text.is_empty() else "%s空" % slot_label

		if slot.locked:
			btn.text = "%s🔒" % slot_label

		var is_valid: bool = check.get("ok", false)
		btn.disabled = not is_valid

		# 样式
		var style := StyleBoxFlat.new()
		var slot_col: Color = UnitVisuals.slot_color(slot.slot_type)
		if is_valid:
			style.bg_color = slot_col.darkened(0.4)
			style.bg_color.a = 0.92
			style.border_color = slot_col.lightened(0.2)
			valid_count += 1
		else:
			style.bg_color = Color(0.2, 0.2, 0.25, 0.7)
			style.border_color = Color(0.4, 0.4, 0.45, 0.5)
		style.set_border_width_all(2)
		style.set_corner_radius_all(6)
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		btn.add_theme_stylebox_override("pressed", style)
		btn.add_theme_stylebox_override("disabled", style)

		if is_valid:
			btn.add_theme_color_override("font_color", Color.WHITE)
		else:
			btn.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))

		var idx: int = i
		btn.pressed.connect(func(): slot_selected.emit(_target_uid, idx))
		add_child(btn)
		_buttons.append(btn)

	# 布局：水平排列在目标单位上方
	var total_width: float = 0.0
	for btn in _buttons:
		total_width += btn.custom_minimum_size.x + 4.0
	total_width -= 4.0

	var start_x: float = screen_pos.x - total_width * 0.5
	var y_pos: float = screen_pos.y - 44.0  # 在单位头顶上方

	var x_offset: float = 0.0
	for btn in _buttons:
		btn.position = Vector2(start_x + x_offset, y_pos)
		btn.size = btn.custom_minimum_size
		x_offset += btn.custom_minimum_size.x + 4.0

	# 确保不超出屏幕
	_clamp_to_screen()

	if valid_count == 0:
		hide_popup()


func show_for_tile(tile: TileState, state: GameState, action: String, screen_pos: Vector2, check_fn: Callable) -> void:
	if visible and _is_tile_mode and _target_tile_pos == tile.pos and _current_action == action:
		return

	_clear_buttons()
	_target_uid = ""
	_target_tile_pos = tile.pos
	_is_tile_mode = true
	_current_action = action
	visible = true

	var valid_count: int = 0
	for i in range(tile.slots.size()):
		var slot: SlotState = tile.slots[i]
		var check: Dictionary = check_fn.call(tile.pos, i)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(64, 32)
		btn.add_theme_font_size_override("font_size", 12)

		var slot_label: String = _slot_label(slot.slot_type)
		var gem_text: String = ""
		if not slot.gem_uid.is_empty():
			var gem: GemState = state.gems.get(slot.gem_uid, null)
			if gem != null:
				gem_text = _gem_name(gem.gem_id)

		match action:
			"extract":
				btn.text = "%s◆%s" % [slot_label, gem_text] if not gem_text.is_empty() else "%s空" % slot_label
			"insert":
				btn.text = "%s嵌入" % slot_label if slot.gem_uid.is_empty() else "%s◆%s" % [slot_label, gem_text]
			"trigger":
				btn.text = "%s◆%s" % [slot_label, gem_text] if not gem_text.is_empty() else "%s空" % slot_label

		if slot.locked:
			btn.text = "%s🔒" % slot_label

		var is_valid: bool = check.get("ok", false)
		btn.disabled = not is_valid

		var style := StyleBoxFlat.new()
		var slot_col: Color = UnitVisuals.slot_color(slot.slot_type)
		if is_valid:
			style.bg_color = slot_col.darkened(0.4)
			style.bg_color.a = 0.92
			style.border_color = slot_col.lightened(0.2)
			valid_count += 1
		else:
			style.bg_color = Color(0.2, 0.2, 0.25, 0.7)
			style.border_color = Color(0.4, 0.4, 0.45, 0.5)
		style.set_border_width_all(2)
		style.set_corner_radius_all(6)
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		btn.add_theme_stylebox_override("pressed", style)
		btn.add_theme_stylebox_override("disabled", style)

		if is_valid:
			btn.add_theme_color_override("font_color", Color.WHITE)
		else:
			btn.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))

		var idx: int = i
		var tile_pos: Vector2i = tile.pos
		btn.pressed.connect(func(): tile_slot_selected.emit(tile_pos, idx))
		add_child(btn)
		_buttons.append(btn)

	var total_width: float = 0.0
	for btn in _buttons:
		total_width += btn.custom_minimum_size.x + 4.0
	total_width -= 4.0

	var start_x: float = screen_pos.x - total_width * 0.5
	var y_pos: float = screen_pos.y - 44.0

	var x_offset: float = 0.0
	for btn in _buttons:
		btn.position = Vector2(start_x + x_offset, y_pos)
		btn.size = btn.custom_minimum_size
		x_offset += btn.custom_minimum_size.x + 4.0

	_clamp_to_screen()

	if valid_count == 0:
		hide_popup()


func hide_popup() -> void:
	visible = false
	_clear_buttons()
	_target_uid = ""
	_target_tile_pos = Vector2i(-1, -1)
	_is_tile_mode = false
	_current_action = ""
	cancelled.emit()


func is_showing() -> bool:
	return visible


func is_mouse_inside() -> bool:
	## 检测鼠标是否在任何一个按钮的区域内（含一定容差）
	if not visible or _buttons.is_empty():
		return false
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var margin: float = 12.0  # 容差区域，防止鼠标在按钮间隙时消失
	for btn in _buttons:
		var rect := Rect2(btn.global_position - Vector2(margin, margin), btn.size + Vector2(margin * 2, margin * 2))
		if rect.has_point(mouse_pos):
			return true
	return false


func get_target_uid() -> String:
	return _target_uid


func _clear_buttons() -> void:
	for btn in _buttons:
		btn.queue_free()
	_buttons.clear()


func _clamp_to_screen() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	for btn in _buttons:
		if btn.position.x < 4:
			var shift: float = 4 - btn.position.x
			for b in _buttons:
				b.position.x += shift
			break
		if btn.position.x + btn.size.x > viewport_size.x - 4:
			var shift: float = (btn.position.x + btn.size.x) - (viewport_size.x - 4)
			for b in _buttons:
				b.position.x -= shift
			break
	for btn in _buttons:
		if btn.position.y < 4:
			btn.position.y = 4


func _slot_label(slot_type: String) -> String:
	match slot_type:
		"red": return "红"
		"blue": return "蓝"
		"black": return "黑"
	return "?"


func _gem_name(gem_id: String) -> String:
	match gem_id:
		"gem_explosion": return "爆炸"
		"gem_poison": return "剧毒"
		"gem_gravity": return "引力"
		"gem_heavy_armor": return "重甲"
		"gem_conductive": return "导电"
		"gem_fragile": return "易碎"
	return "?"


func _gui_input(event: InputEvent) -> void:
	# 点击弹窗外部区域关闭
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			hide_popup()
