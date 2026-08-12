extends "res://scripts/ui/battle_scene_editor_adapter.gd"

func _ready() -> void:
	var ready_started_usec := Time.get_ticks_usec()
	resized.connect(_layout_editor_ui)
	_controller.state_changed.connect(_on_controller_state_changed)
	_controller.battle_ended.connect(_on_battle_ended)
	_controller.anim_move.connect(_on_anim_move)
	_controller.anim_damage.connect(_on_anim_damage)
	_controller.anim_gem_flash.connect(_on_anim_gem_flash)
	_controller.anim_gem_hooked.connect(_on_anim_gem_hooked)
	_board_input.setup(_board)
	_board.cell_clicked.connect(_on_cell_clicked)
	_board.cell_hovered.connect(_on_cell_hovered)
	_board.unit_slot_clicked.connect(_on_board_unit_slot_selected)
	_board.editor_tool_drag_hovered.connect(_on_editor_tool_drag_hovered)
	_board.editor_tool_dropped.connect(_on_editor_tool_dropped)
	_apply_ui_theme()
	_ensure_preview_view().hide(true)
	call_deferred("_fit_status_panel")
	call_deferred("_fit_status_panel_height")
	call_deferred("_setup_held_gem_row")
	_setup_overload_chip()
	_wire_hover_interactions()
	_create_slot_popup()
	_create_damage_text_manager()
	if _editor_available():
		_create_level_console()
		_create_editor_ui()
	_event_player.setup(
		self ,
		_board,
		_controller,
		Callable(self , "_spawn_damage_text"),
		Callable(self , "_scaled_anim_time")
	)
	_setup_relic_bar()
	_create_rich_tooltip()
	_hud_presenter.setup({
		"controller": _controller,
		"board": _board,
		"status_panel": _status_panel,
		"status_vbox": _status_vbox,
		"header_row": _header_row,
		"info_col": _info_col,
		"status_clip": _status_clip,
		"slot_clip": _slot_clip,
		"slot_box": _slot_box,
		"portrait": _portrait,
		"inspect_name": _inspect_name,
		"inspect_stats": _inspect_stats,
		"inspect_status_row": _inspect_status_row,
		"hp_bar_row": _hp_bar_row,
		"shield_icon": _shield_icon,
		"combined_hp_bar": _combined_hp_bar,
		"hp_text": _hp_text,
		"turn_label": _turn_label,
		"move_chip": _move_chip,
		"act_chip": _act_chip,
		"overload_chip": _overload_chip,
		"held_label": _held_label,
		"held_gem_icon": _held_gem_icon,
		"hint_label": _hint_label,
		"phase_badge": _phase_badge,
		"message_label": _message_label,
		"queue_row": _queue_row,
		"queue_hint": _queue_hint,
		"move_btn": _move_btn,
		"attack_btn": _attack_btn,
		"extract_btn": _extract_btn,
		"insert_btn": _insert_btn,
		"hook_insert_btn": _hook_insert_btn,
		"end_turn_btn": _end_turn_btn,
		"toggle_panel_btn": _toggle_panel_btn,
		"turn_chips": _turn_chips,
		"relic_bar_root": _relic_bar_root,
		"relic_bar_scroll": _relic_bar_scroll,
		"relic_bar_vbox": _relic_bar_vbox,
		"tooltip": _rich_tooltip,
		"show_relic_detail_cb": Callable(self , "_show_relic_detail_popup"),
		"select_unit_cb": Callable(self , "_select_unit"),
		"set_timeline_hover_cb": Callable(self , "_set_timeline_hover"),
		"clear_timeline_hover_cb": Callable(self , "_clear_timeline_hover"),
	})
	_apply_animation_speed()
	var start_battle_started_usec := Time.get_ticks_usec()
	_start_battle(GameService.pending_encounter_id)
	_startup_start_battle_duration_usec = Time.get_ticks_usec() - start_battle_started_usec
	call_deferred("_restore_battle_reward_if_needed")
	_startup_ready_duration_usec = Time.get_ticks_usec() - ready_started_usec

func get_startup_ready_duration_ms() -> float:
	return float(_startup_ready_duration_usec) / 1000.0

func get_startup_start_battle_duration_ms() -> float:
	return float(_startup_start_battle_duration_usec) / 1000.0

