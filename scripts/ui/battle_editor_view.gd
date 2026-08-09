extends RefCounted

const BattleUiTheme = preload("res://scripts/ui/battle_ui_theme.gd")


func build(host: Control, editor_panel_script: Script, registry) -> Dictionary:
	var hud_layer := host.get_node("HudLayer")
	var editor_panel = editor_panel_script.new()
	editor_panel.position = Vector2(8, 220)
	editor_panel.size = Vector2(360, 520)
	editor_panel.tool_selected.connect(Callable(host, "_on_editor_tool_selected"))
	editor_panel.tool_drag_started.connect(Callable(host, "_on_editor_tool_drag_started"))
	editor_panel.relic_requested.connect(Callable(host, "_on_editor_relic_requested"))
	editor_panel.encounter_requested.connect(Callable(host, "_on_editor_encounter_requested"))
	editor_panel.clear_enemies_requested.connect(Callable(host, "_on_editor_clear_enemies_requested"))
	editor_panel.close_requested.connect(Callable(host, "_on_editor_panel_close_requested"))
	editor_panel.panel_moved.connect(Callable(host, "_on_editor_panel_moved"))
	hud_layer.add_child(editor_panel)
	editor_panel.setup(registry)

	var panel_toggle_btn := Button.new()
	panel_toggle_btn.position = Vector2(8, 220)
	panel_toggle_btn.size = Vector2(116, 32)
	panel_toggle_btn.text = "展开编辑器"
	panel_toggle_btn.visible = false
	panel_toggle_btn.pressed.connect(Callable(host, "_on_editor_panel_toggle_pressed"))
	BattleUiTheme.apply_button(panel_toggle_btn, "ghost")
	hud_layer.add_child(panel_toggle_btn)

	var inspector := PanelContainer.new()
	inspector.clip_contents = true
	inspector.mouse_filter = Control.MOUSE_FILTER_STOP
	inspector.add_theme_stylebox_override("panel", BattleUiTheme.panel_style(BattleUiTheme.PHASE_PLAYER))
	hud_layer.add_child(inspector)
	var inspector_root := VBoxContainer.new()
	inspector_root.add_theme_constant_override("separation", 6)
	inspector_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspector.add_child(inspector_root)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	inspector_root.add_child(header)
	var title := Label.new()
	title.text = "编辑状态"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", BattleUiTheme.TEXT)
	header.add_child(title)
	var header_spacer := Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(header_spacer)
	var close_btn := Button.new()
	close_btn.custom_minimum_size = Vector2(34, 34)
	close_btn.text = "×"
	close_btn.pressed.connect(Callable(host, "_on_editor_inspector_close_pressed"))
	BattleUiTheme.apply_button(close_btn, "ghost")
	header.add_child(close_btn)

	var inspector_scroll := ScrollContainer.new()
	inspector_scroll.name = "InspectorScroll"
	inspector_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspector_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inspector_root.add_child(inspector_scroll)
	var inspector_body := VBoxContainer.new()
	inspector_body.add_theme_constant_override("separation", 6)
	inspector_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_scroll.add_child(inspector_body)

	var tool_label := Label.new()
	tool_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tool_label.add_theme_color_override("font_color", BattleUiTheme.TEXT)
	inspector_body.add_child(tool_label)
	var target_label := Label.new()
	target_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	target_label.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	inspector_body.add_child(target_label)
	var hover_label := Label.new()
	hover_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hover_label.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
	inspector_body.add_child(hover_label)

	var contents_box := VBoxContainer.new()
	contents_box.add_theme_constant_override("separation", 4)
	inspector_body.add_child(contents_box)
	var gem_title := Label.new()
	gem_title.text = "宝石"
	gem_title.add_theme_font_size_override("font_size", 12)
	gem_title.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
	contents_box.add_child(gem_title)
	var gem_list := VBoxContainer.new()
	gem_list.add_theme_constant_override("separation", 4)
	contents_box.add_child(gem_list)
	var relic_title := Label.new()
	relic_title.text = "遗物"
	relic_title.add_theme_font_size_override("font_size", 12)
	relic_title.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
	contents_box.add_child(relic_title)
	var relic_list := VBoxContainer.new()
	relic_list.add_theme_constant_override("separation", 4)
	contents_box.add_child(relic_list)

	var status_box := VBoxContainer.new()
	status_box.add_theme_constant_override("separation", 4)
	inspector_body.add_child(status_box)
	var status_title := Label.new()
	status_title.text = "状态"
	status_title.add_theme_font_size_override("font_size", 12)
	status_title.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
	status_box.add_child(status_title)
	var status_grid := GridContainer.new()
	status_grid.columns = 5
	status_grid.add_theme_constant_override("h_separation", 4)
	status_grid.add_theme_constant_override("v_separation", 4)
	status_box.add_child(status_grid)

	var result_label := Label.new()
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_label.add_theme_color_override("font_color", BattleUiTheme.TEXT_HINT)
	inspector_body.add_child(result_label)
	var actions := GridContainer.new()
	actions.columns = 2
	actions.add_theme_constant_override("h_separation", 6)
	actions.add_theme_constant_override("v_separation", 6)
	inspector_body.add_child(actions)
	var remove_unit_btn := _action_button("删单位", Callable(host, "_on_editor_remove_unit_pressed"))
	actions.add_child(remove_unit_btn)
	var remove_entity_btn := _action_button("删实体", Callable(host, "_on_editor_remove_entity_pressed"))
	actions.add_child(remove_entity_btn)
	var remove_overlay_btn := _action_button("删Overlay", Callable(host, "_on_editor_remove_overlay_pressed"))
	actions.add_child(remove_overlay_btn)

	var unlimited_btn := _toggle_button("无限行动 关", Callable(host, "_on_editor_unlimited_actions_pressed"))
	inspector_body.add_child(unlimited_btn)
	var player_invincible_btn := _toggle_button("玩家无敌 关", Callable(host, "_on_editor_player_invincible_pressed"))
	inspector_body.add_child(player_invincible_btn)
	var inspector_toggle_btn := Button.new()
	inspector_toggle_btn.position = Vector2(host.size.x - 124, 108)
	inspector_toggle_btn.size = Vector2(116, 32)
	inspector_toggle_btn.text = "展开检查器"
	inspector_toggle_btn.visible = false
	inspector_toggle_btn.pressed.connect(Callable(host, "_on_editor_inspector_toggle_pressed"))
	BattleUiTheme.apply_button(inspector_toggle_btn, "ghost")
	hud_layer.add_child(inspector_toggle_btn)

	return {
		"panel": editor_panel,
		"panel_toggle_btn": panel_toggle_btn,
		"inspector": inspector,
		"inspector_body": inspector_body,
		"tool_label": tool_label,
		"target_label": target_label,
		"hover_label": hover_label,
		"contents_box": contents_box,
		"gem_list": gem_list,
		"relic_list": relic_list,
		"status_box": status_box,
		"status_grid": status_grid,
		"result_label": result_label,
		"remove_unit_btn": remove_unit_btn,
		"remove_entity_btn": remove_entity_btn,
		"remove_overlay_btn": remove_overlay_btn,
		"unlimited_btn": unlimited_btn,
		"player_invincible_btn": player_invincible_btn,
		"inspector_toggle_btn": inspector_toggle_btn,
	}


