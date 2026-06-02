extends Control

const SlotPopup = preload("res://scripts/ui/slot_popup.gd")
const BattleUiTheme = preload("res://scripts/ui/battle_ui_theme.gd")
const StatusUi = preload("res://scripts/ui/status_ui.gd")
const StatusIcons = preload("res://scripts/ui/status_icons.gd")
const EditorConsoleScene = preload("res://scenes/ui/editor_console.tscn")
const DamageTextManagerScript = preload("res://scripts/ui/damage_text_manager.gd")

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
@onready var _trigger_btn: Button = $HudLayer/BottomDock/BottomBar/GemGroup/TriggerBtn
@onready var _end_turn_btn: Button = $HudLayer/BottomDock/BottomBar/TurnGroup/EndTurnBtn

var _controller: BattleController = BattleController.new()
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
var _display_state: GameState = null
var _presentation_playing: bool = false
var _refresh_deferred: bool = false
var _pending_battle_result: String = ""
var _preview_panel_tween: Tween = null
var _preview_visible_target: bool = false
var _preview_fade_serial: int = 0
var _relic_reward_overlay: Node = null
var _held_gem_icon: TextureRect = null
var _relic_bar_scroll: ScrollContainer = null
var _relic_bar_vbox: HFlowContainer = null
var _relic_bar_ids: Array[String] = []
var _tracked_player_uid: String = ""

## 遭遇 room_type → 遗物来源 key（DataRegistry 池筛选用）
const _ENCOUNTER_RELIC_SOURCE := {
	"NORMAL_COMBAT": "normal_chest",
	"ELITE_COMBAT": "elite_combat",
	"END": "large_chest",
}
const _STATUS_PANEL_WIDTH := 320.0

func _ready() -> void:
	_controller.state_changed.connect(_on_controller_state_changed)
	_controller.battle_ended.connect(_on_battle_ended)
	_controller.anim_move.connect(_on_anim_move)
	_controller.anim_damage.connect(_on_anim_damage)
	_controller.anim_gem_flash.connect(_on_anim_gem_flash)
	_board.cell_clicked.connect(_on_cell_clicked)
	_board.cell_hovered.connect(_on_cell_hovered)
	_apply_ui_theme()
	_preview_panel.visible = false
	_preview_panel.modulate.a = 0.0
	call_deferred("_fit_status_panel")
	call_deferred("_fit_status_panel_height")
	call_deferred("_setup_held_gem_row")
	_wire_hover_interactions()
	_create_slot_popup()
	_create_damage_text_manager()
	_create_level_console()
	_apply_animation_speed()
	_setup_relic_bar()
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
				_presentation_playing = true
				_refresh_deferred = false
				_start_presentation(
					move_result.get("presentation_state", _controller.state.clone()),
					_controller.state
				)
				_board.set_highlights({})
				var events: Array = move_result.get("move_events", [])
				await _play_presented_events(events)
				_player_animating = false
				_finish_presentation()
			else:
				_show_result(move_result)
		Constants.ACTION_ATTACK:
			_dismiss_popup()
			if unit != null:
				_inspect_uid = unit.uid
			_player_animating = true
			_presentation_playing = true
			var atk_res := _controller.try_attack_cell(cell)
			_show_result(atk_res)
			if atk_res.get("ok", false):
				var from_pos: Vector2i = atk_res.get("from_pos", Vector2i(-1, -1))
				var to_pos: Vector2i = atk_res.get("to_pos", cell)
				var player := _controller.state.get_player()
				if player != null:
					_board.start_strike_effect(player.uid, to_pos)
				_refresh_deferred = false
				_start_presentation(
					atk_res.get("presentation_state", _controller.state.clone()),
					_controller.state
				)
				var attack_events: Array = atk_res.get("attack_events", [])
				var has_projectile := false
				for ev in attack_events:
					if str(ev.get("type", "")) == "projectile":
						has_projectile = true
						break
				if not has_projectile and from_pos.x >= 0:
					_board.play_projectile(from_pos, to_pos)
					await _board.animation_finished
					await get_tree().create_timer(_scaled_anim_time(0.08)).timeout
				await _play_presented_events(attack_events)
				_player_animating = false
				_finish_presentation()
			else:
				_player_animating = false
				_presentation_playing = false
		Constants.ACTION_EXTRACT, Constants.ACTION_INSERT, Constants.ACTION_TRIGGER:
			var targets: Array = _controller.get_highlights().get("targets", [])
			if cell in targets:
				if unit != null and unit.alive:
					_inspect_uid = unit.uid
					_show_slot_popup(unit)
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


func _show_slot_popup(unit: UnitState) -> void:
	var screen_pos: Vector2 = _board.grid_to_screen(unit.pos)
	var board_global: Vector2 = _board.global_position
	var popup_pos: Vector2 = board_global + screen_pos + Vector2(0, -72)
	_slot_popup.show_for_unit(unit, _controller.state, _controller.selected_action, popup_pos, _controller.check_slot_action)


func _show_tile_slot_popup(tile: TileState, cell: Vector2i) -> void:
	var screen_pos: Vector2 = _board.grid_to_screen(cell)
	var board_global: Vector2 = _board.global_position
	var popup_pos: Vector2 = board_global + screen_pos + Vector2(0, -72)
	_slot_popup.show_for_tile(tile, _controller.state, _controller.selected_action, popup_pos, _controller.check_tile_slot_action)