func _apply_ui_theme() -> void:
	for hud_child in $HudLayer.get_children():
		if hud_child is Control:
			(hud_child as Control).theme = BattleUiTheme.build_theme()
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_status_panel.add_theme_stylebox_override("panel", BattleUiTheme.panel_style(BattleUiTheme.BORDER))
	_status_panel.clip_contents = true
	_held_label.clip_contents = true
	_held_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_top_bar.add_theme_stylebox_override("panel", BattleUiTheme.panel_style(BattleUiTheme.BORDER_ACCENT.darkened(0.2)))
	_bottom_dock.add_theme_stylebox_override("panel", BattleUiTheme.dock_style())
	_apply_command_group_theme()
	$HudLayer/TurnQueuePanel.add_theme_stylebox_override("panel", BattleUiTheme.panel_style(BattleUiTheme.PHASE_PLAYER.darkened(0.35)))
	_preview_panel.add_theme_stylebox_override("panel", BattleUiTheme.tooltip_style())
	_inspect_name.add_theme_color_override("font_color", BattleUiTheme.TEXT)
	_inspect_stats.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
	_message_label.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	_hint_label.add_theme_color_override("font_color", BattleUiTheme.TEXT_HINT)
	_queue_title.add_theme_color_override("font_color", BattleUiTheme.TEXT)
	_shield_icon.texture = StatusIcons.get_icon(Constants.STATUS_ARMOR)
	BattleUiTheme.apply_button(_toggle_panel_btn, "ghost")
	_menu_btn.flat = true

func _apply_command_group_theme() -> void:
	_style_command_group(_move_group, "move")
	_style_command_group(_combat_group, "combat")
	_style_command_group(_gem_group, "gem")
	_style_command_group(_turn_group, "end")

func _style_command_group(group: PanelContainer, kind: String) -> void:
	if group == null:
		return
	group.add_theme_stylebox_override("panel", BattleUiTheme.command_group_style(kind))
	var title := group.get_node_or_null("VBox/Title") as Label
	if title != null:
		title.add_theme_font_override("font", BattleUiTheme.pixel_font())
		title.add_theme_font_size_override("font_size", BattleUiTheme.FONT_SMALL)
		title.add_theme_color_override("font_color", BattleUiTheme.TEXT_HINT)

func _create_slot_popup() -> void:
	_slot_popup = SlotPopup.new()
	$HudLayer.add_child(_slot_popup)
	_slot_popup.slot_selected.connect(_on_popup_slot_selected)
	_slot_popup.dropped_gem_selected.connect(_on_popup_dropped_gem_selected)
	_slot_popup.cancelled.connect(_on_popup_cancelled)

func _create_damage_text_manager() -> void:
	_dmg_text = DamageTextManagerScript.new()
	get_tree().root.add_child.call_deferred(_dmg_text)

func _create_rich_tooltip() -> void:
	if _rich_tooltip != null:
		return
	_rich_tooltip = RichTooltip.new()
	_rich_tooltip.name = "RichTooltip"
	$HudLayer.add_child(_rich_tooltip)

func _create_level_console() -> void:
	var editor_console_scene := _lazy_resources.editor_console_scene() as PackedScene
	if editor_console_scene == null:
		return
	_console_layer = CanvasLayer.new()
	_console_layer.layer = 64
	add_child(_console_layer)
	_console = editor_console_scene.instantiate()
	_console.command_submitted.connect(_on_console_submitted)
	_console_layer.add_child(_console)

func _create_editor_ui() -> void:
	var editor_panel_script := _lazy_resources.editor_panel_script() as Script
	var editor_view_script := _lazy_resources.editor_view_script() as Script
	if editor_panel_script == null or editor_view_script == null:
		return
	_editor_view = editor_view_script.new()
	var controls: Dictionary = _editor_view.build(self, editor_panel_script, DataRegistry)
	_editor_panel = controls.get("panel")
	_editor_panel_toggle_btn = controls.get("panel_toggle_btn")
	_editor_inspector = controls.get("inspector")
	_editor_inspector_body = controls.get("inspector_body")
	_editor_tool_label = controls.get("tool_label")
	_editor_target_label = controls.get("target_label")
	_editor_hover_label = controls.get("hover_label")
	_editor_contents_box = controls.get("contents_box")
	_editor_gem_list = controls.get("gem_list")
	_editor_relic_list = controls.get("relic_list")
	_editor_status_box = controls.get("status_box")
	_editor_status_grid = controls.get("status_grid")
	_editor_result_label = controls.get("result_label")
	_editor_remove_unit_btn = controls.get("remove_unit_btn")
	_editor_remove_entity_btn = controls.get("remove_entity_btn")
	_editor_remove_overlay_btn = controls.get("remove_overlay_btn")
	_editor_unlimited_btn = controls.get("unlimited_btn")
	_editor_player_invincible_btn = controls.get("player_invincible_btn")
	_editor_inspector_toggle_btn = controls.get("inspector_toggle_btn")
	_sync_editor_inspector("")
	call_deferred("_layout_editor_ui")

