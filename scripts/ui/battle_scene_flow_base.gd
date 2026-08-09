extends Control
const SlotPopup = preload("res://scripts/ui/slot_popup.gd")
const BattleUiTheme = preload("res://scripts/ui/battle_ui_theme.gd")
const StatusUi = preload("res://scripts/ui/status_ui.gd")
const StatusIcons = preload("res://scripts/ui/status_icons.gd")
const StatusActionRules = preload("res://scripts/rules/status_action_rules.gd")
const DamageTextManagerScript = preload("res://scripts/ui/damage_text_manager.gd")
const BattleEventPlayerScript = preload("res://scripts/ui/battle_event_player.gd")
const BoardInputAdapterScript = preload("res://scripts/ui/board_input_adapter.gd")
const BattleHudPresenterScript = preload("res://scripts/ui/battle_hud_presenter.gd")
const RichTooltip = preload("res://scripts/ui/rich_tooltip.gd")
const BattlePreviewPanel = preload("res://scripts/ui/battle_preview_panel.gd")
const GemEchoVisuals = preload("res://scripts/ui/gem_echo_visuals.gd")
const CoinIconTexture = preload("res://assets/ui/coin_gold.png")
const BattleSceneLazyResourcesScript = preload("res://scripts/ui/battle_scene_lazy_resources.gd")
const _EDITOR_DOCK_TOP := 220.0
const _EDITOR_INSPECTOR_GAP := 8.0
var _dmg_text: Node = null

@onready var _board: Control = $BoardLayer/IsometricBoard
@onready var _status_panel: PanelContainer = $HudLayer/StatusPanel
@onready var _status_vbox: VBoxContainer = $HudLayer/StatusPanel/VBox
@onready var _header_row: HBoxContainer = $HudLayer/StatusPanel/VBox/HeaderRow
@onready var _turn_chips: HBoxContainer = $HudLayer/StatusPanel/VBox/TurnChips
@onready var _portrait: TextureRect = $HudLayer/StatusPanel/VBox/HeaderRow/Portrait
@onready var _inspect_name: Label = $HudLayer/StatusPanel/VBox/HeaderRow/Info/Name
@onready var _info_col: VBoxContainer = $HudLayer/StatusPanel/VBox/HeaderRow/Info
@onready var _hp_bar_row: HBoxContainer = $HudLayer/StatusPanel/VBox/HeaderRow/Info/HpBarRow
@onready var _shield_icon: TextureRect = $HudLayer/StatusPanel/VBox/HeaderRow/Info/HpBarRow/ShieldIcon
@onready var _combined_hp_bar: CombinedHpBar = $HudLayer/StatusPanel/VBox/HeaderRow/Info/HpBarRow/CombinedHpBar
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
@onready var _turn_queue_panel: PanelContainer = $HudLayer/TurnQueuePanel
@onready var _bottom_dock: PanelContainer = $HudLayer/BottomDock
@onready var _move_group: PanelContainer = $HudLayer/BottomDock/BottomBar/MoveGroup
@onready var _combat_group: PanelContainer = $HudLayer/BottomDock/BottomBar/CombatGroup
@onready var _gem_group: PanelContainer = $HudLayer/BottomDock/BottomBar/GemGroup
@onready var _turn_group: PanelContainer = $HudLayer/BottomDock/BottomBar/TurnGroup
@onready var _move_btn: Button = $HudLayer/BottomDock/BottomBar/MoveGroup/VBox/Row/MoveBtn
@onready var _attack_btn: Button = $HudLayer/BottomDock/BottomBar/CombatGroup/VBox/Row/AttackBtn
@onready var _extract_btn: Button = $HudLayer/BottomDock/BottomBar/GemGroup/VBox/Row/ExtractBtn
@onready var _insert_btn: Button = $HudLayer/BottomDock/BottomBar/GemGroup/VBox/Row/InsertBtn
@onready var _end_turn_btn: Button = $HudLayer/BottomDock/BottomBar/TurnGroup/VBox/Row/EndTurnBtn
@onready var _menu_btn: Button = $SystemMenuHud/Root/MenuBtn

var _controller: BattleController = BattleController.new()
var _event_player = BattleEventPlayerScript.new()
var _board_input = BoardInputAdapterScript.new()
var _hud_presenter = BattleHudPresenterScript.new()
var _encounter_id: String = "tutorial_001"