func _on_popup_tile_slot_selected(tile_pos: Vector2i, slot_index: int) -> void:
	var action := _controller.selected_action
	var result: Dictionary
	match action:
		Constants.ACTION_EXTRACT:
			result = _controller.try_extract_tile(tile_pos, slot_index)
		Constants.ACTION_INSERT:
			result = _controller.try_insert_tile(tile_pos, slot_index)
		Constants.ACTION_TRIGGER:
			result = _controller.try_trigger_tile(tile_pos, slot_index)
		_:
			return
	_dismiss_popup()
	_show_result(result)
	if result.get("ok", false):
		match action:
			Constants.ACTION_EXTRACT:
				_begin_held_gem_extract(tile_pos, result)
				_controller.select_action(Constants.ACTION_INSERT)
				_message_label.text = "已从地块拔出，点击目标嵌入"
			Constants.ACTION_INSERT:
				_begin_held_gem_insert(tile_pos, result)
				if str(result.get("swapped_gem_uid", "")).is_empty():
					_controller.select_action(Constants.ACTION_ATTACK)
					_message_label.text = "已嵌入地块，可攻击或触发"
				else:
					_controller.select_action(Constants.ACTION_INSERT)
					_message_label.text = "已替换，原宝石回到手中"
			Constants.ACTION_TRIGGER:
				_player_animating = true
				_presentation_playing = true
				_refresh_deferred = false
				_start_presentation(
					result.get("presentation_state", _controller.state.clone()),
					_controller.state
				)
				var trigger_events: Array = result.get("events", [])
				await _play_presented_events(trigger_events)
				_player_animating = false
				_finish_presentation()
	_refresh()


func _on_popup_slot_selected(unit_uid: String, slot_index: int) -> void:
	var action := _controller.selected_action
	var result: Dictionary
	match action:
		Constants.ACTION_EXTRACT:
			result = _controller.try_extract(unit_uid, slot_index)
		Constants.ACTION_INSERT:
			result = _controller.try_insert(unit_uid, slot_index)
		Constants.ACTION_TRIGGER:
			result = _controller.try_trigger(unit_uid, slot_index)
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
				_message_label.text = "已拔出，点击目标嵌入（免费）"
			Constants.ACTION_INSERT:
				var insert_target: UnitState = _controller.state.units.get(unit_uid, null)
				if insert_target != null:
					_begin_held_gem_insert(insert_target.pos, result)
				if str(result.get("swapped_gem_uid", "")).is_empty():
					_controller.select_action(Constants.ACTION_ATTACK)
					_message_label.text = "已嵌入，可攻击或触发"
				else:
					_controller.select_action(Constants.ACTION_INSERT)
					_message_label.text = "已替换，原宝石回到手中"
			Constants.ACTION_TRIGGER:
				_player_animating = true
				_presentation_playing = true
				_refresh_deferred = false
				_start_presentation(
					result.get("presentation_state", _controller.state.clone()),
					_controller.state
				)
				var trigger_events: Array = result.get("events", [])
				await _play_presented_events(trigger_events)
				_player_animating = false
				_finish_presentation()
	_refresh()


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
	_refresh_turn_queue()
	for enemy in enemies:
		_refresh_turn_queue()
		if not enemy.alive:
			_consume_enemy_turn(enemy.uid)
			continue
		if _controller.state.phase == Constants.PHASE_ENDED:
			break
		await get_tree().create_timer(_scaled_anim_time(0.22)).timeout
		_presentation_playing = true
		_refresh_deferred = false
		var execution: Dictionary = _controller.execute_single_enemy(enemy)
		_start_presentation(execution.get("presentation_state", _controller.state.clone()))
		var events: Array[Dictionary] = execution.get("events", [])
		await _play_presented_events(events)
		await get_tree().create_timer(_scaled_anim_time(0.35)).timeout
		_finish_presentation()
		_consume_enemy_turn(enemy.uid)
		_refresh_turn_queue()
	if _controller.state.phase != Constants.PHASE_ENDED:
		_controller.finish_enemy_phase()
	_enemy_phase_running = false
	_enemy_turn_queue.clear()
	_message_label.text = _controller.get_action_hint()
	_refresh()


