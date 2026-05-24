extends Control
## 战斗场景主控制器
## 核心改动：
## - 敌方回合用 await 逐个执行，每个敌人动完才轮到下一个
## - 槽位弹窗改为点击触发（不是 hover），解决交互冲突
## - 左侧面板可折叠，地图占满全屏

const UnitVisuals = preload("res://scripts/ui/unit_visuals.gd")
const SlotPopup = preload("res://scripts/ui/slot_popup.gd")

@onready var _board: Control = $BoardLayer/IsometricBoard
@onready var _status_panel: PanelContainer = $HudLayer/StatusPanel
@onready var _portrait: TextureRect = $HudLayer/StatusPanel/VBox/PlayerRow/Portrait
@onready var _player_name: Label = $HudLayer/StatusPanel/VBox/PlayerRow/Info/Name
@onready var _hp_bar: ProgressBar = $HudLayer/StatusPanel/VBox/PlayerRow/Info/HpBar
@onready var _turn_label: Label = $HudLayer/StatusPanel/VBox/TurnLabel
@onready var _held_label: Label = $HudLayer/StatusPanel/VBox/HeldLabel
@onready var _hint_label: Label = $HudLayer/StatusPanel/VBox/HintLabel
@onready var _unit_list: ItemList = $HudLayer/StatusPanel/VBox/UnitList
@onready var _inspect_title: Label = $HudLayer/StatusPanel/VBox/InspectTitle
@onready var _inspect_body: RichTextLabel = $HudLayer/StatusPanel/VBox/InspectBody
@onready var _slot_box: HBoxContainer = $HudLayer/StatusPanel/VBox/SlotBox
@onready var _log_label: RichTextLabel = $HudLayer/StatusPanel/VBox/Log
@onready var _toggle_panel_btn: Button = $HudLayer/TogglePanelBtn
@onready var _preview_panel: PanelContainer = $HudLayer/PreviewPanel
@onready var _preview_title: Label = $HudLayer/PreviewPanel/VBox/Title
@onready var _preview_body: Label = $HudLayer/PreviewPanel/VBox/Body
@onready var _message_label: Label = $HudLayer/TopCenter/Message
@onready var _move_btn: Button = $HudLayer/BottomBar/ActionBar/MoveBtn
@onready var _attack_btn: Button = $HudLayer/BottomBar/ActionBar/AttackBtn
@onready var _skill_btn: Button = $HudLayer/BottomBar/ActionBar/SkillBtn
@onready var _extract_btn: Button = $HudLayer/BottomBar/ActionBar/ExtractBtn
@onready var _insert_btn: Button = $HudLayer/BottomBar/ActionBar/InsertBtn
@onready var _trigger_btn: Button = $HudLayer/BottomBar/ActionBar/TriggerBtn
@onready var _end_turn_btn: Button = $HudLayer/BottomBar/ActionBar/EndTurnBtn

var _controller: BattleController = BattleController.new()
var _encounter_id: String = "tutorial_001"

var _inspect_uid: String = ""
var _hover_cell: Vector2i = Vector2i(-1, -1)
var _panel_visible: bool = true
var _enemy_phase_running: bool = false  # 敌方回合进行中，锁定玩家输入

# 弹出式槽位选择器
var _slot_popup: Control = null


func _ready() -> void:
	_controller.state_changed.connect(_refresh)
	_controller.battle_ended.connect(_on_battle_ended)
	_controller.anim_move.connect(_on_anim_move)
	_controller.anim_move_path.connect(_on_anim_move_path)
	_controller.anim_damage.connect(_on_anim_damage)
	_controller.anim_gem_flash.connect(_on_anim_gem_flash)
	_board.cell_clicked.connect(_on_cell_clicked)
	_board.cell_hovered.connect(_on_cell_hovered)
	_unit_list.item_selected.connect(_on_unit_list_selected)
	_toggle_panel_btn.pressed.connect(_on_toggle_panel)
	_style_action_buttons()
	_create_slot_popup()
	_start_battle(GameService.pending_encounter_id)


