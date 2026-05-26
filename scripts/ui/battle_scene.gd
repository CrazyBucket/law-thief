extends Control

const SlotPopup = preload("res://scripts/ui/slot_popup.gd")
const BattleUiTheme = preload("res://scripts/ui/battle_ui_theme.gd")
const StatusUi = preload("res://scripts/ui/status_ui.gd")
const EditorConsoleScene = preload("res://scenes/ui/editor_console.tscn")

@onready var _board: Control = $BoardLayer/IsometricBoard
@onready var _status_panel: PanelContainer = $HudLayer/StatusPanel
@onready var _portrait: TextureRect = $HudLayer/StatusPanel/VBox/PlayerCard/PlayerRow/Portrait
@onready var _player_name: Label = $HudLayer/StatusPanel/VBox/PlayerCard/PlayerRow/Info/Name
@onready var _hp_bar: ProgressBar = $HudLayer/StatusPanel/VBox/PlayerCard/PlayerRow/Info/HpBar
@onready var _hp_text: Label = $HudLayer/StatusPanel/VBox/PlayerCard/PlayerRow/Info/HpText
@onready var _player_status_row: HBoxContainer = $HudLayer/StatusPanel/VBox/PlayerCard/PlayerRow/Info/StatusRow
@onready var _turn_label: Label = $HudLayer/StatusPanel/VBox/TurnChips/TurnLabel
@onready var _move_chip: Label = $HudLayer/StatusPanel/VBox/TurnChips/MoveChip
@onready var _act_chip: Label = $HudLayer/StatusPanel/VBox/TurnChips/ActChip
@onready var _held_label: Label = $HudLayer/StatusPanel/VBox/HeldLabel
@onready var _hint_label: Label = $HudLayer/StatusPanel/VBox/HintLabel
@onready var _unit_roster: VBoxContainer = $HudLayer/StatusPanel/VBox/UnitScroll/UnitRoster
@onready var _inspect_title: Label = $HudLayer/StatusPanel/VBox/InspectTitle
@onready var _inspect_body: RichTextLabel = $HudLayer/StatusPanel/VBox/InspectBody
@onready var _slot_box: HBoxContainer = $HudLayer/StatusPanel/VBox/SlotBox
@onready var _log_label: RichTextLabel = $HudLayer/StatusPanel/VBox/Log
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
@onready var _skill_btn: Button = $HudLayer/BottomDock/BottomBar/CombatGroup/SkillBtn
@onready var _extract_btn: Button = $HudLayer/BottomDock/BottomBar/GemGroup/ExtractBtn
@onready var _insert_btn: Button = $HudLayer/BottomDock/BottomBar/GemGroup/InsertBtn
@onready var _trigger_btn: Button = $HudLayer/BottomDock/BottomBar/GemGroup/TriggerBtn
@onready var _end_turn_btn: Button = $HudLayer/BottomDock/BottomBar/TurnGroup/EndTurnBtn

var _controller: BattleController = BattleController.new()
var _encounter_id: String = "tutorial_001"

var _inspect_uid: String = ""
var _hover_cell: Vector2i = Vector2i(-1, -1)
var _panel_visible: bool = true
var _enemy_phase_running: bool = false
var _player_animating: bool = false
var _animation_speed_scale: float = 1.0
var _enemy_turn_queue: Array[String] = []
var _slot_popup: Control = null
var _console_layer: CanvasLayer = null
var _console: Control = null

func _ready() -> void:
	_controller.state_changed.connect(_refresh)
	_controller.battle_ended.connect(_on_battle_ended)
	_controller.anim_move.connect(_on_anim_move)
	_controller.anim_damage.connect(_on_anim_damage)
	_controller.anim_gem_flash.connect(_on_anim_gem_flash)
	_board.cell_clicked.connect(_on_cell_clicked)
	_board.cell_hovered.connect(_on_cell_hovered)
	_apply_ui_theme()
	_create_slot_popup()
	_create_level_console()
	_apply_animation_speed()
	_start_battle(GameService.pending_encounter_id)