func _play_anim_event(ev: Dictionary) -> void:
	match ev.get("type", ""):
		"move_step":
			_board.animate_move(ev.get("uid", ""), ev.get("from", Vector2i.ZERO), ev.get("to", Vector2i.ZERO))
			await _board.animation_finished
		"damage":
			var atk_uid: String = str(ev.get("attacker_uid", ""))
			var dmg_pos: Vector2i = ev.get("pos", Vector2i.ZERO)
			var dmg_val: int = ev.get("damage", 1)
			var is_crit: bool = ev.get("is_crit", false)
			if atk_uid != "":
				_board.start_strike_effect(atk_uid, dmg_pos)
				await get_tree().create_timer(_scaled_anim_time(0.12)).timeout
			_board.play_damage_effect(dmg_pos, dmg_val, is_crit)
			_spawn_damage_text(dmg_pos, dmg_val, is_crit, ev.get("reason", ""))
			await get_tree().create_timer(_scaled_anim_time(0.38)).timeout
		"explode":
			var pos_ev: Vector2i = ev.get("pos", Vector2i.ZERO)
			_board.play_explosion(pos_ev)
			_board.queue_redraw()
			await get_tree().create_timer(_scaled_anim_time(0.75)).timeout
		"poison_burst":
			var ppos: Variant = ev.get("pos", Vector2i.ZERO)
			var prad_i: Variant = ev.get("radius", 0)
			_board.play_poison_burst(ppos, int(prad_i))
			await get_tree().create_timer(_scaled_anim_time(0.6)).timeout
			_board.queue_redraw()
		"gem_flash":
			_board.play_gem_flash(ev.get("pos", Vector2i.ZERO), ev.get("color", Color.WHITE))
			await get_tree().create_timer(_scaled_anim_time(0.32)).timeout
		"projectile", "projectile_deflect":
			var proj_color: Color = ev.get("color", Color(0.95, 0.92, 0.45))
			_board.play_projectile(ev.get("from", Vector2i.ZERO), ev.get("to", Vector2i.ZERO), proj_color)
			await _board.animation_finished
			await get_tree().create_timer(_scaled_anim_time(0.08)).timeout
		"lightning", "arc":
			_board.play_damage_effect(ev.get("pos", Vector2i.ZERO), 1, true)
			await get_tree().create_timer(_scaled_anim_time(0.22)).timeout
		"frost_pulse":
			_board.play_heal_effect(ev.get("pos", Vector2i.ZERO))
			await get_tree().create_timer(_scaled_anim_time(0.28)).timeout
		"fire_burst":
			_board.play_explosion(ev.get("pos", Vector2i.ZERO))
			await get_tree().create_timer(_scaled_anim_time(0.4)).timeout


func _exit_tree() -> void:
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
	if _presentation_playing:
		_pending_battle_result = result
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
	return _display_state if _display_state != null else _controller.state


func _on_controller_state_changed() -> void:
	if _presentation_playing:
		_refresh_deferred = true
		return
	_refresh()


func _start_presentation(state_before: GameState, economy_source: GameState = null) -> void:
	_display_state = state_before
	if economy_source != null:
		_display_state.player_moved = economy_source.player_moved
		_display_state.player_acted = economy_source.player_acted
	_board.set_battle_state(_display_state)
	_board.selected_unit_uid = _inspect_uid
	_board.queue_redraw()
	if economy_source != null:
		_refresh_economy_chips()


func _refresh_economy_chips() -> void:
	var state := _view_state()
	if state == null:
		return
	_move_chip.text = "移动 %s" % ("✓" if state.player_moved else "○")
	_act_chip.text = "行动 %s" % ("✓" if state.player_acted else "○")
	_style_chip(_move_chip, not state.player_moved and state.phase == Constants.PHASE_PLAYER, BattleUiTheme.PHASE_PLAYER)
	_style_chip(_act_chip, not state.player_acted and state.phase == Constants.PHASE_PLAYER, BattleUiTheme.TEXT_GOLD)


func _finish_presentation() -> void:
	_display_state = null
	_presentation_playing = false
	_refresh_deferred = false
	_board.set_battle_state(_controller.state)
	_refresh()
	_flush_pending_battle_end()


func _play_presented_events(events: Array) -> void:
	if OS.is_debug_build():
		EventValidator.assert_valid(events, "play_presented_events")
	var i := 0
	while i < events.size():
		var ev: Dictionary = events[i]
		var ev_type := str(ev.get("type", ""))
		if ev_type in ["projectile", "projectile_deflect"]:
			var batch: Array = _collect_consecutive_events(events, i, ["projectile", "projectile_deflect"])
			i += batch.size()
			await _play_projectile_volley(batch)
			continue
		if ev_type == "explode":
			_prime_event_state(ev)
			_board.play_explosion(ev.get("pos", Vector2i.ZERO))
			_board.queue_redraw()
			_apply_event_state(ev)
			i += 1
			# 紧跟爆炸的所有 damage 事件同时弹出，并行显示伤害数字
			var dmg_batch: Array = _collect_consecutive_events(events, i, ["damage"])
			i += dmg_batch.size()
			for dmg_ev in dmg_batch:
				_prime_event_state(dmg_ev)
				var dpos: Vector2i = dmg_ev.get("pos", Vector2i.ZERO)
				var dval: int = dmg_ev.get("damage", 1)
				var dcrit: bool = dmg_ev.get("is_crit", false)
				_board.play_damage_effect(dpos, dval, dcrit)
				_spawn_damage_text(dpos, dval, dcrit, dmg_ev.get("reason", ""))
				_apply_event_state(dmg_ev)
			# 紧跟的所有 move_step（knockback）并行播放
			var kb_batch: Array = _collect_consecutive_events(events, i, ["move_step"])
			i += kb_batch.size()
			if not kb_batch.is_empty():
				for kb_ev in kb_batch:
					_prime_event_state(kb_ev)
				_board.animate_moves_parallel(kb_batch)
				await _board.animation_finished
				for kb_ev in kb_batch:
					_apply_event_state(kb_ev)
			await get_tree().create_timer(_scaled_anim_time(0.75)).timeout
			_board.queue_redraw()
			continue
		if ev_type == "move_step":
			var batch: Array = _collect_consecutive_events(events, i, ["move_step"])
			if _move_batch_is_parallel(batch):
				i += batch.size()
				for step_ev in batch:
					_prime_event_state(step_ev)
				_board.animate_moves_parallel(batch)
				await _board.animation_finished
				for step_ev in batch:
					_apply_event_state(step_ev)
				_board.queue_redraw()
				continue
		if ev_type == "split_spawn":
			_apply_event_state(ev)
			i += 1
			_board.queue_redraw()
			continue
		_prime_event_state(ev)
		await _play_anim_event(ev)
		_apply_event_state(ev)
		i += 1
		_board.queue_redraw()


