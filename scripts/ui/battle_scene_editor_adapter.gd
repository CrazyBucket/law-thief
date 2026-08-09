extends "res://scripts/ui/battle_scene_flow_base.gd"

func _create_generated_export_button() -> void:
	if _generated_export_btn != null:
		return
	var export_button_script := _lazy_resources.generated_export_button_script() as Script
	if export_button_script == null:
		return
	_generated_export_btn = export_button_script.new()
	_generated_export_btn.setup(_controller)
	$HudLayer/TopBar/HBox.add_child(_generated_export_btn)
	BattleUiTheme.apply_button(_generated_export_btn, "ghost")

func setup(encounter_id: String) -> void:
	_encounter_id = encounter_id
	if is_node_ready():
		_start_battle(encounter_id)

func _start_battle(encounter_id: String) -> void:
	_encounter_id = encounter_id
	var editor_battle := _editor_available()
	if editor_battle and not _editor_session_active:
		_begin_editor_session()
	_battle_end_applied = false
	_board.clear_gem_visuals()
	_hide_preview_panel(true)
	_tracked_player_uid = ""
	_editor_dummy_stats.clear()
	_editor_bound_state = null
	_controller.start_encounter(encounter_id, 0, GameService.pending_room_id, not editor_battle)
	if OS.is_debug_build() and _controller.state != null and not _controller.state.generated_encounter_blueprint.is_empty():
		_create_generated_export_button()
	if _generated_export_btn != null:
		_generated_export_btn.sync_for_state(_controller.state)
	_bind_editor_state_signals()
	_mark_visible_enemies_seen()
	_inspect_uid = _controller.selected_unit_uid
	_inspect_cell = Vector2i(-1, -1)
	_board.init_unit_orientations()
	var carried_gem := _controller.get_held_gem()
	if carried_gem != null:
		_board.show_held_gem_orbit(carried_gem)
	if _editor_available() and _editor_panel != null and _editor_auto_boot_enabled:
		_editor_auto_boot_enabled = false
		_enter_editor_mode()
	if not _editor_available() and bool(SettingsService.get_value("show_tutorial")):
		if encounter_id == "tutorial_001":
			_show_tutorial_intro()
		elif encounter_id == "boss_chapter_1":
			_show_old_mage_tutorial_intro()

func _on_cell_hovered(cell: Vector2i, valid: bool) -> void:
	_hover_cell = cell if valid else Vector2i(-1, -1)
	if _controller == null:
		return
	if _editor_drag_active:
		if not valid:
			_board.set_hover(Vector2i(-1, -1))
			_board.clear_editor_preview()
			_sync_editor_hover("", "")
			_refresh_editor_focus()
			_hide_preview_panel(true)
			return
		_board.set_hover(cell)
		var preview := _editor_preview_for_cell(cell)
		_board.set_editor_preview(_typed_preview_cells(preview.get("cells", [])), bool(preview.get("valid", false)), true)
		_sync_editor_hover("格子 %s" % str(cell), str(preview.get("message", "")))
		_refresh_editor_focus()
		_preview_title.text = "编辑预览"
		_preview_body.text = _format_preview_body(str(preview.get("message", "")))
		_show_preview_panel(get_viewport().get_mouse_position())
		return
	if not valid:
		_hide_preview_panel(true)
		_board.set_hover(Vector2i(-1, -1))
		if _timeline_hover_uid.is_empty():
			_board.set_timeline_hover_unit("")
		BattleOverlayPresenter.apply_to_board(_board, _controller.get_highlights())
		_refresh_editor_focus()
		return
	_board.set_hover(cell)
	BattleOverlayPresenter.apply_to_board(_board, _controller.get_highlights(_hover_cell))
	if _timeline_hover_uid.is_empty():
		var hovered_state := _view_state()
		var hovered_unit := hovered_state.get_unit_at(cell) if hovered_state != null else null
		_board.set_timeline_hover_unit(hovered_unit.uid if hovered_unit != null and hovered_unit.alive else "")
	_hide_preview_panel(true)
	_refresh_editor_focus()

func _show_preview_panel(mouse: Vector2) -> void:
	_ensure_preview_view().show_at(mouse, Callable(self, "_clamp_preview_panel"))

