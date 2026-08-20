extends SceneTree

const Contract = preload("res://scripts/tools/ui_visual_regression_contract.gd")
const OUTPUT_ROOT := "res://artifacts/verify/ui-visual"

var _label := "current"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_label = _label_from_args()
	var output_dir := "%s/%s" % [OUTPUT_ROOT, _label]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	if DisplayServer.get_name() == "headless":
		_write_report(output_dir, {
			"schema_version": Contract.SCHEMA_VERSION,
			"label": _label,
			"captures": [],
			"errors": ["renderer_unavailable:headless"],
		})
		print("UI_VISUAL_PROBE_FAIL readable renderer required; do not use --headless")
		quit(2)
		return
	var report := {
		"schema_version": Contract.SCHEMA_VERSION,
		"label": _label,
		"renderer": {
			"display_server": DisplayServer.get_name(),
			"rendering_method": str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")),
			"adapter": RenderingServer.get_video_adapter_name(),
		},
		"captures": [],
		"errors": [],
	}
	for resolution: Vector2i in Contract.RESOLUTIONS:
		for scenario: Dictionary in Contract.SCENARIOS:
			var capture := await _capture_scene(scenario, resolution, output_dir)
			report.captures.append(capture)
	var report_errors := Contract.validate_capture_report(report)
	report.errors.append_array(report_errors)
	_write_report(output_dir, report)
	if report.errors.is_empty():
		print("UI_VISUAL_PROBE_PASS label=%s captures=%d report=%s/report.json" % [
			_label, report.captures.size(), output_dir,
		])
		quit(0)
		return
	for error in report.errors:
		print("UI_VISUAL_PROBE_ERROR %s" % str(error))
	print("UI_VISUAL_PROBE_FAIL label=%s errors=%d" % [_label, report.errors.size()])
	quit(1)


func _capture_scene(scenario: Dictionary, resolution: Vector2i, output_dir: String) -> Dictionary:
	DisplayServer.window_set_size(resolution)
	root.size = resolution
	await process_frame
	await process_frame
	_prepare_scenario(str(scenario.get("id", "")))
	var scene_path := str(scenario.get("scene", ""))
	var packed := load(scene_path) as PackedScene
	var capture_key := Contract.capture_id(str(scenario.get("id", "")), resolution)
	var violations: Array[Dictionary] = []
	if packed == null:
		violations.append({"code": "scene_load_failed", "scene": scene_path})
		return _capture_result(capture_key, scenario, resolution, "", "", violations)
	var node := packed.instantiate()
	root.set_meta("ui_visual_scene_path", scene_path)
	root.add_child(node)
	await process_frame
	await process_frame
	await _configure_scenario(node, str(scenario.get("id", "")))
	await create_timer(0.2).timeout
	var layout_viewport: Vector2 = node.get_viewport_rect().size
	violations.append_array(Contract.audit_layout(node, scenario, layout_viewport))
	violations.append_array(_audit_persistent_hud(node, str(scenario.get("id", "")), layout_viewport))
	var texture := root.get_texture()
	var image := texture.get_image() if texture != null else null
	var relative_path := "%s/%s" % [
		output_dir.trim_prefix("res://"),
		Contract.capture_file_name(str(scenario.get("id", "")), resolution),
	]
	var absolute_path := ProjectSettings.globalize_path("res://%s" % relative_path)
	var sha256 := ""
	if image == null:
		violations.append({"code": "renderer_image_unavailable"})
	else:
		if image.get_size() != resolution:
			violations.append({
				"code": "capture_size_mismatch",
				"expected": {"width": resolution.x, "height": resolution.y},
				"actual": {"width": image.get_width(), "height": image.get_height()},
			})
		var save_error := image.save_png(absolute_path)
		if save_error != OK:
			violations.append({"code": "capture_save_failed", "error": save_error})
		else:
			sha256 = FileAccess.get_sha256(absolute_path)
			print("  [OK] %s -> %s" % [capture_key, absolute_path])
	node.queue_free()
	root.remove_meta("ui_visual_scene_path")
	await process_frame
	return _capture_result(capture_key, scenario, resolution, relative_path, sha256, violations, layout_viewport)


func _audit_persistent_hud(scene: Node, scenario_id: String, viewport_size: Vector2) -> Array[Dictionary]:
	if scenario_id not in ["map_route", "event_room", "shop_room"]:
		return []
	var violations: Array[Dictionary] = []
	var hud := root.get_node_or_null("AdventureStatusHud/AdventureStatusLayer/AdventureStatusRoot/AdventureStatus") as Control
	if hud == null or not hud.is_visible_in_tree():
		return [{"code": "persistent_hud_missing"}]
	var hud_rect := hud.get_global_rect()
	if not hud_rect.position.is_equal_approx(Vector2.ZERO):
		violations.append({"code": "persistent_hud_not_screen_fixed", "position": hud_rect.position})
	if not is_equal_approx(hud_rect.size.x, viewport_size.x) or not is_equal_approx(hud_rect.size.y, 72.0):
		violations.append({"code": "persistent_hud_not_reserved_top_strip"})
	if hud_rect.end.x > viewport_size.x or hud_rect.end.y > viewport_size.y:
		violations.append({"code": "persistent_hud_outside_viewport"})
	var protected_paths: Array[String] = []
	if scenario_id == "event_room":
		protected_paths = ["SafeArea/Layout/TopBar/Row/HeaderTitle", "SafeArea/Layout/TopBar/Row/ChapterLabel"]
	elif scenario_id == "shop_room":
		protected_paths = ["SafeArea/Layout/TopBar/Row/TitleGroup", "SafeArea/Layout/TopBar/Row/LeaveButton"]
	else:
		protected_paths = ["HudLayer/ActionPanel"]
	for path in protected_paths:
		var control := scene.get_node_or_null(path) as Control
		if control != null and control.is_visible_in_tree() and hud_rect.intersects(control.get_global_rect()):
			violations.append({"code": "persistent_hud_overlap", "path": path})
	return violations


