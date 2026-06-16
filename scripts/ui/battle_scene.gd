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
const BattleEditorPanelScript = preload("res://scripts/ui/battle_editor_panel.gd")

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
@onready var _slot_box: Container = $HudLayer/StatusPanel/VBox/SlotClip/SlotBox
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
var _held_banner: PanelContainer = null
var _held_banner_icon: TextureRect = null
var _held_banner_label: Label = null
var _console_layer: CanvasLayer = null
var _console: Control = null
var _preview_panel_tween: Tween = null
var _preview_visible_target: bool = false
var _preview_fade_serial: int = 0
var _relic_reward_overlay: Node = null
var _relic_detail_overlay: Node = null
var _held_gem_icon: TextureRect = null
var _overload_chip: Label = null
var _relic_bar_root: Control = null
var _relic_bar_scroll: ScrollContainer = null
var _relic_bar_vbox: Container = null
var _tracked_player_uid: String = ""
var _editor_mode: bool = false
var _editor_tool: Dictionary = {}
var _editor_drag_active: bool = false
var _editor_panel: Control = null
var _editor_inspector: PanelContainer = null
var _editor_tool_label: Label = null
var _editor_target_label: Label = null
var _editor_hover_label: Label = null
var _editor_contents_box: VBoxContainer = null
var _editor_gem_list: VBoxContainer = null
var _editor_relic_list: VBoxContainer = null
var _editor_status_box: VBoxContainer = null
var _editor_status_grid: GridContainer = null
var _editor_result_label: Label = null
var _editor_remove_unit_btn: Button = null
var _editor_remove_entity_btn: Button = null
var _editor_remove_overlay_btn: Button = null
var _editor_unlimited_btn: Button = null
var _editor_action_cell: Vector2i = Vector2i(-1, -1)
var _editor_bound_state: GameState = null
var _editor_dummy_stats: Dictionary = {}
var _editor_session_active: bool = false
var _editor_run_snapshot: Dictionary = {}
var _editor_auto_boot_enabled: bool = true
var _editor_panel_toggle_btn: Button = null
var _editor_inspector_toggle_btn: Button = null
var _editor_inspector_body: VBoxContainer = null
var _editor_panel_user_positioned: bool = false

## 遭遇 room_type → 遗物来源 key（DataRegistry 池筛选用）
const _ENCOUNTER_RELIC_SOURCE := {
	"NORMAL_COMBAT": "normal_chest",
	"ELITE_COMBAT": "elite_combat",
	"END": "large_chest",
}
const _EDITOR_KIND_LABELS := {
	"unit": "怪物",
	"tile": "地块",
	"entity": "实体",
	"overlay": "Overlay",
	"gem": "宝石",
	"relic": "遗物",
}
const _EDITOR_STATUS_IDS: Array[String] = [
	Constants.STATUS_POISON,
	Constants.STATUS_BURNING,
	Constants.STATUS_SLOWED,
	Constants.STATUS_PARALYZED,
	Constants.STATUS_WET,
	Constants.STATUS_ROOTED,
	Constants.STATUS_VULNERABLE,
	Constants.STATUS_LIGHT_EXPOSED,
	Constants.STATUS_BLINDED,
	Constants.STATUS_ARMOR,
]

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
	_board.editor_tool_drag_hovered.connect(_on_editor_tool_drag_hovered)
	_board.editor_tool_dropped.connect(_on_editor_tool_dropped)
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
		"turn_chips": _turn_chips,
		"relic_bar_root": _relic_bar_root,
		"relic_bar_scroll": _relic_bar_scroll,
		"relic_bar_vbox": _relic_bar_vbox,
		"show_relic_detail_cb": Callable(self , "_show_relic_detail_popup"),
		"select_unit_cb": Callable(self , "_select_unit"),
		"set_timeline_hover_cb": Callable(self , "_set_timeline_hover"),
		"clear_timeline_hover_cb": Callable(self , "_clear_timeline_hover"),
	})
	_apply_animation_speed()
	_start_battle(GameService.pending_encounter_id)
	call_deferred("_restore_battle_reward_if_needed")


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
	$HudLayer/TurnQueuePanel.add_theme_stylebox_override("panel", BattleUiTheme.panel_style(BattleUiTheme.PHASE_PLAYER.darkened(0.35)))
	_preview_panel.add_theme_stylebox_override("panel", BattleUiTheme.tooltip_style())
	_inspect_name.add_theme_color_override("font_color", BattleUiTheme.TEXT)
	_inspect_stats.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
	_message_label.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	_hint_label.add_theme_color_override("font_color", BattleUiTheme.TEXT_HINT)
	_queue_title.add_theme_color_override("font_color", BattleUiTheme.TEXT)
	_hp_bar.add_theme_stylebox_override("background", BattleUiTheme.bar_bg_style())
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
	_slot_popup.editor_unit_slot_selected.connect(_on_editor_unit_slot_selected)
	_slot_popup.editor_tile_slot_selected.connect(_on_editor_tile_slot_selected)
	_slot_popup.editor_unit_slot_added.connect(_on_editor_unit_slot_added)
	_slot_popup.editor_tile_slot_added.connect(_on_editor_tile_slot_added)
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


