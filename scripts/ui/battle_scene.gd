extends Control

const SlotPopup = preload("res://scripts/ui/slot_popup.gd")
const BattleUiTheme = preload("res://scripts/ui/battle_ui_theme.gd")
const StatusUi = preload("res://scripts/ui/status_ui.gd")
const StatusIcons = preload("res://scripts/ui/status_icons.gd")
const EditorConsoleScene = preload("res://scenes/ui/editor_console.tscn")
const DamageTextManagerScript = preload("res://scripts/ui/damage_text_manager.gd")
const BattleEventPlayerScript = preload("res://scripts/ui/battle_event_player.gd")
const BoardInputAdapterScript = preload("res://scripts/ui/board_input_adapter.gd")
const BattleHudPresenterScript = preload("res://scripts/ui/battle_hud_presenter.gd")

var _dmg_text: Node = null

@onready var _board: Control = $BoardLayer/IsometricBoard
@onready var _status_panel: PanelContainer = $HudLayer/StatusPanel
@onready var _status_vbox: VBoxContainer = $HudLayer/StatusPanel/VBox
@onready var _header_row: HBoxContainer = $HudLayer/StatusPanel/VBox/HeaderRow
@onready var _turn_chips: HBoxContainer = $HudLayer/StatusPanel/VBox/TurnChips
@onready var _portrait: TextureRect = $HudLayer/StatusPanel/VBox/HeaderRow/Portrait
@onready var _inspect_name: Label = $HudLayer/StatusPanel/VBox/HeaderRow/Info/Name
@onready var _info_col: VBoxContainer = $HudLayer/StatusPanel/VBox/HeaderRow/Info
@onready var _shield_row: HBoxContainer = $HudLayer/StatusPanel/VBox/HeaderRow/Info/ShieldRow
@onready var _shield_icon: TextureRect = $HudLayer/StatusPanel/VBox/HeaderRow/Info/ShieldRow/ShieldIcon
@onready var _shield_bar: ProgressBar = $HudLayer/StatusPanel/VBox/HeaderRow/Info/ShieldRow/ShieldBar
@onready var _shield_text: Label = $HudLayer/StatusPanel/VBox/HeaderRow/Info/ShieldRow/ShieldText
@onready var _hp_bar: ProgressBar = $HudLayer/StatusPanel/VBox/HeaderRow/Info/HpBar
@onready var _hp_text: Label = $HudLayer/StatusPanel/VBox/HeaderRow/Info/HpText
@onready var _inspect_status_row: HBoxContainer = $HudLayer/StatusPanel/VBox/HeaderRow/Info/StatusClip/StatusRow
@onready var _inspect_stats: Label = $HudLayer/StatusPanel/VBox/StatsLabel
@onready var _slot_box: HBoxContainer = $HudLayer/StatusPanel/VBox/SlotClip/SlotBox
@onready var _status_clip: Control = $HudLayer/StatusPanel/VBox/HeaderRow/Info/StatusClip
@onready var _slot_clip: Control = $HudLayer/StatusPanel/VBox/SlotClip
@onready var _turn_label: Label = $HudLayer/StatusPanel/VBox/TurnChips/TurnLabel
@onready var _move_chip: Label = $HudLayer/StatusPanel/VBox/TurnChips/MoveChip
@onready var _act_chip: Label = $HudLayer/StatusPanel/VBox/TurnChips/ActChip
@onready var _held_label: Label = $HudLayer/StatusPanel/VBox/HeldLabel
@onready var _hint_label: Label = $HudLayer/StatusPanel/VBox/HintLabel
@onready var _toggle_panel_btn: Button = $HudLayer/TogglePanelBtn
@onready var _preview_panel: PanelContainer = $HudLayer/PreviewPanel
@onready var _preview_title: Label = $HudLayer/PreviewPanel/VBox/Title
@onready var _preview_body: RichTextLabel = $HudLayer/PreviewPanel/VBox/Body
@onready var _top_bar: PanelContainer = $HudLayer/TopBar
@onready var _phase_badge: Label = $HudLayer/TopBar/HBox/PhaseBadge
@onready var _message_label: Label = $HudLayer/TopBar/HBox/Message
@onready var _queue_title: Label = $HudLayer/TurnQueuePanel/VBox/Title
@onready var _queue_row: HBoxContainer = $HudLayer/TurnQueuePanel/VBox/QueueRow
@onready var _queue_hint: Label = $HudLayer/TurnQueuePanel/VBox/Hint
@onready var _bottom_dock: PanelContainer = $HudLayer/BottomDock
@onready var _move_btn: Button = $HudLayer/BottomDock/BottomBar/MoveGroup/MoveBtn
@onready var _attack_btn: Button = $HudLayer/BottomDock/BottomBar/CombatGroup/AttackBtn
@onready var _extract_btn: Button = $HudLayer/BottomDock/BottomBar/GemGroup/ExtractBtn
@onready var _insert_btn: Button = $HudLayer/BottomDock/BottomBar/GemGroup/InsertBtn
@onready var _end_turn_btn: Button = $HudLayer/BottomDock/BottomBar/TurnGroup/EndTurnBtn

