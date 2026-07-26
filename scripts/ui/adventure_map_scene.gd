extends Control

const BattleUiTheme = preload("res://scripts/ui/battle_ui_theme.gd")
const GameConfirmDialog = preload("res://scripts/ui/game_confirm_dialog.gd")
const _AdventureRoomDisplay := preload("res://scripts/map/adventure_room_display.gd")
const _AdventureMapCopyPresenter := preload("res://scripts/ui/adventure_map_copy_presenter.gd")
const _IsometricBoard := preload("res://scripts/ui/isometric_board.gd")
const BoardInputAdapterScript = preload("res://scripts/ui/board_input_adapter.gd")
const INVALID_CELL := Vector2i(-999, -999)
const BACKDROP_PATH := "res://assets/ui/adventure_map_sky_ruins.png"

@onready var _board: _IsometricBoard = $BoardLayer/IsometricBoard
@onready var _backdrop: TextureRect = $Backdrop
@onready var _title: Label = $HudLayer/TopBar/VBox/HeaderRow/HeaderVBox/Title
@onready var _hint: Label = $HudLayer/TopBar/VBox/HeaderRow/HeaderVBox/Hint
@onready var _route_state: Label = $HudLayer/TopBar/VBox/HeaderRow/HeaderVBox/RouteState
@onready var _seed_label: Label = $HudLayer/ActionPanel/ActionRow/SeedLabel
@onready var _gold_chip: Label = $HudLayer/TopBar/VBox/SummaryRow/GoldChip
@onready var _hp_chip: Label = $HudLayer/TopBar/VBox/SummaryRow/HpChip
@onready var _relic_chip: Label = $HudLayer/TopBar/VBox/SummaryRow/RelicsChip
@onready var _carried_chip: Label = $HudLayer/TopBar/VBox/SummaryRow/CarriedChip
@onready var _preview_panel: PanelContainer = $HudLayer/PreviewPanel
@onready var _preview_eyebrow: Label = $HudLayer/PreviewPanel/VBox/Eyebrow
@onready var _selection_state: Label = $HudLayer/PreviewPanel/VBox/SelectionState
@onready var _preview_title: Label = $HudLayer/PreviewPanel/VBox/Title
@onready var _preview_body: RichTextLabel = $HudLayer/PreviewPanel/VBox/Body
@onready var _outlook_title: Label = $HudLayer/PreviewPanel/VBox/OutlookTitle
@onready var _outlook_body: RichTextLabel = $HudLayer/PreviewPanel/VBox/OutlookBody
@onready var _legend_title: Label = $HudLayer/PreviewPanel/VBox/LegendTitle
@onready var _legend_body: RichTextLabel = $HudLayer/PreviewPanel/VBox/LegendBody
@onready var _back_btn: Button = $HudLayer/ActionPanel/ActionRow/BackBtn
@onready var _regen_btn: Button = $HudLayer/ActionPanel/ActionRow/RegenBtn

var _map_state: GameState = null
var _board_input = BoardInputAdapterScript.new()
var _hover_cell: Vector2i = INVALID_CELL
var _leave_confirm_dialog: GameConfirmDialog = null


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
	_refresh_preview()
	_create_leave_confirm_dialog()