func _apply_ui_theme() -> void:
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_status_panel.add_theme_stylebox_override("panel", BattleUiTheme.panel_style(BattleUiTheme.BORDER))
	_top_bar.add_theme_stylebox_override("panel", BattleUiTheme.panel_style(BattleUiTheme.BORDER_ACCENT.darkened(0.2)))
	_bottom_dock.add_theme_stylebox_override("panel", BattleUiTheme.dock_style())
	$HudLayer/TurnQueuePanel.add_theme_stylebox_override("panel", BattleUiTheme.panel_style(BattleUiTheme.PHASE_PLAYER.darkened(0.35)))
	_preview_panel.add_theme_stylebox_override("panel", BattleUiTheme.tooltip_style())
	$HudLayer/StatusPanel/VBox/PlayerCard.add_theme_stylebox_override("panel", BattleUiTheme.panel_style(BattleUiTheme.BORDER.darkened(0.15)))
	_player_name.add_theme_color_override("font_color", BattleUiTheme.TEXT)
	_message_label.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	_hint_label.add_theme_color_override("font_color", BattleUiTheme.TEXT_HINT)
	for label_path in ["RosterTitle", "LogTitle", "InspectTitle"]:
		var label: Label = $HudLayer/StatusPanel/VBox.get_node(label_path)
		label.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
	_queue_title.add_theme_color_override("font_color", BattleUiTheme.TEXT)
	_hp_bar.add_theme_stylebox_override("background", _flat_style(Color(0.12, 0.13, 0.18), Color(0.22, 0.24, 0.3)))
	BattleUiTheme.apply_button(_toggle_panel_btn, "ghost")


func _create_slot_popup() -> void:
	_slot_popup = SlotPopup.new()
	$HudLayer.add_child(_slot_popup)
	_slot_popup.slot_selected.connect(_on_popup_slot_selected)
	_slot_popup.tile_slot_selected.connect(_on_popup_tile_slot_selected)
	_slot_popup.cancelled.connect(_on_popup_cancelled)


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
	_controller.start_encounter(encounter_id)
	_inspect_uid = ""
	_controller.select_action("")
	_refresh()
	if encounter_id == "tutorial_001":
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
	if _enemy_phase_running or _player_animating:
		return
	var state := _controller.state
	if state == null or state.phase != Constants.PHASE_PLAYER:
		return
	var unit := state.get_unit_at(cell)
	match _controller.selected_action:
		Constants.ACTION_MOVE:
			_dismiss_popup()
			var move_result := _controller.try_move(cell)
			if move_result.get("ok", false):
				_player_animating = true
				_board.set_highlights({})
				var events: Array = move_result.get("move_events", [])
				for ev in events:
					await _play_anim_event(ev)
				_player_animating = false
				_refresh()
			else:
				_show_result(move_result)
		Constants.ACTION_ATTACK:
			_dismiss_popup()
			if unit != null:
				_inspect_uid = unit.uid
				var atk_res := _controller.try_attack(unit.uid)
				_show_result(atk_res)
				if atk_res.get("ok", false):
					var from_pos: Vector2i = atk_res.get("from_pos", Vector2i(-1, -1))
					var to_pos: Vector2i = atk_res.get("to_pos", unit.pos)
					_player_animating = true
					if from_pos.x >= 0:
						_board.play_projectile(from_pos, to_pos)
						await _board.animation_finished
					# 消费 pipeline 产生的后续事件（爆炸、击退等）
					var attack_events: Array = atk_res.get("attack_events", [])
					for ev in attack_events:
						await _play_anim_event(ev)
					_player_animating = false
					_refresh()
		Constants.ACTION_SKILL:
			_dismiss_popup()
			var skill_result := _controller.try_skill(cell)
			_show_result(skill_result)
			if skill_result.get("ok", false):
				var skill_events: Array = skill_result.get("events", [])
				for ev in skill_events:
					await _play_anim_event(ev)
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
	if not valid:
		_preview_panel.visible = false
		_board.set_hover(Vector2i(-1, -1))
		return
	_board.set_hover(cell)
	var preview: Dictionary = _controller.get_cell_preview(cell)
	_preview_title.text = preview.get("title", "")
	_preview_body.text = _format_preview_body(preview.get("body", ""))
	_preview_panel.visible = true
	var mouse: Vector2 = get_viewport().get_mouse_position()
	_preview_panel.position = mouse + Vector2(18, 18)
	_clamp_preview_panel()


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
	var result: Dictionary
	match _controller.selected_action:
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
		match _controller.selected_action:
			Constants.ACTION_EXTRACT:
				_controller.select_action(Constants.ACTION_INSERT)
				_message_label.text = "已从地块拔出，点击目标嵌入"
			Constants.ACTION_INSERT:
				_controller.select_action(Constants.ACTION_ATTACK)
				_message_label.text = "已嵌入地块，可攻击或触发"
	_refresh()