var _inspect_uid: String = ""
var _inspect_cell: Vector2i = Vector2i(-1, -1)
var _hover_cell: Vector2i = Vector2i(-1, -1)
var _timeline_hover_uid: String = ""
var _panel_visible: bool = true
var _enemy_phase_running: bool = false
var _enemy_action_resolving: bool = false
var _player_animating: bool = false
var _battle_end_applied: bool = false
var _animation_speed_scale: float = 1.0
var _enemy_turn_queue: Array[String] = []
var _slot_popup: Control = null
var _held_banner: PanelContainer = null
var _held_banner_icon: TextureRect = null
var _held_banner_label: Label = null
var _console_layer: CanvasLayer = null
var _console: Control = null
var _generated_export_btn = null
var _preview_view: BattlePreviewPanel = null
var _relic_reward_overlay: Node = null
var _relic_detail_overlay: Node = null
var _settlement_overlay: Node = null
var _settlement_rows_box: VBoxContainer = null
var _settlement_result: String = ""
var _settlement_relic_offer: Array[String] = []
var _settlement_dropped_gems: Array[Dictionary] = []
var _settlement_relic_pending: bool = false
var _settlement_gem_pending: bool = false
var _settlement_gold_amount: int = 0
var _settlement_is_boss: bool = false
var _settlement_root_ctrl: Control = null
var _settlement_gold_chip_label: Label = null
var _settlement_gold_displayed: int = 0
var _settlement_gold_claimed: bool = false
var _run_result_overlay: Node = null
var _tutorial_overlay: Control = null
var _held_gem_icon: TextureRect = null
var _overload_chip: Label = null
var _relic_bar_root: Control = null
var _relic_bar_scroll: ScrollContainer = null
var _relic_bar_vbox: Container = null
var _rich_tooltip: RichTooltip = null
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
var _editor_player_invincible_btn: Button = null
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
var _editor_view = null
var _leave_confirm_dialog = null
var _battle_menu = null
var _return_to_menu_after_leave_cancel: bool = false
var _lazy_resources := BattleSceneLazyResourcesScript.new()
var _startup_ready_duration_usec: int = 0
var _startup_start_battle_duration_usec: int = 0

const _EDITOR_KIND_LABELS := {
	"unit": "怪物",
	"tile": "地块",
	"entity": "实体",
	"overlay": "Overlay",
	"surface_overlay": "Overlay",
	"gem": "宝石",
	"relic": "遗物",
}
const _EDITOR_STATUS_IDS: Array[String] = [
	Constants.STATUS_POISON,
	Constants.STATUS_BURNING,
	Constants.STATUS_SLOWED,
	Constants.STATUS_PARALYZED,
	Constants.STATUS_FROZEN,
	Constants.STATUS_WET,
	Constants.STATUS_ROOTED,
	Constants.STATUS_VULNERABLE,
	Constants.STATUS_WEAK,
	Constants.STATUS_LIGHT_EXPOSED,
	Constants.STATUS_BLINDED,
	Constants.STATUS_ARMOR,
]

func _editor_available() -> bool:
	return GameService.pending_battle_mode == "editor" and OS.is_debug_build() and bool(SettingsService.get_value("battle_editor_enabled"))

func _battle_reward_overlay() -> Script: return _lazy_resources.battle_reward_overlay()

func _battle_reward_card_factory() -> Script: return _lazy_resources.battle_reward_card_factory()

func _battle_settlement_service() -> Script: return _lazy_resources.battle_settlement_service()

func _battle_reward_view() -> RefCounted: return _lazy_resources.battle_reward_view()

func _sync_unit_slot_panels() -> void:
	if _controller == null or _board == null:
		return
	var action := _controller.selected_action
	if action in [Constants.ACTION_EXTRACT, Constants.ACTION_INSERT]:
		_board.configure_unit_slot_panels(
			action,
			_controller.check_slot_action,
			_controller.is_unit_in_slot_action_range
		)
	else:
		_board.clear_unit_slot_panels()

func _view_state() -> GameState:
	return _event_player.get_view_state(_controller.state)

func _apply_battle_end(result: String) -> void:
	if GameService.pending_battle_mode == "editor":
		# A debug editor is a persistent sandbox. Keep this defensive branch even
		# though the controller normally suppresses the terminal signal itself.
		_battle_end_applied = false
		_controller._check_battle_end()
		_message_label.text = "编辑模式：死亡状态保留，可继续编辑"
		_refresh()
		return
	if _battle_end_applied:
		return
	_battle_end_applied = true
	_message_label.text = "战斗结束 — %s" % ("胜利" if result == "win" else "失败")
	_hint_label.text = ""
	var end_turn := _controller.state.turn_index if _controller.state != null else 0
	_phase_badge.text = "结束 · 第%d回合" % end_turn
	_phase_badge.add_theme_color_override("font_color", BattleUiTheme.PHASE_END)
	if result == "win" and RunService.is_run_active():
		_settlement_gold_amount = _grant_combat_gold_once()
		var room_id := GameService.pending_room_id
		var relic_offer: Array[String] = _battle_relic_offer(room_id)
		var has_relics := not relic_offer.is_empty() and not relic_offer.all(
			func(rid: String) -> bool: return rid == "relic_placeholder"
		)
		_settlement_result = result
		_settlement_is_boss = AdventureService.pending_room_type.to_upper() == "END"
		_settlement_relic_offer = []
		if has_relics:
			_settlement_relic_offer = relic_offer
		_settlement_relic_pending = has_relics
		_settlement_dropped_gems = []
		if _has_pending_dropped_gem_reward():
			_settlement_dropped_gems = _dropped_gem_offer()
		_settlement_gem_pending = not _settlement_dropped_gems.is_empty()
		_open_battle_settlement()
		return
	if result != "win" and RunService.is_run_active() and GameService.adventure_return:
		_show_run_result_overlay("lose")
		return
	_finish_battle_and_navigate(result)