func _collect_consecutive_events(events: Array, start: int, types: Array) -> Array:
	var batch: Array = []
	var i := start
	while i < events.size() and str(events[i].get("type", "")) in types:
		batch.append(events[i])
		i += 1
	return batch


func _play_projectile_volley(batch: Array) -> void:
	if batch.is_empty():
		return
	if batch.size() == 1:
		var single: Dictionary = batch[0]
		var proj_color: Color = single.get("color", Color(0.95, 0.92, 0.45))
		_board.play_projectile(single.get("from", Vector2i.ZERO), single.get("to", Vector2i.ZERO), proj_color)
	else:
		var shots: Array = []
		for ev in batch:
			shots.append({
				"from": ev.get("from", Vector2i.ZERO),
				"to": ev.get("to", Vector2i.ZERO),
				"color": ev.get("color", Color(0.95, 0.92, 0.45)),
			})
		_board.play_projectiles(shots)
	await _board.animation_finished
	await get_tree().create_timer(_scaled_anim_time(0.08)).timeout


func _move_batch_is_parallel(batch: Array) -> bool:
	if batch.size() <= 1:
		return false
	var first_uid := str(batch[0].get("uid", ""))
	for ev in batch:
		if str(ev.get("uid", "")) != first_uid:
			return true
	return false


func _prime_event_state(ev: Dictionary) -> void:
	if _display_state == null:
		return
	match str(ev.get("type", "")):
		"move_step":
			var uid := str(ev.get("uid", ""))
			var unit: UnitState = _display_state.units.get(uid, null)
			if unit != null:
				var from_pos: Vector2i = ev.get("from", unit.pos)
				var to_pos: Vector2i = ev.get("to", unit.pos)
				unit.pos = to_pos
				unit.facing = UnitState.facing_from_step(from_pos, to_pos)


func _apply_event_state(ev: Dictionary) -> void:
	if _display_state == null:
		return
	match str(ev.get("type", "")):
		"damage":
			var pos: Vector2i = ev.get("pos", Vector2i.ZERO)
			var victim := _display_state.get_unit_at(pos)
			if victim == null:
				return
			victim.hp = maxi(0, victim.hp - int(ev.get("damage", 0)))
			if victim.hp <= 0:
				victim.alive = false
		"poison_burst":
			var poison_center: Vector2i = ev.get("pos", Vector2i.ZERO)
			var poison_radius: int = int(ev.get("radius", 0))
			for cell in BoardUtils.cells_in_radius(poison_center, poison_radius):
				if not BoardUtils.in_bounds(_display_state, cell):
					continue
				TileRules.create_poison_fog(_display_state, cell)
		"fire_burst":
			TileRules.create_fire(_display_state, ev.get("pos", Vector2i.ZERO))
		"explode", "gem_flash", "projectile_deflect", "lightning", "frost_pulse", "arc":
			pass
		"split_spawn":
			var clone_uid := str(ev.get("uid", ""))
			var clone: UnitState = _controller.state.units.get(clone_uid, null)
			if clone != null and clone.alive:
				_display_state.register_unit(clone.clone())
				_display_state.rebuild_occupancy()


func _flush_pending_battle_end() -> void:
	if _pending_battle_result.is_empty():
		return
	var result := _pending_battle_result
	_pending_battle_result = ""
	_apply_battle_end(result)


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
		var offer: Array[String] = RunService.get_or_roll_relic_offer(room_id, source, 3)
		if not offer.is_empty():
			var all_placeholder := offer.all(func(rid: String) -> bool:
				return rid == "relic_placeholder"
			)
			var display_offer: Array[String] = offer if not all_placeholder else _placeholder_relic_offer()
			_show_relic_reward(display_offer, result)
			return
	_finish_battle_and_navigate(result)


func _placeholder_relic_offer() -> Array[String]:
	var offer: Array[String] = []
	offer.append("relic_placeholder")
	return offer


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
	var rarity_color := BattleUiTheme.TEXT_MUTED if is_placeholder else _rarity_color(rarity)
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
	var desc_text := _relic_desc_text(def)
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


func _relic_desc_text(def: Dictionary) -> String:
	var desc := str(def.get("desc", ""))
	if not desc.is_empty():
		return desc
	return "（暂无描述）"


func _rarity_display_name(rarity: String) -> String:
	match rarity:
		"common": return "普通"
		"rare": return "稀有"
		"epic": return "史诗"
		"legendary": return "传说"
		"boss": return "首领"
		_: return rarity


func _rarity_color(rarity: String) -> Color:
	match rarity:
		"common": return Color("#c8cad4")
		"rare": return Color("#6ec6f5")
		"epic": return Color("#c77dff")
		"legendary": return Color("#ffd166")
		"boss": return Color("#ff6b6b")
		_: return Color("#c8cad4")


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
	_sync_toggle_btn_x()


