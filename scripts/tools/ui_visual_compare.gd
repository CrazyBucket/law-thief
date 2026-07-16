extends SceneTree

const Contract = preload("res://scripts/tools/ui_visual_regression_contract.gd")
const OUTPUT_ROOT := "res://artifacts/verify/ui-visual"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var labels := _labels_from_args()
	var baseline_label := str(labels.get("baseline", ""))
	var candidate_label := str(labels.get("candidate", ""))
	if baseline_label.is_empty() or candidate_label.is_empty():
		print("UI_VISUAL_COMPARE_FAIL usage: --baseline=<label> --candidate=<label>")
		quit(2)
		return
	var baseline_dir := "%s/%s" % [OUTPUT_ROOT, baseline_label]
	var candidate_dir := "%s/%s" % [OUTPUT_ROOT, candidate_label]
	var baseline_report := Contract.load_json_file(ProjectSettings.globalize_path("%s/report.json" % baseline_dir))
	var candidate_report := Contract.load_json_file(ProjectSettings.globalize_path("%s/report.json" % candidate_dir))
	var errors: Array[String] = []
	for error in Contract.validate_capture_report(baseline_report):
		errors.append("baseline:%s" % error)
	for error in Contract.validate_capture_report(candidate_report):
		errors.append("candidate:%s" % error)
	var comparison_dir := "%s/compare-%s-vs-%s" % [OUTPUT_ROOT, baseline_label, candidate_label]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(comparison_dir))
	var comparisons: Array[Dictionary] = []
	if errors.is_empty():
		var baseline_by_id := _captures_by_id(baseline_report.captures)
		var candidate_by_id := _captures_by_id(candidate_report.captures)
		for capture_key in Contract.expected_capture_ids():
			var baseline_capture: Dictionary = baseline_by_id.get(capture_key, {})
			var candidate_capture: Dictionary = candidate_by_id.get(capture_key, {})
			var comparison := _compare_capture(
				capture_key, baseline_capture, candidate_capture, comparison_dir
			)
			comparisons.append(comparison)
			if not bool(comparison.get("ok", false)):
				errors.append("compare_failed:%s:%s" % [capture_key, comparison.get("reason", "unknown")])
	var report := {
		"schema_version": Contract.SCHEMA_VERSION,
		"baseline": baseline_label,
		"candidate": candidate_label,
		"comparisons": comparisons,
		"errors": errors,
	}
	var report_path := ProjectSettings.globalize_path("%s/report.json" % comparison_dir)
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
	if errors.is_empty():
		print("UI_VISUAL_COMPARE_PASS pairs=%d report=%s" % [comparisons.size(), report_path])
		quit(0)
		return
	for error in errors:
		print("UI_VISUAL_COMPARE_ERROR %s" % error)
	print("UI_VISUAL_COMPARE_FAIL errors=%d report=%s" % [errors.size(), report_path])
	quit(1)


func _compare_capture(
	capture_key: String,
	baseline_capture: Dictionary,
	candidate_capture: Dictionary,
	comparison_dir: String
) -> Dictionary:
	var baseline_path := ProjectSettings.globalize_path("res://%s" % str(baseline_capture.get("image_path", "")))
	var candidate_path := ProjectSettings.globalize_path("res://%s" % str(candidate_capture.get("image_path", "")))
	var baseline_image := Image.load_from_file(baseline_path)
	var candidate_image := Image.load_from_file(candidate_path)
	var result := Contract.compare_images(baseline_image, candidate_image)
	var comparison := {
		"capture_id": capture_key,
		"ok": bool(result.get("ok", false)),
		"baseline_sha256": str(baseline_capture.get("sha256", "")),
		"candidate_sha256": str(candidate_capture.get("sha256", "")),
	}
	if not comparison.ok:
		comparison["reason"] = str(result.get("reason", "unknown"))
		return comparison
	for key in ["exact_match", "changed_pixels", "pixel_count", "changed_ratio", "mean_absolute_rgb_delta", "max_channel_delta"]:
		comparison[key] = result.get(key)
	var diff_image := result.get("diff_image") as Image
	var diff_relative := "%s/%s-diff.png" % [comparison_dir.trim_prefix("res://"), capture_key]
	if diff_image == null or diff_image.save_png(ProjectSettings.globalize_path("res://%s" % diff_relative)) != OK:
		comparison["ok"] = false
		comparison["reason"] = "diff_save_failed"
	else:
		comparison["diff_path"] = diff_relative
	return comparison


func _captures_by_id(captures: Array) -> Dictionary:
	var result := {}
	for raw_capture in captures:
		if raw_capture is Dictionary:
			result[str(raw_capture.get("capture_id", ""))] = raw_capture
	return result


func _labels_from_args() -> Dictionary:
	var result := {"baseline": "", "candidate": ""}
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--baseline="):
			result.baseline = Contract.sanitize_label(argument.trim_prefix("--baseline="))
		elif argument.begins_with("--candidate="):
			result.candidate = Contract.sanitize_label(argument.trim_prefix("--candidate="))
	return result