func _hide_preview_panel(immediate: bool = false) -> void:
	_ensure_preview_view().hide(immediate)

func _ensure_preview_view() -> BattlePreviewPanel:
	if _preview_view == null:
		_preview_view = BattlePreviewPanel.new(_preview_panel, _preview_title, _preview_body)
	return _preview_view

func _format_preview_body(body: String) -> String:
	if body.is_empty():
		return ""
	var lines: PackedStringArray = body.split("\n")
	var formatted: Array[String] = []
	for line in lines:
		if line.begins_with("→"):
			formatted.append("[color=#7fd4ff]%s[/color]" % line)
		elif line.begins_with("意图:"):
			formatted.append("[color=#ffb07a]%s[/color]" % line)
		elif line.begins_with("状态:"):
			formatted.append("[color=#ff7070]%s[/color]" % line)
		elif line.begins_with("预判:"):
			formatted.append("[color=#ffd166]%s[/color]" % line)
		else:
			formatted.append("[color=#c8cad4]%s[/color]" % line)
	return "\n".join(formatted)

func _show_result(result: Dictionary) -> void:
	if result.get("ok", false):
		_message_label.text = _controller.get_action_hint()
	else:
		var reason: String = result.get("reason", "")
		if reason.is_empty():
			reason = "无法执行"
		push_warning("BattleScene: action failed — %s" % reason)
		_message_label.text = reason

func _enter_editor_mode() -> void:
	if not _editor_available():
		return
	if not _editor_session_active:
		_begin_editor_session()
	_editor_mode = true
	_editor_drag_active = false
	_sync_editor_inspector("")
	_refresh()

func _on_editor_mode_toggled(enabled: bool) -> void:
	if enabled:
		_enter_editor_mode()
		return
	_editor_mode = false
	_editor_drag_active = false
	_board.clear_editor_preview()
	_hide_preview_panel()
	_sync_editor_inspector("")
	_refresh()

func _on_editor_tool_selected(tool: Dictionary) -> void:
	_editor_tool = tool.duplicate(true)
	_editor_drag_active = false
	_sync_editor_inspector("")
	if str(_editor_tool.get("kind", "")) == "relic":
		_sync_editor_inspector("点击左侧遗物条目添加，下方列表可移除")
	_board.clear_editor_preview()

func _on_editor_tool_drag_started(tool: Dictionary) -> void:
	if not _editor_mode:
		return
	_editor_tool = tool.duplicate(true)
	_editor_drag_active = true
	_sync_editor_inspector("正在拖拽资源")
	if _hover_cell.x >= 0:
		var preview := _editor_preview_for_cell(_hover_cell)
		_board.set_editor_preview(_typed_preview_cells(preview.get("cells", [])), bool(preview.get("valid", false)), true)

func _on_editor_tool_drag_hovered(tool: Dictionary, cell: Vector2i, valid: bool) -> void:
	if not _editor_mode:
		return
	_editor_tool = tool.duplicate(true)
	_editor_drag_active = true
	_on_cell_hovered(cell, valid)

func _on_editor_tool_dropped(tool: Dictionary, cell: Vector2i, valid: bool) -> void:
	if not _editor_mode:
		return
	_editor_tool = tool.duplicate(true)
	if valid:
		_try_editor_place(cell)
	_editor_drag_active = false
	_board.clear_editor_preview()
	_hide_preview_panel()
	_refresh()

func _editor_preview_for_cell(cell: Vector2i) -> Dictionary:
	if _editor_view == null:
		return {"valid": false, "cells": [], "message": "编辑器未加载"}
	return _editor_view.preview_for_cell(_controller.state, _editor_tool, cell, DataRegistry)

func _editor_auto_slot_index(pos: Vector2i, target_kind: String, gem_id: String) -> int:
	if _editor_view == null:
		return -1
	return _editor_view.auto_slot_index(_controller.state, pos, target_kind, gem_id, DataRegistry)