func _on_action_pressed(action: String) -> void:
	if _enemy_phase_running:
		return
	_dismiss_popup()
	if _controller.selected_action == action:
		_controller.select_action("")
		_message_label.text = "已取消选择"
	else:
		_controller.select_action(action)
		_message_label.text = _controller.get_action_hint()

func _on_cell_clicked(cell: Vector2i) -> void:
	if _editor_available():
		_editor_action_cell = cell
		_refresh_editor_focus()
	if _player_animating:
		return
	var state := _controller.state
	if state == null:
		return
	var unit := state.get_unit_at(cell)
	var action := _controller.selected_action
	var presentation_refreshed := false
	if unit == null and action == Constants.ACTION_EXTRACT:
		unit = state.get_corpse_at(cell)
	if action.is_empty():
		_dismiss_popup()
		_set_inspect_target(cell)
		_refresh()
		return
	if _enemy_phase_running or state.phase != Constants.PHASE_PLAYER:
		_set_inspect_target(cell)
		_refresh()
		return
	match action:
		Constants.ACTION_MOVE:
			_dismiss_popup()
			var move_result := _controller.try_move(cell)
			if move_result.get("ok", false):
				_player_animating = true
				_board.clear_overlays()
				var events: Array = move_result.get("move_events", [])
				await _play_presentation_sequence(
					move_result.get("presentation_state", _controller.state.clone()),
					events,
					_controller.state
				)
				_player_animating = false
				presentation_refreshed = true
			else:
				_show_result(move_result)
				_set_inspect_target(cell)
		Constants.ACTION_ATTACK:
			_dismiss_popup()
			if unit != null:
				_set_inspect_target(cell)
			_player_animating = true
			var atk_res := _controller.try_attack_cell(cell)
			_show_result(atk_res)
			if atk_res.get("ok", false):
				var from_pos: Vector2i = atk_res.get("from_pos", Vector2i(-1, -1))
				var to_pos: Vector2i = atk_res.get("to_pos", cell)
				var attack_events: Array = atk_res.get("attack_events", [])
				var is_impact_attack := attack_events.any(func(ev):
					return str(ev.get("type", "")) == "impact_charge"
				)
				var player := _controller.state.get_player()
				if player != null and not is_impact_attack:
					_board.start_strike_effect(player.uid, to_pos)
				var has_attack_visual := false
				for ev in attack_events:
					if str(ev.get("type", "")) in ["projectile", "light_beam", "impact_charge"]:
						has_attack_visual = true
						break
				if not has_attack_visual and from_pos.x >= 0:
					await _event_player.play_prefire_projectile(from_pos, to_pos)
				await _play_presentation_sequence(
					atk_res.get("presentation_state", _controller.state.clone()),
					attack_events,
					_controller.state
				)
				_player_animating = false
				presentation_refreshed = true
			else:
				_player_animating = false
				_set_inspect_target(cell)
		Constants.ACTION_EXTRACT, Constants.ACTION_INSERT, Constants.ACTION_INSERT_HOOKED:
			var targets: Array = _controller.get_highlights().get("targets", [])
			if cell in targets:
				var extractable_ground: Array[String] = []
				if action == Constants.ACTION_EXTRACT:
					for gem_uid in state.get_dropped_gem_uids_at(cell):
						if _controller.check_dropped_gem_action(gem_uid).get("ok", false):
							extractable_ground.append(gem_uid)
				if not extractable_ground.is_empty():
					_set_inspect_target(cell)
					_slot_popup.show_for_dropped_gems(
						extractable_ground,
						state,
						get_viewport().get_mouse_position(),
						_controller.check_dropped_gem_action
					)
				elif unit != null and (unit.alive or action == Constants.ACTION_EXTRACT):
					_set_inspect_target(cell)
					_sync_unit_slot_panels()
				else:
					_set_inspect_target(cell)
					# Tile gem operations are intentionally not part of the current player-facing design.
					_dismiss_popup()
			else:
				_dismiss_popup()
				_set_inspect_target(cell)
	if not presentation_refreshed:
		_refresh()

func _set_preview_panel_visible(shown: bool, immediate: bool = false) -> void:
	_ensure_preview_view().set_visible(shown, immediate)

func _on_board_unit_slot_selected(unit_uid: String, slot_index: int) -> void:
	if _player_animating or _enemy_phase_running:
		return
	_on_popup_slot_selected(unit_uid, slot_index)

func _on_popup_dropped_gem_selected(gem_uid: String) -> void:
	var result := _controller.try_extract_dropped(gem_uid)
	_dismiss_popup()
	_show_result(result)
	if result.get("ok", false):
		_controller.select_action(Constants.ACTION_INSERT)
		_message_label.text = "已从地面拔取，选择槽位嵌入"
	_refresh()
	_sync_unit_slot_panels()