func _create_editor_ui() -> void:
	_editor_panel = BattleEditorPanelScript.new()
	_editor_panel.position = Vector2(8, 220)
	_editor_panel.size = Vector2(360, 520)
	_editor_panel.tool_selected.connect(_on_editor_tool_selected)
	_editor_panel.tool_drag_started.connect(_on_editor_tool_drag_started)
	_editor_panel.relic_requested.connect(_on_editor_relic_requested)
	_editor_panel.close_requested.connect(_on_editor_panel_close_requested)
	_editor_panel.panel_moved.connect(_on_editor_panel_moved)
	$HudLayer.add_child(_editor_panel)
	_editor_panel.setup(Engine.get_main_loop().root.get_node("DataRegistry"))

	_editor_panel_toggle_btn = Button.new()
	_editor_panel_toggle_btn.position = Vector2(8, 220)
	_editor_panel_toggle_btn.size = Vector2(116, 32)
	_editor_panel_toggle_btn.text = "展开编辑器"
	_editor_panel_toggle_btn.visible = false
	_editor_panel_toggle_btn.pressed.connect(_on_editor_panel_toggle_pressed)
	BattleUiTheme.apply_button(_editor_panel_toggle_btn, "ghost")
	$HudLayer.add_child(_editor_panel_toggle_btn)

	_editor_inspector = PanelContainer.new()
	_editor_inspector.mouse_filter = Control.MOUSE_FILTER_STOP
	_editor_inspector.add_theme_stylebox_override("panel", BattleUiTheme.panel_style(BattleUiTheme.PHASE_PLAYER))
	$HudLayer.add_child(_editor_inspector)

	var inspector_vbox := VBoxContainer.new()
	inspector_vbox.add_theme_constant_override("separation", 6)
	_editor_inspector.add_child(inspector_vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	inspector_vbox.add_child(header)

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
	close_btn.pressed.connect(_on_editor_inspector_close_pressed)
	BattleUiTheme.apply_button(close_btn, "ghost")
	header.add_child(close_btn)

	_editor_inspector_body = VBoxContainer.new()
	_editor_inspector_body.add_theme_constant_override("separation", 6)
	inspector_vbox.add_child(_editor_inspector_body)

	_editor_tool_label = Label.new()
	_editor_tool_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_editor_tool_label.add_theme_color_override("font_color", BattleUiTheme.TEXT)
	_editor_inspector_body.add_child(_editor_tool_label)

	_editor_target_label = Label.new()
	_editor_target_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_editor_target_label.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	_editor_inspector_body.add_child(_editor_target_label)

	_editor_hover_label = Label.new()
	_editor_hover_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_editor_hover_label.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
	_editor_inspector_body.add_child(_editor_hover_label)

	_editor_contents_box = VBoxContainer.new()
	_editor_contents_box.add_theme_constant_override("separation", 4)
	_editor_inspector_body.add_child(_editor_contents_box)

	var gem_title := Label.new()
	gem_title.text = "宝石"
	gem_title.add_theme_font_size_override("font_size", 12)
	gem_title.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
	_editor_contents_box.add_child(gem_title)

	_editor_gem_list = VBoxContainer.new()
	_editor_gem_list.add_theme_constant_override("separation", 4)
	_editor_contents_box.add_child(_editor_gem_list)

	var relic_title := Label.new()
	relic_title.text = "遗物"
	relic_title.add_theme_font_size_override("font_size", 12)
	relic_title.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
	_editor_contents_box.add_child(relic_title)

	_editor_relic_list = VBoxContainer.new()
	_editor_relic_list.add_theme_constant_override("separation", 4)
	_editor_contents_box.add_child(_editor_relic_list)

	_editor_status_box = VBoxContainer.new()
	_editor_status_box.add_theme_constant_override("separation", 4)
	_editor_inspector_body.add_child(_editor_status_box)
	var status_title := Label.new()
	status_title.text = "状态"
	status_title.add_theme_font_size_override("font_size", 12)
	status_title.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
	_editor_status_box.add_child(status_title)
	_editor_status_grid = GridContainer.new()
	_editor_status_grid.columns = 5
	_editor_status_grid.add_theme_constant_override("h_separation", 4)
	_editor_status_grid.add_theme_constant_override("v_separation", 4)
	_editor_status_box.add_child(_editor_status_grid)

	_editor_result_label = Label.new()
	_editor_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_editor_result_label.add_theme_color_override("font_color", BattleUiTheme.TEXT_HINT)
	_editor_inspector_body.add_child(_editor_result_label)

	var actions := GridContainer.new()
	actions.columns = 2
	actions.add_theme_constant_override("h_separation", 6)
	actions.add_theme_constant_override("v_separation", 6)
	_editor_inspector_body.add_child(actions)

	_editor_remove_unit_btn = Button.new()
	_editor_remove_unit_btn.text = "删单位"
	_editor_remove_unit_btn.pressed.connect(_on_editor_remove_unit_pressed)
	actions.add_child(_editor_remove_unit_btn)
	BattleUiTheme.apply_button(_editor_remove_unit_btn, "ghost")

	_editor_remove_entity_btn = Button.new()
	_editor_remove_entity_btn.text = "删实体"
	_editor_remove_entity_btn.pressed.connect(_on_editor_remove_entity_pressed)
	actions.add_child(_editor_remove_entity_btn)
	BattleUiTheme.apply_button(_editor_remove_entity_btn, "ghost")

	_editor_remove_overlay_btn = Button.new()
	_editor_remove_overlay_btn.text = "删Overlay"
	_editor_remove_overlay_btn.pressed.connect(_on_editor_remove_overlay_pressed)
	actions.add_child(_editor_remove_overlay_btn)
	BattleUiTheme.apply_button(_editor_remove_overlay_btn, "ghost")

	_editor_unlimited_btn = Button.new()
	_editor_unlimited_btn.toggle_mode = true
	_editor_unlimited_btn.text = "无限行动 关"
	_editor_unlimited_btn.pressed.connect(_on_editor_unlimited_actions_pressed)
	_editor_inspector_body.add_child(_editor_unlimited_btn)
	BattleUiTheme.apply_button(_editor_unlimited_btn, "ghost")


	_editor_inspector_toggle_btn = Button.new()
	_editor_inspector_toggle_btn.position = Vector2(size.x - 124, 108)
	_editor_inspector_toggle_btn.size = Vector2(116, 32)
	_editor_inspector_toggle_btn.text = "展开检查器"
	_editor_inspector_toggle_btn.visible = false
	_editor_inspector_toggle_btn.pressed.connect(_on_editor_inspector_toggle_pressed)
	BattleUiTheme.apply_button(_editor_inspector_toggle_btn, "ghost")
	$HudLayer.add_child(_editor_inspector_toggle_btn)

	_sync_editor_inspector("")
	call_deferred("_layout_editor_ui")


func _editor_available() -> bool:
	return GameService.pending_battle_mode == "editor" and OS.is_debug_build() and bool(SettingsService.get_value("battle_editor_enabled"))


func setup(encounter_id: String) -> void:
	_encounter_id = encounter_id
	if is_node_ready():
		_start_battle(encounter_id)


func _start_battle(encounter_id: String) -> void:
	_encounter_id = encounter_id
	_board.clear_gem_visuals()
	_tracked_player_uid = ""
	_editor_dummy_stats.clear()
	_editor_bound_state = null
	_controller.start_encounter(encounter_id, 0, GameService.pending_room_id)
	_bind_editor_state_signals()
	_mark_visible_enemies_seen()
	_inspect_uid = _controller.selected_unit_uid
	_controller.select_action("")
	_refresh()
	_board.init_unit_orientations()
	if _editor_available() and _editor_panel != null and _editor_auto_boot_enabled:
		_editor_auto_boot_enabled = false
		_enter_editor_mode()
	if encounter_id == "tutorial_001" and not _editor_available() and bool(SettingsService.get_value("show_tutorial")):
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
				var has_attack_visual := false
				for ev in attack_events:
					if str(ev.get("type", "")) in ["projectile", "light_beam"]:
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
	if _editor_drag_active:
		if not valid:
			_board.set_hover(Vector2i(-1, -1))
			_board.clear_editor_preview()
			_sync_editor_hover("", "")
			_refresh_editor_focus()
			_hide_preview_panel()
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
		_hide_preview_panel()
		_board.set_hover(Vector2i(-1, -1))
		if _timeline_hover_uid.is_empty():
			_board.set_timeline_hover_unit("")
		_board.set_highlights(_controller.get_highlights())
		_refresh_editor_focus()
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
	_refresh_editor_focus()


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
		var execution: Dictionary = _controller.execute_single_enemy(enemy)
		var events: Array[Dictionary] = execution.get("events", [])
		await _play_presentation_sequence(execution.get("presentation_state", _controller.state.clone()), events)
		if not is_inside_tree():
			break
		await _await_scene_timer(0.35)
		if not is_inside_tree():
			break
		_consume_enemy_turn(enemy.uid)
		_refresh()
	if is_inside_tree() and _controller.state != null and _controller.state.phase != Constants.PHASE_ENDED:
		_controller.finish_enemy_phase()
	_enemy_phase_running = false
	_enemy_turn_queue.clear()
	if not is_inside_tree():
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
	GameService.pending_battle_mode = "normal"
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
		_grant_combat_gold_once()
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


func _grant_combat_gold_once() -> void:
	if not GameService.adventure_return:
		return
	var room_id := GameService.pending_room_id
	if room_id.is_empty():
		return
	var transaction_id := "%s:battle_gold" % room_id
	var reward := EconomyService.get_combat_reward(AdventureService.pending_room_type)
	var grant_result := EconomyService.grant("gold", reward, "combat_reward", {
		"transaction_id": transaction_id,
		"room_id": room_id,
		"room_type": AdventureService.pending_room_type,
	})
	if not bool(grant_result.get("ok", false)):
		return
	var entry: Dictionary = grant_result.get("entry", {})
	if entry.is_empty():
		return
	_message_label.text = "战斗结束 — 胜利 · %s" % EconomyService.format_entry(entry)


func _placeholder_relic_offer() -> Array[String]:
	var offer: Array[String] = []
	offer.append("relic_placeholder")
	return offer


func _show_gem_reward(gem_offer: Array[String], relic_offer: Array[String], battle_result: String) -> void:
	_mark_battle_reward_pending("gem", battle_result, not relic_offer.is_empty())
	var overlay := _build_gem_overlay(gem_offer, relic_offer, battle_result)
	_relic_reward_overlay = overlay
	add_child(overlay)


func _build_gem_overlay(gem_offer: Array[String], relic_offer: Array[String], battle_result: String) -> Node:
	var canvas := CanvasLayer.new()
	canvas.layer = 80

	var root_ctrl := Control.new()
	root_ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_ctrl.theme = BattleUiTheme.build_theme()
	canvas.add_child(root_ctrl)

	var bg := ColorRect.new()
	bg.color = Color(UiPalette.BG_DEEP, 0.82)
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
	title.add_theme_font_size_override("font_size", BattleUiTheme.FONT_TITLE)
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
		var acquire_result := RunService.acquire_gem(gem_id)
		if not bool(acquire_result.get("ok", false)):
			var carried_gem_id := str(acquire_result.get("carried_gem_id", ""))
			var carried_name := DataRegistry.get_gem_display_name(carried_gem_id) if not carried_gem_id.is_empty() else "已有手持宝石"
			_message_label.text = "无法领取：当前手持 %s，请先跳过或在后续流程中处理。" % carried_name
			return
	if canvas != null and is_instance_valid(canvas):
		canvas.queue_free()
	_relic_reward_overlay = null
	var has_relics := not relic_offer.is_empty() and not relic_offer.all(
		func(rid: String) -> bool: return rid == "relic_placeholder"
	)
	if has_relics:
		_show_relic_reward(relic_offer, battle_result)
	else:
		RunService.clear_pending_decision()
		RunService.set_run_phase("MAP")
		_finish_battle_and_navigate(battle_result)


func _show_relic_reward(offer: Array[String], battle_result: String) -> void:
	_mark_battle_reward_pending("relic", battle_result, false)
	var overlay := _build_relic_overlay(offer, battle_result)
	_relic_reward_overlay = overlay
	add_child(overlay)


func _build_relic_overlay(offer: Array[String], battle_result: String) -> Node:
	var canvas := CanvasLayer.new()
	canvas.layer = 80

	var root_ctrl := Control.new()
	root_ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_ctrl.theme = BattleUiTheme.build_theme()
	canvas.add_child(root_ctrl)

	var bg := ColorRect.new()
	bg.color = Color(UiPalette.BG_DEEP, 0.82)
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
	title.add_theme_font_size_override("font_size", BattleUiTheme.FONT_TITLE)
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
	RunService.clear_pending_decision()
	RunService.set_run_phase("MAP")
	_finish_battle_and_navigate(battle_result)


func _finish_battle_and_navigate(result: String) -> void:
	if GameService.pending_battle_mode == "editor":
		GameService.pending_battle_mode = "normal"
		get_tree().change_scene_to_file("res://scenes/main/main.tscn")
		return
	_record_enemy_codex_progress()
	if result == "win" and _controller.state != null:
		RunService.capture_player_battle_state(_controller.state)
	elif result != "win" and RunService.is_run_active():
		RunService.complete_run("loss")
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


func _mark_battle_reward_pending(reward_kind: String, battle_result: String, has_followup_relic: bool) -> void:
	if not RunService.is_run_active():
		return
	RunService.set_run_phase("BATTLE_REWARD")
	RunService.set_pending_decision({
		"type": "battle_reward",
		"room_id": GameService.pending_room_id,
		"room_type": AdventureService.pending_room_type,
		"encounter_id": _encounter_id,
		"battle_result": battle_result,
		"reward_kind": reward_kind,
		"has_followup_relic": has_followup_relic,
	})


func _restore_battle_reward_if_needed() -> void:
	if not RunService.is_run_active():
		return
	if RunService.get_run_phase() != "BATTLE_REWARD":
		return
	var pending := RunService.get_pending_decision()
	if str(pending.get("type", "")) != "battle_reward":
		return
	var room_id := str(pending.get("room_id", GameService.pending_room_id))
	var battle_result := str(pending.get("battle_result", "win"))
	var source: String = str(_ENCOUNTER_RELIC_SOURCE.get(
		AdventureService.pending_room_type.to_upper(), "normal_chest"
	))
	var gem_offer: Array[String] = RunService.get_or_roll_gem_offer(room_id, source, 3)
	var relic_offer: Array[String] = RunService.get_or_roll_relic_offer(room_id, source, 3)
	match str(pending.get("reward_kind", "")):
		"gem":
			if _relic_reward_overlay == null:
				var overlay := _build_gem_overlay(gem_offer, relic_offer, battle_result)
				_relic_reward_overlay = overlay
				add_child(overlay)
		"relic":
			if _relic_reward_overlay == null:
				var overlay := _build_relic_overlay(relic_offer, battle_result)
				_relic_reward_overlay = overlay
				add_child(overlay)


func _on_toggle_panel() -> void:
	_panel_visible = not _panel_visible
	_status_panel.visible = _panel_visible
	_toggle_panel_btn.text = "◀" if _panel_visible else "▶"
	_hud_presenter.sync_toggle_btn_x(_panel_visible)
	_editor_panel_user_positioned = false
	_layout_editor_ui()


func _refresh() -> void:
	var state := _view_state()
	if state == null:
		return
	if _editor_inspector != null:
		if _editor_inspector_toggle_btn != null:
			_editor_inspector_toggle_btn.position = Vector2(size.x - _editor_inspector_toggle_btn.size.x - 8.0, 108.0)
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
		"editor_compact": _editor_available() and _editor_mode,
	})
	_inspect_uid = str(hud_state.get("inspect_uid", _inspect_uid))
	_tracked_player_uid = str(hud_state.get("tracked_player_uid", _tracked_player_uid))
	if _relic_bar_root != null and _relic_bar_scroll != null:
		_relic_bar_root.visible = _relic_bar_scroll.visible
	var active_turn_uid := str(hud_state.get("active_turn_uid", ""))
	_board.set_active_turn_unit(active_turn_uid)
	if _editor_drag_active:
		_board.set_highlights({})
		if _hover_cell.x >= 0:
			var preview := _editor_preview_for_cell(_hover_cell)
			_board.set_editor_preview(_typed_preview_cells(preview.get("cells", [])), bool(preview.get("valid", false)), true)
		else:
			_board.clear_editor_preview()
	else:
		_board.set_highlights(_controller.get_highlights(_hover_cell))
		_board.clear_editor_preview()
	_sync_unit_slot_panels()
	_update_held_banner()
	_board.queue_redraw()
	call_deferred("_fit_status_panel")
	call_deferred("_fit_status_panel_height")
	call_deferred("_layout_editor_ui")