func preview_for_cell(state: GameState, tool: Dictionary, cell: Vector2i, registry) -> Dictionary:
	if state == null or tool.is_empty():
		return {"valid": false, "cells": [], "message": "未选择资源"}
	var kind := str(tool.get("kind", ""))
	var resource_id := str(tool.get("id", ""))
	match kind:
		"relic":
			return {"valid": false, "cells": [], "message": "遗物无需落板，点击左侧条目即可获取"}
		"unit":
			var unit_def: Dictionary = registry.get_unit_def(resource_id)
			var fp_raw: Variant = unit_def.get("footprint_size", [1, 1])
			var footprint := Vector2i(1, 1)
			if fp_raw is Array and fp_raw.size() >= 2:
				footprint = Vector2i(int(fp_raw[0]), int(fp_raw[1]))
			var cells: Array[Vector2i] = []
			for dx in range(footprint.x):
				for dy in range(footprint.y):
					cells.append(cell + Vector2i(dx, dy))
			for check_cell in cells:
				if not BoardUtils.in_bounds(state, check_cell):
					return {"valid": false, "cells": cells, "message": "单位超出棋盘"}
				if state.get_unit_at(check_cell) != null:
					return {"valid": false, "cells": cells, "message": "目标格已有单位"}
				var entity := state.get_entity_at(check_cell)
				if entity != null and entity.alive and entity.blocks_movement():
					return {"valid": false, "cells": cells, "message": "目标格被阻挡实体占用"}
			return {"valid": true, "cells": cells, "message": "松手放置怪物"}
		"tile":
			return {"valid": BoardUtils.in_bounds(state, cell), "cells": [cell], "message": "替换地块为 %s" % resource_id}
		"surface_overlay":
			return {"valid": BoardUtils.in_bounds(state, cell), "cells": [cell], "message": "松手添加 %s" % resource_id}
		"entity":
			var occupied_entity := state.get_entity_at(cell)
			if occupied_entity != null and occupied_entity.alive:
				return {"valid": false, "cells": [cell], "message": "该格已有实体"}
			return {"valid": true, "cells": [cell], "message": "松手放置实体"}
		"overlay":
			if resource_id == Constants.TILE_MOD_POISON_PUDDLE and not state.get_tile(cell).has_ground_tag(Constants.GROUND_TAG_WATER):
				return {"valid": false, "cells": [cell], "message": "毒水洼只能放在水地块上"}
			return {"valid": true, "cells": [cell], "message": "松手添加 overlay"}
		"gem":
			if state.get_unit_at(cell) != null:
				return {"valid": true, "cells": [cell], "message": "松手后选择单位槽位"}
			return {"valid": false, "cells": [cell], "message": "该格没有可编辑单位"}
	return {"valid": false, "cells": [cell], "message": "暂不支持此资源"}