func _on_popup_slot_selected(unit_uid: String, slot_index: int) -> void:
	var action := _controller.selected_action
	var result: Dictionary
	match action:
		Constants.ACTION_EXTRACT:
			result = _controller.try_extract(unit_uid, slot_index)
		Constants.ACTION_INSERT:
			result = _controller.try_insert(unit_uid, slot_index)
		Constants.ACTION_INSERT_HOOKED:
			result = _controller.try_insert_hooked(unit_uid, slot_index)
		_:
			return
	_dismiss_popup()
	_show_result(result)
	if result.get("ok", false):
		match action:
			Constants.ACTION_EXTRACT:
				var extract_target: UnitState = _controller.state.units.get(unit_uid, null)
				if extract_target != null:
					_begin_held_gem_extract(extract_target.pos, result)
				_controller.select_action(Constants.ACTION_INSERT)
				_message_label.text = "已拔出，选择槽位嵌入"
			Constants.ACTION_INSERT:
				var insert_target: UnitState = _controller.state.units.get(unit_uid, null)
				if insert_target != null:
					_begin_held_gem_insert(insert_target.pos, result)
				if bool(result.get("overload_forced", false)):
					_message_label.text = "过载嵌入：已压入槽位，结束回合后异变生效"
				elif bool(result.get("old_mage_decoy", false)):
					_message_label.text = "无法解读：宝石将销毁，老法师下回合停止行动"
				else:
					_message_label.text = "已嵌入" if str(result.get("swapped_gem_uid", "")).is_empty() else "已替换，原宝石回到手中"
			Constants.ACTION_INSERT_HOOKED:
				if not bool(result.get("overload_armed", false)):
					var hook_target: UnitState = _controller.state.units.get(unit_uid, null)
					if hook_target != null:
						_begin_hooked_gem_insert(hook_target.pos, result)
				if bool(result.get("overload_armed", false)):
					_message_label.text = TranslationServer.translate("battle.gem.hook_overload_armed")
				elif bool(result.get("overload_forced", false)):
					_message_label.text = TranslationServer.translate("battle.gem.hook_overload_done")
				else:
					_message_label.text = TranslationServer.translate("battle.gem.hook_inserted")
	_refresh()
	_sync_unit_slot_panels()

func _begin_held_gem_extract(source_grid: Vector2i, result: Dictionary) -> void:
	var gem_uid := str(result.get("gem_uid", ""))
	if gem_uid.is_empty() or _controller.state == null:
		return
	var gem: GemState = _controller.state.gems.get(gem_uid, null)
	if gem == null:
		return
	_board.start_held_gem_extract(source_grid, gem)

func _begin_held_gem_insert(target_grid: Vector2i, result: Dictionary) -> void:
	var gem_uid := str(result.get("gem_uid", ""))
	if gem_uid.is_empty() or _controller.state == null:
		return
	var gem: GemState = _controller.state.gems.get(gem_uid, null)
	if gem == null:
		return
	_board.start_held_gem_insert(target_grid, gem)
	var swapped_uid := str(result.get("swapped_gem_uid", ""))
	if swapped_uid.is_empty():
		return
	var swapped_gem: GemState = _controller.state.gems.get(swapped_uid, null)
	if swapped_gem == null:
		return
	_schedule_swapped_gem_extract(target_grid, swapped_gem)

func _begin_hooked_gem_insert(target_grid: Vector2i, result: Dictionary) -> void:
	var gem_uid := str(result.get("gem_uid", ""))
	if gem_uid.is_empty() or _controller.state == null:
		return
	var gem: GemState = _controller.state.gems.get(gem_uid, null)
	if gem != null:
		_board.start_hooked_gem_insert(target_grid, gem)

func _schedule_swapped_gem_extract(target_grid: Vector2i, gem: GemState) -> void:
	var duration: float = 0.38
	if _board != null and _board.has_method("gem_insert_anim_duration"):
		duration = float(_board.call("gem_insert_anim_duration"))
	get_tree().create_timer(_scaled_anim_time(duration)).timeout.connect(
		_on_swapped_gem_extract_ready.bind(target_grid, gem.uid),
		CONNECT_ONE_SHOT
	)

func _on_swapped_gem_extract_ready(target_grid: Vector2i, gem_uid: String) -> void:
	if not is_instance_valid(_board) or _controller == null or _controller.state == null:
		return
	if _controller.state.held_gem_uid != gem_uid:
		return
	if _board.has_active_held_gem_visual():
		return
	var gem: GemState = _controller.state.gems.get(gem_uid, null)
	if gem == null:
		return
	_board.start_held_gem_extract(target_grid, gem)