func _refresh() -> void:
	var state := _view_state()
	if state == null:
		return
	_sync_controlled_player_inspect(state)
	_turn_label.text = "T%d" % state.turn_index
	_move_chip.text = "移动 %s" % ("✓" if state.player_moved else "○")
	_act_chip.text = "行动 %s" % ("✓" if state.player_acted else "○")
	_style_chip(_move_chip, not state.player_moved and state.phase == Constants.PHASE_PLAYER, BattleUiTheme.PHASE_PLAYER)
	_style_chip(_act_chip, not state.player_acted and state.phase == Constants.PHASE_PLAYER, BattleUiTheme.TEXT_GOLD)

	var turn_suffix := " · 第%d回合" % state.turn_index
	match state.phase:
		Constants.PHASE_PLAYER:
			var queue_suffix := ""
			if not state.controllable_queue.is_empty():
				var total := 1 + state.controllable_queue.size()
				var current := total - state.controllable_queue.size()
				queue_suffix = " · %d/%d" % [current, total]
			_phase_badge.text = "你的回合" + turn_suffix + queue_suffix
			_phase_badge.add_theme_color_override("font_color", BattleUiTheme.PHASE_PLAYER)
		Constants.PHASE_ENDED:
			_phase_badge.text = "战斗结束" + turn_suffix
			_phase_badge.add_theme_color_override("font_color", BattleUiTheme.PHASE_END)
		_:
			_phase_badge.text = "敌方回合" + turn_suffix
			_phase_badge.add_theme_color_override("font_color", BattleUiTheme.PHASE_ENEMY)

	var held := _controller.get_held_gem()
	if held != null:
		var gem_name: String = _data_registry().get_gem_display_name(held)
		if _held_gem_icon != null:
			_held_gem_icon.texture = UnitLooks.get_gem_texture(held)
			_held_gem_icon.self_modulate = UnitLooks.gem_sprite_modulate(held)
			_held_gem_icon.visible = true
		_held_label.text = "手持 %s" % gem_name
		_held_label.add_theme_color_override("font_color", UnitLooks.gem_color(held).lightened(0.15))
	else:
		if _held_gem_icon != null:
			_held_gem_icon.visible = false
		_held_label.text = ""
		_held_label.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)

	_hint_label.text = _controller.get_tutorial_hint()
	var tutorial_hint: String = _controller.get_tutorial_hint()
	if not tutorial_hint.is_empty():
		_message_label.text = tutorial_hint.split("\n")[0]
	elif _message_label.text.is_empty():
		_message_label.text = _controller.get_action_hint()

	_board.set_battle_state(state)
	_board.selected_unit_uid = _inspect_uid
	_board.set_timeline_hover_unit(_timeline_hover_uid)
	_board.set_active_turn_unit(_get_active_turn_uid())
	_board.set_highlights(_controller.get_highlights(_hover_cell))
	if not _enemy_phase_running:
		_enemy_turn_queue.clear()
		for enemy in _controller.get_sorted_enemies():
			_enemy_turn_queue.append(enemy.uid)
	_refresh_turn_queue()
	_refresh_inspect()
	_refresh_action_buttons()
	_refresh_relic_bar()
	_board.queue_redraw()
	call_deferred("_fit_status_panel")
	call_deferred("_fit_status_panel_height")


func _fit_status_panel() -> void:
	if not is_node_ready():
		return
	var margins := _status_panel_content_margins()
	var panel_w := _STATUS_PANEL_WIDTH
	var inner_w := panel_w - margins.x
	var header_gap := float(_header_row.get_theme_constant("separation", "HBoxContainer"))
	var info_w := inner_w - _portrait.custom_minimum_size.x - header_gap
	_info_col.custom_minimum_size.x = info_w
	_shield_bar.custom_minimum_size.x = maxf(0.0, info_w - 40.0)
	_hp_bar.custom_minimum_size.x = info_w
	_status_clip.custom_minimum_size.x = info_w
	_inspect_status_row.offset_right = info_w
	_apply_status_inner_width(inner_w)
	var panel_h := _status_vbox.get_minimum_size().y + margins.y
	_status_panel.custom_minimum_size = Vector2(panel_w, panel_h)
	_status_panel.size = Vector2(panel_w, panel_h)
	_status_panel.offset_right = _status_panel.offset_left + panel_w
	_sync_toggle_btn_x()


func _fit_status_panel_height() -> void:
	if not is_node_ready():
		return
	var margins := _status_panel_content_margins()
	var panel_h := _status_vbox.get_minimum_size().y + margins.y
	if absf(panel_h - _status_panel.size.y) < 0.5:
		return
	_status_panel.custom_minimum_size.y = panel_h
	_status_panel.size.y = panel_h
	_status_panel.offset_bottom = _status_panel.offset_top + panel_h


func _sync_toggle_btn_x() -> void:
	if _panel_visible:
		_toggle_panel_btn.position.x = _status_panel.position.x + _status_panel.size.x + 8.0


func _sync_controlled_player_inspect(state: GameState) -> void:
	var player: UnitState = state.get_player()
	if player == null or not player.alive:
		return
	if player.uid == _tracked_player_uid:
		return
	_tracked_player_uid = player.uid
	_inspect_uid = player.uid
	_controller.selected_unit_uid = player.uid