func auto_slot_index(state: GameState, pos: Vector2i, target_kind: String, gem_id: String, registry) -> int:
	if state == null:
		return -1
	var slots: Array = []
	if target_kind == "unit":
		var unit := state.get_unit_at(pos)
		if unit != null:
			slots = unit.slots
	var gem_type := str(registry.get_gem_def(gem_id).get("slot_type", ""))
	for index in range(slots.size()):
		var slot: SlotState = slots[index]
		if slot == null or not slot.gem_uid.is_empty() or slot.locked or slot.is_split_disabled():
			continue
		if gem_type.is_empty() or slot.accepts_slot_type(gem_type):
			return index
	return -1


func typed_preview_cells(values: Variant) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if values is Array:
		for value in values:
			if value is Vector2i:
				cells.append(value)
	return cells


func tool_summary(tool: Dictionary, kind_labels: Dictionary) -> String:
	if tool.is_empty():
		return "工具: 未选择（左侧列表选择资源）"
	var kind := str(tool.get("kind", ""))
	var kind_label := str(kind_labels.get(kind, kind))
	var tool_id := str(tool.get("id", ""))
	var action_hint := "点击条目添加" if kind == "relic" else "拖到棋盘放置"
	return "工具: %s · %s（%s）" % [tool_id, kind_label, action_hint]


