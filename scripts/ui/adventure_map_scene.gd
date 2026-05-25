extends Control

const BattleUiTheme = preload("res://scripts/ui/battle_ui_theme.gd")
const _AdventureRoomDisplay := preload("res://scripts/map/adventure_room_display.gd")

@onready var _board: Control = $BoardLayer/IsometricBoard
@onready var _title: Label = $HudLayer/TopBar/HBox/Title
@onready var _hint: Label = $HudLayer/TopBar/HBox/Hint
@onready var _seed_label: Label = $HudLayer/TopBar/HBox/SeedLabel
@onready var _preview_title: Label = $HudLayer/PreviewPanel/VBox/Title
@onready var _preview_body: RichTextLabel = $HudLayer/PreviewPanel/VBox/Body
@onready var _back_btn: Button = $HudLayer/TopBar/HBox/BackBtn
@onready var _regen_btn: Button = $HudLayer/TopBar/HBox/RegenBtn

var _map_state: GameState = null


func _ready() -> void:
	if not AdventureService.run_active or AdventureService.map_matrix.is_empty():
		AdventureService.start_new_run()
	_apply_theme()
	_board.invert_origin = true
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
	var display: Dictionary = _AdventureRoomDisplay.get_display(node.room_type)
	_title.text = "冒险地图"
	_hint.text = "当前：%s %s  |  点击高亮相邻格前进" % [display["glyph"], display["label"]]
	_seed_label.text = "种子 %d" % AdventureService.map_seed


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
	var display: Dictionary = _AdventureRoomDisplay.get_display(node.room_type)
	var reachable: bool = AdventureService.can_enter_cell(cell)
	var is_current: bool = (cell == AdventureService.current_pos)
	_preview_title.text = "%s %s" % [display["glyph"], display["label"]]
	var lines: PackedStringArray = PackedStringArray([
		"[color=#c8ccd8]层数：[/color] L%d" % node.layer,
		"[color=#c8ccd8]坐标：[/color] (%d, %d)" % [cell.x, cell.y],
	])
	if is_current:
		lines.append("[color=#f2d46a]当前位置[/color]")
	elif reachable:
		lines.append("[color=#5eb8f2]可进入 → 点击进入[/color]")
	else:
		lines.append("[color=#888c96]不可进入（需从相邻格走过来）[/color]")
	_preview_body.text = "\n".join(lines)


func _on_back_pressed() -> void:
	AdventureService.run_active = false
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")


func _on_regen_pressed() -> void:
	AdventureService.start_new_run(int(Time.get_unix_time_from_system()) % 100000)
	_rebuild_board()
	_refresh_hud()