func _apply_status_inner_width(inner_w: float) -> void:
	_status_vbox.custom_minimum_size.x = inner_w
	_header_row.custom_minimum_size.x = inner_w
	_hint_label.custom_minimum_size.x = inner_w
	_inspect_stats.custom_minimum_size.x = inner_w
	_held_label.custom_minimum_size.x = inner_w
	_slot_clip.custom_minimum_size.x = inner_w
	_slot_box.size.x = inner_w
	if _relic_bar_scroll != null:
		_relic_bar_scroll.custom_minimum_size.x = inner_w


func _status_panel_content_margins() -> Vector2:
	var style := _status_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if style == null:
		return Vector2(24.0, 20.0)
	return Vector2(
		style.content_margin_left + style.content_margin_right,
		style.content_margin_top + style.content_margin_bottom
	)


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


func _refresh_inspect() -> void:
	var state := _view_state()
	for child in _slot_box.get_children():
		child.queue_free()
	if _inspect_uid.is_empty():
		_clear_inspect_header("单位详情")
		_inspect_stats.text = "点击时间轴或棋盘"
		return
	var unit: UnitState = state.units.get(_inspect_uid, null)
	if unit == null or not unit.alive:
		_clear_inspect_header("已阵亡")
		_inspect_stats.text = ""
		return
	var unit_name: String = _data_registry().get_unit_display_name(unit.unit_def_id)
	_portrait.texture = UnitLooks.get_unit_texture(unit.unit_def_id)
	_portrait.self_modulate = UnitLooks.sprite_modulate_for_unit(unit.team, unit.unit_def_id)
	_inspect_name.text = unit_name
	_hp_bar.max_value = unit.max_hp
	_hp_bar.value = unit.hp
	var ratio := float(unit.hp) / float(maxi(unit.max_hp, 1))
	_hp_bar.add_theme_stylebox_override("fill", _flat_style(BattleUiTheme.hp_fill_color(ratio), BattleUiTheme.hp_fill_color(ratio).lightened(0.08)))
	_hp_text.text = "%d / %d" % [unit.hp, unit.max_hp]
	_refresh_inspect_shield(state, unit)
	StatusUi.populate_status_row(_inspect_status_row, unit, true, [Constants.STATUS_ARMOR])
	var attack_value := CombatRules.attack_damage(state, unit)
	var stat_parts: Array[String] = ["攻击 %d · 速度 %d" % [attack_value, unit.speed]]
	if unit.intent != null and unit.team == Constants.TEAM_ENEMY:
		stat_parts.append(unit.intent.preview_text)
	_inspect_stats.text = "\n".join(stat_parts)
	for slot in unit.slots:
		_slot_box.add_child(_create_slot_chip(state, unit, slot))


func _refresh_inspect_shield(state: GameState, unit: UnitState) -> void:
	var shield_value := CombatRules.current_shield(state, unit)
	_shield_row.visible = shield_value > 0
	if shield_value <= 0:
		_shield_bar.value = 0.0
		_shield_text.text = ""
		return
	var shield_max := maxi(unit.max_hp, shield_value)
	_shield_bar.max_value = float(shield_max)
	_shield_bar.value = float(shield_value)
	_shield_text.text = str(shield_value)
	_shield_row.tooltip_text = "护盾 %d" % shield_value


func _clear_inspect_header(title: String) -> void:
	_portrait.texture = null
	_portrait.self_modulate = Color.WHITE
	_inspect_name.text = title
	_hp_bar.max_value = 1.0
	_hp_bar.value = 0.0
	_hp_text.text = ""
	_shield_row.visible = false
	_shield_bar.value = 0.0
	_shield_text.text = ""
	while _inspect_status_row.get_child_count() > 0:
		_inspect_status_row.get_child(0).free()


func _create_slot_chip(state: GameState, unit: UnitState, slot: SlotState) -> Control:
	var chip := PanelContainer.new()
	var color := UnitLooks.slot_color(slot.slot_type)
	var gem: GemState = null
	if not slot.gem_uid.is_empty():
		gem = state.gems.get(slot.gem_uid, null)
		if gem != null:
			color = UnitLooks.gem_color(gem)
	chip.add_theme_stylebox_override("panel", BattleUiTheme.chip_style(color))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var label := Label.new()
	var slot_name := _slot_display_name(slot.slot_type)
	var is_dual := not slot.dual_type.is_empty()
	var dual_name := _slot_display_name(slot.dual_type) if is_dual else ""
	var display_name := ("%s/%s" % [slot_name, dual_name]) if is_dual else slot_name
	if slot.locked:
		label.text = "%s🔒" % display_name
		chip.tooltip_text = "%s槽：锁定" % display_name
	elif slot.gem_uid.is_empty():
		label.text = "%s○" % display_name
		var tip := "%s槽：空" % display_name
		if is_dual:
			tip += "（双色槽，可嵌入%s或%s宝石）" % [slot_name, dual_name]
		chip.tooltip_text = tip
	else:
		if gem == null:
			label.text = "%s?" % display_name
			chip.tooltip_text = "%s槽：无宝石数据" % display_name
		else:
			var gem_icon := _make_gem_icon(gem, 14)
			if gem_icon != null:
				row.add_child(gem_icon)
			label.text = display_name
			chip.tooltip_text = _slot_chip_tooltip(gem, slot, unit)

	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", BattleUiTheme.TEXT)
	row.add_child(label)
	chip.add_child(row)
	return chip