func _consume_pending_battle_end_if_any() -> bool:
	if _battle_end_applied:
		return false
	var pending_battle_end := _event_player.take_pending_battle_end()
	if pending_battle_end.is_empty() and _controller.state != null and _controller.state.phase == Constants.PHASE_ENDED:
		pending_battle_end = _controller.state.result
	if pending_battle_end.is_empty():
		return false
	_apply_battle_end(pending_battle_end)
	return true

func _battle_relic_offer(room_id: String) -> Array[String]:
	var room_type := AdventureService.pending_room_type.to_upper()
	return RunService.get_or_roll_relic_offer(
		room_id,
		DataRegistry.get_battle_relic_offer_source(room_type),
		DataRegistry.get_battle_relic_offer_count(room_type)
	)

func _grant_combat_gold_once() -> int:
	var grant_result: Dictionary = _battle_settlement_service().grant_combat_gold(
		GameService.pending_room_id,
		AdventureService.pending_room_type,
		GameService.adventure_return
	)
	if not bool(grant_result.get("ok", false)):
		return 0
	var entry: Dictionary = grant_result.get("entry", {})
	_message_label.text = "战斗结束 — 胜利 · %s" % EconomyService.format_entry(entry)
	return int(grant_result.get("amount", 0))

func _open_battle_settlement() -> void:
	_mark_battle_reward_pending("settlement", _settlement_result, _settlement_relic_pending)
	if _settlement_overlay != null and is_instance_valid(_settlement_overlay):
		_settlement_overlay.queue_free()
	_settlement_gold_claimed = false
	_settlement_gold_displayed = maxi(0, RunService.get_balance("gold") - _settlement_gold_amount)
	_settlement_overlay = _build_settlement_overlay()
	add_child(_settlement_overlay)

func _build_settlement_overlay() -> Node:
	var settlement := DataRegistry.get_battle_reward_ui_layout("settlement")
	var canvas := CanvasLayer.new()
	canvas.layer = int(settlement.get("canvas_layer", 0))

	var root_ctrl := Control.new()
	root_ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_ctrl.theme = BattleUiTheme.build_theme()
	canvas.add_child(root_ctrl)
	_settlement_root_ctrl = root_ctrl

	var bg := ColorRect.new()
	bg.color = Color(UiPalette.BG_DEEP, 0.9)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_ctrl.add_child(bg)

	root_ctrl.add_child(_build_gold_chip())

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_ctrl.add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", BattleUiTheme.panel_style(BattleUiTheme.TEXT_GOLD))
	panel.custom_minimum_size = Vector2(float(settlement.get("panel_width", 0)), 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	var panel_margin := int(settlement.get("panel_margin", 0))
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, panel_margin)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(settlement.get("content_separation", 0)))
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "首领已伏诛" if _settlement_is_boss else "战斗胜利"
	title.add_theme_font_size_override("font_size", BattleUiTheme.FONT_TITLE)
	title.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "战利品结算"
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	_settlement_rows_box = VBoxContainer.new()
	_settlement_rows_box.add_theme_constant_override("separation", int(settlement.get("row_separation", 0)))
	vbox.add_child(_settlement_rows_box)

	var continue_wrap := CenterContainer.new()
	var continue_btn := Button.new()
	continue_btn.text = _settlement_continue_label()
	continue_btn.custom_minimum_size = Vector2(
		float(settlement.get("continue_button_width", 0)),
		float(settlement.get("continue_button_height", 0))
	)
	BattleUiTheme.apply_button(continue_btn, "end")
	continue_btn.pressed.connect(_on_settlement_continue)
	continue_wrap.add_child(continue_btn)
	vbox.add_child(continue_wrap)

	_refresh_settlement_rows()
	_animate_panel_in(panel)
	return canvas


## 结算页左上角的金币总额 chip，作为金币飞行落点。
func _build_gold_chip() -> Control:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", BattleUiTheme.chip_style(BattleUiTheme.TEXT_GOLD))
	chip.position = Vector2(18, 16)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	chip.add_child(hbox)

	var icon := TextureRect.new()
	icon.texture = CoinIconTexture
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.custom_minimum_size = Vector2(22, 22)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(icon)

	_settlement_gold_chip_label = Label.new()
	_settlement_gold_chip_label.text = str(_settlement_gold_displayed)
	_settlement_gold_chip_label.add_theme_font_size_override("font_size", 18)
	_settlement_gold_chip_label.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	_settlement_gold_chip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(_settlement_gold_chip_label)

	return chip


## 面板整体入场保持轻量，避免奖励领取流程反复抢戏。
func _animate_panel_in(panel: Control) -> void:
	panel.modulate.a = 0.0
	panel.pivot_offset = panel.custom_minimum_size * 0.5
	panel.scale = Vector2(0.97, 0.97)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(panel, "modulate:a", 1.0, 0.14)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _settlement_continue_label() -> String:
	if _settlement_is_boss:
		var chapter := AdventureService.get_current_chapter()
		if chapter < AdventureService.get_chapter_count():
			return "进入第 %d 关" % (chapter + 1)
		return "凯旋 · 通关"
	return "返回路线"