func _try_editor_place(cell: Vector2i) -> void:
	if _editor_tool.is_empty():
		_sync_editor_inspector("先从左侧选择资源")
		return
	var preview := _editor_preview_for_cell(cell)
	if not bool(preview.get("valid", false)):
		_sync_editor_inspector(str(preview.get("message", "")))
		return
	var kind := str(_editor_tool.get("kind", ""))
	var resource_id := str(_editor_tool.get("id", ""))
	var tile_resource_id := str(_editor_tool.get("tile_id", resource_id))
	if kind == "gem":
		var target_kind := "unit" if _controller.state.get_unit_at(cell) != null else "tile"
		var slot_index := _editor_auto_slot_index(cell, target_kind, resource_id)
		if slot_index < 0:
			_sync_editor_inspector("没有匹配的空槽位；先从右侧移除宝石")
			return
		var gem_result := _controller.run_editor_action("spawn_gem", {
			"gem_id": resource_id,
			"pos": cell,
			"target_kind": target_kind,
			"slot_index": slot_index,
		})
		_sync_editor_inspector(str(gem_result.get("message", "")))
		_show_result(gem_result)
		_refresh()
		return
	var result := {}
	match kind:
		"unit":
			result = _controller.run_editor_action("spawn_unit", {
				"unit_def_id": resource_id,
				"pos": cell,
				"team": Constants.TEAM_ENEMY,
			})
		"tile":
			result = _controller.run_editor_action("set_tile", {"tile_id": resource_id, "pos": cell})
		"surface_overlay":
			result = _controller.run_editor_action("set_tile", {
				"tile_id": tile_resource_id,
				"pos": cell,
				"surface_variant": str(_editor_tool.get("surface_variant", "")),
			})
		"entity":
			result = _controller.run_editor_action("spawn_entity", {"entity_id": resource_id, "pos": cell})
		"overlay":
			result = _controller.run_editor_action("spawn_overlay", {"overlay_id": resource_id, "pos": cell})
		_:
			result = {"ok": false, "message": "暂不支持此资源"}
	_sync_editor_inspector(str(result.get("message", "")))
	_show_result(result)
	_refresh()

func _sync_editor_hover(title: String, detail: String) -> void:
	if _editor_hover_label == null:
		return
	_editor_hover_label.text = title if detail.is_empty() else "%s\n%s" % [title, detail]
	if _editor_panel != null and _editor_panel.has_method("set_hover_summary"):
		_editor_panel.set_hover_summary(detail)
		_layout_editor_ui()

func _refresh_editor_focus() -> void:
	if not _editor_available():
		return
	_sync_editor_inspector(_editor_result_label.text if _editor_result_label != null else "")

func _sync_editor_inspector(message: String) -> void:
	_bind_editor_state_signals()
	if _editor_tool_label != null:
		_editor_tool_label.text = _editor_tool_summary()
	if _editor_target_label != null:
		_editor_target_label.text = _editor_target_summary()
	if _editor_result_label != null and not message.is_empty():
		_editor_result_label.text = message
	if _editor_player_invincible_btn != null:
		var invincible := _controller.editor_player_invincible_enabled()
		_editor_player_invincible_btn.button_pressed = invincible
		_editor_player_invincible_btn.text = "玩家无敌 开" if invincible else "玩家无敌 关"
	_rebuild_editor_contents()
	_rebuild_editor_status_panel()
	_refresh_editor_action_buttons()

func _editor_tool_summary() -> String:
	return _editor_view.tool_summary(_editor_tool, _EDITOR_KIND_LABELS)

func _editor_target_summary() -> String:
	return _editor_view.target_summary(
		_controller.state,
		_editor_action_cell,
		_editor_dummy_stats,
		DataRegistry
	)

func _bind_editor_state_signals() -> void:
	if _controller == null or _controller.state == null or _controller.state == _editor_bound_state:
		return
	_editor_bound_state = _controller.state
	_editor_bound_state.on_damage_taken.connect(_on_editor_damage_taken)

func _refresh_editor_action_buttons() -> void:
	_editor_view.refresh_action_buttons(_controller.state, _editor_action_cell, {
		"unit": _editor_remove_unit_btn,
		"entity": _editor_remove_entity_btn,
		"overlay": _editor_remove_overlay_btn,
	})

func _rebuild_editor_contents() -> void:
	_editor_view.rebuild_contents(
		_controller.state,
		_editor_action_cell,
		_editor_gem_list,
		_editor_relic_list,
		DataRegistry,
		_hud_presenter,
		_on_editor_remove_gem_target,
		_on_editor_remove_relic
	)