var _controller: BattleController = BattleController.new()
var _event_player = BattleEventPlayerScript.new()
var _board_input = BoardInputAdapterScript.new()
var _hud_presenter = BattleHudPresenterScript.new()
var _encounter_id: String = "tutorial_001"

var _inspect_uid: String = ""
var _hover_cell: Vector2i = Vector2i(-1, -1)
var _timeline_hover_uid: String = ""
var _panel_visible: bool = true
var _enemy_phase_running: bool = false
var _player_animating: bool = false
var _animation_speed_scale: float = 1.0
var _enemy_turn_queue: Array[String] = []
var _slot_popup: Control = null
var _console_layer: CanvasLayer = null
var _console: Control = null
var _preview_panel_tween: Tween = null
var _preview_visible_target: bool = false
var _preview_fade_serial: int = 0
var _relic_reward_overlay: Node = null
var _relic_detail_overlay: Node = null
var _held_gem_icon: TextureRect = null
var _overload_chip: Label = null
var _relic_bar_scroll: ScrollContainer = null
var _relic_bar_vbox: VBoxContainer = null
var _tracked_player_uid: String = ""

## 遭遇 room_type → 遗物来源 key（DataRegistry 池筛选用）
const _ENCOUNTER_RELIC_SOURCE := {
	"NORMAL_COMBAT": "normal_chest",
	"ELITE_COMBAT": "elite_combat",
	"END": "large_chest",
}
func _ready() -> void:
	_controller.state_changed.connect(_on_controller_state_changed)
	_controller.battle_ended.connect(_on_battle_ended)
	_controller.anim_move.connect(_on_anim_move)
	_controller.anim_damage.connect(_on_anim_damage)
	_controller.anim_gem_flash.connect(_on_anim_gem_flash)
	_board_input.setup(_board)
	_board.cell_clicked.connect(_on_cell_clicked)
	_board.cell_hovered.connect(_on_cell_hovered)
	_board.unit_slot_clicked.connect(_on_board_unit_slot_selected)
	_apply_ui_theme()
	_preview_panel.visible = false
	_preview_panel.modulate.a = 0.0
	call_deferred("_fit_status_panel")
	call_deferred("_fit_status_panel_height")
	call_deferred("_setup_held_gem_row")
	_setup_overload_chip()
	_wire_hover_interactions()
	_create_slot_popup()
	_create_damage_text_manager()
	_create_level_console()
	_event_player.setup(
		self,
		_board,
		_controller,
		Callable(self, "_spawn_damage_text"),
		Callable(self, "_scaled_anim_time")
	)
	_setup_relic_bar()
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
		"shield_row": _shield_row,
		"shield_bar": _shield_bar,
		"shield_text": _shield_text,
		"hp_bar": _hp_bar,
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
		"end_turn_btn": _end_turn_btn,
		"toggle_panel_btn": _toggle_panel_btn,
		"relic_bar_scroll": _relic_bar_scroll,
		"relic_bar_vbox": _relic_bar_vbox,
		"show_relic_detail_cb": Callable(self, "_show_relic_detail_popup"),
		"select_unit_cb": Callable(self, "_select_unit"),
		"set_timeline_hover_cb": Callable(self, "_set_timeline_hover"),
		"clear_timeline_hover_cb": Callable(self, "_clear_timeline_hover"),
	})
	_apply_animation_speed()
	_start_battle(GameService.pending_encounter_id)


func _apply_ui_theme() -> void:
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_status_panel.add_theme_stylebox_override("panel", BattleUiTheme.panel_style(BattleUiTheme.BORDER))
	_status_panel.clip_contents = true
	_held_label.clip_contents = true
	_held_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_top_bar.add_theme_stylebox_override("panel", BattleUiTheme.panel_style(BattleUiTheme.BORDER_ACCENT.darkened(0.2)))
	_bottom_dock.add_theme_stylebox_override("panel", BattleUiTheme.dock_style())
	$HudLayer/TurnQueuePanel.add_theme_stylebox_override("panel", BattleUiTheme.panel_style(BattleUiTheme.PHASE_PLAYER.darkened(0.35)))
	_preview_panel.add_theme_stylebox_override("panel", BattleUiTheme.tooltip_style())
	_inspect_name.add_theme_color_override("font_color", BattleUiTheme.TEXT)
	_inspect_stats.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
	_message_label.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	_hint_label.add_theme_color_override("font_color", BattleUiTheme.TEXT_HINT)
	_queue_title.add_theme_color_override("font_color", BattleUiTheme.TEXT)
	_hp_bar.add_theme_stylebox_override("background", _flat_style(Color(0.12, 0.13, 0.18), Color(0.22, 0.24, 0.3)))
	var shield_styles := BattleUiTheme.shield_bar_styles()
	_shield_bar.add_theme_stylebox_override("background", shield_styles.background)
	_shield_bar.add_theme_stylebox_override("fill", shield_styles.fill)
	_shield_icon.texture = StatusIcons.get_icon(Constants.STATUS_ARMOR)
	_shield_text.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
	BattleUiTheme.apply_button(_toggle_panel_btn, "ghost")