func _apply_theme() -> void:
	$HudLayer/TopBar.add_theme_stylebox_override("panel", BattleUiTheme.panel_style(BattleUiTheme.BORDER_ACCENT.darkened(0.2)))
	$HudLayer/ActionPanel.add_theme_stylebox_override("panel", BattleUiTheme.panel_style(BattleUiTheme.BORDER_ACCENT.darkened(0.35)))
	_preview_panel.add_theme_stylebox_override("panel", BattleUiTheme.panel_style(BattleUiTheme.BORDER_ACCENT))
	_backdrop.texture = _load_backdrop_texture()
	_backdrop.modulate = Color(1, 1, 1, 0.92)
	BattleUiTheme.apply_button(_back_btn, "ghost")
	BattleUiTheme.apply_button(_regen_btn, "ghost")
	_regen_btn.visible = OS.is_debug_build()
	_seed_label.visible = OS.is_debug_build()
	_title.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	_hint.add_theme_color_override("font_color", BattleUiTheme.TEXT_HINT)
	_route_state.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
	_seed_label.add_theme_color_override("font_color", BattleUiTheme.TEXT_HINT)
	_preview_eyebrow.add_theme_color_override("font_color", BattleUiTheme.TEXT_HINT)
	_selection_state.add_theme_color_override("font_color", BattleUiTheme.TEXT_MUTED)
	_outlook_title.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	_legend_title.add_theme_color_override("font_color", BattleUiTheme.TEXT_GOLD)
	for chip in [_gold_chip, _hp_chip, _relic_chip, _carried_chip]:
		(chip as Label).add_theme_color_override("font_color", BattleUiTheme.TEXT)
	_refresh_legend()


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
	var focus_choice := _hover_cell if AdventureService.can_enter_cell(_hover_cell) else INVALID_CELL
	if _has_valid_cell(focus_choice):
		overlays.append({"kind": "map_focus", "cells": [focus_choice]})
	var future_cells := _future_cells_for(focus_choice)
	if not future_cells.is_empty():
		overlays.append({"kind": "map_future", "cells": future_cells})
	var routes: Array = []
	if AdventureService.travel_path.size() > 1:
		routes.append({
			"kind": "map_travel",
			"path": AdventureService.travel_path,
			"show_arrow": false,
		})
	_board.set_overlays(overlays, routes)
	_board.set_hover(_hover_cell if _has_valid_cell(_hover_cell) else INVALID_CELL)


func _refresh_hud() -> void:
	var node = AdventureService.get_current_node()
	if node == null:
		return
	var display: Dictionary = _AdventureRoomDisplay.get_display(
		node.room_type, AdventureService.get_current_chapter(), AdventureService.get_chapter_count()
	)
	_title.text = AdventureService.get_chapter_label()
	_hint.text = _tr("map.screen.progress", {
		"room": _AdventureRoomDisplay.display_name(display),
		"count": AdventureService.get_reachable_cells().size(),
	})
	_route_state.text = "已行进 %d 格" % maxi(0, AdventureService.travel_path.size() - 1)
	if _seed_label.visible:
		_seed_label.text = "调试种子 %d" % AdventureService.map_seed
	_refresh_resource_chips()


func _on_cell_clicked(cell: Vector2i) -> void:
	if not AdventureService.can_enter_cell(cell):
		return
	AdventureService.enter_cell(cell)


func _on_cell_hovered(cell: Vector2i, has_cell: bool) -> void:
	_hover_cell = cell if has_cell else INVALID_CELL
	_board.set_hover(_hover_cell if has_cell else INVALID_CELL)
	_rebuild_board()
	_refresh_hud()
	_refresh_preview()


func _on_back_pressed() -> void:
	if _leave_confirm_dialog == null:
		_confirm_leave_map()
		return
	_leave_confirm_dialog.popup_centered(Vector2i(420, 180))


func _create_leave_confirm_dialog() -> void:
	if _leave_confirm_dialog != null:
		return
	_leave_confirm_dialog = GameConfirmDialog.new()
	_leave_confirm_dialog.configure(
		tr("map.leave.confirm.title"),
		tr("map.leave.confirm.body"),
		tr("map.leave.confirm.ok"),
		tr("map.leave.confirm.cancel")
	)
	_leave_confirm_dialog.confirmed.connect(_confirm_leave_map)
	add_child(_leave_confirm_dialog)


func _confirm_leave_map() -> void:
	AdventureService.save_and_return_to_main()


func _on_regen_pressed() -> void:
	AdventureService.start_new_run(int(Time.get_unix_time_from_system()) % 100000)
	_hover_cell = INVALID_CELL
	_rebuild_board()
	_refresh_hud()
	_refresh_preview()


func _exit_tree() -> void:
	_board_input.teardown()