func _rebuild_editor_status_panel() -> void:
	_editor_view.rebuild_status_panel(
		_controller.state,
		_editor_action_cell,
		_editor_status_box,
		_editor_status_grid,
		_EDITOR_STATUS_IDS,
		StatusIcons,
		_on_editor_apply_status
	)

func _on_editor_apply_status(status_id: String) -> void:
	if not _editor_action_cell_valid():
		return
	var result := _controller.run_editor_action("apply_unit_status", {
		"pos": _editor_action_cell,
		"status_id": status_id,
	})
	_editor_result_label.text = str(result.get("message", ""))
	_rebuild_editor_status_panel()
	_refresh()

func _on_editor_remove_gem_target(target: Dictionary) -> void:
	if not _editor_action_cell_valid():
		return
	var result := _controller.run_editor_action("remove_gem", {
		"pos": _editor_action_cell,
		"target_kind": str(target.get("target_kind", "")),
		"slot_index": int(target.get("slot_index", -1)),
		"slot_type": str(target.get("slot_type", "")),
	})
	_sync_editor_inspector(str(result.get("message", "")))
	_show_result(result)
	_refresh()

func _on_editor_relic_requested(relic_id: String) -> void:
	var run_service: Node = Engine.get_main_loop().root.get_node_or_null("RunService")
	if run_service != null and not run_service.is_run_active():
		run_service.start_run(1, 1)
	var result := _controller.run_editor_action("add_relic", {"relic_id": relic_id})
	_sync_editor_inspector(str(result.get("message", "")))
	_show_result(result)
	_refresh()

func _begin_editor_session() -> void:
	var run_service: Node = Engine.get_main_loop().root.get_node_or_null("RunService")
	_editor_session_active = true
	_editor_run_snapshot = {}
	if run_service != null and run_service.has_method("snapshot_active_run"):
		_editor_run_snapshot = run_service.snapshot_active_run()
	if run_service != null and run_service.has_method("begin_temporary_run"):
		run_service.begin_temporary_run()

func _end_editor_session() -> void:
	if not _editor_session_active:
		return
	var run_service: Node = Engine.get_main_loop().root.get_node_or_null("RunService")
	if run_service != null and run_service.has_method("restore_run_snapshot"):
		run_service.restore_run_snapshot(_editor_run_snapshot)
	_editor_session_active = false
	_editor_run_snapshot = {}
	_editor_dummy_stats.clear()
	_editor_bound_state = null
	_controller.editor_unlimited_actions = false
	_controller.set_editor_player_invincible(false)
	if _editor_unlimited_btn != null:
		_editor_unlimited_btn.button_pressed = false
		_editor_unlimited_btn.text = "无限行动 关"
	if _editor_player_invincible_btn != null:
		_editor_player_invincible_btn.button_pressed = false
		_editor_player_invincible_btn.text = "玩家无敌 关"

func _on_editor_remove_relic(relic_id: String) -> void:
	if relic_id.is_empty():
		return
	var result := _controller.run_editor_action("remove_relic", {"relic_id": relic_id})
	_sync_editor_inspector(str(result.get("message", "")))
	_show_result(result)
	_refresh()

func _editor_action_cell_valid() -> bool:
	return _editor_action_cell.x >= 0

func _on_editor_remove_unit_pressed() -> void:
	if not _editor_action_cell_valid():
		return
	var result := _controller.run_editor_action("remove_unit", {"pos": _editor_action_cell})
	_sync_editor_inspector(str(result.get("message", "")))
	_show_result(result)
	_refresh()

func _on_editor_remove_entity_pressed() -> void:
	if not _editor_action_cell_valid():
		return
	var result := _controller.run_editor_action("remove_entity", {"pos": _editor_action_cell})
	_sync_editor_inspector(str(result.get("message", "")))
	_show_result(result)
	_refresh()

func _on_editor_remove_overlay_pressed() -> void:
	var state := _controller.state
	if state == null or not _editor_action_cell_valid():
		return
	var tile := state.get_tile(_editor_action_cell)
	if tile == null or tile.modifiers.is_empty():
		return
	var overlay_id := str(tile.modifiers[0].get("type", ""))
	var result := _controller.run_editor_action("remove_overlay", {"pos": _editor_action_cell, "overlay_id": overlay_id})
	_sync_editor_inspector(str(result.get("message", "")))
	_show_result(result)
	_refresh()