func _fit_status_panel() -> void:
	if not is_node_ready():
		return
	_hud_presenter.fit_status_panel(_panel_visible)


func _fit_status_panel_height() -> void:
	if not is_node_ready():
		return
	_hud_presenter.fit_status_panel_height()
	_layout_editor_ui()


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
	var state := _controller.state
	if state == null or _editor_tool.is_empty():
		return {"valid": false, "cells": [], "message": "未选择资源"}
	var kind := str(_editor_tool.get("kind", ""))
	var resource_id := str(_editor_tool.get("id", ""))
	match kind:
		"relic":
			return {"valid": false, "cells": [], "message": "遗物无需落板，点击左侧条目即可获取"}
		"unit":
			var unit_def: Dictionary = Engine.get_main_loop().root.get_node("DataRegistry").get_unit_def(resource_id)
			var fp_raw: Variant = unit_def.get("footprint_size", [1, 1])
			var fp := Vector2i(1, 1)
			if fp_raw is Array and fp_raw.size() >= 2:
				fp = Vector2i(int(fp_raw[0]), int(fp_raw[1]))
			var cells: Array[Vector2i] = []
			for dx in range(fp.x):
				for dy in range(fp.y):
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
			return {
				"valid": BoardUtils.in_bounds(state, cell),
				"cells": [cell],
				"message": "替换地块为 %s" % resource_id,
			}
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
			var unit := state.get_unit_at(cell)
			if unit != null:
				return {"valid": true, "cells": [cell], "message": "松手后选择单位槽位"}
			var tile := state.get_tile(cell)
			if tile != null:
				return {"valid": true, "cells": [cell], "message": "松手后选择地块槽位"}
			return {"valid": false, "cells": [cell], "message": "该格没有可编辑目标"}
	return {"valid": false, "cells": [cell], "message": "暂不支持此资源"}


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
		"entity":
			result = _controller.run_editor_action("spawn_entity", {"entity_id": resource_id, "pos": cell})
		"overlay":
			result = _controller.run_editor_action("spawn_overlay", {"overlay_id": resource_id, "pos": cell})
		"gem":
			_show_editor_gem_slot_picker(cell, resource_id)
			return
		_:
			result = {"ok": false, "message": "暂不支持此资源"}
	_sync_editor_inspector(str(result.get("message", "")))
	_show_result(result)
	_refresh()