func _on_popup_cancelled() -> void:
	_refresh()

func _dismiss_popup() -> void:
	if _slot_popup != null and _slot_popup.is_showing():
		_slot_popup.hide_popup()

func _on_end_turn_pressed() -> void:
	if _enemy_phase_running:
		return
	_dismiss_popup()
	var turn_end_execution: Dictionary = _controller.begin_enemy_phase()
	# 若分身切换后仍在玩家回合，刷新 UI 继续操控下一个分身
	if _controller.state != null and _controller.state.phase == Constants.PHASE_PLAYER:
		_message_label.text = _controller.get_action_hint()
		_refresh()
		return
	_run_enemy_phase_async(turn_end_execution)

func _run_enemy_phase_async(opening_execution: Dictionary = {}) -> void:
	_enemy_phase_running = true
	var opening_events: Array = opening_execution.get("events", [])
	if not opening_events.is_empty():
		await _play_presentation_sequence(
			opening_execution.get("presentation_state", _controller.state.clone()),
			opening_events
		)
	if not is_inside_tree() or _controller.state == null or _controller.state.phase == Constants.PHASE_ENDED:
		_enemy_phase_running = false
		_refresh()
		return
	# begin_enemy_phase 已在 _on_end_turn_pressed 中调用，此处不重复调用
	_message_label.text = "敌方行动中..."
	_refresh()
	var enemies := _controller.get_sorted_enemies()
	_enemy_turn_queue.clear()
	for enemy in enemies:
		_enemy_turn_queue.append(enemy.uid)
	_refresh()
	for enemy in enemies:
		if not is_inside_tree():
			break
		_refresh()
		if not enemy.alive:
			_consume_enemy_turn(enemy.uid)
			continue
		if _controller.state.phase == Constants.PHASE_ENDED:
			break
		await _await_scene_timer(0.22)
		if not is_inside_tree():
			break
		_board.clear_overlays()
		_enemy_action_resolving = true
		var execution: Dictionary = _controller.execute_single_enemy(enemy)
		var events: Array[Dictionary] = execution.get("events", [])
		await _play_presentation_sequence(execution.get("presentation_state", _controller.state.clone()), events)
		_enemy_action_resolving = false
		_refresh()
		if not is_inside_tree():
			break
		await _await_scene_timer(0.35)
		if not is_inside_tree():
			break
		_consume_enemy_turn(enemy.uid)
		_refresh()
	var auto_enemy_execution: Dictionary = {}
	if is_inside_tree() and _controller.state != null and _controller.state.phase != Constants.PHASE_ENDED:
		var turn_start_execution: Dictionary = _controller.finish_enemy_phase()
		auto_enemy_execution = turn_start_execution.get("auto_enemy_execution", {})
		var turn_start_events: Array = turn_start_execution.get("events", [])
		if not turn_start_events.is_empty():
			await _play_presentation_sequence(
				turn_start_execution.get("presentation_state", _controller.state.clone()),
				turn_start_events
			)
	_enemy_phase_running = false
	_enemy_turn_queue.clear()
	if not is_inside_tree():
		return
	if _consume_pending_battle_end_if_any():
		return
	if not auto_enemy_execution.is_empty():
		_run_enemy_phase_async(auto_enemy_execution)
		return
	_message_label.text = _controller.get_action_hint()
	_refresh()

func _await_scene_timer(seconds: float) -> void:
	if not is_inside_tree():
		return
	await get_tree().create_timer(_scaled_anim_time(seconds)).timeout

func _exit_tree() -> void:
	_end_editor_session()
	_board_input.teardown()
	if _dmg_text != null and is_instance_valid(_dmg_text):
		_dmg_text.queue_free()
		_dmg_text = null

func _on_back_pressed() -> void:
	if _leave_confirm_dialog == null:
		_create_leave_confirm_dialog()
	if _leave_confirm_dialog == null:
		return
	_leave_confirm_dialog.popup_centered(Vector2i(420, 180))

func _on_menu_pressed() -> void:
	if _battle_menu == null:
		_create_battle_menu()
	if _battle_menu == null:
		return
	_dismiss_popup()
	_hide_preview_panel(true)
	_battle_menu.open_menu()

func _create_battle_menu() -> void:
	if _battle_menu != null:
		return
	var menu_script := _lazy_resources.system_pause_menu_script()
	if menu_script == null:
		return
	_battle_menu = menu_script.new()
	_battle_menu.name = "SystemPauseMenu"
	_battle_menu.configure_context("battle.menu.resume", "继续战斗")
	_battle_menu.save_and_exit_requested.connect(_on_battle_menu_save_and_exit_requested)
	_battle_menu.animation_speed_changed.connect(_apply_animation_speed)
	add_child(_battle_menu)