func _on_popup_slot_selected(unit_uid: String, slot_index: int) -> void:
	var result: Dictionary
	match _controller.selected_action:
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
		match _controller.selected_action:
			Constants.ACTION_EXTRACT:
				_controller.select_action(Constants.ACTION_INSERT)
				_message_label.text = "已拔出，点击目标嵌入（免费）"
			Constants.ACTION_INSERT:
				_controller.select_action(Constants.ACTION_ATTACK)
				_message_label.text = "已嵌入，可攻击或触发"
	_refresh()


func _on_popup_cancelled() -> void:
	_refresh()


func _dismiss_popup() -> void:
	if _slot_popup != null and _slot_popup.is_showing():
		_slot_popup.hide_popup()


func _on_end_turn_pressed() -> void:
	if _enemy_phase_running:
		return
	_dismiss_popup()
	_run_enemy_phase_async()


func _run_enemy_phase_async() -> void:
	_enemy_phase_running = true
	_controller.begin_enemy_phase()
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
		var events: Array[Dictionary] = _controller.execute_single_enemy(enemy)
		for ev in events:
			await _play_anim_event(ev)
		await get_tree().create_timer(_scaled_anim_time(0.2)).timeout
		_board.queue_redraw()
		_refresh()
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
			if atk_uid != "":
				_board.start_strike_effect(atk_uid, ev.get("pos", Vector2i.ZERO))
			_board.play_damage_effect(ev.get("pos", Vector2i.ZERO), ev.get("damage", 1), ev.get("is_crit", false))
			await get_tree().create_timer(_scaled_anim_time(0.3)).timeout
		"explode":
			var pos_ev: Vector2i = ev.get("pos", Vector2i.ZERO)
			_board.play_explosion(pos_ev)
			_board.queue_redraw()
			await get_tree().create_timer(_scaled_anim_time(0.6)).timeout
		"poison_burst":
			var ppos: Variant = ev.get("pos", Vector2i.ZERO)
			var prad_i: Variant = ev.get("radius", 1)
			_board.play_poison_burst(ppos, int(prad_i))
			await get_tree().create_timer(_scaled_anim_time(0.5)).timeout
			_board.queue_redraw()
		"gem_flash":
			_board.play_gem_flash(ev.get("pos", Vector2i.ZERO), ev.get("color", Color.WHITE))
			await get_tree().create_timer(_scaled_anim_time(0.25)).timeout


func _on_back_pressed() -> void:
	if GameService.adventure_return:
		GameService.adventure_return = false
		get_tree().change_scene_to_file("res://scenes/map/adventure_map.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/main/main.tscn")


func _on_battle_ended(result: String) -> void:
	_message_label.text = "战斗结束 — %s" % ("胜利" if result == "win" else "失败")
	_hint_label.text = ""
	_phase_badge.text = "结束"
	_phase_badge.add_theme_color_override("font_color", BattleUiTheme.PHASE_END)
	GameService.finish_battle(result, _encounter_id, _controller.state.turn_index if _controller.state != null else 0)


func _show_result(result: Dictionary) -> void:
	if result.get("ok", false):
		_message_label.text = _controller.get_action_hint()
	else:
		_message_label.text = result.get("reason", "无法执行")


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