func _create_slot_popup() -> void:
	_slot_popup = SlotPopup.new()
	$HudLayer.add_child(_slot_popup)
	_slot_popup.slot_selected.connect(_on_popup_slot_selected)
	_slot_popup.tile_slot_selected.connect(_on_popup_tile_slot_selected)
	_slot_popup.cancelled.connect(_on_popup_cancelled)


func _create_damage_text_manager() -> void:
	_dmg_text = DamageTextManagerScript.new()
	get_tree().root.add_child.call_deferred(_dmg_text)


func _create_level_console() -> void:
	_console_layer = CanvasLayer.new()
	_console_layer.layer = 64
	add_child(_console_layer)
	_console = EditorConsoleScene.instantiate()
	_console.command_submitted.connect(_on_console_submitted)
	_console_layer.add_child(_console)


func setup(encounter_id: String) -> void:
	_encounter_id = encounter_id
	if is_node_ready():
		_start_battle(encounter_id)


func _start_battle(encounter_id: String) -> void:
	_encounter_id = encounter_id
	_board.clear_gem_visuals()
	_tracked_player_uid = ""
	_controller.start_encounter(encounter_id, 0, GameService.pending_room_id)
	_mark_visible_enemies_seen()
	_inspect_uid = _controller.selected_unit_uid
	_controller.select_action("")
	_refresh()
	_board.init_unit_orientations()
	if encounter_id == "tutorial_001" and bool(SettingsService.get_value("show_tutorial")):
		_show_tutorial_intro()


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
	_refresh()
	_sync_unit_slot_panels()


func _on_cell_clicked(cell: Vector2i) -> void:
	if _player_animating:
		return
	var state := _controller.state
	if state == null:
		return
	var unit := state.get_unit_at(cell)
	var action := _controller.selected_action
	if action.is_empty():
		if unit != null and unit.alive:
			_select_unit(unit.uid)
		else:
			_dismiss_popup()
			_refresh()
		return
	if _enemy_phase_running or state.phase != Constants.PHASE_PLAYER:
		if unit != null and unit.alive:
			_select_unit(unit.uid)
		else:
			_refresh()
		return
	match action:
		Constants.ACTION_MOVE:
			_dismiss_popup()
			var move_result := _controller.try_move(cell)
			if move_result.get("ok", false):
				_player_animating = true
				_board.set_highlights({})
				var events: Array = move_result.get("move_events", [])
				await _play_presentation_sequence(
					move_result.get("presentation_state", _controller.state.clone()),
					events,
					_controller.state
				)
				_player_animating = false
			else:
				_show_result(move_result)
		Constants.ACTION_ATTACK:
			_dismiss_popup()
			if unit != null:
				_inspect_uid = unit.uid
			_player_animating = true
			var atk_res := _controller.try_attack_cell(cell)
			_show_result(atk_res)
			if atk_res.get("ok", false):
				var from_pos: Vector2i = atk_res.get("from_pos", Vector2i(-1, -1))
				var to_pos: Vector2i = atk_res.get("to_pos", cell)
				var player := _controller.state.get_player()
				if player != null:
					_board.start_strike_effect(player.uid, to_pos)
				var attack_events: Array = atk_res.get("attack_events", [])
				var has_projectile := false
				for ev in attack_events:
					if str(ev.get("type", "")) == "projectile":
						has_projectile = true
						break
				if not has_projectile and from_pos.x >= 0:
					await _event_player.play_prefire_projectile(from_pos, to_pos)
				await _play_presentation_sequence(
					atk_res.get("presentation_state", _controller.state.clone()),
					attack_events,
					_controller.state
				)
				_player_animating = false
			else:
				_player_animating = false
		Constants.ACTION_EXTRACT, Constants.ACTION_INSERT:
			var targets: Array = _controller.get_highlights().get("targets", [])
			if cell in targets:
				if unit != null and unit.alive:
					_inspect_uid = unit.uid
					_sync_unit_slot_panels()
				else:
					var tile: TileState = _controller.state.get_tile(cell)
					if tile != null and tile.has_slots():
						_show_tile_slot_popup(tile, cell)
					else:
						_dismiss_popup()
			else:
				_dismiss_popup()
	_refresh()