func _refresh_preview() -> void:
	var focus_cell := _hover_cell
	if not _has_valid_cell(focus_cell):
		_preview_panel.visible = false
		return
	var node = AdventureService.get_node_at(focus_cell)
	if node == null:
		_preview_panel.visible = false
		return
	_preview_panel.visible = true
	var display: Dictionary = _AdventureRoomDisplay.get_display(
		node.room_type, AdventureService.get_current_chapter(), AdventureService.get_chapter_count()
	)
	_preview_eyebrow.text = _preview_eyebrow_text(focus_cell)
	_selection_state.text = _preview_selection_state_text()
	_preview_title.text = _AdventureRoomDisplay.display_name(display)
	_preview_body.text = _build_room_body(node, focus_cell)
	_outlook_body.text = _build_outlook_text(node, focus_cell)


func _refresh_resource_chips() -> void:
	var snapshot := RunService.get_player_run_snapshot()
	if snapshot.is_empty():
		_gold_chip.text = _tr("map.screen.resource.gold.short", {"value": 0})
		_hp_chip.text = _tr("map.screen.resource.hp.short", {"current": "--", "max": "--"})
		_relic_chip.text = _tr("map.screen.resource.relics.short", {"value": 0})
		_carried_chip.text = _tr("map.screen.resource.carried.short", {"value": "无"})
		return
	var carried_gem_name := str(snapshot.get("carried_gem_name", ""))
	if carried_gem_name.is_empty():
		carried_gem_name = "无"
	_gold_chip.text = _tr("map.screen.resource.gold.short", {"value": RunService.get_balance("gold")})
	_hp_chip.text = _tr("map.screen.resource.hp.short", {
		"current": int(snapshot.get("hp", 0)),
		"max": int(snapshot.get("max_hp", 0)),
	})
	_relic_chip.text = _tr("map.screen.resource.relics.short", {"value": int(snapshot.get("owned_relic_count", 0))})
	_carried_chip.text = _tr("map.screen.resource.carried.short", {"value": carried_gem_name})


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
			return _tr("map.screen.summary.start")
		"END":
			return _tr("map.screen.summary.end")
		"NORMAL_COMBAT":
			return _tr("map.screen.summary.normal")
		"ELITE_COMBAT":
			return _tr("map.screen.summary.elite")
		"REST_SITE":
			return _tr("map.screen.summary.rest")
		"SHOP":
			return _tr("map.screen.summary.shop")
		"EVENT":
			return _tr("map.screen.summary.event")
	return "未知房间"


func _build_route_state_text() -> String:
	if _has_valid_cell(_hover_cell):
		return _tr("map.screen.status.hovering", {"room": _room_name_for_cell(_hover_cell)})
	return _tr("map.screen.status.current", {"room": _room_name_for_cell(AdventureService.current_pos)})


func _preview_eyebrow_text(focus_cell: Vector2i) -> String:
	if focus_cell == AdventureService.current_pos:
		return _tr("map.screen.current_route")
	if _has_valid_cell(_hover_cell) and focus_cell == _hover_cell:
		return _tr("map.screen.hover_probe")
	return _tr("map.screen.current_route")


func _preview_selection_state_text() -> String:
	var current_text := _tr("map.screen.status.current", {"room": _room_name_for_cell(AdventureService.current_pos)})
	if _has_valid_cell(_hover_cell) and _hover_cell != AdventureService.current_pos:
		current_text += "  ·  %s" % _tr("map.screen.status.hovering", {"room": _room_name_for_cell(_hover_cell)})
	return current_text


func _build_room_body(node, cell: Vector2i) -> String:
	var room_id := AdventureService.room_id_for_cell(cell)
	var resolved: bool = RunService.is_room_resolved(room_id)
	var reachable: bool = AdventureService.can_enter_cell(cell)
	var is_current: bool = cell == AdventureService.current_pos
	var state_text := _tr(
		"map.screen.room.resolved" if resolved else "map.screen.room.unresolved"
	)
	var lines: PackedStringArray = PackedStringArray([
		"[color=#c8ccd8]%s[/color]" % _tr("map.screen.room.layer", {"layer": node.layer}),
		"[color=#c8ccd8]%s[/color]" % _tr("map.screen.room.state", {
			"state": "[color=#8fd18a]%s[/color]" % state_text if resolved else "[color=#f2d46a]%s[/color]" % state_text,
		}),
		"[color=#c8ccd8]%s[/color]" % _tr("map.screen.room.effect", {"effect": _room_preview_line(str(node.room_type))}),
	])
	if is_current:
		lines.append("[color=#f2d46a]%s[/color]" % _tr("map.screen.room.here"))
	elif reachable:
		lines.append("[color=#6ec6f5]%s[/color]" % _tr("map.screen.room.connected"))
	else:
		lines.append("[color=#888c96]%s[/color]" % _tr("map.screen.room.blocked"))
	return "\n".join(lines)


