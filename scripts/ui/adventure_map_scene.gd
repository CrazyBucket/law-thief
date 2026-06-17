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
	theme = BattleUiTheme.build_theme()
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
	$HudLayer/PreviewPanel.add_theme_stylebox_override("panel", BattleUiTheme.panel_style(BattleUiTheme.BORDER_ACCENT))
	BattleUiTheme.apply_button(_back_btn, "ghost")
	BattleUiTheme.apply_button(_regen_btn, "ghost")
	_regen_btn.visible = OS.is_debug_build()
	_seed_label.visible = OS.is_debug_build()
	_title.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	_hint.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
	_seed_label.add_theme_color_override("font_color", BattleUiTheme.TEXT_HINT)
	_run_summary.add_theme_color_override("font_color", BattleUiTheme.TEXT_HINT)


func _rebuild_board() -> void:
	_map_state = AdventureService.build_board_state()
	_board.set_battle_state(_map_state)
	var reachable := AdventureService.get_reachable_cells()
	var resolved_cells := _resolved_map_cells()
	var overlays: Array = []
	if not resolved_cells.is_empty():
		overlays.append({"kind": "map_resolved", "cells": resolved_cells})
	overlays.append({"kind": "map_current", "cells": [AdventureService.current_pos]})
	if not reachable.is_empty():
		overlays.append({"kind": "map_choice", "cells": reachable})
	var routes: Array = []
	for cell in reachable:
		routes.append({
			"kind": "map_choice",
			"path": [AdventureService.current_pos, cell],
			"arrow_reverse": false,
		})
	_board.set_highlights({
		"targets": [AdventureService.current_pos],
		"reachable": reachable,
		"overlays": overlays,
		"routes": routes,
	})


func _refresh_hud() -> void:
	var node = AdventureService.get_current_node()
	if node == null:
		return
	var display: Dictionary = _AdventureRoomDisplay.get_display(
		node.room_type, AdventureService.get_current_chapter(), AdventureService.get_chapter_count()
	)
	_title.text = "%s · %s" % [SaveService.get_active_slot_label(), AdventureService.get_chapter_label()]
	_hint.text = "当前位置：%s %s  ·  前方 %d 个选择" % [
		display["glyph"],
		display["label"],
		AdventureService.get_reachable_cells().size(),
	]
	if _seed_label.visible:
		_seed_label.text = "调试种子 %d" % AdventureService.map_seed
	_run_summary.text = _build_run_summary_text()


func _on_cell_clicked(cell: Vector2i) -> void:
	if not AdventureService.can_enter_cell(cell):
		return
	AdventureService.enter_cell(cell)


func _on_cell_hovered(cell: Vector2i, has_cell: bool) -> void:
	_board.set_hover(cell if has_cell else Vector2i(-1, -1))
	if not has_cell:
		_preview_title.text = "路线图"
		_preview_body.text = "选择前方房间，确认下一段旅程。"
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
		"[color=#c8ccd8]路标：[/color] 第 %d 层" % node.layer,
		"[color=#c8ccd8]状态：[/color] %s" % ("[color=#8fd18a]已探索[/color]" if resolved else "[color=#f2d46a]未探索[/color]"),
		"[color=#c8ccd8]预期：[/color] %s" % _room_preview_line(str(node.room_type)),
	])
	var event_id := str(node.properties.get("event_id", ""))
	if not event_id.is_empty():
		lines.append("[color=#c8ccd8]事件：[/color] 未知事件")
	var active_rules: Array = AdventureRuleRegistry.get_active_rule_display()
	if not active_rules.is_empty():
		var rule_names: Array[String] = []
		for rule in active_rules:
			if rule is Dictionary:
				rule_names.append(str(rule.get("name", rule.get("rule_id", ""))))
		lines.append("[color=#c8ccd8]全局规则：[/color] %s" % " / ".join(rule_names))
	if is_current:
		lines.append("[color=#f2d46a]你在这里[/color]")
	elif reachable:
		lines.append("[color=#5eb8f2]路线已连通[/color]")
	else:
		lines.append("[color=#888c96]尚未连通[/color]")
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


func _resolved_map_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in range(AdventureService.map_matrix.size()):
		var column: Array = AdventureService.map_matrix[x]
		for y in range(column.size()):
			var cell := Vector2i(x, y)
			if RunService.is_room_resolved(AdventureService.room_id_for_cell(cell)):
				cells.append(cell)
	return cells


func _room_preview_line(room_type: String) -> String:
	match room_type:
		"START":
			return "旅程起点"
		"END":
			return "本章出口或终局挑战"
		"NORMAL_COMBAT":
			return "常规战斗，获得基础奖励"
		"ELITE_COMBAT":
			return "强敌战斗，风险与奖励更高"
		"REST_SITE":
			return "休整与恢复"
		"SHOP":
			return "补给、交易与构筑调整"
		"EVENT":
			return "特殊事件，结果未明"
	return "未知房间"