func _create_slot_popup() -> void:
	_slot_popup = SlotPopup.new()
	$HudLayer.add_child(_slot_popup)
	_slot_popup.slot_selected.connect(_on_popup_slot_selected)
	_slot_popup.tile_slot_selected.connect(_on_popup_tile_slot_selected)
	_slot_popup.cancelled.connect(_on_popup_cancelled)


func setup(encounter_id: String) -> void:
	_encounter_id = encounter_id
	if is_node_ready():
		_start_battle(encounter_id)


func _start_battle(encounter_id: String) -> void:
	_encounter_id = encounter_id
	_controller.start_encounter(encounter_id)
	_inspect_uid = ""
	_controller.select_action(Constants.ACTION_EXTRACT if encounter_id == "tutorial_001" else Constants.ACTION_MOVE)
	_refresh()
	if encounter_id == "tutorial_001":
		_show_tutorial_intro()


func _on_action_pressed(action: String) -> void:
	if _enemy_phase_running:
		return
	_dismiss_popup()
	_controller.select_action(action)
	_message_label.text = _controller.get_action_hint()
	_refresh()


# ═══════════════════════════════════════════════════════════════════════════
# 玩家输入
# ═══════════════════════════════════════════════════════════════════════════

func _on_cell_clicked(cell: Vector2i) -> void:
	if _enemy_phase_running:
		return
	var state := _controller.state
	if state == null or state.phase != Constants.PHASE_PLAYER:
		return

	var unit := state.get_unit_at(cell)

	match _controller.selected_action:
		Constants.ACTION_MOVE:
			_dismiss_popup()
			_show_result(_controller.try_move(cell))
		Constants.ACTION_ATTACK:
			_dismiss_popup()
			if unit != null:
				_inspect_uid = unit.uid
				_show_result(_controller.try_attack(unit.uid))
		Constants.ACTION_SKILL:
			_dismiss_popup()
			var skill_result := _controller.try_skill(cell)
			_show_result(skill_result)
			if skill_result.get("ok", false):
				# 播放技能动画
				var skill_events: Array = skill_result.get("events", [])
				for ev in skill_events:
					_play_anim_event(ev)
		Constants.ACTION_EXTRACT, Constants.ACTION_INSERT, Constants.ACTION_TRIGGER:
			# 点击有效目标 → 显示槽位弹窗（单位或地块）
			var targets: Array = _controller.get_highlights().get("targets", [])
			if cell in targets:
				if unit != null and unit.alive:
					_inspect_uid = unit.uid
					_show_slot_popup(unit)
				else:
					# 无单位但地块有槽位（祭坛/石柱）
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

	# 预览面板（跟随鼠标）
	var preview: Dictionary = _controller.get_cell_preview(cell)
	_preview_title.text = preview.get("title", "")
	_preview_body.text = preview.get("body", "")
	_preview_panel.visible = true
	var mouse: Vector2 = get_viewport().get_mouse_position()
	_preview_panel.position = mouse + Vector2(16, 16)
	_clamp_preview_panel()


func _show_slot_popup(unit: UnitState) -> void:
	var screen_pos: Vector2 = _board.grid_to_screen(unit.pos)
	var board_global: Vector2 = _board.global_position
	var popup_pos: Vector2 = board_global + screen_pos + Vector2(0, -60)
	_slot_popup.show_for_unit(
		unit,
		_controller.state,
		_controller.selected_action,
		popup_pos,
		_controller.check_slot_action
	)


func _show_tile_slot_popup(tile: TileState, cell: Vector2i) -> void:
	var screen_pos: Vector2 = _board.grid_to_screen(cell)
	var board_global: Vector2 = _board.global_position
	var popup_pos: Vector2 = board_global + screen_pos + Vector2(0, -60)
	_slot_popup.show_for_tile(
		tile,
		_controller.state,
		_controller.selected_action,
		popup_pos,
		_controller.check_tile_slot_action
	)


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
				_message_label.text = "已从地块拔出！点击目标嵌入"
			Constants.ACTION_INSERT:
				_controller.select_action(Constants.ACTION_ATTACK)
				_message_label.text = "已嵌入地块！选择攻击或触发"
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
				_message_label.text = "已拔出！点击目标嵌入（免费）"
			Constants.ACTION_INSERT:
				_controller.select_action(Constants.ACTION_ATTACK)
				_message_label.text = "已嵌入！选择攻击或触发"
	_refresh()