func _build_outlook_text(node, cell: Vector2i) -> String:
	var lines: PackedStringArray = PackedStringArray([
		"[color=#c8ccd8]%s[/color]" % _tr("map.screen.room.followup", {"followup": _followup_summary(node)}),
	])
	var active_rules: Array = AdventureRuleRegistry.get_active_rule_display()
	var copy := _AdventureMapCopyPresenter.present(active_rules, {
		"cell": cell,
		"room_id": AdventureService.room_id_for_cell(cell),
		"event_id": str(node.properties.get("event_id", "")),
	}, _debug_metadata_visible())
	var rule_names: Array[String] = copy.get("rule_names", [])
	if not rule_names.is_empty():
		lines.append("[color=#c8ccd8]%s[/color]" % _tr("map.screen.room.rules", {
			"rules": " / ".join(rule_names),
		}))
	for debug_line in copy.get("debug_lines", PackedStringArray()):
		lines.append("[color=#777b86][DEBUG] %s[/color]" % str(debug_line))
	return "\n".join(lines)


func _debug_metadata_visible() -> bool:
	return Engine.is_editor_hint() or OS.is_debug_build()


func _followup_summary(node) -> String:
	if str(node.room_type) == "END":
		if AdventureService.get_current_chapter() >= AdventureService.get_chapter_count():
			return _tr("map.screen.followup.final")
		return _tr("map.screen.followup.exit")
	if node.children.is_empty():
		return _tr("map.screen.followup.none")
	var labels: Array[String] = []
	for child_cell in node.children:
		var child_node = AdventureService.get_node_at(child_cell)
		if child_node == null:
			continue
		var display: Dictionary = _AdventureRoomDisplay.get_display(
			child_node.room_type, AdventureService.get_current_chapter(), AdventureService.get_chapter_count()
		)
		var room_label := _AdventureRoomDisplay.display_name(display)
		if not room_label in labels:
			labels.append(room_label)
	return _tr("map.screen.followup.options", {"rooms": " / ".join(labels)}) if not labels.is_empty() else _tr("map.screen.followup.none")


func _focus_cell() -> Vector2i:
	if _has_valid_cell(_hover_cell):
		return _hover_cell
	return AdventureService.current_pos


func _has_valid_cell(cell: Vector2i) -> bool:
	return cell != INVALID_CELL and AdventureService.get_node_at(cell) != null


func _future_cells_for(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not _has_valid_cell(cell):
		return result
	var node = AdventureService.get_node_at(cell)
	if node == null:
		return result
	for child in node.children:
		result.append(child)
	return result


func _room_name_for_cell(cell: Vector2i) -> String:
	var node = AdventureService.get_node_at(cell)
	if node == null:
		return ""
	var display: Dictionary = _AdventureRoomDisplay.get_display(
		node.room_type, AdventureService.get_current_chapter(), AdventureService.get_chapter_count()
	)
	return _AdventureRoomDisplay.display_name(display)


func _refresh_legend() -> void:
	_legend_body.text = "\n".join([
		"[color=#5fc06a]%s[/color]" % _tr("map.screen.legend.current"),
		"[color=#7ec4ec]%s[/color]" % _tr("map.screen.legend.choice"),
		"[color=#f2cf6b]%s[/color]" % _tr("map.screen.legend.selected"),
		"[color=#8b8fa0]%s[/color]" % _tr("map.screen.legend.resolved"),
	])


func _tr(key: String, params: Dictionary = {}) -> String:
	var text := tr(key)
	return text.format(params) if not params.is_empty() else text


func _load_backdrop_texture() -> Texture2D:
	var global_path := ProjectSettings.globalize_path(BACKDROP_PATH)
	if not FileAccess.file_exists(global_path):
		return null
	var image := Image.load_from_file(global_path)
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)