func _on_battle_menu_save_and_exit_requested() -> void:
	if _battle_menu != null:
		_battle_menu.close_menu()
	_return_to_menu_after_leave_cancel = true
	_on_back_pressed()

func _create_leave_confirm_dialog() -> void:
	if _leave_confirm_dialog != null:
		return
	var dialog_script := _lazy_resources.game_confirm_dialog_script()
	if dialog_script == null:
		return
	_leave_confirm_dialog = dialog_script.new()
	_leave_confirm_dialog.configure(
		tr("battle.leave.confirm.title"),
		tr("battle.leave.confirm.body"),
		tr("battle.leave.confirm.ok"),
		tr("battle.leave.confirm.cancel")
	)
	_leave_confirm_dialog.confirmed.connect(_confirm_leave_battle)
	_leave_confirm_dialog.cancelled.connect(_on_leave_confirm_cancelled)
	add_child(_leave_confirm_dialog)

func _on_leave_confirm_cancelled() -> void:
	if not _return_to_menu_after_leave_cancel:
		return
	_return_to_menu_after_leave_cancel = false
	if _battle_menu != null:
		_battle_menu.open_menu()

func _confirm_leave_battle() -> void:
	if _player_animating or _enemy_phase_running or _event_player.is_playing():
		_message_label.text = tr("battle.leave.busy")
		if _return_to_menu_after_leave_cancel and _battle_menu != null:
			_return_to_menu_after_leave_cancel = false
			_battle_menu.open_menu()
		return
	_return_to_menu_after_leave_cancel = false
	_dismiss_popup()
	var editor_battle := GameService.pending_battle_mode == "editor"
	GameService.pending_battle_mode = "normal"
	if not editor_battle and RunService.is_run_active():
		if _controller != null and _controller.state != null:
			RunService.capture_player_battle_state(_controller.state)
		if GameService.adventure_return and RunService.get_run_phase() != "BATTLE_REWARD":
			if GameService.pending_room_id.is_empty():
				GameService.pending_room_id = AdventureService.current_room_id()
			RunService.set_run_phase("BATTLE")
			RunService.set_pending_decision({
				"type": "battle",
				"room_id": GameService.pending_room_id,
				"room_type": AdventureService.pending_room_type,
				"encounter_id": _encounter_id,
			})
		RunService.save_run()
	GameService.reset_session_state()
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")

func _on_battle_ended(result: String) -> void:
	if _battle_end_applied:
		return
	if _event_player.is_playing() or _player_animating or _enemy_phase_running:
		_event_player.queue_battle_end(result)
		return
	_apply_battle_end(result)

func _on_console_submitted(command: String) -> void:
	if _enemy_phase_running or _player_animating:
		_console.append_log("> %s" % command, "#ffd166")
		_console.append_log("Editor CLI is unavailable during animations or enemy turns.", "#ff8a80")
		return
	_console.append_log("> %s" % command, "#ffd166")
	var result := _controller.run_editor_command(command)
	if result.get("ok", false):
		var message := str(result.get("message", "Command succeeded"))
		_console.append_log(message, "#8fd4a8")
		for warning in result.get("warnings", []):
			_console.append_log("Warning: %s" % str(warning), "#ffd166")
		for line in result.get("lines", []):
			_console.append_log("- %s" % str(line), "#c8cad4")
		if _controller.state != null:
			_message_label.text = message
	else:
		var reason := str(result.get("reason", "Command failed"))
		_console.append_log(reason, "#ff8a80")
		_message_label.text = reason

func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node("DataRegistry")

func _on_controller_state_changed() -> void:
	if _event_player.is_playing() or _enemy_action_resolving:
		return
	_refresh()

func _play_presentation_sequence(state_before: GameState, events: Array, economy_source: GameState = null) -> void:
	if not is_inside_tree():
		return
	if economy_source != null:
		_refresh_economy_chips()
	var pending_battle_end: String = await _event_player.play_sequence(
		state_before,
		_inspect_uid,
		_controller.state,
		events,
		economy_source
	)
	if not is_inside_tree():
		return
	_refresh()
	if not pending_battle_end.is_empty():
		_apply_battle_end(pending_battle_end)
		return
	_try_auto_skip_incapacitated_player_turn()