func _refresh_settlement_rows(play_intro: bool = true) -> void:
	if _settlement_rows_box == null or not is_instance_valid(_settlement_rows_box):
		return
	for child in _settlement_rows_box.get_children():
		child.queue_free()
	var rows: Array[Control] = []
	if _settlement_gold_amount > 0:
		if _settlement_gold_claimed:
			rows.append(_build_settlement_row(
				"金币", "+%d" % _settlement_gold_amount, "", BattleUiTheme.TEXT_MUTED, Callable(), CoinIconTexture
			))
		else:
			rows.append(_build_settlement_row(
				"金币", "+%d" % _settlement_gold_amount, "领取", BattleUiTheme.TEXT_GOLD, Callable(self, "_on_settlement_claim_gold"), CoinIconTexture
			))
	if not _settlement_relic_offer.is_empty():
		if _settlement_relic_pending:
			rows.append(_build_settlement_row(
				"遗物", "三选一", "领取", BattleUiTheme.TEXT_GOLD, Callable(self, "_open_settlement_relic"), null
			))
		else:
			rows.append(_build_settlement_row(
				"遗物", "已领取", "", BattleUiTheme.TEXT_MUTED, Callable(), null
			))
	if not _settlement_dropped_gems.is_empty():
		if _settlement_gem_pending:
			rows.append(_build_settlement_row(
				"掉落宝石", "%d 颗" % _settlement_dropped_gems.size(), "拾取", BattleUiTheme.TEXT_GOLD, Callable(self, "_open_settlement_gem"), null
			))
		else:
			rows.append(_build_settlement_row(
				"掉落宝石", "已处理", "", BattleUiTheme.TEXT_MUTED, Callable(), null
			))
	for row in rows:
		_settlement_rows_box.add_child(row)
	if rows.is_empty():
		var empty := Label.new()
		empty.text = "无额外战利品"
		empty.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_settlement_rows_box.add_child(empty)
	elif play_intro:
		_battle_reward_overlay().animate_cards_in(self, rows, {"stagger": 0.035, "from": Vector2(32.0, 4.0), "tilt": 0.0})

func _build_settlement_row(label_text: String, value_text: String, action_text: String, value_color: Color, action_cb: Callable, icon_tex: Texture2D) -> Control:
	var settlement := DataRegistry.get_battle_reward_ui_layout("settlement")
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", BattleUiTheme.panel_style(BattleUiTheme.BORDER))
	row.custom_minimum_size = Vector2(
		float(settlement.get("row_width", 0)),
		float(settlement.get("row_height", 0))
	)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	row.add_child(hbox)

	if icon_tex != null:
		var icon := TextureRect.new()
		icon.texture = icon_tex
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.custom_minimum_size = Vector2(28, 28)
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hbox.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.text = label_text
	name_lbl.add_theme_color_override("font_color", BattleUiTheme.TEXT_HINT)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(name_lbl)

	var value_lbl := Label.new()
	value_lbl.text = value_text
	value_lbl.add_theme_font_size_override("font_size", 16)
	value_lbl.add_theme_color_override("font_color", value_color)
	value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(value_lbl)

	if not action_text.is_empty() and action_cb.is_valid():
		var btn := Button.new()
		btn.text = action_text
		btn.custom_minimum_size = Vector2(
			float(settlement.get("row_action_width", 0)),
			float(settlement.get("row_action_height", 0))
		)
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		BattleUiTheme.apply_button(btn, "end")
		btn.pressed.connect(action_cb)
		hbox.add_child(btn)
	else:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(14, 0)
		hbox.add_child(spacer)

	return row

func _on_settlement_claim_gold() -> void:
	if _settlement_gold_claimed:
		return
	_settlement_gold_claimed = true
	var from_global := _settlement_rows_box.get_global_rect().get_center() if _settlement_rows_box != null else get_viewport_rect().get_center()
	var to_global := Vector2(40, 28)
	if _settlement_gold_chip_label != null and is_instance_valid(_settlement_gold_chip_label):
		to_global = _settlement_gold_chip_label.get_global_rect().get_center()
	_spawn_coin_burst(from_global, to_global, 12)
	_refresh_settlement_rows(false)