func _on_popup_cancelled() -> void:
	_refresh()


func _dismiss_popup() -> void:
	if _slot_popup != null and _slot_popup.is_showing():
		_slot_popup.hide_popup()


func _on_unit_list_selected(index: int) -> void:
	var meta: Variant = _unit_list.get_item_metadata(index)
	if meta is String:
		_inspect_uid = meta
		_refresh()


# ═══════════════════════════════════════════════════════════════════════════
# 敌方回合：真正的异步逐个执行
# ═══════════════════════════════════════════════════════════════════════════

func _on_end_turn_pressed() -> void:
	if _enemy_phase_running:
		return
	_dismiss_popup()
	_run_enemy_phase_async()


func _run_enemy_phase_async() -> void:
	_enemy_phase_running = true
	_controller.begin_enemy_phase()
	_message_label.text = "敌方回合..."
	_refresh()

	var enemies := _controller.get_sorted_enemies()
	for enemy in enemies:
		if not enemy.alive:
			continue
		if _controller.state.phase == Constants.PHASE_ENDED:
			break

		# 执行这个敌人的意图，获取动画事件
		var events: Array[Dictionary] = _controller.execute_single_enemy(enemy)

		# 逐个播放动画事件，每个都 await 完成
		for ev in events:
			await _play_anim_event(ev)

		# 每个敌人之间短暂停顿
		await get_tree().create_timer(0.2).timeout
		_board.queue_redraw()

	# 所有敌人执行完毕
	if _controller.state.phase != Constants.PHASE_ENDED:
		_controller.finish_enemy_phase()

	_enemy_phase_running = false
	_message_label.text = _controller.get_action_hint()
	_refresh()


## 播放单个动画事件并等待完成
func _play_anim_event(ev: Dictionary) -> void:
	match ev.get("type", ""):
		"move_step":
			var uid: String = ev.get("uid", "")
			var from_pos: Vector2i = ev.get("from", Vector2i.ZERO)
			var to_pos: Vector2i = ev.get("to", Vector2i.ZERO)
			_board.animate_move(uid, from_pos, to_pos)
			await get_tree().create_timer(0.22).timeout
		"damage":
			var pos: Vector2i = ev.get("pos", Vector2i.ZERO)
			var damage: int = ev.get("damage", 1)
			var is_crit: bool = ev.get("is_crit", false)
			_board.play_damage_effect(pos, damage, is_crit)
			await get_tree().create_timer(0.3).timeout
		"explode":
			var pos: Vector2i = ev.get("pos", Vector2i.ZERO)
			var radius: int = ev.get("radius", 1)
			_board.play_explosion(pos)
			var affected: Array[Vector2i] = BoardUtils.cells_in_radius(pos, radius)
			for cell in affected:
				if cell != pos:
					_board.play_damage_effect(cell, 4, true)
			_board.queue_redraw()
			await get_tree().create_timer(0.6).timeout
		"gem_flash":
			var pos: Vector2i = ev.get("pos", Vector2i.ZERO)
			var color: Color = ev.get("color", Color.WHITE)
			_board.play_gem_flash(pos, color)
			await get_tree().create_timer(0.25).timeout
		_:
			pass  # unit_start, unit_end 等标记不需要动画


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")


func _on_battle_ended(result: String) -> void:
	_message_label.text = "战斗结束: %s" % ("胜利！" if result == "win" else "失败...")
	_hint_label.text = ""
	GameService.finish_battle(result, _encounter_id, _controller.state.turn_index if _controller.state != null else 0)


func _show_result(result: Dictionary) -> void:
	if result.get("ok", false):
		_message_label.text = _controller.get_action_hint()
	else:
		_message_label.text = result.get("reason", "操作失败")


func _data_registry() -> Node:
	return Engine.get_main_loop().root.get_node("DataRegistry")