func _on_cell_hovered(cell: Vector2i, valid: bool) -> void:
	_hover_cell = cell if valid else Vector2i(-1, -1)
	if _controller == null:
		return
	if not valid:
		_hide_preview_panel()
		_board.set_hover(Vector2i(-1, -1))
		if _timeline_hover_uid.is_empty():
			_board.set_timeline_hover_unit("")
		_board.set_highlights(_controller.get_highlights())
		return
	_board.set_hover(cell)
	_board.set_highlights(_controller.get_highlights(_hover_cell))
	if _timeline_hover_uid.is_empty():
		var hovered_state := _view_state()
		var hovered_unit := hovered_state.get_unit_at(cell) if hovered_state != null else null
		_board.set_timeline_hover_unit(hovered_unit.uid if hovered_unit != null and hovered_unit.alive else "")
	var preview: Dictionary = _controller.get_cell_preview(cell)
	_preview_title.text = preview.get("title", "")
	_preview_body.text = _format_preview_body(preview.get("body", ""))
	var mouse: Vector2 = get_viewport().get_mouse_position()
	_show_preview_panel(mouse)


func _show_preview_panel(mouse: Vector2) -> void:
	_preview_panel.position = mouse + Vector2(18, 18)
	_clamp_preview_panel()
	_set_preview_panel_visible(true)


func _hide_preview_panel() -> void:
	_set_preview_panel_visible(false)


func _set_preview_panel_visible(shown: bool) -> void:
	if _preview_visible_target == shown:
		if shown and not _preview_panel.visible:
			_preview_panel.visible = true
		return
	_preview_visible_target = shown
	_preview_fade_serial += 1
	var fade_serial := _preview_fade_serial
	if _preview_panel_tween != null:
		_preview_panel_tween.kill()
	_preview_panel_tween = create_tween()
	_preview_panel_tween.set_trans(Tween.TRANS_QUAD)
	_preview_panel_tween.set_ease(Tween.EASE_OUT)
	if shown:
		_preview_panel.visible = true
		_preview_panel_tween.tween_property(_preview_panel, "modulate:a", 1.0, 0.12)
	else:
		_preview_panel_tween.tween_property(_preview_panel, "modulate:a", 0.0, 0.24)
		_preview_panel_tween.tween_callback(_finalize_preview_panel_hide.bind(fade_serial))


func _finalize_preview_panel_hide(fade_serial: int) -> void:
	if fade_serial != _preview_fade_serial or _preview_visible_target:
		return
	_preview_panel.visible = false


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


func _show_tile_slot_popup(tile: TileState, cell: Vector2i) -> void:
	var screen_pos: Vector2 = _board.grid_to_screen(cell)
	var board_global: Vector2 = _board.global_position
	var popup_pos: Vector2 = board_global + screen_pos + Vector2(0, -72)
	_slot_popup.show_for_tile(tile, _controller.state, _controller.selected_action, popup_pos, _controller.check_tile_slot_action)


func _sync_unit_slot_panels() -> void:
	if _controller == null or _board == null:
		return
	var action := _controller.selected_action
	if action in [Constants.ACTION_EXTRACT, Constants.ACTION_INSERT]:
		_board.configure_unit_slot_panels(action, _controller.check_slot_action)
	else:
		_board.clear_unit_slot_panels()


func _on_board_unit_slot_selected(unit_uid: String, slot_index: int) -> void:
	if _player_animating or _enemy_phase_running:
		return
	_on_popup_slot_selected(unit_uid, slot_index)


func _on_popup_tile_slot_selected(tile_pos: Vector2i, slot_index: int) -> void:
	var action := _controller.selected_action
	var result: Dictionary
	match action:
		Constants.ACTION_EXTRACT:
			result = _controller.try_extract_tile(tile_pos, slot_index)
		Constants.ACTION_INSERT:
			result = _controller.try_insert_tile(tile_pos, slot_index)
		_:
			return
	_dismiss_popup()
	_show_result(result)
	if result.get("ok", false):
		match action:
			Constants.ACTION_EXTRACT:
				_begin_held_gem_extract(tile_pos, result)
				_controller.select_action(Constants.ACTION_INSERT)
				_message_label.text = "已从地块拔出，选择槽位嵌入"
			Constants.ACTION_INSERT:
				_begin_held_gem_insert(tile_pos, result)
				if bool(result.get("overload_forced", false)):
					_message_label.text = "过载嵌入：已压入地块，结束回合后异变生效"
				else:
					_message_label.text = "已嵌入地块" if str(result.get("swapped_gem_uid", "")).is_empty() else "已替换，原宝石回到手中"
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
				else:
					_message_label.text = "已嵌入" if str(result.get("swapped_gem_uid", "")).is_empty() else "已替换，原宝石回到手中"
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
	_controller.begin_enemy_phase()
	# 若分身切换后仍在玩家回合，刷新 UI 继续操控下一个分身
	if _controller.state != null and _controller.state.phase == Constants.PHASE_PLAYER:
		_message_label.text = _controller.get_action_hint()
		_refresh()
		return
	_run_enemy_phase_async()