## 金币迸发动画：从奖励行向左上角金币 chip 抛出若干金币精灵，逐枚到达时累加显示数值。
func _spawn_coin_burst(from_global: Vector2, to_global: Vector2, count: int) -> void:
	if _settlement_root_ctrl == null or not is_instance_valid(_settlement_root_ctrl):
		_settlement_gold_displayed += _settlement_gold_amount
		_update_gold_chip_label()
		return
	var per_coin: int = maxi(1, int(round(float(_settlement_gold_amount) / float(count))))
	var remaining := _settlement_gold_amount
	for i in range(count):
		var coin := TextureRect.new()
		coin.texture = CoinIconTexture
		coin.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		coin.size = Vector2(24, 24)
		coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var scatter := Vector2(randf_range(-60.0, 60.0), randf_range(-40.0, 20.0))
		coin.global_position = from_global - coin.size * 0.5 + scatter
		_settlement_root_ctrl.add_child(coin)
		var add_amount: int = remaining if i == count - 1 else per_coin
		remaining -= add_amount
		var target := to_global - coin.size * 0.5
		var delay := float(i) * 0.04
		var dur := randf_range(0.42, 0.58)
		var tween := create_tween()
		tween.tween_interval(delay)
		tween.tween_property(coin, "global_position", target, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.parallel().tween_property(coin, "scale", Vector2(0.6, 0.6), dur)
		tween.tween_callback(_on_coin_arrived.bind(add_amount))
		tween.tween_callback(coin.queue_free)

func _on_coin_arrived(add_amount: int) -> void:
	_settlement_gold_displayed += add_amount
	_update_gold_chip_label()

func _update_gold_chip_label() -> void:
	if _settlement_gold_chip_label != null and is_instance_valid(_settlement_gold_chip_label):
		_settlement_gold_chip_label.text = str(_settlement_gold_displayed)
		var pop := create_tween()
		_settlement_gold_chip_label.pivot_offset = _settlement_gold_chip_label.size * 0.5
		pop.tween_property(_settlement_gold_chip_label, "scale", Vector2(1.25, 1.25), 0.06)
		pop.tween_property(_settlement_gold_chip_label, "scale", Vector2.ONE, 0.1)

func _open_settlement_relic() -> void:
	if _settlement_overlay != null and is_instance_valid(_settlement_overlay):
		_settlement_overlay.visible = false
	var overlay := _build_relic_overlay(_settlement_relic_offer, _settlement_result)
	_relic_reward_overlay = overlay
	add_child(overlay)

func _open_settlement_gem() -> void:
	if _settlement_overlay != null and is_instance_valid(_settlement_overlay):
		_settlement_overlay.visible = false
	var empty_relics: Array[String] = []
	var overlay := _build_dropped_gem_overlay(_settlement_dropped_gems, empty_relics, _settlement_result)
	_relic_reward_overlay = overlay
	add_child(overlay)

func _return_to_settlement() -> void:
	_mark_battle_reward_pending("settlement", _settlement_result, _settlement_relic_pending)
	if _settlement_overlay != null and is_instance_valid(_settlement_overlay):
		_settlement_overlay.visible = true
		_refresh_settlement_rows(false)
	else:
		_open_battle_settlement()

func _on_settlement_continue() -> void:
	var is_final_boss := _settlement_is_boss and AdventureService.get_current_chapter() >= AdventureService.get_chapter_count()
	if is_final_boss:
		if _settlement_overlay != null and is_instance_valid(_settlement_overlay):
			_settlement_overlay.queue_free()
		_settlement_overlay = null
		_show_run_result_overlay("win")
		return
	_finalize_settlement_navigation()

func _finalize_settlement_navigation() -> void:
	if _settlement_overlay != null and is_instance_valid(_settlement_overlay):
		_settlement_overlay.queue_free()
	_settlement_overlay = null
	var battle_result := _settlement_result
	if GameService.adventure_return and RunService.is_run_active():
		RunService.mark_room_resolved(GameService.pending_room_id, {
			"room_id": GameService.pending_room_id,
			"room_type": AdventureService.pending_room_type,
			"battle_result": battle_result,
			"summary": "战斗房间已结算。",
		})
	RunService.clear_pending_decision()
	RunService.set_run_phase("MAP")
	_finish_battle_and_navigate(battle_result)


## 整局胜利/战败的独立结算页。kind: "win"（通关）/ "lose"（战败）。
func _show_run_result_overlay(kind: String) -> void:
	if _run_result_overlay != null and is_instance_valid(_run_result_overlay):
		return
	var is_win := kind == "win"
	var accent: Color = BattleUiTheme.TEXT_GOLD if is_win else UiPalette.HP_LOW

	var canvas := CanvasLayer.new()
	canvas.layer = 90
	var root_ctrl := Control.new()
	root_ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_ctrl.theme = BattleUiTheme.build_theme()
	canvas.add_child(root_ctrl)

	var bg := ColorRect.new()
	bg.color = Color(UiPalette.BG_DEEP, 0.95)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_ctrl.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_ctrl.add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", BattleUiTheme.panel_style(accent))
	panel.custom_minimum_size = Vector2(440, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 30)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "凯旋归来" if is_win else "战败"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", accent)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "三关线路全部打通，本局胜利。" if is_win else "你在第 %d 关倒下了。" % AdventureService.get_current_chapter()
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(subtitle)

	vbox.add_child(HSeparator.new())

	var stats_box := VBoxContainer.new()
	stats_box.add_theme_constant_override("separation", 8)
	for stat in _run_result_stats():
		stats_box.add_child(_build_run_result_stat_row(str(stat[0]), str(stat[1])))
	vbox.add_child(stats_box)

	var back_btn := Button.new()
	back_btn.text = "返回主菜单"
	back_btn.custom_minimum_size = Vector2(0, 48)
	BattleUiTheme.apply_button(back_btn, "end" if is_win else "ghost")
	back_btn.pressed.connect(func() -> void:
		if _run_result_overlay != null and is_instance_valid(_run_result_overlay):
			_run_result_overlay.queue_free()
		_run_result_overlay = null
		if is_win:
			_finalize_settlement_navigation()
		else:
			_finish_battle_and_navigate("lose")
	)
	vbox.add_child(back_btn)

	_run_result_overlay = canvas
	add_child(canvas)
	_animate_panel_in(panel)

func _run_result_stats() -> Array:
	var gold := RunService.get_balance("gold")
	var relic_count := 0
	var run := RunService.get_run()
	if run != null:
		relic_count = run.owned_relics.size()
	var turns := _controller.state.turn_index if _controller != null and _controller.state != null else 0
	return [
		["到达章节", "%d / %d" % [AdventureService.get_current_chapter(), AdventureService.get_chapter_count()]],
		["累计金币", str(gold)],
		["持有遗物", str(relic_count)],
		["坚持回合", str(turns)],
	]

func _build_run_result_stat_row(label_text: String, value_text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var name_lbl := Label.new()
	name_lbl.text = label_text
	name_lbl.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_lbl)
	var value_lbl := Label.new()
	value_lbl.text = value_text
	value_lbl.add_theme_font_size_override("font_size", 16)
	value_lbl.add_theme_color_override("font_color", BattleUiTheme.TEXT)
	value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_lbl)
	return row