func _on_toggle_panel() -> void:
	_panel_visible = not _panel_visible
	_status_panel.visible = _panel_visible
	_toggle_panel_btn.text = "◀" if _panel_visible else "▶"
	_toggle_panel_btn.position.x = 260.0 if _panel_visible else 8.0


func _refresh() -> void:
	var state := _controller.state
	if state == null:
		return
	var player := state.get_player()
	if player != null:
		_portrait.texture = UnitLooks.get_unit_texture(player.unit_def_id)
		_portrait.self_modulate = UnitLooks.sprite_modulate_for_unit(player.team, player.unit_def_id)
		_player_name.text = _data_registry().get_unit_display_name(player.unit_def_id)
		_hp_bar.max_value = player.max_hp
		_hp_bar.value = player.hp
		var ratio := float(player.hp) / float(maxi(player.max_hp, 1))
		_hp_bar.add_theme_stylebox_override("fill", _flat_style(BattleUiTheme.hp_fill_color(ratio), BattleUiTheme.hp_fill_color(ratio).lightened(0.08)))
		_hp_text.text = "%d / %d" % [player.hp, player.max_hp]
		_refresh_player_status_row(player)

	_turn_label.text = "T%d" % state.turn_index
	_move_chip.text = "移动 %s" % ("✓" if state.player_moved else "○")
	_act_chip.text = "行动 %s" % ("✓" if state.player_acted else "○")
	_style_chip(_move_chip, not state.player_moved and state.phase == Constants.PHASE_PLAYER, BattleUiTheme.PHASE_PLAYER)
	_style_chip(_act_chip, not state.player_acted and state.phase == Constants.PHASE_PLAYER, BattleUiTheme.TEXT_GOLD)

	match state.phase:
		Constants.PHASE_PLAYER:
			_phase_badge.text = "你的回合"
			_phase_badge.add_theme_color_override("font_color", BattleUiTheme.PHASE_PLAYER)
		Constants.PHASE_ENDED:
			_phase_badge.text = "战斗结束"
			_phase_badge.add_theme_color_override("font_color", BattleUiTheme.PHASE_END)
		_:
			_phase_badge.text = "敌方回合"
			_phase_badge.add_theme_color_override("font_color", BattleUiTheme.PHASE_ENEMY)

	var held := _controller.get_held_gem()
	if held != null:
		var gem_name: String = _data_registry().get_gem_display_name(held)
		_held_label.text = "手持 ◆ %s" % gem_name
		_held_label.add_theme_color_override("font_color", UnitLooks.gem_color(held).lightened(0.15))
	else:
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
	_board.set_highlights(_controller.get_highlights())
	if not _enemy_phase_running:
		_enemy_turn_queue.clear()
		for enemy in _controller.get_sorted_enemies():
			_enemy_turn_queue.append(enemy.uid)
	_refresh_turn_queue()
	_refresh_unit_roster()
	_refresh_inspect()
	_refresh_action_buttons()
	_refresh_combat_log()
	_board.queue_redraw()


func _refresh_player_status_row(player: UnitState) -> void:
	StatusUi.populate_status_row(_player_status_row, player, true)


func _refresh_unit_roster() -> void:
	for child in _unit_roster.get_children():
		_unit_roster.remove_child(child)
		child.free()
	var state := _controller.state
	for unit in state.units.values():
		if not unit.alive:
			continue
		var card := _create_unit_card(unit, state)
		_unit_roster.add_child(card)