func _show_editor_gem_slot_picker(cell: Vector2i, gem_id: String) -> void:
	var state := _controller.state
	if state == null:
		return
	var screen_pos: Vector2 = _board.global_position + _board.grid_to_screen(cell) + Vector2(0, -72)
	var unit := state.get_unit_at(cell)
	if unit != null:
		_slot_popup.show_for_editor_unit(unit, state, gem_id, screen_pos)
		_sync_editor_inspector("选择现有槽位，或新增同色槽位")
		return
	var tile := state.get_tile(cell)
	if tile != null:
		_slot_popup.show_for_editor_tile(tile, state, gem_id, screen_pos)
		_sync_editor_inspector("选择现有地块槽位，或新增槽位")


func _on_editor_unit_slot_selected(unit_uid: String, slot_index: int) -> void:
	var unit: UnitState = _controller.state.units.get(unit_uid, null)
	if unit == null:
		return
	_place_editor_gem(unit.pos, "unit", slot_index)


func _on_editor_tile_slot_selected(tile_pos: Vector2i, slot_index: int) -> void:
	_place_editor_gem(tile_pos, "tile", slot_index)


func _on_editor_unit_slot_added(unit_uid: String, slot_type: String) -> void:
	var unit: UnitState = _controller.state.units.get(unit_uid, null)
	if unit == null:
		return
	_place_editor_gem(unit.pos, "unit", -1, slot_type)