func _placeholder_relic_offer() -> Array[String]:
	var offer: Array[String] = []
	offer.append("relic_placeholder")
	return offer

func _show_gem_reward(gem_offer: Array[String], relic_offer: Array[String], battle_result: String) -> void:
	_mark_battle_reward_pending("gem", battle_result, not relic_offer.is_empty())
	var overlay := _build_gem_overlay(gem_offer, relic_offer, battle_result)
	_relic_reward_overlay = overlay
	add_child(overlay)

func _show_dropped_gem_reward(dropped_gems: Array[Dictionary], relic_offer: Array[String], battle_result: String) -> void:
	_mark_battle_reward_pending("dropped_gem", battle_result, not relic_offer.is_empty())
	var overlay := _build_dropped_gem_overlay(dropped_gems, relic_offer, battle_result)
	_relic_reward_overlay = overlay
	add_child(overlay)

func _dropped_gem_offer() -> Array[Dictionary]:
	if _controller == null or _controller.state == null:
		return [] as Array[Dictionary]
	return _battle_settlement_service().dropped_gem_offer(_controller.state)

func _has_pending_dropped_gem_reward() -> bool:
	if _controller == null or _controller.state == null:
		return false
	return _battle_settlement_service().has_pending_dropped_gem_reward(_controller.state)

func _build_dropped_gem_overlay(dropped_gems: Array[Dictionary], relic_offer: Array[String], battle_result: String) -> Node:
	return _battle_reward_view().build_dropped_gem_overlay(self, dropped_gems, relic_offer, battle_result)

func _build_dropped_gem_card(drop: Dictionary, battle_result: String, relic_offer: Array[String], canvas: Node) -> Control:
	return _battle_reward_view().build_dropped_gem_card(self, drop, battle_result, relic_offer, canvas)

func _on_dropped_gem_selected_for_insert(gem_uid: String, battle_result: String, relic_offer: Array[String], canvas: Node) -> void:
	if _controller == null or _controller.state == null:
		_message_label.text = "无法嵌入：战斗状态不存在。"
		return
	var gem: GemState = _controller.state.gems.get(gem_uid, null)
	if gem == null or not _controller.state.dropped_gems.has(gem_uid):
		_message_label.text = "无法嵌入：掉落宝石不存在。"
		return
	if canvas != null and is_instance_valid(canvas):
		canvas.queue_free()
	var overlay := _build_dropped_gem_slot_overlay(gem_uid, battle_result, relic_offer)
	_relic_reward_overlay = overlay
	add_child(overlay)

func _build_dropped_gem_slot_overlay(gem_uid: String, battle_result: String, relic_offer: Array[String]) -> Node:
	return _battle_reward_view().build_dropped_gem_slot_overlay(self, gem_uid, battle_result, relic_offer)

func _build_player_slot_embed_card(gem_uid: String, slot_index: int, battle_result: String, relic_offer: Array[String], canvas: Node) -> Control:
	return _battle_reward_view().build_player_slot_embed_card(self, gem_uid, slot_index, battle_result, relic_offer, canvas)

func _build_gem_overlay(gem_offer: Array[String], relic_offer: Array[String], battle_result: String) -> Node:
	return _battle_reward_view().build_gem_overlay(self, gem_offer, relic_offer, battle_result)

func _build_gem_card(gem_id: String, battle_result: String, relic_offer: Array[String], canvas: Node) -> Control:
	return _battle_reward_view().build_gem_card(self, gem_id, battle_result, relic_offer, canvas)

func _on_gem_chosen(gem_id: String, battle_result: String, relic_offer: Array[String], canvas: Node) -> void:
	if not gem_id.is_empty():
		var acquire_result: Dictionary = _battle_settlement_service().acquire_run_gem(gem_id)
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