func _try_auto_skip_incapacitated_player_turn() -> void:
	if _enemy_phase_running or _controller == null or _controller.state == null:
		return
	if _controller.state.phase != Constants.PHASE_PLAYER:
		return
	var player: UnitState = _controller.state.get_player()
	var skip_status := StatusActionRules.turn_skip_status(player)
	if skip_status.is_empty():
		return
	var message_key := "status.frozen.skip" if skip_status == Constants.STATUS_FROZEN else "status.paralyzed.skip"
	var fallback := "冻结生效，跳过本回合" if skip_status == Constants.STATUS_FROZEN else "麻痹生效，跳过本回合"
	var translated := TranslationServer.translate(message_key)
	_message_label.text = fallback if translated == message_key else translated
	_on_end_turn_pressed()

func _refresh_economy_chips() -> void:
	var state := _view_state()
	if state == null:
		return
	_hud_presenter.refresh_economy_chips(state)

func _fit_status_panel() -> void:
	if not is_node_ready():
		return
	_hud_presenter.fit_status_panel(_panel_visible)

func _fit_status_panel_height() -> void:
	if not is_node_ready():
		return
	_hud_presenter.fit_status_panel_height()
	_layout_editor_ui()

func _set_inspect_target(cell: Vector2i) -> void:
	var state := _controller.state
	if state == null:
		return
	var unit := state.get_unit_at(cell)
	if unit != null and unit.alive:
		_inspect_uid = unit.uid
		_inspect_cell = Vector2i(-1, -1)
		_controller.selected_unit_uid = unit.uid
		return
	_inspect_uid = ""
	_inspect_cell = cell
	_controller.selected_unit_uid = ""

func _set_timeline_hover(uid: String) -> void:
	if _timeline_hover_uid == uid:
		return
	_timeline_hover_uid = uid
	_board.set_timeline_hover_unit(uid)
	_board.queue_redraw()

func _clear_timeline_hover(uid: String = "") -> void:
	if not uid.is_empty() and _timeline_hover_uid != uid:
		return
	_timeline_hover_uid = ""
	var hovered_unit := _view_state().get_unit_at(_hover_cell) if _hover_cell.x >= 0 else null
	_board.set_timeline_hover_unit(hovered_unit.uid if hovered_unit != null and hovered_unit.alive else "")
	_board.queue_redraw()


func _setup_held_gem_row() -> void:
	if _held_label == null or _held_gem_icon != null:
		return
	var vbox: Node = _held_label.get_parent()
	if vbox == null:
		return
	var row := HBoxContainer.new()
	row.name = "HeldRow"
	row.add_theme_constant_override("separation", 4)
	var idx := _held_label.get_index()
	vbox.remove_child(_held_label)
	vbox.add_child(row)
	vbox.move_child(row, idx)
	_held_gem_icon = TextureRect.new()
	_held_gem_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_held_gem_icon.custom_minimum_size = Vector2(14, 14)
	_held_gem_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_held_gem_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_held_gem_icon.visible = false
	row.add_child(_held_gem_icon)
	row.add_child(_held_label)

func _setup_overload_chip() -> void:
	if _turn_chips == null or _overload_chip != null:
		return
	_overload_chip = Label.new()
	_overload_chip.name = "OverloadChip"
	_overload_chip.add_theme_font_size_override("font_size", 12)
	_overload_chip.text = "过载 0"
	_turn_chips.add_child(_overload_chip)

func _clamp_preview_panel() -> void:
	var max_panel_h: float = size.y * 0.42
	if _preview_panel.size.y > max_panel_h:
		_preview_panel.size.y = max_panel_h
	var max_x: float = size.x - _preview_panel.size.x - 8.0
	var max_y: float = size.y - _preview_panel.size.y - 80.0
	_preview_panel.position.x = clampf(_preview_panel.position.x, 8.0, maxf(max_x, 8.0))
	_preview_panel.position.y = clampf(_preview_panel.position.y, 56.0, maxf(max_y, 56.0))

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and _editor_drag_active:
			_editor_drag_active = false
			_sync_editor_inspector("已取消拖拽")
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F9 and _console != null:
			_console.toggle()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE and _console != null and _console.is_open():
			_console.close()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE and _relic_detail_overlay != null:
			_dismiss_relic_detail_popup()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.echo:
		return
	if event.is_action_pressed("pause_menu"):
		if _leave_confirm_dialog != null and _leave_confirm_dialog.visible:
			return
		if _slot_popup != null and _slot_popup.is_showing():
			_dismiss_popup()
			get_viewport().set_input_as_handled()
			return
		if _battle_menu != null and _battle_menu.is_open():
			_battle_menu.handle_cancel()
		else:
			_on_menu_pressed()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if _relic_detail_overlay != null:
			_dismiss_relic_detail_popup()
			get_viewport().set_input_as_handled()
			return
		if _slot_popup != null and _slot_popup.is_showing():
			_dismiss_popup()
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return
	if not event.is_action_pressed("end_turn"):
		return
	if _battle_menu != null and _battle_menu.is_open():
		return
	if _leave_confirm_dialog != null and _leave_confirm_dialog.visible:
		return
	if _console != null and _console.is_open():
		return
	if _slot_popup != null and _slot_popup.is_showing():
		return
	if _relic_detail_overlay != null or _battle_end_applied:
		return
	if _tutorial_overlay != null and is_instance_valid(_tutorial_overlay):
		return
	if _player_animating or _enemy_phase_running or _event_player.is_playing():
		return
	if _end_turn_btn == null or _end_turn_btn.disabled:
		return
	if _controller.state == null or _controller.state.phase != Constants.PHASE_PLAYER:
		return
	_on_end_turn_pressed()
	get_viewport().set_input_as_handled()