func _on_editor_damage_taken(unit_uid: String, amount: int, reason: String) -> void:
	var state := _controller.state
	if state == null:
		return
	var unit: UnitState = state.units.get(unit_uid, null)
	if unit == null or not unit.has_tag("unit:training_dummy"):
		return
	var stats: Dictionary = _editor_dummy_stats.get(unit_uid, {"hits": 0, "total_damage": 0, "max_hit": 0, "last_reason": ""})
	stats["hits"] = int(stats.get("hits", 0)) + 1
	stats["total_damage"] = int(stats.get("total_damage", 0)) + amount
	stats["max_hit"] = maxi(int(stats.get("max_hit", 0)), amount)
	stats["last_reason"] = reason
	_editor_dummy_stats[unit_uid] = stats
	if _editor_action_cell == unit.pos:
		_sync_editor_inspector("训练稻草人已记录本次伤害")

func _typed_preview_cells(values: Variant) -> Array[Vector2i]:
	if _editor_view == null:
		return [] as Array[Vector2i]
	return _editor_view.typed_preview_cells(values)

func _on_editor_panel_close_requested() -> void:
	if _editor_panel != null:
		_editor_panel.visible = false
	if _editor_panel_toggle_btn != null:
		_editor_panel_toggle_btn.visible = true
	_layout_editor_ui()

func _on_editor_panel_toggle_pressed() -> void:
	if _editor_panel != null:
		_editor_panel.visible = true
	if _editor_panel_toggle_btn != null:
		_editor_panel_toggle_btn.visible = false
	_layout_editor_ui()

func _on_editor_encounter_requested(encounter_id: String) -> void:
	if encounter_id.is_empty() or not _editor_available():
		return
	_editor_action_cell = Vector2i(-1, -1)
	_editor_drag_active = false
	_board.clear_editor_preview()
	_start_battle(encounter_id)
	_editor_mode = true
	_sync_editor_inspector("已载入场景 %s" % encounter_id)
	_refresh()

func _on_editor_clear_enemies_requested() -> void:
	if not _editor_available():
		return
	var result := _controller.run_editor_action("clear_enemies")
	_sync_editor_inspector(str(result.get("message", "")))
	_show_result(result)
	_refresh()

func _on_editor_inspector_close_pressed() -> void:
	if _editor_inspector != null:
		_editor_inspector.visible = false
	if _editor_inspector_toggle_btn != null:
		_editor_inspector_toggle_btn.visible = true

func _on_editor_inspector_toggle_pressed() -> void:
	if _editor_inspector != null:
		_editor_inspector.visible = true
	if _editor_inspector_toggle_btn != null:
		_editor_inspector_toggle_btn.visible = false

func _on_editor_unlimited_actions_pressed() -> void:
	var enabled := _editor_unlimited_btn != null and _editor_unlimited_btn.button_pressed
	_controller.editor_unlimited_actions = enabled
	if _editor_unlimited_btn != null:
		_editor_unlimited_btn.text = "无限行动 开" if enabled else "无限行动 关"
	_refresh()

func _on_editor_player_invincible_pressed() -> void:
	var enabled := _editor_player_invincible_btn != null and _editor_player_invincible_btn.button_pressed
	_controller.set_editor_player_invincible(enabled)
	if _editor_player_invincible_btn != null:
		_editor_player_invincible_btn.text = "玩家无敌 开" if enabled else "玩家无敌 关"
	_refresh()

func _select_unit(uid: String) -> void:
	_inspect_uid = uid
	_inspect_cell = Vector2i(-1, -1)
	_controller.selected_unit_uid = uid
	_refresh()

func _mark_visible_enemies_seen() -> void:
	if _controller.state == null:
		return
	for unit in _controller.state.units.values():
		if unit.team != Constants.TEAM_ENEMY:
			continue
		ProfileService.mark_enemy_seen(unit.unit_def_id)
	AchievementService.refresh_progress_flags()