func _run_enemy_phase_async() -> void:
	_enemy_phase_running = true
	# begin_enemy_phase 已在 _on_end_turn_pressed 中调用，此处不重复调用
	_message_label.text = "敌方行动中..."
	_refresh()
	var enemies := _controller.get_sorted_enemies()
	_enemy_turn_queue.clear()
	for enemy in enemies:
		_enemy_turn_queue.append(enemy.uid)
	_refresh()
	for enemy in enemies:
		_refresh()
		if not enemy.alive:
			_consume_enemy_turn(enemy.uid)
			continue
		if _controller.state.phase == Constants.PHASE_ENDED:
			break
		await get_tree().create_timer(_scaled_anim_time(0.22)).timeout
		var execution: Dictionary = _controller.execute_single_enemy(enemy)
		var events: Array[Dictionary] = execution.get("events", [])
		await _play_presentation_sequence(execution.get("presentation_state", _controller.state.clone()), events)
		await get_tree().create_timer(_scaled_anim_time(0.35)).timeout
		_consume_enemy_turn(enemy.uid)
		_refresh()
	if _controller.state.phase != Constants.PHASE_ENDED:
		_controller.finish_enemy_phase()
	_enemy_phase_running = false
	_enemy_turn_queue.clear()
	_message_label.text = _controller.get_action_hint()
	_refresh()


func _exit_tree() -> void:
	_board_input.teardown()
	if _dmg_text != null and is_instance_valid(_dmg_text):
		_dmg_text.queue_free()
		_dmg_text = null


func _on_back_pressed() -> void:
	if GameService.adventure_return:
		GameService.adventure_return = false
		get_tree().change_scene_to_file("res://scenes/map/adventure_map.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/main/main.tscn")


func _on_battle_ended(result: String) -> void:
	if _event_player.is_playing() or _player_animating or _enemy_phase_running:
		_event_player.queue_battle_end(result)
		return
	_apply_battle_end(result)


func _show_result(result: Dictionary) -> void:
	if result.get("ok", false):
		_message_label.text = _controller.get_action_hint()
	else:
		var reason: String = result.get("reason", "")
		if reason.is_empty():
			reason = "无法执行"
		push_warning("BattleScene: action failed — %s" % reason)
		_message_label.text = reason


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


func _view_state() -> GameState:
	return _event_player.get_view_state(_controller.state)


func _on_controller_state_changed() -> void:
	if _event_player.is_playing():
		return
	_refresh()


func _play_presentation_sequence(state_before: GameState, events: Array, economy_source: GameState = null) -> void:
	if economy_source != null:
		_refresh_economy_chips()
	var pending_battle_end: String = await _event_player.play_sequence(
		state_before,
		_inspect_uid,
		_controller.state,
		events,
		economy_source
	)
	_refresh()
	if not pending_battle_end.is_empty():
		_apply_battle_end(pending_battle_end)


func _refresh_economy_chips() -> void:
	var state := _view_state()
	if state == null:
		return
	_hud_presenter.refresh_economy_chips(state)


func _apply_battle_end(result: String) -> void:
	_message_label.text = "战斗结束 — %s" % ("胜利" if result == "win" else "失败")
	_hint_label.text = ""
	var end_turn := _controller.state.turn_index if _controller.state != null else 0
	_phase_badge.text = "结束 · 第%d回合" % end_turn
	_phase_badge.add_theme_color_override("font_color", BattleUiTheme.PHASE_END)
	if result == "win" and RunService.is_run_active():
		var source: String = str(_ENCOUNTER_RELIC_SOURCE.get(
			AdventureService.pending_room_type.to_upper(), "normal_chest"
		))
		var room_id := GameService.pending_room_id
		var gem_offer: Array[String] = RunService.get_or_roll_gem_offer(room_id, source, 3)
		var relic_offer: Array[String] = RunService.get_or_roll_relic_offer(room_id, source, 3)
		var has_gems := gem_offer.any(func(gid: String) -> bool: return not gid.is_empty())
		var has_relics := not relic_offer.is_empty() and not relic_offer.all(
			func(rid: String) -> bool: return rid == "relic_placeholder"
		)
		if has_gems:
			_show_gem_reward(gem_offer, relic_offer, result)
			return
		if has_relics:
			_show_relic_reward(relic_offer, result)
			return
	_finish_battle_and_navigate(result)


func _placeholder_relic_offer() -> Array[String]:
	var offer: Array[String] = []
	offer.append("relic_placeholder")
	return offer


func _show_gem_reward(gem_offer: Array[String], relic_offer: Array[String], battle_result: String) -> void:
	var overlay := _build_gem_overlay(gem_offer, relic_offer, battle_result)
	_relic_reward_overlay = overlay
	add_child(overlay)