# ═══════════════════════════════════════════════════════════════════════════
# 面板折叠
# ═══════════════════════════════════════════════════════════════════════════

func _on_toggle_panel() -> void:
	_panel_visible = not _panel_visible
	_status_panel.visible = _panel_visible
	_toggle_panel_btn.text = "◀" if _panel_visible else "▶"
	# 调整棋盘区域
	var board_layer: Control = $BoardLayer
	if _panel_visible:
		board_layer.offset_left = 240.0
	else:
		board_layer.offset_left = 0.0


# ═══════════════════════════════════════════════════════════════════════════
# 刷新 UI
# ═══════════════════════════════════════════════════════════════════════════

func _refresh() -> void:
	var state := _controller.state
	if state == null:
		return
	var player := state.get_player()
	if player != null:
		_portrait.texture = UnitVisuals.get_unit_texture(player.unit_def_id)
		_player_name.text = _data_registry().get_unit_display_name(player.unit_def_id)
		_hp_bar.max_value = player.max_hp
		_hp_bar.value = player.hp

	var phase_text: String = "你的回合" if state.phase == Constants.PHASE_PLAYER else ("结束" if state.phase == Constants.PHASE_ENDED else "敌方")
	var move_icon: String = "✓" if state.player_moved else "○"
	var act_icon: String = "✓" if state.player_acted else "○"
	_turn_label.text = "T%d %s  移动%s 行动%s" % [state.turn_index, phase_text, move_icon, act_icon]

	var held := _controller.get_held_gem()
	if held != null:
		_held_label.text = "◆%s" % _data_registry().get_gem_display_name(held.gem_id)
		_held_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	else:
		_held_label.text = ""
		_held_label.remove_theme_color_override("font_color")

	var tutorial_hint: String = _controller.get_tutorial_hint()
	_hint_label.text = tutorial_hint

	# 教学关：步骤提示优先显示在顶部大字区域
	if not tutorial_hint.is_empty():
		_message_label.text = tutorial_hint.split("\n")[0]
	elif _message_label.text == "选择操作" or _message_label.text.is_empty():
		_message_label.text = _controller.get_action_hint()
	_board.state = state
	_board.selected_unit_uid = _inspect_uid
	_board.set_highlights(_controller.get_highlights())
	_refresh_unit_list()
	_refresh_inspect()
	_refresh_action_buttons()
	_board.queue_redraw()


func _refresh_unit_list() -> void:
	var state := _controller.state
	_unit_list.clear()
	for unit in state.units.values():
		if not unit.alive:
			continue
		var unit_name: String = _data_registry().get_unit_display_name(unit.unit_def_id)
		var hp_text: String = "♥%d/%d" % [unit.hp, unit.max_hp]
		var slot_text: String = _slot_icons(unit, state)
		var intent_text: String = ""
		if unit.intent != null and unit.team == Constants.TEAM_ENEMY:
			intent_text = " →%s" % unit.intent.preview_text
		var line: String = "%s %s%s%s" % [unit_name, hp_text, slot_text, intent_text]
		var idx: int = _unit_list.add_item(line)
		_unit_list.set_item_metadata(idx, unit.uid)
		if unit.uid == _inspect_uid:
			_unit_list.select(idx)


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
			if gem != null:
				parts.append(UnitVisuals.gem_symbol(gem.gem_id))
			else:
				parts.append("?")
	return " [%s]" % "".join(parts)