func _show_tutorial_intro() -> void:
	_show_tutorial_overlay(
		"窃律者 · 操作指南",
		"""[color=#9aa0ad]每回合资源：[/color]
[color=#5ad8ff]● 1 次移动[/color]　[color=#ffcc44]● 1 次行动[/color]（攻击/技能/触发）
[color=#88ff88]● 拔出/嵌入免费[/color]，可穿插在行动前后
[color=#ff6666]核心：偷敌人宝石 → 装入自己槽位 → 释放技能[/color]

[color=#ff5555]红槽[/color] 主动　[color=#5599ff]蓝槽[/color] 被动　[color=#888]黑槽[/color] 死亡触发

[color=#ffffff]教学目标：拔工兵红槽 → 技能/黑槽嫁祸 → 结束回合[/color]""",
		"开始战斗"
	)

func _show_old_mage_tutorial_intro() -> void:
	_show_tutorial_overlay(
		_translate_or("boss.old_mage.tutorial.title", "老法师：读懂施法与抢夺"),
		_translate_or("boss.old_mage.tutorial.body", "老法师会在施法与补充之间交替。红槽技能是主动法术，蓝槽技能需要满足反应条件；预警会锁定目标、范围与落点。优先抢走技能池宝石，非池宝石只会让它浪费一回合。低于 20 生命后每回合黑化一个槽位，移动力固定为 2。"),
		_translate_or("boss.old_mage.tutorial.begin", "开始战斗")
	)

func _translate_or(key: String, fallback: String) -> String:
	var translated := TranslationServer.translate(key)
	return fallback if translated == key or translated.is_empty() else translated

func _show_tutorial_overlay(title_text: String, body_text: String, button_text: String) -> void:
	if _tutorial_overlay != null and is_instance_valid(_tutorial_overlay):
		_tutorial_overlay.queue_free()
	var overlay := ColorRect.new()
	_tutorial_overlay = overlay
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.02, 0.02, 0.05, 0.82)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(560, 0)
	panel.offset_left = -280
	panel.offset_right = 280
	panel.offset_top = -220
	panel.offset_bottom = 220
	panel.add_theme_stylebox_override("panel", BattleUiTheme.panel_style(BattleUiTheme.BORDER_ACCENT))
	overlay.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)
	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	vbox.add_child(title)
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.custom_minimum_size = Vector2(0, 260)
	body.text = body_text
	vbox.add_child(body)
	var btn := Button.new()
	btn.text = button_text
	btn.custom_minimum_size = Vector2(180, 44)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	BattleUiTheme.apply_button(btn, "end")
	btn.pressed.connect(_dismiss_tutorial_overlay)
	vbox.add_child(btn)
	overlay.modulate.a = 0.0
	create_tween().tween_property(overlay, "modulate:a", 1.0, 0.28)

func _layout_editor_ui() -> void:
	if not is_node_ready():
		return
	var viewport_size := get_viewport_rect().size
	var left := 8.0
	if _hud_presenter != null:
		_hud_presenter.sync_toggle_btn_x(_panel_visible)
	# The editor owns a fixed left dock lane. It never follows the inspect card's
	# content height, so an attack or a new selection cannot push it into the HUD.
	var editor_top := _EDITOR_DOCK_TOP
	var editor_dock_visible := _editor_panel != null and _editor_panel.visible
	if _relic_bar_root != null and _relic_bar_scroll != null:
		var relic_width := maxf(_relic_bar_scroll.custom_minimum_size.x, 0.0)
		var relic_h := maxf(_relic_bar_scroll.custom_minimum_size.y, 0.0)
		var relic_left := left + 12.0
		_relic_bar_root.position = Vector2(relic_left, editor_top)
		_relic_bar_root.size = Vector2(relic_width, relic_h)
		_relic_bar_scroll.size = Vector2(relic_width, relic_h)
		# The editor owns this lane while open; keep the optional relic list from
		# creating a second, invisible layout owner underneath the editor dock.
		_relic_bar_root.visible = _relic_bar_scroll.visible and not editor_dock_visible
	var bottom_limit := viewport_size.y - _bottom_dock.size.y - 8.0
	if editor_dock_visible:
		var editor_width := minf(380.0, maxf(viewport_size.x * 0.30, 340.0))
		var editor_height := maxf(bottom_limit - editor_top, 240.0)
		_editor_panel.size = Vector2(editor_width, editor_height)
		var max_editor_x := maxf(left, viewport_size.x * 0.5 - editor_width - 8.0)
		var editor_x := clampf(_editor_panel.position.x, left, max_editor_x) if _editor_panel_user_positioned else left
		var max_editor_y := maxf(editor_top, bottom_limit - editor_height)
		var editor_y := clampf(_editor_panel.position.y, editor_top, max_editor_y) if _editor_panel_user_positioned else editor_top
		_editor_panel.position = Vector2(editor_x, editor_y)
	if _editor_panel_toggle_btn != null:
		_editor_panel_toggle_btn.position = Vector2(left, editor_top)
	if _editor_inspector != null and _editor_inspector.visible:
		var inspector_w := minf(340.0, maxf(viewport_size.x * 0.24, 300.0))
		var inspector_top := _turn_queue_panel.position.y + _turn_queue_panel.size.y + _EDITOR_INSPECTOR_GAP
		var inspector_h := maxf(bottom_limit - inspector_top, 240.0)
		_editor_inspector.size = Vector2(inspector_w, inspector_h)
		_editor_inspector.position = Vector2(viewport_size.x - inspector_w - 8.0, inspector_top)
	if _editor_inspector_toggle_btn != null:
		var inspector_top := _turn_queue_panel.position.y + _turn_queue_panel.size.y + _EDITOR_INSPECTOR_GAP
		_editor_inspector_toggle_btn.position = Vector2(viewport_size.x - _editor_inspector_toggle_btn.size.x - 8.0, inspector_top)