func _build_gem_overlay(gem_offer: Array[String], relic_offer: Array[String], battle_result: String) -> Node:
	var canvas := CanvasLayer.new()
	canvas.layer = 80

	var root_ctrl := Control.new()
	root_ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(root_ctrl)

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08, 0.82)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_ctrl.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_ctrl.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "选择宝石"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var cards_row := HBoxContainer.new()
	cards_row.add_theme_constant_override("separation", 20)
	vbox.add_child(cards_row)

	for gem_id in gem_offer:
		if gem_id.is_empty():
			continue
		var card := _build_gem_card(gem_id, battle_result, relic_offer, canvas)
		cards_row.add_child(card)

	var skip_btn := Button.new()
	skip_btn.text = "跳过"
	skip_btn.custom_minimum_size = Vector2(140, 40)
	BattleUiTheme.apply_button(skip_btn, "ghost")
	skip_btn.pressed.connect(func() -> void:
		_on_gem_chosen("", battle_result, relic_offer, canvas)
	)
	vbox.add_child(skip_btn)

	return canvas


func _build_gem_card(gem_id: String, battle_result: String, relic_offer: Array[String], canvas: Node) -> Control:
	var panel := PanelContainer.new()
	var rarity: String = DataRegistry.get_gem_rarity(gem_id)
	var rarity_color: Color = _hud_presenter.rarity_color(rarity)
	panel.add_theme_stylebox_override("panel", BattleUiTheme.panel_style(rarity_color))
	panel.custom_minimum_size = Vector2(160, 200)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)

	var dummy_gem := GemState.new()
	dummy_gem.gem_id = gem_id
	dummy_gem.uid = "_preview_%s" % gem_id
	var icon_tex := UnitLooks.get_gem_texture(dummy_gem)
	if icon_tex != null:
		var icon := TextureRect.new()
		icon.texture = icon_tex
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.self_modulate = UnitLooks.gem_sprite_modulate(dummy_gem)
		icon.custom_minimum_size = Vector2(48, 48)
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		vb.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.text = DataRegistry.get_gem_display_name(dummy_gem)
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color", rarity_color)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(name_lbl)

	var tag_str := str(DataRegistry.get_gem_tag(gem_id))
	var pool_tier := int(DataRegistry.get_gem_pool_tier(gem_id))
	var tag_key := "gem.%s.symbol" % tag_str
	var tag_sym: String = TranslationServer.translate(tag_key)
	if tag_sym == tag_key:
		tag_sym = tag_str
	var rarity_name: String = _rarity_display_name(rarity)
	var meta_lbl := Label.new()
	meta_lbl.text = "[%s] %s  T%d" % [rarity_name, tag_sym, pool_tier]
	meta_lbl.add_theme_font_size_override("font_size", 11)
	meta_lbl.add_theme_color_override("font_color", rarity_color.darkened(0.15))
	meta_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(meta_lbl)

	var pick_btn := Button.new()
	pick_btn.text = "选择"
	pick_btn.custom_minimum_size = Vector2(0, 40)
	BattleUiTheme.apply_button(pick_btn, "end")
	pick_btn.pressed.connect(func() -> void:
		_on_gem_chosen(gem_id, battle_result, relic_offer, canvas)
	)
	vb.add_child(pick_btn)

	return panel


func _on_gem_chosen(gem_id: String, battle_result: String, relic_offer: Array[String], canvas: Node) -> void:
	if not gem_id.is_empty():
		RunService.acquire_gem(gem_id)
	if canvas != null and is_instance_valid(canvas):
		canvas.queue_free()
	_relic_reward_overlay = null
	var has_relics := not relic_offer.is_empty() and not relic_offer.all(
		func(rid: String) -> bool: return rid == "relic_placeholder"
	)
	if has_relics:
		_show_relic_reward(relic_offer, battle_result)
	else:
		_finish_battle_and_navigate(battle_result)


func _show_relic_reward(offer: Array[String], battle_result: String) -> void:
	var overlay := _build_relic_overlay(offer, battle_result)
	_relic_reward_overlay = overlay
	add_child(overlay)


func _build_relic_overlay(offer: Array[String], battle_result: String) -> Node:
	var canvas := CanvasLayer.new()
	canvas.layer = 80

	var root_ctrl := Control.new()
	root_ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(root_ctrl)

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08, 0.82)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_ctrl.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_ctrl.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	center.add_child(vbox)

	var is_no_relics := offer.size() == 1 and offer[0] == "relic_placeholder"

	var title := Label.new()
	title.text = "无可选遗物" if is_no_relics else "选择遗物"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED if is_no_relics else BattleUiTheme.TEXT_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var cards_row := HBoxContainer.new()
	cards_row.add_theme_constant_override("separation", 20)
	vbox.add_child(cards_row)

	for relic_id in offer:
		var def: Dictionary = DataRegistry.get_relic_def(relic_id)
		var rarity: String = DataRegistry.get_relic_rarity(relic_id)
		var card := _build_relic_card(relic_id, def, rarity, battle_result)
		cards_row.add_child(card)

	var skip_btn := Button.new()
	skip_btn.text = "跳过"
	skip_btn.custom_minimum_size = Vector2(140, 40)
	BattleUiTheme.apply_button(skip_btn, "ghost")
	skip_btn.pressed.connect(func() -> void:
		_on_relic_chosen("", battle_result)
	)
	vbox.add_child(skip_btn)

	return canvas