func _create_unit_card(unit: UnitState, state: GameState) -> Control:
	var card := PanelContainer.new()
	var selected := unit.uid == _inspect_uid
	var accent := Color(0.95, 0.35, 0.35) if unit.team == Constants.TEAM_ENEMY else BattleUiTheme.PHASE_PLAYER
	card.add_theme_stylebox_override("panel", BattleUiTheme.panel_style(accent if selected else BattleUiTheme.BORDER.darkened(0.1)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(28, 28)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = UnitLooks.get_unit_texture(unit.unit_def_id)
	icon.self_modulate = UnitLooks.sprite_modulate_for_unit(unit.team, unit.unit_def_id)
	row.add_child(icon)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var unit_name: String = _data_registry().get_unit_display_name(unit.unit_def_id)
	var title := Label.new()
	title.text = unit_name
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", BattleUiTheme.TEXT)
	info.add_child(title)
	var meta := Label.new()
	var armor := CombatRules.current_armor(state, unit)
	meta.text = "HP %d/%d  速%d  甲%d  %s" % [unit.hp, unit.max_hp, unit.speed, armor, _slot_icons(unit, state)]
	meta.add_theme_font_size_override("font_size", 10)
	meta.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
	info.add_child(meta)
	if not unit.statuses.is_empty():
		info.add_child(StatusUi.build_status_row(unit, true))
	if unit.intent != null and unit.team == Constants.TEAM_ENEMY:
		var intent_label := Label.new()
		intent_label.text = unit.intent.preview_text
		intent_label.add_theme_font_size_override("font_size", 10)
		intent_label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.45))
		info.add_child(intent_label)
	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	btn.pressed.connect(func(): _select_unit(unit.uid))
	card.add_child(btn)
	card.custom_minimum_size = Vector2(0, 56)
	return card


func _select_unit(uid: String) -> void:
	_inspect_uid = uid
	_refresh()


func _slot_icons(unit: UnitState, state: GameState) -> String:
	if unit.slots.is_empty():
		return ""
	var parts: Array[String] = []
	for slot in unit.slots:
		if slot.locked:
			parts.append("🔒")
		elif slot.gem_uid.is_empty():
			parts.append("○")
		else:
			var gem: GemState = state.gems.get(slot.gem_uid, null)
			parts.append(UnitLooks.gem_symbol(gem) if gem != null else "?")
	return "[%s]" % "".join(parts)


func _refresh_inspect() -> void:
	var state := _controller.state
	for child in _slot_box.get_children():
		child.queue_free()
	if _inspect_uid.is_empty():
		_inspect_title.text = "单位详情"
		_inspect_body.text = "[color=#666b78]点击左侧单位或棋盘单位查看详情[/color]"
		return
	var unit: UnitState = state.units.get(_inspect_uid, null)
	if unit == null:
		_inspect_title.text = "已阵亡"
		_inspect_body.text = ""
		return
	var unit_name: String = _data_registry().get_unit_display_name(unit.unit_def_id)
	var armor_value := CombatRules.current_armor(state, unit)
	_inspect_title.text = "%s" % unit_name
	var lines: Array[String] = []
	lines.append("[color=#9aa0ad]HP %d/%d · 护甲 %d · 速度 %d[/color]" % [unit.hp, unit.max_hp, armor_value, unit.speed])
	if unit.intent != null and unit.team == Constants.TEAM_ENEMY:
		lines.append("[color=#ffb07a]意图: %s[/color]" % unit.intent.preview_text)
	lines.append(StatusUi.format_all_bbcode(unit))
	for slot in unit.slots:
		lines.append(_slot_detail_bbcode(state, unit, slot))
		_slot_box.add_child(_create_slot_chip(state, unit, slot))
	_inspect_body.text = "\n".join(lines)


func _slot_detail_bbcode(state: GameState, unit: UnitState, slot: SlotState) -> String:
	var slot_name := "红" if slot.slot_type == Constants.SLOT_RED else ("蓝" if slot.slot_type == Constants.SLOT_BLUE else "黑")
	var slot_col := UnitLooks.slot_color(slot.slot_type)
	var col_hex := slot_col.to_html(false)
	if slot.locked:
		return "[color=%s]  %s 🔒 锁定[/color]" % [col_hex, slot_name]
	if slot.gem_uid.is_empty():
		return "[color=%s]  %s ○ 空槽[/color]" % [col_hex, slot_name]
	var gem: GemState = state.gems.get(slot.gem_uid, null)
	if gem == null:
		return "[color=%s]  %s ?[/color]" % [col_hex, slot_name]
	var gem_name: String = _data_registry().get_gem_display_name(gem)
	var effect: String = GemEffects.get_slot_effect_description(gem, slot.slot_type, _slot_effect_context(unit, slot))
	if effect.is_empty():
		return "[color=%s]  %s ◆ %s[/color]" % [col_hex, slot_name, gem_name]
	return "[color=%s]  %s ◆ %s[/color] [color=#8a909c]— %s[/color]" % [col_hex, slot_name, gem_name, effect]