func _on_editor_tile_slot_added(tile_pos: Vector2i, slot_type: String) -> void:
	_place_editor_gem(tile_pos, "tile", -1, slot_type)


func _place_editor_gem(pos: Vector2i, target_kind: String, slot_index: int, create_slot_type: String = "") -> void:
	var gem_id := str(_editor_tool.get("id", ""))
	if gem_id.is_empty() or str(_editor_tool.get("kind", "")) != "gem":
		return
	var result := _controller.run_editor_action("spawn_gem", {
		"gem_id": gem_id,
		"pos": pos,
		"target_kind": target_kind,
		"slot_index": slot_index,
		"create_slot_type": create_slot_type,
	})
	_slot_popup.hide_popup()
	_sync_editor_inspector(str(result.get("message", "")))
	_show_result(result)
	_refresh()


func _sync_editor_hover(title: String, detail: String) -> void:
	if _editor_hover_label == null:
		return
	_editor_hover_label.text = title if detail.is_empty() else "%s\n%s" % [title, detail]
	if _editor_panel != null and _editor_panel.has_method("set_hover_summary"):
		_editor_panel.set_hover_summary(detail)


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
	_rebuild_editor_contents()
	_rebuild_editor_status_panel()
	_refresh_editor_action_buttons()


func _editor_tool_summary() -> String:
	if _editor_tool.is_empty():
		return "工具: 未选择（左侧列表选择资源）"
	var kind := str(_editor_tool.get("kind", ""))
	var kind_label := str(_EDITOR_KIND_LABELS.get(kind, kind))
	var tool_id := str(_editor_tool.get("id", ""))
	var action_hint := "拖到棋盘放置"
	if kind == "relic":
		action_hint = "点击条目添加"
	return "工具: %s · %s（%s）" % [tool_id, kind_label, action_hint]


