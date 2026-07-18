extends SceneTree

const Contract = preload("res://scripts/tools/ui_visual_regression_contract.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	assert(Contract.RESOLUTIONS == [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(2048, 1152)], "visual regression must cover the three required 16:9 resolutions")
	assert(Contract.expected_capture_ids().size() == 9, "three fixed scenarios at three resolutions should produce nine captures")
	assert(Contract.sanitize_label(" before/../candidate ") == "beforecandidate", "artifact labels must be path-safe")
	assert(Contract.capture_file_name("map_route", Vector2i(1280, 720)) == "map_route-1280x720.png")
	_test_image_metrics()
	_test_report_validation()
	await _test_layout_audit()
	print("UI_VISUAL_REGRESSION_CONTRACT_TEST_PASS")
	quit(0)


func _test_image_metrics() -> void:
	var baseline := Image.create(2, 1, false, Image.FORMAT_RGBA8)
	baseline.fill(Color.BLACK)
	var candidate := baseline.duplicate()
	candidate.set_pixel(1, 0, Color.WHITE)
	var comparison := Contract.compare_images(baseline, candidate)
	assert(comparison.ok, "same-size images should be comparable")
	assert(not comparison.exact_match and comparison.changed_pixels == 1, "pixel comparison should count changed pixels")
	assert(is_equal_approx(float(comparison.changed_ratio), 0.5), "one of two changed pixels should yield a 0.5 ratio")
	assert(comparison.max_channel_delta == 255, "comparison should preserve the maximum channel delta")
	assert(comparison.diff_image is Image, "comparison should produce an inspectable diff image")
	var mismatch := Contract.compare_images(baseline, Image.create(1, 1, false, Image.FORMAT_RGBA8))
	assert(not mismatch.ok and mismatch.reason == "size_mismatch", "dimension mismatches should be structural failures")


func _test_report_validation() -> void:
	var report := {"schema_version": Contract.SCHEMA_VERSION, "captures": []}
	for capture_key in Contract.expected_capture_ids():
		report.captures.append({
			"capture_id": capture_key,
			"sha256": "0".repeat(64),
			"violations": [],
		})
	assert(Contract.validate_capture_report(report).is_empty(), "complete clean capture matrices should validate")
	var incomplete := report.duplicate(true)
	incomplete.captures.pop_back()
	assert(Contract.validate_capture_report(incomplete).has("capture_matrix_mismatch"), "missing resolutions or scenarios must fail validation")
	var violated := report.duplicate(true)
	violated.captures[0].violations = [{"code": "control_outside_viewport"}]
	assert(not Contract.validate_capture_report(violated).is_empty(), "layout violations must invalidate a capture report")


func _test_layout_audit() -> void:
	var host := Control.new()
	host.size = Vector2(100, 100)
	root.add_child(host)
	var panel := Control.new()
	panel.name = "Panel"
	panel.position = Vector2(90, 90)
	panel.size = Vector2(20, 20)
	host.add_child(panel)
	await process_frame
	var violations := Contract.audit_layout(host, {"critical_controls": ["Panel"]}, Vector2(100, 100))
	var codes: Array[String] = []
	for violation in violations:
		codes.append(str(violation.get("code", "")))
	assert(codes.has("control_outside_viewport"), "layout audit should report critical controls outside the viewport")
	host.queue_free()