func _on_dropped_gem_slot_chosen(gem_uid: String, slot_index: int, battle_result: String, relic_offer: Array[String], canvas: Node) -> void:
	if _controller == null or _controller.state == null:
		_message_label.text = "无法嵌入：战斗状态不存在。"
		return
	var result: Dictionary = _battle_settlement_service().embed_dropped_gem(_controller.state, gem_uid, slot_index)
	if not bool(result.get("ok", false)):
		_message_label.text = "无法嵌入：%s" % str(result.get("reason", "未知错误"))
		return
	var gem: GemState = result.get("gem", null)
	_message_label.text = "已嵌入 %s" % DataRegistry.get_gem_display_name(gem)
	_refresh()
	if canvas != null and is_instance_valid(canvas):
		canvas.queue_free()
	_relic_reward_overlay = null
	_continue_after_dropped_gem_embed(battle_result, relic_offer)

func _on_dropped_gem_insert_skipped(battle_result: String, relic_offer: Array[String], canvas: Node) -> void:
	if canvas != null and is_instance_valid(canvas):
		canvas.queue_free()
	_relic_reward_overlay = null
	if _settlement_overlay != null and is_instance_valid(_settlement_overlay):
		_return_to_settlement()
		return
	if _controller != null and _controller.state != null:
		_battle_settlement_service().skip_dropped_gem_reward(_controller.state)
	_continue_after_dropped_gem_embed(battle_result, relic_offer)

func _continue_after_dropped_gem_embed(battle_result: String, relic_offer: Array[String]) -> void:
	if _settlement_overlay != null and is_instance_valid(_settlement_overlay):
		_settlement_gem_pending = false
		_return_to_settlement()
		return
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
	if _has_pending_dropped_gem_reward():
		_show_dropped_gem_reward(_dropped_gem_offer(), offer, battle_result)
		return
	_mark_battle_reward_pending("relic", battle_result, false)
	var overlay := _build_relic_overlay(offer, battle_result)
	_relic_reward_overlay = overlay
	add_child(overlay)

func _build_relic_overlay(offer: Array[String], battle_result: String) -> Node:
	return _battle_reward_view().build_relic_overlay(self, offer, battle_result)

func _build_relic_card(relic_id: String, def: Dictionary, rarity: String, battle_result: String) -> Control:
	return _battle_reward_view().build_relic_card(self, relic_id, def, rarity, battle_result)

func _rarity_display_name(rarity: String) -> String:
	return _battle_reward_card_factory().rarity_display_name(rarity)

func _on_relic_overlay_dismissed(battle_result: String) -> void:
	if _relic_reward_overlay != null:
		_relic_reward_overlay.queue_free()
		_relic_reward_overlay = null
	if _settlement_overlay != null and is_instance_valid(_settlement_overlay):
		_return_to_settlement()
		return
	_on_relic_chosen("", battle_result)

func _on_relic_chosen(relic_id: String, battle_result: String) -> void:
	if _settlement_overlay != null and is_instance_valid(_settlement_overlay):
		if not relic_id.is_empty():
			_battle_settlement_service().acquire_run_relic(relic_id, _controller.state if _controller != null else null)
			_settlement_relic_pending = false
		if _relic_reward_overlay != null:
			_relic_reward_overlay.queue_free()
			_relic_reward_overlay = null
		_return_to_settlement()
		return
	if _has_pending_dropped_gem_reward():
		if _relic_reward_overlay != null:
			_relic_reward_overlay.queue_free()
			_relic_reward_overlay = null
		var relic_offer: Array[String] = _battle_relic_offer(GameService.pending_room_id)
		_show_dropped_gem_reward(_dropped_gem_offer(), relic_offer, battle_result)
		return
	if not relic_id.is_empty():
		_battle_settlement_service().acquire_run_relic(relic_id, _controller.state if _controller != null else null)
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
		var was_boss_room := AdventureService.pending_room_type.to_upper() == "END"
		GameService.adventure_return = false
		if result == "win" and RunService.is_run_active():
			if was_boss_room:
				AdventureService.advance_after_boss_room()
			else:
				AdventureService.finish_room_and_return()
		else:
			AdventureService.reset_local_state()
			get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/main/main.tscn")

func _mark_battle_reward_pending(reward_kind: String, battle_result: String, has_followup_relic: bool) -> void:
	_battle_settlement_service().mark_reward_pending(
		_encounter_id,
		reward_kind,
		battle_result,
		has_followup_relic,
		GameService.pending_room_id,
		AdventureService.pending_room_type,
		_controller.state if _controller != null else null
	)