func _on_anim_move(unit_uid: String, from_pos: Vector2i, to_pos: Vector2i) -> void:
	_board.animate_move(unit_uid, from_pos, to_pos)

func _on_anim_damage(grid: Vector2i, damage: int, is_crit: bool) -> void:
	_board.play_damage_effect(grid, damage, is_crit)

func _on_anim_gem_flash(grid: Vector2i, gem_color: Color) -> void:
	_board.play_gem_flash(grid, gem_color)

func _on_anim_gem_hooked(gem_uid: String, from_pos: Vector2i) -> void:
	if _controller.state == null:
		return
	var gem: GemState = _controller.state.gems.get(gem_uid, null)
	if gem != null:
		_board.start_hooked_gem_extract(from_pos, gem)

func _spawn_damage_text(grid: Vector2i, value: int, is_crit: bool, reason: String, shield_only: bool = false) -> void:
	if _dmg_text == null or value <= 0:
		return
	var board_global: Vector2 = _board.global_position
	var cell_screen: Vector2 = _board.grid_to_screen(grid)
	var world_pos: Vector2 = board_global + cell_screen + Vector2(0, -24)
	var dmg_type: String
	if shield_only:
		dmg_type = DamageTextManagerScript.DMG_ARMOR
	elif is_crit:
		dmg_type = DamageTextManagerScript.DMG_CRIT
	elif reason == "spike" or reason == "spike_enter" or reason == "spike_collision":
		dmg_type = DamageTextManagerScript.DMG_FIRE
	elif reason == "poison":
		dmg_type = DamageTextManagerScript.DMG_POISON
	elif reason == "lawless_attack":
		dmg_type = DamageTextManagerScript.DMG_TRUE
	else:
		dmg_type = DamageTextManagerScript.DMG_NORMAL
	_dmg_text.spawn(world_pos, value, dmg_type)

func set_animation_speed_scale(speed_scale: float) -> void:
	_animation_speed_scale = maxf(speed_scale, 0.05)
	_apply_animation_speed()

func _apply_animation_speed() -> void:
	_animation_speed_scale = SettingsService.get_animation_speed_scale()
	if _board != null:
		_board.set_animation_speed_scale(_animation_speed_scale)

func _scaled_anim_time(base_duration: float) -> float:
	return base_duration / _animation_speed_scale

func _consume_enemy_turn(enemy_uid: String) -> void:
	var idx: int = _enemy_turn_queue.find(enemy_uid)
	if idx >= 0:
		_enemy_turn_queue.remove_at(idx)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		call_deferred("_refresh_relic_bar_after_resize")

func _refresh_relic_bar_after_resize() -> void:
	if not is_node_ready():
		return
	if _hud_presenter != null:
		_hud_presenter._refresh_relic_bar(_relic_bar_available_height())
	_layout_editor_ui()

func _wire_hover_interactions() -> void:
	for button in [_move_btn, _attack_btn, _extract_btn, _insert_btn, _hook_insert_btn, _end_turn_btn, _menu_btn, _toggle_panel_btn]:
		if button == null:
			continue
		button.focus_mode = Control.FOCUS_NONE

func _setup_relic_bar() -> void:
	if _relic_bar_scroll != null:
		return
	_relic_bar_root = Control.new()
	_relic_bar_root.name = "RelicBarRoot"
	_relic_bar_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_relic_bar_root.visible = false
	$HudLayer.add_child(_relic_bar_root)

	var scroll := ScrollContainer.new()
	scroll.name = "RelicBarScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.visible = false
	_relic_bar_root.add_child(scroll)

	var relic_grid := GridContainer.new()
	relic_grid.name = "RelicBarGrid"
	relic_grid.columns = 1
	relic_grid.add_theme_constant_override("h_separation", 4)
	relic_grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(relic_grid)
	_relic_bar_scroll = scroll
	_relic_bar_vbox = relic_grid

func _flat_style(bg: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(0)
	return box