func _create_slot_chip(state: GameState, unit: UnitState, slot: SlotState) -> Control:
	var chip := PanelContainer.new()
	var color := UnitLooks.slot_color(slot.slot_type)
	if not slot.gem_uid.is_empty():
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem != null:
			color = UnitLooks.gem_color(gem)
	chip.add_theme_stylebox_override("panel", BattleUiTheme.chip_style(color))
	var label := Label.new()
	var slot_name := "红" if slot.slot_type == Constants.SLOT_RED else ("蓝" if slot.slot_type == Constants.SLOT_BLUE else "黑")
	if slot.locked:
		label.text = "%s🔒" % slot_name
		chip.tooltip_text = "%s槽：锁定" % slot_name
	elif slot.gem_uid.is_empty():
		label.text = "%s○" % slot_name
		chip.tooltip_text = "%s槽：空" % slot_name
	else:
		var gem: GemState = state.gems.get(slot.gem_uid, null)
		if gem == null:
			label.text = "%s?" % slot_name
			chip.tooltip_text = "%s槽：无宝石数据" % slot_name
		else:
			var gem_name: String = _data_registry().get_gem_display_name(gem)
			label.text = "%s·%s" % [slot_name, gem_name]
			chip.tooltip_text = _slot_chip_tooltip(gem, slot, unit)

	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", BattleUiTheme.TEXT)
	chip.add_child(label)
	return chip


func _slot_effect_context(unit: UnitState, slot: SlotState) -> String:
	match slot.slot_type:
		Constants.SLOT_RED:
			return "enemy_active" if unit.team == Constants.TEAM_ENEMY else "player_trigger"
		Constants.SLOT_BLUE:
			return "unit_blue"
	return ""


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
	_skill_btn.disabled = not can_act or not _controller.can_use_action(Constants.ACTION_SKILL)
	_extract_btn.disabled = not can_act or not _controller.can_use_action(Constants.ACTION_EXTRACT)
	_insert_btn.disabled = not can_act or not _controller.can_use_action(Constants.ACTION_INSERT)
	_trigger_btn.disabled = not can_act or not _controller.can_use_action(Constants.ACTION_TRIGGER)
	_end_turn_btn.disabled = not can_act or _controller.state == null or _controller.state.phase != Constants.PHASE_PLAYER
	BattleUiTheme.apply_button(_move_btn, "move", current == Constants.ACTION_MOVE)
	BattleUiTheme.apply_button(_attack_btn, "combat", current == Constants.ACTION_ATTACK)
	BattleUiTheme.apply_button(_skill_btn, "skill", current == Constants.ACTION_SKILL)
	BattleUiTheme.apply_button(_extract_btn, "gem", current == Constants.ACTION_EXTRACT)
	BattleUiTheme.apply_button(_insert_btn, "gem", current == Constants.ACTION_INSERT)
	BattleUiTheme.apply_button(_trigger_btn, "gem", current == Constants.ACTION_TRIGGER)
	BattleUiTheme.apply_button(_end_turn_btn, "end", false)
	if _controller.can_use_action(Constants.ACTION_SKILL):
		var held := _controller.get_held_gem()
		if held != null:
			_skill_btn.text = "技能·%s" % _data_registry().get_gem_display_name(held)
		else:
			var player := _controller.state.get_player()
			var red := player.get_slot(Constants.SLOT_RED) if player != null else null
			if red != null and not red.gem_uid.is_empty():
				var gem: GemState = _controller.state.gems.get(red.gem_uid, null)
				if gem != null:
					_skill_btn.text = "技能·%s" % _data_registry().get_gem_display_name(gem)
				else:
					_skill_btn.text = "技能"
			else:
				_skill_btn.text = "技能"
	else:
		_skill_btn.text = "技能"
	_extract_btn.text = "拔出" if _controller.can_use_action(Constants.ACTION_EXTRACT) else "拔出×"
	_insert_btn.text = "嵌入" if _controller.can_use_action(Constants.ACTION_INSERT) else "嵌入×"