func _make_gem_icon(gem: GemState, size_px: int) -> TextureRect:
	var tex := UnitLooks.get_gem_texture(gem)
	if tex == null:
		return null
	var icon := TextureRect.new()
	icon.texture = tex
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.custom_minimum_size = Vector2(size_px, size_px)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.self_modulate = UnitLooks.gem_sprite_modulate(gem)
	return icon


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


func _slot_display_name(slot_type: String) -> String:
	match slot_type:
		Constants.SLOT_RED: return "红"
		Constants.SLOT_BLUE: return "蓝"
		Constants.SLOT_BLACK: return "黑"
	return "?"


func _slot_effect_context(unit: UnitState, slot: SlotState) -> String:
	return RulesIndex.slot_inspect_context(unit, slot)


func _slot_chip_tooltip(gem: GemState, slot: SlotState, unit: UnitState) -> String:
	var gem_name: String = _data_registry().get_gem_display_name(gem)
	var effect: String = GemEffects.get_slot_effect_description(gem, slot.slot_type, _slot_effect_context(unit, slot))
	if effect.is_empty():
		return gem_name
	return "%s\n%s" % [gem_name, effect]


func _refresh_action_buttons() -> void:
	var current: String = _controller.selected_action
	var can_act: bool = not _enemy_phase_running
	_move_btn.disabled = not can_act or not _controller.can_use_action(Constants.ACTION_MOVE)
	_attack_btn.disabled = not can_act or not _controller.can_use_action(Constants.ACTION_ATTACK)
	_extract_btn.disabled = not can_act or not _controller.can_use_action(Constants.ACTION_EXTRACT)
	_insert_btn.disabled = not can_act or not _controller.can_use_action(Constants.ACTION_INSERT)
	_trigger_btn.disabled = not can_act or not _controller.can_use_action(Constants.ACTION_TRIGGER)
	_end_turn_btn.disabled = not can_act or _controller.state == null or _controller.state.phase != Constants.PHASE_PLAYER
	BattleUiTheme.apply_button(_move_btn, "move", current == Constants.ACTION_MOVE)
	BattleUiTheme.apply_button(_attack_btn, "combat", current == Constants.ACTION_ATTACK)
	BattleUiTheme.apply_button(_extract_btn, "gem", current == Constants.ACTION_EXTRACT)
	BattleUiTheme.apply_button(_insert_btn, "gem", current == Constants.ACTION_INSERT)
	BattleUiTheme.apply_button(_trigger_btn, "gem", current == Constants.ACTION_TRIGGER)
	BattleUiTheme.apply_button(_end_turn_btn, "end", false)
	_extract_btn.text = "拔出" if _controller.can_use_action(Constants.ACTION_EXTRACT) else "拔出×"
	_insert_btn.text = "嵌入" if _controller.can_use_action(Constants.ACTION_INSERT) else "嵌入×"


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
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
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


func _refresh_turn_queue() -> void:
	var state := _view_state()
	if state == null:
		return
	var active_uid: String = _get_active_turn_uid()
	_board.set_active_turn_unit(active_uid)
	for child in _queue_row.get_children():
		child.queue_free()
	var focus_uid := _timeline_hover_uid if not _timeline_hover_uid.is_empty() else active_uid
	var active_unit: UnitState = state.units.get(active_uid, null)
	if active_unit != null:
		var active_name: String = _data_registry().get_unit_display_name(active_unit.unit_def_id)
		_queue_hint.text = "当前 %s · 速 %d" % [active_name, active_unit.speed]
	else:
		_queue_hint.text = "当前 —"
	for uid in _build_turn_timeline_uids(active_uid, 8):
		var unit: UnitState = state.units.get(uid, null)
		if unit != null and unit.alive:
			_queue_row.add_child(_create_timeline_avatar(unit, uid == active_uid, uid == focus_uid))


func _get_active_turn_uid() -> String:
	var state := _view_state()
	if state == null:
		return ""
	if state.phase == Constants.PHASE_PLAYER:
		var player: UnitState = state.get_player()
		return player.uid if player != null and player.alive else ""
	if _enemy_phase_running and not _enemy_turn_queue.is_empty():
		return _enemy_turn_queue[0]
	return ""


func _build_turn_timeline_uids(active_uid: String, max_items: int) -> Array[String]:
	var state := _view_state()
	if state == null:
		return []
	var units: Array = []
	for unit in state.units.values():
		if unit.alive:
			units.append(unit)
	units.sort_custom(func(a: UnitState, b: UnitState) -> bool:
		if a.speed == b.speed:
			return a.uid < b.uid
		return a.speed > b.speed
	)
	if units.is_empty():
		return []
	var ordered: Array[String] = []
	for unit in units:
		ordered.append(unit.uid)
	var start_idx: int = 0
	if not active_uid.is_empty():
		var idx: int = ordered.find(active_uid)
		if idx >= 0:
			start_idx = idx
	var timeline: Array[String] = []
	for i in range(max_items):
		timeline.append(ordered[(start_idx + i) % ordered.size()])
	return timeline


