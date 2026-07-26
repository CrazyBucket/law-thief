class_name UiVisualRegressionContract extends RefCounted

const SCHEMA_VERSION := 1
const RESOLUTIONS := [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(2048, 1152),
]
const SCENARIOS := [
	{
		"id": "battle_overlays",
		"scene": "res://scenes/battle/battle_scene.tscn",
		"critical_controls": [
			"HudLayer/TopBar",
			"HudLayer/StatusPanel",
			"HudLayer/TurnQueuePanel",
			"HudLayer/BottomDock",
		],
	},
	{
		"id": "map_route",
		"scene": "res://scenes/map/adventure_map.tscn",
		"critical_controls": [
			"HudLayer/ActionPanel",
			"HudLayer/PreviewPanel",
		],
	},
	{
		"id": "event_room",
		"scene": "res://scenes/adventure/event_scene.tscn",
		"critical_controls": [
			"SafeArea/Layout/TopBar",
			"SafeArea/Layout/Main/ArtFrame",
			"SafeArea/Layout/Main/StoryColumn/StoryPanel",
			"SafeArea/Layout/Main/StoryColumn/ChoicePanel",
		],
	},
	{
		"id": "shop_room",
		"scene": "res://scenes/adventure/shop_scene.tscn",
		"critical_controls": [
			"SafeArea/Layout/TopBar",
			"SafeArea/Layout/TopBar/Row/LeaveButton",
			"SafeArea/Layout/Main/InfoRail",
			"SafeArea/Layout/Main/CatalogFrame",
		],
	},
]
const _SAFE_LABEL_CHARS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"


static func sanitize_label(raw_label: String) -> String:
	var cleaned := ""
	for index in range(raw_label.length()):
		var character := raw_label.substr(index, 1)
		if _SAFE_LABEL_CHARS.contains(character):
			cleaned += character
	if cleaned.is_empty():
		return "current"
	return cleaned.left(48)


static func capture_id(scenario_id: String, resolution: Vector2i) -> String:
	return "%s-%dx%d" % [scenario_id, resolution.x, resolution.y]


static func capture_file_name(scenario_id: String, resolution: Vector2i) -> String:
	return "%s.png" % capture_id(scenario_id, resolution)


static func expected_capture_ids() -> Array[String]:
	var result: Array[String] = []
	for resolution: Vector2i in RESOLUTIONS:
		for scenario: Dictionary in SCENARIOS:
			result.append(capture_id(str(scenario.get("id", "")), resolution))
	return result


static func audit_layout(scene: Node, scenario: Dictionary, viewport_size: Vector2) -> Array[Dictionary]:
	var violations: Array[Dictionary] = []
	var viewport_rect := Rect2(Vector2.ZERO, viewport_size)
	for raw_path in scenario.get("critical_controls", []):
		var path := str(raw_path)
		var control := scene.get_node_or_null(path) as Control
		if control == null:
			violations.append({"code": "missing_control", "path": path})
			continue
		if not control.is_visible_in_tree():
			violations.append({"code": "hidden_control", "path": path})
			continue
		var rect := control.get_global_rect()
		if not _contains_rect(viewport_rect, rect, 1.0):
			violations.append({
				"code": "control_outside_viewport",
				"path": path,
				"rect": _rect_to_json(rect),
				"viewport": _size_to_json(viewport_size),
			})
	for raw_button in scene.find_children("*", "Button", true, false):
		var button := raw_button as Button
		if button == null or not button.is_visible_in_tree():
			continue
		var minimum := button.get_combined_minimum_size()
		if button.size.x + 1.0 < minimum.x or button.size.y + 1.0 < minimum.y:
			violations.append({
				"code": "button_content_overflow",
				"path": str(scene.get_path_to(button)),
				"size": _size_to_json(button.size),
				"minimum": _size_to_json(minimum),
			})
	return violations