func _editor_target_summary() -> String:
	if not _editor_action_cell_valid():
		return "操作目标: 点击棋盘格子锁定"
	var state := _controller.state
	if state == null:
		return "操作目标: —"
	var lines: Array[String] = ["操作目标: %s" % str(_editor_action_cell)]
	var tile := state.get_tile(_editor_action_cell)
	var unit := state.get_unit_at(_editor_action_cell)
	if unit != null and unit.alive:
		lines.append("%s · HP %d/%d" % [
			DataRegistry.get_unit_display_name(unit.unit_def_id),
			unit.hp,
			unit.max_hp,
		])
		if unit.has_tag("unit:training_dummy"):
			var stats: Dictionary = _editor_dummy_stats.get(unit.uid, {})
			lines.append("稻草人: 受击 %d · 总伤 %d" % [
				int(stats.get("hits", 0)),
				int(stats.get("total_damage", 0)),
			])
	elif tile != null:
		lines.append(DataRegistry.get_tile_display_name(tile.tile_id))
	var entity := state.get_entity_at(_editor_action_cell)
	if entity != null and entity.alive:
		lines.append("实体: %s" % entity.entity_id)
	if tile != null and not tile.modifiers.is_empty():
		var overlay_ids: Array[String] = []
		for modifier in tile.modifiers:
			overlay_ids.append(str(modifier.get("type", "")))
		lines.append("Overlay: %s" % ", ".join(overlay_ids))
	return "\n".join(lines)


func _bind_editor_state_signals() -> void:
	if _controller == null or _controller.state == null or _controller.state == _editor_bound_state:
		return
	_editor_bound_state = _controller.state
	_editor_bound_state.on_damage_taken.connect(_on_editor_damage_taken)


func _refresh_editor_action_buttons() -> void:
	var state := _controller.state
	var cell := _editor_action_cell
	var has_cell := state != null and cell.x >= 0
	var tile := state.get_tile(cell) if has_cell else null
	var unit := state.get_unit_at(cell) if has_cell else null
	var entity := state.get_entity_at(cell) if has_cell else null
	_editor_remove_unit_btn.disabled = not has_cell or unit == null or unit.uid == state.player_uid
	_editor_remove_entity_btn.disabled = not has_cell or entity == null or not entity.alive
	_editor_remove_overlay_btn.disabled = not has_cell or tile == null or tile.modifiers.is_empty()


func _rebuild_editor_contents() -> void:
	_clear_editor_list(_editor_gem_list)
	_clear_editor_list(_editor_relic_list)
	if not _editor_action_cell_valid():
		_editor_gem_list.add_child(_editor_empty_hint("锁定格子后显示槽位"))
		_editor_relic_list.add_child(_editor_empty_hint("—"))
		return
	var gem_targets := _editor_list_gem_targets(_editor_action_cell)
	if gem_targets.is_empty():
		_editor_gem_list.add_child(_editor_empty_hint("该格无宝石"))
	else:
		for target in gem_targets:
			_editor_gem_list.add_child(_create_editor_gem_row(target))
	if not RunService.is_run_active():
		_editor_relic_list.add_child(_editor_empty_hint("未开启 Run"))
		return
	var owned := RunService.get_owned_relics()
	if owned.is_empty():
		_editor_relic_list.add_child(_editor_empty_hint("无遗物 · 左侧列表点击添加"))
	else:
		for relic_id in owned:
			_editor_relic_list.add_child(_create_editor_relic_row(str(relic_id)))