func target_summary(
	state: GameState,
	cell: Vector2i,
	dummy_stats: Dictionary,
	registry
) -> String:
	if cell.x < 0:
		return "操作目标: 点击棋盘格子锁定"
	if state == null:
		return "操作目标: —"
	var lines: Array[String] = ["操作目标: %s" % str(cell)]
	var tile := state.get_tile(cell)
	var unit := state.get_unit_at(cell)
	if unit != null and unit.alive:
		lines.append("%s · HP %d/%d" % [
			registry.get_unit_display_name(unit.unit_def_id),
			unit.hp,
			unit.max_hp,
		])
		if unit.has_tag("unit:training_dummy"):
			var stats: Dictionary = dummy_stats.get(unit.uid, {})
			lines.append("稻草人: 受击 %d · 总伤 %d" % [
				int(stats.get("hits", 0)),
				int(stats.get("total_damage", 0)),
			])
	elif tile != null:
		lines.append(registry.get_tile_display_name(tile.tile_id))
	var entity := state.get_entity_at(cell)
	if entity != null and entity.alive:
		lines.append("实体: %s" % entity.entity_id)
	if tile != null and not tile.modifiers.is_empty():
		var overlay_ids: Array[String] = []
		for modifier in tile.modifiers:
			overlay_ids.append(str(modifier.get("type", "")))
		lines.append("Overlay: %s" % ", ".join(overlay_ids))
	return "\n".join(lines)


func refresh_action_buttons(state: GameState, cell: Vector2i, buttons: Dictionary) -> void:
	var has_cell := state != null and cell.x >= 0
	var tile = state.get_tile(cell) if has_cell else null
	var unit = state.get_unit_at(cell) if has_cell else null
	var entity = state.get_entity_at(cell) if has_cell else null
	var remove_unit_btn: Button = buttons.get("unit")
	var remove_entity_btn: Button = buttons.get("entity")
	var remove_overlay_btn: Button = buttons.get("overlay")
	if remove_unit_btn != null:
		remove_unit_btn.disabled = not has_cell or unit == null or unit.uid == state.player_uid
	if remove_entity_btn != null:
		remove_entity_btn.disabled = not has_cell or entity == null or not entity.alive
	if remove_overlay_btn != null:
		remove_overlay_btn.disabled = not has_cell or tile == null or tile.modifiers.is_empty()


func rebuild_contents(
	state: GameState,
	cell: Vector2i,
	gem_list: VBoxContainer,
	relic_list: VBoxContainer,
	registry,
	hud_presenter,
	remove_gem_callback: Callable,
	remove_relic_callback: Callable
) -> void:
	_clear_list(gem_list)
	_clear_list(relic_list)
	if cell.x < 0:
		gem_list.add_child(_empty_hint("锁定格子后显示槽位"))
		relic_list.add_child(_empty_hint("—"))
		return
	var gem_targets := _list_gem_targets(state, cell)
	if gem_targets.is_empty():
		gem_list.add_child(_empty_hint("该格无宝石"))
	else:
		for target in gem_targets:
			gem_list.add_child(_create_gem_row(
				state,
				cell,
				target,
				registry,
				remove_gem_callback
			))
	if not RunService.is_run_active():
		relic_list.add_child(_empty_hint("未开启 Run"))
		return
	var owned := RunService.get_owned_relics()
	if owned.is_empty():
		relic_list.add_child(_empty_hint("无遗物 · 左侧列表点击添加"))
	else:
		for relic_id in owned:
			relic_list.add_child(_create_relic_row(
				str(relic_id),
				registry,
				hud_presenter,
				remove_relic_callback
			))


func rebuild_status_panel(
	state: GameState,
	cell: Vector2i,
	status_box: VBoxContainer,
	status_grid: GridContainer,
	status_ids: Array[String],
	status_icons,
	apply_status_callback: Callable
) -> void:
	if status_grid == null:
		return
	for child in status_grid.get_children():
		child.queue_free()
	if cell.x < 0 or state == null:
		status_box.visible = false
		return
	var unit := state.get_unit_at(cell)
	if unit == null or not unit.alive:
		status_box.visible = false
		return
	status_box.visible = true
	for status_id in status_ids:
		var button := Button.new()
		button.custom_minimum_size = Vector2(36, 36)
		button.tooltip_text = StatusRegistry.display_name(status_id)
		button.pressed.connect(apply_status_callback.bind(status_id))
		BattleUiTheme.apply_button(button, "ghost")
		var icon_tex = status_icons.get_icon(status_id)
		if icon_tex != null:
			var icon := TextureRect.new()
			icon.texture = icon_tex
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon.custom_minimum_size = Vector2(22, 22)
			icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon.set_anchors_preset(Control.PRESET_CENTER)
			button.add_child(icon)
		status_grid.add_child(button)