func _create_timeline_avatar(unit: UnitState, is_active: bool, is_hovered: bool) -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(58, 76)
	var stack := VBoxContainer.new()
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(stack)
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(44, 44)
	var team_color := BattleUiTheme.PHASE_PLAYER if unit.team == Constants.TEAM_PLAYER else BattleUiTheme.PHASE_ENEMY
	var accent := BattleUiTheme.BORDER
	if is_hovered:
		accent = BattleUiTheme.TEXT_GOLD
	elif is_active:
		accent = team_color
	frame.add_theme_stylebox_override("panel", BattleUiTheme.panel_style(accent))
	stack.add_child(frame)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(34, 34)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = UnitLooks.get_unit_texture(unit.unit_def_id)
	icon.self_modulate = UnitLooks.sprite_modulate_for_unit(unit.team, unit.unit_def_id)
	frame.add_child(icon)
	if is_active:
		var arrow := Label.new()
		arrow.text = "▼"
		arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		arrow.add_theme_font_size_override("font_size", 12)
		arrow.add_theme_color_override("font_color", team_color)
		stack.add_child(arrow)
	var hp_label := Label.new()
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_label.text = "%d/%d" % [unit.hp, unit.max_hp]
	hp_label.add_theme_font_size_override("font_size", 9)
	hp_label.add_theme_color_override("font_color", BattleUiTheme.TEXT)
	stack.add_child(hp_label)
	var speed_label := Label.new()
	speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speed_label.text = "%d" % unit.speed
	speed_label.add_theme_font_size_override("font_size", 10)
	speed_label.add_theme_color_override("font_color", team_color if is_active else (BattleUiTheme.TEXT_GOLD if is_hovered else BattleUiTheme.TEXT_MUTED))
	stack.add_child(speed_label)
	var hover_btn := Button.new()
	hover_btn.flat = true
	hover_btn.focus_mode = Control.FOCUS_NONE
	hover_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	hover_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hover_btn.mouse_entered.connect(_set_timeline_hover.bind(unit.uid), CONNECT_DEFERRED)
	hover_btn.mouse_exited.connect(_clear_timeline_hover.bind(unit.uid), CONNECT_DEFERRED)
	hover_btn.pressed.connect(_select_unit.bind(unit.uid))
	root.add_child(hover_btn)
	return root


func _wire_hover_interactions() -> void:
	for button in [_move_btn, _attack_btn, _extract_btn, _insert_btn, _trigger_btn, _end_turn_btn, _toggle_panel_btn]:
		button.focus_mode = Control.FOCUS_NONE


func _style_chip(label: Label, highlight: bool, color: Color) -> void:
	if not highlight:
		label.remove_theme_stylebox_override("normal")
		label.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
		return
	label.add_theme_stylebox_override("normal", BattleUiTheme.chip_style(color))
	label.add_theme_color_override("font_color", BattleUiTheme.TEXT)


func _setup_relic_bar() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "RelicBarScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.visible = false
	var flow := HFlowContainer.new()
	flow.name = "RelicBarFlow"
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(flow)
	_status_vbox.add_child(scroll)
	_status_vbox.move_child(scroll, _header_row.get_index() + 1)
	_relic_bar_scroll = scroll
	_relic_bar_vbox = flow


func _refresh_relic_bar() -> void:
	if _relic_bar_vbox == null or _relic_bar_scroll == null:
		return
	var owned: Array[String] = RunService.get_owned_relics() if RunService.is_run_active() else []
	var ids_changed := owned != _relic_bar_ids
	if ids_changed:
		_relic_bar_ids = owned.duplicate()
		for child in _relic_bar_vbox.get_children():
			child.queue_free()
		for relic_id in owned:
			_relic_bar_vbox.add_child(_create_relic_badge(relic_id))
	_relic_bar_scroll.visible = not owned.is_empty()
	if owned.is_empty():
		_relic_bar_scroll.custom_minimum_size = Vector2(0, 0)
		return
	var inner_w := _status_vbox.custom_minimum_size.x
	if inner_w <= 0.0:
		inner_w = _STATUS_PANEL_WIDTH - _status_panel_content_margins().x
	_relic_bar_scroll.custom_minimum_size.x = inner_w
	var content_h := _relic_bar_vbox.get_minimum_size().y
	var max_h := 92.0
	_relic_bar_scroll.custom_minimum_size.y = minf(content_h, max_h)


func _create_relic_badge(relic_id: String) -> Control:
	var def: Dictionary = DataRegistry.get_relic_def(relic_id)
	var rarity: String = DataRegistry.get_relic_rarity(relic_id)
	var rarity_col := _rarity_color(rarity)
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(40, 40)
	var style := StyleBoxFlat.new()
	style.bg_color = rarity_col.darkened(0.55)
	style.border_color = rarity_col
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(3)
	badge.add_theme_stylebox_override("panel", style)
	var name_str: String = str(def.get("name", relic_id))
	var icon_tex := UnitLooks.get_relic_texture(relic_id)
	if icon_tex != null:
		var icon := TextureRect.new()
		icon.texture = icon_tex
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		badge.add_child(icon)
	var tooltip_text: String = name_str + "\n" + _relic_desc_text(def)
	badge.tooltip_text = tooltip_text
	return badge


func _flat_style(bg: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_corner_radius_all(4)
	return box