func _build_relic_card(relic_id: String, def: Dictionary, rarity: String, battle_result: String) -> Control:
	var is_placeholder := bool(def.get("placeholder", false))
	var panel := PanelContainer.new()
	var rarity_color: Color = BattleUiTheme.TEXT_MUTED if is_placeholder else _hud_presenter.rarity_color(rarity)
	panel.add_theme_stylebox_override("panel", BattleUiTheme.panel_style(rarity_color))
	panel.custom_minimum_size = Vector2(180, 220)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)

	var icon_tex := UnitLooks.get_relic_texture(relic_id)
	if icon_tex != null:
		var icon := TextureRect.new()
		icon.texture = icon_tex
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.custom_minimum_size = Vector2(48, 48)
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		vb.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.text = str(def.get("name", relic_id))
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", rarity_color)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(name_lbl)

	var rarity_lbl := Label.new()
	rarity_lbl.text = "[%s]" % _rarity_display_name(rarity)
	rarity_lbl.add_theme_font_size_override("font_size", 11)
	rarity_lbl.add_theme_color_override("font_color", rarity_color.darkened(0.15))
	rarity_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(rarity_lbl)

	var desc_lbl := RichTextLabel.new()
	var desc_text: String = _hud_presenter.relic_desc_text(def)
	desc_lbl.bbcode_enabled = false
	desc_lbl.text = desc_text
	desc_lbl.add_theme_font_size_override("normal_font_size", 12)
	desc_lbl.add_theme_color_override("default_color", BattleUiTheme.TEXT_HINT)
	desc_lbl.custom_minimum_size = Vector2(160, 80)
	desc_lbl.fit_content = true
	vb.add_child(desc_lbl)

	var pick_btn := Button.new()
	pick_btn.text = "收下" if is_placeholder else "选择"
	pick_btn.custom_minimum_size = Vector2(0, 40)
	BattleUiTheme.apply_button(pick_btn, "ghost" if is_placeholder else "end")
	pick_btn.pressed.connect(func() -> void:
		_on_relic_chosen("" if is_placeholder else relic_id, battle_result)
	)
	vb.add_child(pick_btn)

	return panel


func _rarity_display_name(rarity: String) -> String:
	match rarity:
		"common": return "普通"
		"rare": return "稀有"
		"epic": return "史诗"
		"legendary": return "传说"
		"boss": return "首领"
		_: return rarity


func _on_relic_chosen(relic_id: String, battle_result: String) -> void:
	if not relic_id.is_empty():
		RunService.acquire_relic(relic_id)
	if GameService.adventure_return and RunService.is_run_active():
		RunService.mark_room_resolved(GameService.pending_room_id, {
			"room_id": GameService.pending_room_id,
			"room_type": AdventureService.pending_room_type,
			"battle_result": battle_result,
			"summary": "战斗房间已结算。",
			"relic_id": relic_id,
		})
	if _relic_reward_overlay != null:
		_relic_reward_overlay.queue_free()
		_relic_reward_overlay = null
	_finish_battle_and_navigate(battle_result)


func _finish_battle_and_navigate(result: String) -> void:
	_record_enemy_codex_progress()
	if result == "win" and _controller.state != null:
		RunService.capture_player_battle_state(_controller.state)
	elif result != "win" and RunService.is_run_active():
		RunService.end_run()
	GameService.finish_battle(result, _encounter_id, _controller.state.turn_index if _controller.state != null else 0)
	if GameService.adventure_return:
		GameService.adventure_return = false
		if result == "win" and RunService.is_run_active():
			AdventureService.finish_room_and_return()
		else:
			AdventureService.reset_local_state()
			get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/main/main.tscn")


func _on_toggle_panel() -> void:
	_panel_visible = not _panel_visible
	_status_panel.visible = _panel_visible
	_toggle_panel_btn.text = "◀" if _panel_visible else "▶"
	_hud_presenter.sync_toggle_btn_x(_panel_visible)


func _refresh() -> void:
	var state := _view_state()
	if state == null:
		return
	_board.set_battle_state(state)
	_board.selected_unit_uid = _inspect_uid
	_board.set_timeline_hover_unit(_timeline_hover_uid)
	if not _enemy_phase_running:
		_enemy_turn_queue.clear()
		for enemy in _controller.get_sorted_enemies():
			_enemy_turn_queue.append(enemy.uid)
	var hud_state := _hud_presenter.refresh({
		"state": state,
		"inspect_uid": _inspect_uid,
		"tracked_player_uid": _tracked_player_uid,
		"timeline_hover_uid": _timeline_hover_uid,
		"enemy_phase_running": _enemy_phase_running,
		"enemy_turn_queue": _enemy_turn_queue,
	})
	_inspect_uid = str(hud_state.get("inspect_uid", _inspect_uid))
	_tracked_player_uid = str(hud_state.get("tracked_player_uid", _tracked_player_uid))
	var active_turn_uid := str(hud_state.get("active_turn_uid", ""))
	_board.set_active_turn_unit(active_turn_uid)
	_board.set_highlights(_controller.get_highlights(_hover_cell))
	_sync_unit_slot_panels()
	_board.queue_redraw()
	call_deferred("_fit_status_panel")
	call_deferred("_fit_status_panel_height")