func _prepare_scenario(scenario_id: String) -> void:
	var transition_manager := root.get_node_or_null("TransitionManager")
	if transition_manager != null and transition_manager.has_method("reset_immediately"):
		transition_manager.call("reset_immediately")
	match scenario_id:
		"battle_overlays", "battle_menu":
			root.get_node("SettingsService").call("set_value", "show_tutorial", false)
			var adventure_service := root.get_node("AdventureService")
			adventure_service.set("pending_room_type", "NORMAL_COMBAT")
			adventure_service.set("pending_room_label", "")
			root.get_node("GameService").set("pending_room_id", "")
			root.get_node("GameService").call("start_battle", "tutorial_001")
		"map_route", "map_menu":
			root.get_node("AdventureService").call("start_new_run", 12345)
		"event_room":
			var adventure_service := root.get_node("AdventureService")
			adventure_service.call("start_new_run", 20260717)
			adventure_service.set("current_pos", Vector2i.ZERO)
			adventure_service.set("pending_room_type", "EVENT")
			adventure_service.set("pending_room_label", "奇遇")
			var map_node: Variant = adventure_service.call("get_current_node")
			if map_node != null:
				map_node.set("room_type", "EVENT")
				var properties: Dictionary = map_node.get("properties")
				properties["event_id"] = "event_injury_appraisal"
				map_node.set("properties", properties)
		"shop_room":
			var shop_adventure_service := root.get_node("AdventureService")
			shop_adventure_service.call("start_new_run", 20260720)
			shop_adventure_service.set("current_pos", Vector2i.ZERO)
			shop_adventure_service.set("pending_room_type", "SHOP")
			shop_adventure_service.set("pending_room_label", "黑市")
			var shop_map_node: Variant = shop_adventure_service.call("get_current_node")
			if shop_map_node != null:
				shop_map_node.set("room_type", "SHOP")


func _configure_scenario(node: Node, scenario_id: String) -> void:
	match scenario_id:
		"battle_overlays":
			_configure_battle_overlays(node)
		"battle_menu":
			node.call("_on_menu_pressed")
		"map_route":
			var adventure_service := root.get_node("AdventureService")
			var reachable: Array = adventure_service.call("get_reachable_cells")
			if not reachable.is_empty():
				node.call("_on_cell_hovered", reachable[0], true)
		"map_menu":
			node.call("_on_menu_pressed")
	await process_frame
	await process_frame


func _configure_battle_overlays(node: Node) -> void:
	var controller: Variant = node.get("_controller")
	if controller == null or controller.state == null:
		return
	var state: GameState = controller.state
	var player := state.get_player()
	if player == null:
		return
	var cells := _nearby_cells(state, player.pos)
	if cells.size() < 7:
		return
	var overlays: Array = [
		{"kind": "move", "cells": [cells[0], cells[1]]},
		{"kind": "attack_range", "cells": [cells[2], cells[3]]},
		{"kind": "danger", "cells": [cells[4], cells[5]]},
		{"kind": "effect", "preview_kind": "explosion", "cells": [cells[3], cells[4], cells[6]]},
	]
	var routes: Array = [
		{"kind": "move", "path": [player.pos, cells[0], cells[1]], "arrow_reverse": false},
		{"kind": "intent", "path": [cells[6], cells[5], cells[4]], "arrow_reverse": false},
	]
	var board := node.get_node("BoardLayer/IsometricBoard")
	board.call("set_overlays", overlays, routes)
	board.call("set_hover", cells[3])


func _nearby_cells(state: GameState, origin: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for offset in [
		Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
		Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
		Vector2i(2, 0), Vector2i(0, 2), Vector2i(-2, 0), Vector2i(0, -2),
	]:
		var cell: Vector2i = origin + offset
		if state.get_tile(cell) != null:
			result.append(cell)
	return result


func _capture_result(
	capture_key: String,
	scenario: Dictionary,
	resolution: Vector2i,
	image_path: String,
	sha256: String,
	violations: Array[Dictionary],
	layout_viewport: Vector2 = Vector2.ZERO
) -> Dictionary:
	return {
		"capture_id": capture_key,
		"scenario_id": str(scenario.get("id", "")),
		"scene": str(scenario.get("scene", "")),
		"resolution": {"width": resolution.x, "height": resolution.y},
		"layout_viewport": {"width": layout_viewport.x, "height": layout_viewport.y},
		"image_path": image_path,
		"sha256": sha256,
		"violations": violations,
	}


func _label_from_args() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="):
			return Contract.sanitize_label(argument.trim_prefix("--label="))
	return "current"


func _write_report(output_dir: String, report: Dictionary) -> void:
	var path := ProjectSettings.globalize_path("%s/report.json" % output_dir)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