static func compare_images(baseline_source: Image, candidate_source: Image) -> Dictionary:
	if baseline_source == null or candidate_source == null:
		return {"ok": false, "reason": "image_unavailable"}
	if baseline_source.get_size() != candidate_source.get_size():
		return {
			"ok": false,
			"reason": "size_mismatch",
			"baseline_size": _size_to_json(baseline_source.get_size()),
			"candidate_size": _size_to_json(candidate_source.get_size()),
		}
	var baseline := baseline_source.duplicate()
	var candidate := candidate_source.duplicate()
	baseline.convert(Image.FORMAT_RGBA8)
	candidate.convert(Image.FORMAT_RGBA8)
	var baseline_data: PackedByteArray = baseline.get_data()
	var candidate_data: PackedByteArray = candidate.get_data()
	var diff_data := PackedByteArray()
	diff_data.resize(baseline_data.size())
	var changed_pixels := 0
	var max_channel_delta := 0
	var absolute_delta_sum := 0
	for offset in range(0, baseline_data.size(), 4):
		var pixel_changed := false
		var pixel_delta := 0
		for channel in range(4):
			var delta := absi(int(baseline_data[offset + channel]) - int(candidate_data[offset + channel]))
			max_channel_delta = maxi(max_channel_delta, delta)
			pixel_delta = maxi(pixel_delta, delta)
			if channel < 3:
				absolute_delta_sum += delta
			if delta > 0:
				pixel_changed = true
		if pixel_changed:
			changed_pixels += 1
		var emphasized := mini(255, pixel_delta * 4)
		diff_data[offset] = emphasized
		diff_data[offset + 1] = emphasized
		diff_data[offset + 2] = emphasized
		diff_data[offset + 3] = 255
	var pixel_count: int = baseline.get_width() * baseline.get_height()
	var diff_image := Image.create_from_data(
		baseline.get_width(), baseline.get_height(), false, Image.FORMAT_RGBA8, diff_data
	)
	return {
		"ok": true,
		"exact_match": changed_pixels == 0,
		"changed_pixels": changed_pixels,
		"pixel_count": pixel_count,
		"changed_ratio": float(changed_pixels) / float(maxi(pixel_count, 1)),
		"mean_absolute_rgb_delta": float(absolute_delta_sum) / float(maxi(pixel_count * 3 * 255, 1)),
		"max_channel_delta": max_channel_delta,
		"diff_image": diff_image,
	}


static func validate_capture_report(report: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if int(report.get("schema_version", 0)) != SCHEMA_VERSION:
		errors.append("schema_version_mismatch")
	var raw_captures: Variant = report.get("captures", null)
	if not raw_captures is Array:
		errors.append("captures_missing")
		return errors
	var captures := raw_captures as Array
	var actual_ids: Array[String] = []
	for raw_capture in captures:
		if not raw_capture is Dictionary:
			errors.append("capture_not_dictionary")
			continue
		var capture := raw_capture as Dictionary
		var capture_key := str(capture.get("capture_id", ""))
		if capture_key.is_empty() or capture_key in actual_ids:
			errors.append("capture_id_invalid:%s" % capture_key)
		else:
			actual_ids.append(capture_key)
		if not (capture.get("violations", []) as Array).is_empty():
			errors.append("capture_has_violations:%s" % capture_key)
		if str(capture.get("sha256", "")).length() != 64:
			errors.append("capture_hash_invalid:%s" % capture_key)
	actual_ids.sort()
	var expected_ids := expected_capture_ids()
	expected_ids.sort()
	if actual_ids != expected_ids:
		errors.append("capture_matrix_mismatch")
	return errors


static func load_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var data: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return (data as Dictionary).duplicate(true) if data is Dictionary else {}


static func _contains_rect(outer: Rect2, inner: Rect2, tolerance: float) -> bool:
	return (
		inner.position.x >= outer.position.x - tolerance
		and inner.position.y >= outer.position.y - tolerance
		and inner.end.x <= outer.end.x + tolerance
		and inner.end.y <= outer.end.y + tolerance
	)


static func _rect_to_json(rect: Rect2) -> Dictionary:
	return {
		"x": snappedf(rect.position.x, 0.01),
		"y": snappedf(rect.position.y, 0.01),
		"width": snappedf(rect.size.x, 0.01),
		"height": snappedf(rect.size.y, 0.01),
	}


static func _size_to_json(size: Vector2) -> Dictionary:
	return {"width": snappedf(size.x, 0.01), "height": snappedf(size.y, 0.01)}