func _fit_status_panel() -> void:
	if not is_node_ready():
		return
	_hud_presenter.fit_status_panel(_panel_visible)


func _fit_status_panel_height() -> void:
	if not is_node_ready():
		return
	_hud_presenter.fit_status_panel_height()


func _select_unit(uid: String) -> void:
	_inspect_uid = uid
	_controller.selected_unit_uid = uid
	_refresh()


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
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if _relic_detail_overlay != null:
			_dismiss_relic_detail_popup()
			get_viewport().set_input_as_handled()
			return
		if _slot_popup != null and _slot_popup.is_showing():
			_dismiss_popup()
			get_viewport().set_input_as_handled()


func _on_anim_move(unit_uid: String, from_pos: Vector2i, to_pos: Vector2i) -> void:
	_board.animate_move(unit_uid, from_pos, to_pos)


func _on_anim_damage(grid: Vector2i, damage: int, is_crit: bool) -> void:
	_board.play_damage_effect(grid, damage, is_crit)


func _on_anim_gem_flash(grid: Vector2i, gem_color: Color) -> void:
	_board.play_gem_flash(grid, gem_color)


func _spawn_damage_text(grid: Vector2i, value: int, is_crit: bool, reason: String) -> void:
	if _dmg_text == null or value <= 0:
		return
	var board_global: Vector2 = _board.global_position
	var cell_screen: Vector2 = _board.grid_to_screen(grid)
	var world_pos: Vector2 = board_global + cell_screen + Vector2(0, -24)
	var dmg_type: String
	if is_crit:
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


func _mark_visible_enemies_seen() -> void:
	if _controller.state == null:
		return
	for unit in _controller.state.units.values():
		if unit.team != Constants.TEAM_ENEMY:
			continue
		ProfileService.mark_enemy_seen(unit.unit_def_id)
	AchievementService.refresh_progress_flags()


func _record_enemy_codex_progress() -> void:
	if _controller.state == null:
		return
	for unit in _controller.state.units.values():
		if unit.team != Constants.TEAM_ENEMY:
			continue
		ProfileService.mark_enemy_seen(unit.unit_def_id)
		if not unit.alive:
			ProfileService.mark_enemy_killed(unit.unit_def_id)
	AchievementService.refresh_progress_flags()


func _show_tutorial_intro() -> void:
	var overlay := ColorRect.new()
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
	title.text = "窃律者 · 操作指南"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	vbox.add_child(title)
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.custom_minimum_size = Vector2(0, 260)
	body.text = """[color=#9aa0ad]每回合资源：[/color]
[color=#5ad8ff]● 1 次移动[/color]　[color=#ffcc44]● 1 次行动[/color]（攻击/技能/触发）
[color=#88ff88]● 拔出/嵌入免费[/color]，可穿插在行动前后

[color=#ff6666]核心：偷敌人宝石 → 装入自己槽位 → 释放技能[/color]

[color=#ff5555]红槽[/color] 主动　[color=#5599ff]蓝槽[/color] 被动　[color=#888]黑槽[/color] 死亡触发
[color=#ffaa44]祭坛[/color] 立即全场　[color=#6699ff]机关柱[/color] 每回合光环

[color=#ffffff]教学目标：拔工兵红槽 → 技能/黑槽嫁祸 → 结束回合[/color]"""
	vbox.add_child(body)
	var btn := Button.new()
	btn.text = "开始战斗"
	btn.custom_minimum_size = Vector2(180, 44)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	BattleUiTheme.apply_button(btn, "end")
	btn.pressed.connect(func(): overlay.queue_free())
	vbox.add_child(btn)
	overlay.modulate.a = 0.0
	create_tween().tween_property(overlay, "modulate:a", 1.0, 0.28)


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


func _wire_hover_interactions() -> void:
	for button in [_move_btn, _attack_btn, _extract_btn, _insert_btn, _end_turn_btn, _toggle_panel_btn]:
		if button == null:
			continue
		button.focus_mode = Control.FOCUS_NONE


func _setup_relic_bar() -> void:
	if _info_col == null or _relic_bar_scroll != null:
		return
	var scroll := ScrollContainer.new()
	scroll.name = "RelicBarScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	scroll.visible = false
	var column := VBoxContainer.new()
	column.name = "RelicBarColumn"
	column.add_theme_constant_override("separation", 6)
	scroll.add_child(column)
	_info_col.add_child(scroll)
	_info_col.move_child(scroll, _hp_text.get_index() + 1)
	_relic_bar_scroll = scroll
	_relic_bar_vbox = column


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


func _flat_style(bg: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_corner_radius_all(4)
	return box
