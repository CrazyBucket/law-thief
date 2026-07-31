extends SceneTree

const OverlayCloudLayoutClass := preload("res://scripts/map/overlay_cloud_layout.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var cell := Vector2i(3, 2)
	var fog: Dictionary = OverlayCloudLayoutClass.build(cell, Constants.TILE_MOD_POISON_FOG)
	var repeated: Dictionary = OverlayCloudLayoutClass.build(cell, Constants.TILE_MOD_POISON_FOG)
	var smoke: Dictionary = OverlayCloudLayoutClass.build(cell, Constants.TILE_MOD_TOXIC_SMOKE)
	_require(fog == repeated, "cloud layout must be deterministic for one cell and effect")
	_require(fog != OverlayCloudLayoutClass.build(Vector2i(4, 2), Constants.TILE_MOD_POISON_FOG), "neighboring cells must not share one stamped layout")
	_check_layout(fog, 8, 5, "poison fog")
	_check_layout(smoke, 11, 9, "toxic smoke")
	_require(_average_speed(smoke["parts"]) > _average_speed(fog["parts"]), "toxic smoke vertical churn must remain clearly visible")
	_require(_average_abs_x(fog["parts"]) > _average_abs_x(smoke["parts"]), "poison fog must spread wider than toxic smoke")
	_require(_average_width(smoke["parts"]) > _average_width(fog["parts"]), "toxic smoke must use thicker parts than poison fog")
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("OVERLAY_CLOUD_LAYOUT_TEST_PASS")
	quit()


func _check_layout(layout: Dictionary, expected_parts: int, expected_particles: int, label: String) -> void:
	var parts: Array = layout.get("parts", [])
	var particles: Array = layout.get("particles", [])
	_require(parts.size() == expected_parts, "%s must use the expected part density" % label)
	_require(particles.size() == expected_particles, "%s must use the expected particle density" % label)
	var directions := {}
	var bands := {}
	var front_count := 0
	for part_variant in parts:
		var part: Dictionary = part_variant
		var atlas_index := int(part.get("atlas_index", -1))
		_require(atlas_index >= 0 and atlas_index < OverlayCloudLayoutClass.ATLAS_PART_COUNT, "%s part must select a valid atlas cell" % label)
		directions[signf(float(part["direction"]))] = true
		var vertical := float(part["vertical"])
		bands[int(floor(vertical * 4.0))] = true
		if bool(part["front"]):
			front_count += 1
			_require(vertical >= 0.55, "%s front parts must stay in the lower character portion" % label)
	_require(directions.size() == 2, "%s parts must travel both left and right" % label)
	_require(bands.size() == 4, "%s parts must cover the nominal character height" % label)
	_require(front_count >= 1, "%s must reserve at least one low front-layer part" % label)
	if not parts.is_empty():
		var sample: Dictionary = parts[0]
		var edge_time := (1.0 - float(sample["phase"])) / float(sample["speed"])
		var middle_time := (1.5 - float(sample["phase"])) / float(sample["speed"])
		if bool(sample["vertical_motion"]):
			var quarter_time := (1.25 - float(sample["phase"])) / float(sample["speed"])
			var edge_offset := OverlayCloudLayoutClass.animated_offset(sample, edge_time)
			var quarter_offset := OverlayCloudLayoutClass.animated_offset(sample, quarter_time)
			_require(OverlayCloudLayoutClass.drift_alpha(sample, edge_time) > 0.99, "%s vertical motion must not blink at its loop edge" % label)
			_require(absf(quarter_offset.y - edge_offset.y) > absf(quarter_offset.x - edge_offset.x), "%s motion must be predominantly vertical" % label)
		else:
			_require(OverlayCloudLayoutClass.drift_alpha(sample, edge_time) < 0.001, "%s parts must vanish before their horizontal wrap" % label)
			_require(OverlayCloudLayoutClass.drift_alpha(sample, middle_time) > 0.99, "%s parts must remain solid through the middle of their drift" % label)


func _average_speed(parts: Array) -> float:
	var total := 0.0
	for part_variant in parts:
		total += float((part_variant as Dictionary)["speed"])
	return total / maxf(float(parts.size()), 1.0)


func _average_abs_x(parts: Array) -> float:
	var total := 0.0
	for part_variant in parts:
		total += absf(((part_variant as Dictionary)["base_position"] as Vector2).x)
	return total / maxf(float(parts.size()), 1.0)


func _average_width(parts: Array) -> float:
	var total := 0.0
	for part_variant in parts:
		total += float((part_variant as Dictionary)["width_ratio"])
	return total / maxf(float(parts.size()), 1.0)


func _require(condition: bool, message: String) -> void:
	if condition:
		return
	failures.append(message)