func _refresh_inspect() -> void:
	var state := _controller.state
	for child in _slot_box.get_children():
		child.queue_free()

	if _inspect_uid.is_empty():
		_inspect_title.text = ""
		_inspect_body.text = ""
	else:
		var unit: UnitState = state.units.get(_inspect_uid, null)
		if unit == null:
			_inspect_title.text = "已阵亡"
			_inspect_body.text = ""
		else:
			var unit_name: String = _data_registry().get_unit_display_name(unit.unit_def_id)
			_inspect_title.text = "%s  %d/%d HP" % [unit_name, unit.hp, unit.max_hp]
			var lines: Array[String] = []
			if unit.intent != null and unit.team == Constants.TEAM_ENEMY:
				lines.append("意图: %s" % unit.intent.preview_text)
			for i in range(unit.slots.size()):
				var slot: SlotState = unit.slots[i]
				lines.append(_slot_detail_line(state, slot))
			_inspect_body.text = "\n".join(lines)

			for i in range(unit.slots.size()):
				var slot: SlotState = unit.slots[i]
				var indicator := ColorRect.new()
				indicator.custom_minimum_size = Vector2(20, 20)
				indicator.color = UnitVisuals.slot_color(slot.slot_type)
				if slot.gem_uid.is_empty():
					indicator.color.a = 0.3
				if slot.locked:
					indicator.color = indicator.color.darkened(0.5)
				_slot_box.add_child(indicator)

	var log_lines := state.combat_log.slice(maxi(0, state.combat_log.size() - 4))
	_log_label.text = "\n".join(log_lines)


func _slot_detail_line(state: GameState, slot: SlotState) -> String:
	var label: String = "红" if slot.slot_type == Constants.SLOT_RED else ("蓝" if slot.slot_type == Constants.SLOT_BLUE else "黑")
	if slot.locked:
		return "  %s🔒" % label
	if slot.gem_uid.is_empty():
		return "  %s○" % label
	var gem: GemState = state.gems.get(slot.gem_uid, null)
	if gem == null:
		return "  %s?" % label
	return "  %s◆%s" % [label, _data_registry().get_gem_display_name(gem.gem_id)]


func _refresh_action_buttons() -> void:
	var current: String = _controller.selected_action
	_highlight_action_button(_move_btn, current == Constants.ACTION_MOVE)
	_highlight_action_button(_attack_btn, current == Constants.ACTION_ATTACK)
	_highlight_action_button(_skill_btn, current == Constants.ACTION_SKILL)
	_highlight_action_button(_extract_btn, current == Constants.ACTION_EXTRACT)
	_highlight_action_button(_insert_btn, current == Constants.ACTION_INSERT)
	_highlight_action_button(_trigger_btn, current == Constants.ACTION_TRIGGER)
	var can_act: bool = not _enemy_phase_running
	_move_btn.disabled = not can_act or not _controller.can_use_action(Constants.ACTION_MOVE)
	_attack_btn.disabled = not can_act or not _controller.can_use_action(Constants.ACTION_ATTACK)
	_skill_btn.disabled = not can_act or not _controller.can_use_action(Constants.ACTION_SKILL)
	_extract_btn.disabled = not can_act or not _controller.can_use_action(Constants.ACTION_EXTRACT)
	_insert_btn.disabled = not can_act or not _controller.can_use_action(Constants.ACTION_INSERT)
	_trigger_btn.disabled = not can_act or not _controller.can_use_action(Constants.ACTION_TRIGGER)
	_end_turn_btn.disabled = not can_act or _controller.state == null or _controller.state.phase != Constants.PHASE_PLAYER

	# 技能按钮动态文本：显示当前持有宝石名
	if _controller.can_use_action(Constants.ACTION_SKILL):
		var held := _controller.get_held_gem()
		if held != null:
			_skill_btn.text = "技能(%s)" % _data_registry().get_gem_display_name(held.gem_id)
		else:
			_skill_btn.text = "技能"
	else:
		_skill_btn.text = "技能(空)"

	_extract_btn.text = "拔出" if _controller.can_use_action(Constants.ACTION_EXTRACT) else "拔出(满)"
	_insert_btn.text = "嵌入" if _controller.can_use_action(Constants.ACTION_INSERT) else "嵌入(空)"


func _highlight_action_button(button: Button, active: bool) -> void:
	var style := StyleBoxFlat.new()
	if active:
		style.bg_color = Color(0.85, 0.65, 0.2, 0.95)
		style.border_color = Color(1, 0.9, 0.5)
	else:
		style.bg_color = Color(0.18, 0.18, 0.24, 0.92)
		style.border_color = Color(0.35, 0.35, 0.42)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("disabled", style)


func _style_action_buttons() -> void:
	for button in [_move_btn, _attack_btn, _skill_btn, _extract_btn, _insert_btn, _trigger_btn, _end_turn_btn]:
		button.custom_minimum_size = Vector2(88, 44)


