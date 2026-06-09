extends Control

const BattleUiTheme = preload("res://scripts/ui/battle_ui_theme.gd")
const _AdventureRoomDisplay := preload("res://scripts/map/adventure_room_display.gd")
const _IsometricBoard := preload("res://scripts/ui/isometric_board.gd")
const BoardInputAdapterScript = preload("res://scripts/ui/board_input_adapter.gd")

@onready var _board: _IsometricBoard = $BoardLayer/IsometricBoard
@onready var _title: Label = $HudLayer/TopBar/VBox/HBox/Title
@onready var _hint: Label = $HudLayer/TopBar/VBox/HBox/Hint
@onready var _seed_label: Label = $HudLayer/TopBar/VBox/HBox/SeedLabel
@onready var _run_summary: Label = $HudLayer/TopBar/VBox/RunSummary
@onready var _preview_title: Label = $HudLayer/PreviewPanel/VBox/Title
@onready var _preview_body: RichTextLabel = $HudLayer/PreviewPanel/VBox/Body
@onready var _back_btn: Button = $HudLayer/TopBar/VBox/HBox/BackBtn
@onready var _regen_btn: Button = $HudLayer/TopBar/VBox/HBox/RegenBtn

var _map_state: GameState = null
var _board_input = BoardInputAdapterScript.new()


func _ready() -> void:
	if not AdventureService.run_active or AdventureService.map_matrix.is_empty():
		AdventureService.start_new_run()
	_apply_theme()
	_board.invert_origin = true
	_board_input.setup(_board)
	_board.cell_clicked.connect(_on_cell_clicked)
	_board.cell_hovered.connect(_on_cell_hovered)
	_rebuild_board()
	_refresh_hud()


func _apply_theme() -> void:
	$HudLayer/TopBar.add_theme_stylebox_override("panel", BattleUiTheme.panel_style(BattleUiTheme.BORDER_ACCENT.darkened(0.2)))
	$HudLayer/PreviewPanel.add_theme_stylebox_override("panel", BattleUiTheme.tooltip_style())
	BattleUiTheme.apply_button(_back_btn, "ghost")
	BattleUiTheme.apply_button(_regen_btn, "ghost")
	_title.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	_hint.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
	_seed_label.add_theme_color_override("font_color", BattleUiTheme.TEXT_HINT)
	_run_summary.add_theme_color_override("font_color", BattleUiTheme.TEXT_HINT)


func _rebuild_board() -> void:
	_map_state = AdventureService.build_board_state()
	_board.set_battle_state(_map_state)
	_board.set_highlights({
		"targets": [AdventureService.current_pos],
		"reachable": AdventureService.get_reachable_cells(),
	})


func _refresh_hud() -> void:
	var node = AdventureService.get_current_node()
	if node == null:
		return
	var display: Dictionary = _AdventureRoomDisplay.get_display(
		node.room_type, AdventureService.get_current_chapter(), AdventureService.get_chapter_count()
	)
	_title.text = "%s · %s" % [SaveService.get_active_slot_label(), AdventureService.get_chapter_label()]
	_hint.text = "当前：%s %s  |  层级 L%d  |  点击高亮相邻格前进" % [display["glyph"], display["label"], int(node.layer)]
	_seed_label.text = "种子 %d" % AdventureService.map_seed
	_run_summary.text = _build_run_summary_text()


func _on_cell_clicked(cell: Vector2i) -> void:
	if not AdventureService.can_enter_cell(cell):
		return
	AdventureService.enter_cell(cell)


func _on_cell_hovered(cell: Vector2i, has_cell: bool) -> void:
	_board.set_hover(cell if has_cell else Vector2i(-1, -1))
	if not has_cell:
		_preview_title.text = "地块预览"
		_preview_body.text = "将鼠标移到棋盘格子上查看房间信息。"
		return
	var node = AdventureService.get_node_at(cell)
	if node == null:
		return
	var display: Dictionary = _AdventureRoomDisplay.get_display(
		node.room_type, AdventureService.get_current_chapter(), AdventureService.get_chapter_count()
	)
	var reachable: bool = AdventureService.can_enter_cell(cell)
	var is_current: bool = (cell == AdventureService.current_pos)
	var room_id := AdventureService.room_id_for_cell(cell)
	var resolved: bool = RunService.is_room_resolved(room_id)
	_preview_title.text = "%s %s" % [display["glyph"], display["label"]]
	var lines: PackedStringArray = PackedStringArray([
		"[color=#c8ccd8]层数：[/color] L%d" % node.layer,
		"[color=#c8ccd8]坐标：[/color] (%d, %d)" % [cell.x, cell.y],
		"[color=#c8ccd8]状态：[/color] %s" % ("[color=#8fd18a]已结算[/color]" if resolved else "[color=#f2d46a]未结算[/color]"),
	])
	var event_id := str(node.properties.get("event_id", ""))
	if not event_id.is_empty():
		lines.append("[color=#c8ccd8]事件：[/color] %s" % event_id)
	var active_rules: Array = AdventureRuleRegistry.get_active_rule_display()
	if not active_rules.is_empty():
		var rule_names: Array[String] = []
		for rule in active_rules:
			if rule is Dictionary:
				rule_names.append(str(rule.get("name", rule.get("rule_id", ""))))
		lines.append("[color=#c8ccd8]全局规则：[/color] %s" % " / ".join(rule_names))
	if is_current:
		lines.append("[color=#f2d46a]当前位置[/color]")
	elif reachable:
		lines.append("[color=#5eb8f2]可进入 → 点击进入[/color]")
	else:
		lines.append("[color=#888c96]不可进入（需从相邻格走过来）[/color]")
	_preview_body.text = "\n".join(lines)


func _on_back_pressed() -> void:
	if RunService.is_run_active():
		RunService.save_run()
	AdventureService.run_active = false
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")


func _on_regen_pressed() -> void:
	AdventureService.start_new_run(int(Time.get_unix_time_from_system()) % 100000)
	_rebuild_board()
	_refresh_hud()


func _exit_tree() -> void:
	_board_input.teardown()


func _build_run_summary_text() -> String:
	var snapshot := RunService.get_player_run_snapshot()
	if snapshot.is_empty():
		return "金币 0  ·  HP --/--  ·  遗物 0  ·  手持 无"
	var carried_gem_name := str(snapshot.get("carried_gem_name", ""))
	if carried_gem_name.is_empty():
		carried_gem_name = "无"
	return "金币 %d  ·  %s  ·  HP %d/%d  ·  遗物 %d  ·  手持 %s" % [
		RunService.get_balance("gold"),
		AdventureService.get_chapter_label(),
		int(snapshot.get("hp", 0)),
		int(snapshot.get("max_hp", 0)),
		int(snapshot.get("owned_relic_count", 0)),
		carried_gem_name,
	]