func _rebuild_editor_status_panel() -> void:
	if _editor_status_grid == null:
		return
	for child in _editor_status_grid.get_children():
		child.queue_free()
	if not _editor_action_cell_valid() or _controller == null or _controller.state == null:
		_editor_status_box.visible = false
		return
	var unit := _controller.state.get_unit_at(_editor_action_cell)
	if unit == null or not unit.alive:
		_editor_status_box.visible = false
		return
	_editor_status_box.visible = true
	for status_id in _EDITOR_STATUS_IDS:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(36, 36)
		btn.tooltip_text = StatusRegistry.display_name(status_id)
		btn.pressed.connect(_on_editor_apply_status.bind(status_id))
		BattleUiTheme.apply_button(btn, "ghost")
		var icon_tex := StatusIcons.get_icon(status_id)
		if icon_tex != null:
			var icon := TextureRect.new()
			icon.texture = icon_tex
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon.custom_minimum_size = Vector2(22, 22)
			icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon.set_anchors_preset(Control.PRESET_CENTER)
			btn.add_child(icon)
		_editor_status_grid.add_child(btn)


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


func _clear_editor_list(list: VBoxContainer) -> void:
	if list == null:
		return
	for child in list.get_children():
		child.queue_free()


func _editor_empty_hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", BattleUiTheme.TEXT_HINT)
	return label


func _create_editor_gem_row(target: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var state := _controller.state
	var gem: GemState = null
	var slot_index := int(target.get("slot_index", -1))
	var target_kind := str(target.get("target_kind", ""))
	if state != null and slot_index >= 0:
		if target_kind == "unit":
			var unit := state.get_unit_at(_editor_action_cell)
			if unit != null and slot_index < unit.slots.size():
				var slot: SlotState = unit.slots[slot_index]
				if slot != null and not slot.gem_uid.is_empty():
					gem = state.gems.get(slot.gem_uid, null)
		elif target_kind == "tile":
			var tile := state.get_tile(_editor_action_cell)
			if tile != null and slot_index < tile.slots.size():
				var slot: SlotState = tile.slots[slot_index]
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
	var gem_name := DataRegistry.get_gem_display_name(gem) if gem != null else str(target.get("label", ""))
	label.text = "%s槽 · %s" % [_editor_slot_label(str(target.get("slot_type", ""))), gem_name]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 11)
	row.add_child(label)
	var btn := Button.new()
	btn.text = "移除"
	btn.custom_minimum_size = Vector2(52, 28)
	btn.pressed.connect(_on_editor_remove_gem_target.bind(target))
	BattleUiTheme.apply_button(btn, "ghost")
	row.add_child(btn)
	return row