func _on_editor_panel_moved() -> void:
	_editor_panel_user_positioned = true

func _show_relic_detail_popup(relic_id: String) -> void:
	if relic_id.is_empty():
		return
	_dismiss_relic_detail_popup()
	var def: Dictionary = DataRegistry.get_relic_def(relic_id)
	var rarity: String = DataRegistry.get_relic_rarity(relic_id)
	var rarity_color := _hud_presenter.rarity_color(rarity)
	var canvas := CanvasLayer.new()
	canvas.layer = 72
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.06, 0.72)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(420, 0)
	panel.offset_left = -210
	panel.offset_right = 210
	panel.offset_top = -180
	panel.offset_bottom = 180
	panel.add_theme_stylebox_override("panel", BattleUiTheme.panel_style(rarity_color))
	root.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)
	var icon_tex := UnitLooks.get_relic_texture(relic_id)
	if icon_tex != null:
		var icon := TextureRect.new()
		icon.texture = icon_tex
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.custom_minimum_size = Vector2(54, 54)
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vbox.add_child(icon)
	var title := Label.new()
	title.text = str(def.get("name", relic_id))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", rarity_color)
	vbox.add_child(title)
	var rarity_label := Label.new()
	rarity_label.text = _rarity_display_name(rarity)
	rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rarity_label.add_theme_font_size_override("font_size", 13)
	rarity_label.add_theme_color_override("font_color", rarity_color.lightened(0.08))
	vbox.add_child(rarity_label)
	var body := RichTextLabel.new()
	body.bbcode_enabled = false
	body.fit_content = true
	body.scroll_active = false
	body.custom_minimum_size = Vector2(0, 120)
	body.text = _hud_presenter.relic_desc_text(def)
	body.add_theme_font_size_override("normal_font_size", 14)
	body.add_theme_color_override("default_color", BattleUiTheme.TEXT)
	vbox.add_child(body)
	var close_btn := Button.new()
	close_btn.text = "关闭"
	close_btn.custom_minimum_size = Vector2(140, 40)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	BattleUiTheme.apply_button(close_btn, "ghost")
	close_btn.pressed.connect(_dismiss_relic_detail_popup)
	vbox.add_child(close_btn)
	_relic_detail_overlay = canvas
	add_child(canvas)

func _dismiss_relic_detail_popup() -> void:
	if _relic_detail_overlay == null:
		return
	_relic_detail_overlay.queue_free()
	_relic_detail_overlay = null


func _dismiss_tutorial_overlay() -> void:
	if _tutorial_overlay == null or not is_instance_valid(_tutorial_overlay):
		_tutorial_overlay = null
		return
	_tutorial_overlay.queue_free()
	_tutorial_overlay = null