func _restore_battle_reward_if_needed() -> void:
	if not RunService.is_run_active():
		return
	if RunService.get_run_phase() != "BATTLE_REWARD":
		return
	var pending := RunService.get_pending_decision()
	if str(pending.get("type", "")) != "battle_reward":
		return
	var room_id := str(pending.get("room_id", GameService.pending_room_id))
	_battle_settlement_service().restore_pending_dropped_gems(_controller.state if _controller != null else null)
	var battle_result := str(pending.get("battle_result", "win"))
	var relic_offer: Array[String] = _battle_relic_offer(room_id)
	match str(pending.get("reward_kind", "")):
		"settlement":
			var has_relics := not relic_offer.is_empty() and not relic_offer.all(
				func(rid: String) -> bool: return rid == "relic_placeholder"
			)
			_settlement_result = battle_result
			_settlement_is_boss = AdventureService.pending_room_type.to_upper() == "END"
			_settlement_relic_offer = []
			if has_relics:
				_settlement_relic_offer = relic_offer
			_settlement_relic_pending = has_relics
			_settlement_dropped_gems = []
			if _has_pending_dropped_gem_reward():
				_settlement_dropped_gems = _dropped_gem_offer()
			_settlement_gem_pending = not _settlement_dropped_gems.is_empty()
			_settlement_gold_amount = EconomyService.get_combat_reward(AdventureService.pending_room_type, room_id)
			if _settlement_overlay == null:
				_open_battle_settlement()
		"dropped_gem":
			var dropped_gems := _dropped_gem_offer()
			if not dropped_gems.is_empty():
				if _relic_reward_overlay == null:
					var overlay := _build_dropped_gem_overlay(dropped_gems, relic_offer, battle_result)
					_relic_reward_overlay = overlay
					add_child(overlay)
			else:
				if not relic_offer.is_empty():
					_show_relic_reward(relic_offer, battle_result)
				else:
					RunService.clear_pending_decision()
					RunService.set_run_phase("MAP")
					_finish_battle_and_navigate(battle_result)
		"gem":
			RunService.clear_pending_decision()
			RunService.set_run_phase("MAP")
			if not relic_offer.is_empty():
				_show_relic_reward(relic_offer, battle_result)
			else:
				_finish_battle_and_navigate(battle_result)
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
	_hud_presenter._refresh_relic_bar(_relic_bar_available_height())
	_editor_panel_user_positioned = false
	_layout_editor_ui()

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
		"inspect_cell": _inspect_cell,
		"tracked_player_uid": _tracked_player_uid,
		"timeline_hover_uid": _timeline_hover_uid,
		"enemy_phase_running": _enemy_phase_running,
		"enemy_turn_queue": _enemy_turn_queue,
		"editor_compact": _editor_available() and _editor_mode,
		"relic_bar_available_height": _relic_bar_available_height(),
	})
	_inspect_uid = str(hud_state.get("inspect_uid", _inspect_uid))
	_inspect_cell = hud_state.get("inspect_cell", _inspect_cell)
	_tracked_player_uid = str(hud_state.get("tracked_player_uid", _tracked_player_uid))
	if _relic_bar_root != null and _relic_bar_scroll != null:
		_relic_bar_root.visible = _relic_bar_scroll.visible
	var active_turn_uid := str(hud_state.get("active_turn_uid", ""))
	_board.set_active_turn_unit(active_turn_uid)
	if _editor_drag_active:
		_board.clear_overlays()
		if _hover_cell.x >= 0:
			var preview := _editor_preview_for_cell(_hover_cell)
			_board.set_editor_preview(_typed_preview_cells(preview.get("cells", [])), bool(preview.get("valid", false)), true)
		else:
			_board.clear_editor_preview()
	else:
		if _enemy_phase_running:
			_board.clear_overlays()
		else:
			BattleOverlayPresenter.apply_to_board(_board, _controller.get_highlights(_hover_cell))
		_board.clear_editor_preview()
	_sync_unit_slot_panels()
	_update_held_banner()
	_board.queue_redraw()
	call_deferred("_fit_status_panel")
	call_deferred("_fit_status_panel_height")
	call_deferred("_layout_editor_ui")

func _relic_bar_available_height() -> float:
	var top := 8.0
	if _status_panel != null and _status_panel.visible:
		top = _status_panel.position.y + _status_panel.size.y + 4.0
	elif _toggle_panel_btn != null:
		top = _toggle_panel_btn.position.y + maxf(_toggle_panel_btn.size.y, 40.0) + 6.0
	var bottom := get_viewport_rect().size.y - 12.0
	if _bottom_dock != null and _bottom_dock.visible:
		bottom -= _bottom_dock.size.y + 8.0
	return maxf(64.0, bottom - top)

func _editor_preview_for_cell(cell: Vector2i) -> Dictionary:
	if _editor_view == null:
		return {"valid": false, "cells": [], "message": "编辑器未加载"}
	return _editor_view.preview_for_cell(_controller.state, _editor_tool, cell, DataRegistry)

func _typed_preview_cells(values: Variant) -> Array[Vector2i]:
	if _editor_view == null:
		return [] as Array[Vector2i]
	return _editor_view.typed_preview_cells(values)

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


## 手持宝石横幅：拔出后玩家处于"必须嵌入"的中间态，状态面板里的一行小字
## 容易被忽略，这里在屏幕顶部常驻提示，直到宝石被嵌入。
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
	GemEchoVisuals.apply_icon_material(_held_banner_icon, _controller.state, held.uid)
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