func _create_editor_relic_row(relic_id: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var def: Dictionary = DataRegistry.get_relic_def(relic_id)
	var rarity := DataRegistry.get_relic_rarity(relic_id)
	var rarity_col := _hud_presenter.rarity_color(rarity)
	var icon_tex := UnitLooks.get_relic_texture(relic_id)
	if icon_tex != null:
		var icon := TextureRect.new()
		icon.texture = icon_tex
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.custom_minimum_size = Vector2(20, 20)
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.self_modulate = rarity_col
		row.add_child(icon)
	var label := Label.new()
	label.text = str(def.get("name", relic_id))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", rarity_col)
	row.add_child(label)
	var btn := Button.new()
	btn.text = "移除"
	btn.custom_minimum_size = Vector2(52, 28)
	btn.pressed.connect(_on_editor_remove_relic.bind(relic_id))
	BattleUiTheme.apply_button(btn, "ghost")
	row.add_child(btn)
	return row


func _editor_list_gem_targets(cell: Vector2i) -> Array[Dictionary]:
	var state := _controller.state
	var targets: Array[Dictionary] = []
	if state == null or cell.x < 0:
		return targets
	var unit := state.get_unit_at(cell)
	if unit != null:
		for i in range(unit.slots.size()):
			var slot: SlotState = unit.slots[i]
			if slot != null and not slot.gem_uid.is_empty():
				var gem: GemState = state.gems.get(slot.gem_uid, null)
				var gem_id := gem.gem_id if gem != null else "?"
				targets.append({
					"target_kind": "unit",
					"slot_index": i,
					"slot_type": slot.slot_type,
					"label": "%s · %s" % [_editor_slot_label(slot.slot_type), gem_id],
				})
	var tile := state.get_tile(cell)
	if tile != null and tile.has_slots():
		for i in range(tile.slots.size()):
			var slot: SlotState = tile.slots[i]
			if slot != null and not slot.gem_uid.is_empty():
				var gem: GemState = state.gems.get(slot.gem_uid, null)
				var gem_id := gem.gem_id if gem != null else "?"
				targets.append({
					"target_kind": "tile",
					"slot_index": i,
					"slot_type": slot.slot_type,
					"label": "%s · %s" % [_editor_slot_label(slot.slot_type), gem_id],
				})
	return targets


func _editor_slot_label(slot_type: String) -> String:
	match slot_type:
		Constants.SLOT_RED:
			return "红"
		Constants.SLOT_BLUE:
			return "蓝"
		Constants.SLOT_BLACK:
			return "黑"
		_:
			return slot_type


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
	if _editor_unlimited_btn != null:
		_editor_unlimited_btn.button_pressed = false
		_editor_unlimited_btn.text = "无限行动 关"


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
	var cells: Array[Vector2i] = []
	if values is Array:
		for value in values:
			if value is Vector2i:
				cells.append(value)
	return cells


func _on_editor_panel_close_requested() -> void:
	if _editor_panel != null:
		_editor_panel.visible = false
	if _editor_panel_toggle_btn != null:
		_editor_panel_toggle_btn.visible = true


func _on_editor_panel_toggle_pressed() -> void:
	if _editor_panel != null:
		_editor_panel.visible = true
	if _editor_panel_toggle_btn != null:
		_editor_panel_toggle_btn.visible = false


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


## 手持宝石横幅：拔出后玩家处于"必须嵌入"的中间态，状态面板里的一行小字
## 容易被忽略，这里在屏幕顶部常驻提示，直到宝石被嵌入
func _update_held_banner() -> void:
	var held := _controller.get_held_gem()
	if held == null:
		if _held_banner != null:
			_held_banner.visible = false
		return
	if _held_banner == null:
		_create_held_banner()
	_held_banner_icon.texture = UnitLooks.get_gem_texture(held)
	_held_banner_icon.self_modulate = UnitLooks.gem_sprite_modulate(held)
	_held_banner_icon.visible = _held_banner_icon.texture != null
	var gem_name: String = DataRegistry.get_gem_display_name(held)
	_held_banner_label.text = "手持 %s — 点击发光槽位嵌入" % gem_name
	_held_banner_label.add_theme_color_override("font_color", UnitLooks.gem_color(held).lightened(0.25))
	_held_banner.visible = true


func _create_held_banner() -> void:
	_held_banner = PanelContainer.new()
	_held_banner.name = "HeldGemBanner"
	_held_banner.add_theme_stylebox_override("panel", BattleUiTheme.tooltip_style())
	_held_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_held_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_held_banner.offset_top = 56.0
	_held_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_held_banner_icon = TextureRect.new()
	_held_banner_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_held_banner_icon.custom_minimum_size = Vector2(20, 20)
	_held_banner_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_held_banner_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(_held_banner_icon)
	_held_banner_label = Label.new()
	_held_banner_label.add_theme_font_size_override("font_size", BattleUiTheme.FONT_BODY)
	row.add_child(_held_banner_label)
	_held_banner.add_child(row)
	$HudLayer.add_child(_held_banner)


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


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		call_deferred("_layout_editor_ui")


func _wire_hover_interactions() -> void:
	for button in [_move_btn, _attack_btn, _extract_btn, _insert_btn, _end_turn_btn, _toggle_panel_btn]:
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
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.visible = false
	_relic_bar_root.add_child(scroll)

	var relic_vbox := VBoxContainer.new()
	relic_vbox.name = "RelicBarVBox"
	relic_vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(relic_vbox)
	_relic_bar_scroll = scroll
	_relic_bar_vbox = relic_vbox


func _layout_editor_ui() -> void:
	if not is_node_ready():
		return
	var viewport_size := get_viewport_rect().size
	var left := 8.0
	var top := 8.0
	if _status_panel.visible:
		top = _status_panel.position.y + _status_panel.size.y + 4.0
	if _relic_bar_root != null and _relic_bar_scroll != null:
		var relic_width := _status_panel.size.x if _status_panel.visible else minf(420.0, maxf(viewport_size.x - 16.0, 260.0))
		var relic_h := maxf(_relic_bar_scroll.custom_minimum_size.y, 0.0)
		_relic_bar_root.position = Vector2(left, top)
		_relic_bar_root.size = Vector2(relic_width, relic_h)
		_relic_bar_scroll.size = Vector2(relic_width, relic_h)
		if _relic_bar_root.visible and relic_h > 0.0:
			top += relic_h + 4.0
	var bottom_limit := viewport_size.y - _bottom_dock.size.y - 8.0
	if _editor_panel != null and _editor_panel.visible:
		var editor_width := minf(380.0, maxf(viewport_size.x * 0.46, 340.0))
		var editor_height := maxf(bottom_limit - top, 200.0)
		_editor_panel.size = Vector2(editor_width, editor_height)
		if not _editor_panel_user_positioned:
			_editor_panel.position = Vector2(left, top)
	if _editor_panel_toggle_btn != null:
		_editor_panel_toggle_btn.position = Vector2(left, top)
	if _editor_inspector != null and _editor_inspector.visible:
		var inspector_w := 280.0
		var inspector_h := maxf(_editor_inspector.get_combined_minimum_size().y, 320.0)
		_editor_inspector.size = Vector2(inspector_w, inspector_h)
		_editor_inspector.position = Vector2(viewport_size.x - inspector_w - 8.0, 8.0)
	if _editor_inspector_toggle_btn != null:
		_editor_inspector_toggle_btn.position = Vector2(viewport_size.x - _editor_inspector_toggle_btn.size.x - 8.0, 8.0)


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


func _flat_style(bg: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(0)
	return box