func _refresh_combat_log() -> void:
	var state := _controller.state
	if state == null:
		_log_label.text = ""
		return
	var log_lines := state.combat_log.slice(maxi(0, state.combat_log.size() - 6))
	_log_label.text = _format_combat_log(log_lines)


func _format_combat_log(lines: PackedStringArray) -> String:
	var formatted: Array[String] = []
	for line in lines:
		if "伤害" in line or "被击败" in line:
			formatted.append("[color=#ff8a80]%s[/color]" % line)
		elif "嵌入" in line or "拔出" in line or "宝石" in line:
			formatted.append("[color=#8fd4a8]%s[/color]" % line)
		elif "回合" in line or "遭遇" in line:
			formatted.append("[color=#9aa0ad]%s[/color]" % line)
		else:
			formatted.append("[color=#c8cad4]%s[/color]" % line)
	return "\n".join(formatted)


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
	if _board != null:
		_board.set_animation_speed_scale(_animation_speed_scale)


func _scaled_anim_time(base_duration: float) -> float:
	return base_duration / _animation_speed_scale


func _consume_enemy_turn(enemy_uid: String) -> void:
	var idx: int = _enemy_turn_queue.find(enemy_uid)
	if idx >= 0:
		_enemy_turn_queue.remove_at(idx)


func _refresh_turn_queue() -> void:
	var state := _controller.state
	if state == null:
		return
	for child in _queue_row.get_children():
		child.queue_free()
	var active_uid: String = _get_active_turn_uid()
	var active_unit: UnitState = state.units.get(active_uid, null)
	if active_unit != null:
		var active_name: String = _data_registry().get_unit_display_name(active_unit.unit_def_id)
		_queue_hint.text = "当前 %s · 速 %d" % [active_name, active_unit.speed]
	else:
		_queue_hint.text = "当前 —"
	for uid in _build_turn_timeline_uids(active_uid, 8):
		var unit: UnitState = state.units.get(uid, null)
		if unit != null and unit.alive:
			_queue_row.add_child(_create_timeline_avatar(unit, uid == active_uid))


func _get_active_turn_uid() -> String:
	var state := _controller.state
	if state == null:
		return ""
	if state.phase == Constants.PHASE_PLAYER:
		var player: UnitState = state.get_player()
		return player.uid if player != null and player.alive else ""
	if _enemy_phase_running and not _enemy_turn_queue.is_empty():
		return _enemy_turn_queue[0]
	return ""


func _build_turn_timeline_uids(active_uid: String, max_items: int) -> Array[String]:
	var state := _controller.state
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


func _create_timeline_avatar(unit: UnitState, is_active: bool) -> Control:
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(48, 54)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(40, 40)
	var accent := BattleUiTheme.TEXT_GOLD if is_active else BattleUiTheme.BORDER
	frame.add_theme_stylebox_override("panel", BattleUiTheme.panel_style(accent))
	root.add_child(frame)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(32, 32)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = UnitLooks.get_unit_texture(unit.unit_def_id)
	frame.add_child(icon)
	var speed_label := Label.new()
	speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speed_label.text = "%d" % unit.speed
	speed_label.add_theme_font_size_override("font_size", 10)
	speed_label.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD if is_active else BattleUiTheme.TEXT_MUTED)
	root.add_child(speed_label)
	return root


func _style_chip(label: Label, highlight: bool, color: Color) -> void:
	if not highlight:
		label.remove_theme_stylebox_override("normal")
		label.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
		return
	label.add_theme_stylebox_override("normal", BattleUiTheme.chip_style(color))
	label.add_theme_color_override("font_color", BattleUiTheme.TEXT)


func _flat_style(bg: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_corner_radius_all(4)
	return box