func _clamp_preview_panel() -> void:
	# 限制预览面板最大高度为屏幕的 40%
	var max_panel_h: float = size.y * 0.4
	if _preview_panel.size.y > max_panel_h:
		_preview_panel.size.y = max_panel_h
		_preview_body.clip_text = true
	else:
		_preview_body.clip_text = false
	var max_x: float = size.x - _preview_panel.size.x - 8
	var max_y: float = size.y - _preview_panel.size.y - 8
	_preview_panel.position.x = clampf(_preview_panel.position.x, 8, maxf(max_x, 8.0))
	_preview_panel.position.y = clampf(_preview_panel.position.y, 8, maxf(max_y, 8.0))


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if _slot_popup != null and _slot_popup.is_showing():
			_dismiss_popup()
			get_viewport().set_input_as_handled()


# ═══════════════════════════════════════════════════════════════════════════
# 玩家动作动画回调（移动/攻击/宝石操作）
# ═══════════════════════════════════════════════════════════════════════════

func _on_anim_move(unit_uid: String, from_pos: Vector2i, to_pos: Vector2i) -> void:
	_board.animate_move(unit_uid, from_pos, to_pos)


func _on_anim_move_path(events: Array[Dictionary]) -> void:
	for ev in events:
		await _play_anim_event(ev)


func _on_anim_damage(grid: Vector2i, damage: int, is_crit: bool) -> void:
	_board.play_damage_effect(grid, damage, is_crit)


func _on_anim_gem_flash(grid: Vector2i, gem_color: Color) -> void:
	_board.play_gem_flash(grid, gem_color)


# ═══════════════════════════════════════════════════════════════════════════
# 教学引导
# ═══════════════════════════════════════════════════════════════════════════

func _show_tutorial_intro() -> void:
	var overlay := ColorRect.new()
	overlay.name = "TutorialOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.0, 0.0, 0.0, 0.75)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vbox.offset_left = -280
	vbox.offset_right = 280
	vbox.offset_top = -200
	vbox.offset_bottom = 200
	vbox.add_theme_constant_override("separation", 16)
	overlay.add_child(vbox)

	var title := Label.new()
	title.text = "窃律者 — 操作指南"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	vbox.add_child(title)

	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.custom_minimum_size = Vector2(0, 240)
	body.text = """[color=#aaaacc]这是一个回合制战术游戏。每回合你有：[/color]

[color=#5ad8ff]● 1次移动[/color] — 点底部「移动」按钮，再点蓝色高亮格
[color=#ffcc44]● 1次行动[/color] — 攻击/技能/触发宝石（三选一）
[color=#88ff88]● 免费操作[/color] — 拔出/嵌入宝石（不消耗行动）

[color=#ff6666]核心玩法：偷取敌人的宝石 → 装入自己红槽 → 释放技能！[/color]

[color=#aaaacc]你有 3 个槽位：[/color]
[color=#ff5555]红槽[/color] — 主动技能：装入宝石后点「技能」释放
[color=#5599ff]蓝槽[/color] — 被动防御：自动触发防御效果
[color=#333333]黑槽[/color] — 死亡触发：嵌入敌人身上，击杀时引爆

[color=#aaaacc]本关目标：[/color]
[color=#ffffff]① 点「拔出」→ 点自爆工兵 → 选红槽偷走爆炸宝石
② 点「技能」→ 对守卫释放爆炸（范围伤害！）
③ 或者：嵌入守卫黑槽 → 攻击补刀 → 死亡引爆[/color]

[color=#88ff88]操作完毕点「结束回合」，敌人会行动。[/color]"""
	vbox.add_child(body)

	var btn := Button.new()
	btn.text = "明白了，开始战斗！"
	btn.custom_minimum_size = Vector2(200, 48)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.85, 0.25, 0.35, 0.95)
	style.border_color = Color(1.0, 0.5, 0.4)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.pressed.connect(func(): overlay.queue_free())
	vbox.add_child(btn)

	# 淡入
	overlay.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(overlay, "modulate:a", 1.0, 0.3)