func _clear_list(list: VBoxContainer) -> void:
	if list == null:
		return
	for child in list.get_children():
		child.queue_free()


func _empty_hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", BattleUiTheme.TEXT_HINT)
	return label


func _create_gem_row(
	state: GameState,
	cell: Vector2i,
	target: Dictionary,
	registry,
	remove_callback: Callable
) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var gem: GemState = null
	var slot_index := int(target.get("slot_index", -1))
	var target_kind := str(target.get("target_kind", ""))
	if state != null and slot_index >= 0 and target_kind == "unit":
		var unit := state.get_unit_at(cell)
		if unit != null and slot_index < unit.slots.size():
			var slot: SlotState = unit.slots[slot_index]
			if slot != null and not slot.gem_uid.is_empty():
				gem = state.gems.get(slot.gem_uid, null)
	if gem != null:
		var icon := TextureRect.new()
		icon.texture = UnitLooks.get_gem_texture(gem)
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.custom_minimum_size = Vector2(16, 16)
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.self_modulate = UnitLooks.gem_sprite_modulate(gem)
		row.add_child(icon)
	var label := Label.new()
	var gem_name: String = registry.get_gem_display_name(gem) if gem != null else str(target.get("label", ""))
	label.text = "%s槽 · %s" % [_slot_label(str(target.get("slot_type", ""))), gem_name]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 11)
	row.add_child(label)
	var button := Button.new()
	button.text = "移除"
	button.custom_minimum_size = Vector2(52, 28)
	button.pressed.connect(remove_callback.bind(target))
	BattleUiTheme.apply_button(button, "ghost")
	row.add_child(button)
	return row


func _create_relic_row(
	relic_id: String,
	registry,
	hud_presenter,
	remove_callback: Callable
) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var definition: Dictionary = registry.get_relic_def(relic_id)
	var rarity: String = registry.get_relic_rarity(relic_id)
	var rarity_color: Color = hud_presenter.rarity_color(rarity)
	var icon_tex := UnitLooks.get_relic_texture(relic_id)
	if icon_tex != null:
		var icon := TextureRect.new()
		icon.texture = icon_tex
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.custom_minimum_size = Vector2(20, 20)
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.self_modulate = rarity_color
		row.add_child(icon)
	var label := Label.new()
	label.text = str(definition.get("name", relic_id))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", rarity_color)
	row.add_child(label)
	var button := Button.new()
	button.text = "移除"
	button.custom_minimum_size = Vector2(52, 28)
	button.pressed.connect(remove_callback.bind(relic_id))
	BattleUiTheme.apply_button(button, "ghost")
	row.add_child(button)
	return row


func _list_gem_targets(state: GameState, cell: Vector2i) -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	if state == null or cell.x < 0:
		return targets
	var unit := state.get_unit_at(cell)
	if unit != null:
		for index in range(unit.slots.size()):
			var slot: SlotState = unit.slots[index]
			if slot != null and not slot.gem_uid.is_empty():
				var gem: GemState = state.gems.get(slot.gem_uid, null)
				var gem_id := gem.gem_id if gem != null else "?"
				targets.append({
					"target_kind": "unit",
					"slot_index": index,
					"slot_type": slot.slot_type,
					"label": "%s · %s" % [_slot_label(slot.slot_type), gem_id],
				})
	return targets


func _slot_label(slot_type: String) -> String:
	match slot_type:
		Constants.SLOT_RED:
			return "红"
		Constants.SLOT_BLUE:
			return "蓝"
		Constants.SLOT_BLACK:
			return "黑"
		_:
			return slot_type


func _action_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	BattleUiTheme.apply_button(button, "ghost")
	return button


func _toggle_button(text: String, callback: Callable) -> Button:
	var button := _action_button(text, callback)
	button.toggle_mode = true
	return button
