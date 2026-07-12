extends SceneTree

const WaterAutotileClass := preload("res://scripts/map/water_autotile.gd")
const WaterLayerClass := preload("res://scripts/map/water_layer.gd")

const FRAME_SIZE := Vector2i(128, 64)
const CANVAS_SIZE := Vector2i(640, 384)
const ORIGIN := Vector2i(320, 96)
const OUTPUT_DIR := "user://water_frame_contract"
const EDGE_POINTS := [
	[Vector2(64, 0), Vector2(128, 32)],
	[Vector2(128, 32), Vector2(64, 64)],
	[Vector2(64, 64), Vector2(0, 32)],
	[Vector2(0, 32), Vector2(64, 0)],
]

var sheet_top: Image
var sheet_right: Image
var source_top: Image
var source_right: Image
var mask_top: Image
var mask_right: Image
var failures: Array[String] = []


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	sheet_top = _load_image("res://assets/tiles/waterEdgeTop.generated.png")
	sheet_right = _load_image("res://assets/tiles/waterEdgeRight.generated.png")
	source_top = _load_image("res://assets/tiles/waterEdge1.png")
	source_right = _load_image("res://assets/tiles/waterEdge2.png")
	mask_top = _load_image("res://assets/tiles/waterMaskTop.generated.png")
	mask_right = _load_image("res://assets/tiles/waterMaskRight.generated.png")
	_require(
		sheet_top != null and sheet_right != null and source_top != null and source_right != null
			and mask_top != null and mask_right != null,
		"failed to load water edge sheets"
	)

	_verify_source_preservation(sheet_top, source_top, range(8), "top/Sprite468")
	_verify_source_preservation(sheet_right, source_right, range(8), "right/Sprite469")
	_verify_single_tile_uses_top_pair()
	_verify_single_fill_stays_inside_shore()
	_verify_shape("single", [Vector2i(0, 0)])
	_verify_shape("pair_x", [Vector2i(0, 0), Vector2i(1, 0)])
	_verify_shape("pair_y", [Vector2i(0, 0), Vector2i(0, 1)])
	_verify_shape("square", [
		Vector2i(0, 0), Vector2i(1, 0),
		Vector2i(0, 1), Vector2i(1, 1),
	])
	_verify_shape("L", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)])
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("WATER_FRAME_COMPOSITE_TEST_PASS")
	quit()


func _verify_source_preservation(generated: Image, source: Image, frames: Array, label: String) -> void:
	for frame: int in frames:
		var output := _frame(generated, frame)
		var original := _frame(source, frame)
		var mismatch_count := 0
		for y in range(FRAME_SIZE.y):
			for x in range(FRAME_SIZE.x):
				var expected_shore: bool = _is_source_shore(original.get_pixel(x, y))
				var actual_shore: bool = output.get_pixel(x, y).a > 0.01
				if expected_shore != actual_shore:
					mismatch_count += 1
		_require(mismatch_count == 0, "%s frame %d differs from source by %d shore pixels" % [
			label, frame, mismatch_count,
		])
	print("  [OK] %s generated frames preserve source shore pixels" % label)


func _verify_frame_semantics(sheet: Image, side_a_edge: int, side_b_edge: int, label: String) -> void:
	for frame in range(8):
		var counts := _edge_counts(_frame(sheet, frame))
		var has_side_a: bool = counts[side_a_edge] > 100
		var has_side_b: bool = counts[side_b_edge] > 100
		_require(has_side_a == bool(frame & WaterAutotileClass.SIDE_A), "%s frame %d side A mismatch: %s" % [
			label, frame, counts,
		])
		_require(has_side_b == bool(frame & WaterAutotileClass.SIDE_B), "%s frame %d side B mismatch: %s" % [
			label, frame, counts,
		])
	_require(not _has_gray(_frame(sheet, 0)), "%s state 0 must be empty" % label)
	print("  [OK] %s states 0..7 body edges match bits 1/4" % label)


func _verify_single_tile_uses_top_pair() -> void:
	var composed := WaterLayerClass.compose_edge_image(sheet_top, sheet_right, Vector4i(5, 5, 5, 5))
	var expected := Image.create(FRAME_SIZE.x, FRAME_SIZE.y, false, Image.FORMAT_RGBA8)
	expected.fill(Color.TRANSPARENT)
	_blit_opaque(expected, _frame(sheet_top, 5))
	var bottom := _frame(sheet_top, 5)
	bottom.flip_y()
	_blit_opaque(expected, bottom)
	expected = WaterLayerClass._apply_diamond_alpha(expected)
	var mismatches := 0
	for y in range(FRAME_SIZE.y):
		for x in range(FRAME_SIZE.x):
			if composed.get_pixel(x, y) != expected.get_pixel(x, y):
				mismatches += 1
	_require(mismatches == 0, "single tile must equal top frame 5 plus its vertical mirror; mismatches=%d" % mismatches)
	print("  [OK] single uses top frame 5 plus its vertical mirror")


func _verify_single_fill_stays_inside_shore() -> void:
	var fill := WaterLayerClass.compose_fill_image(mask_top, mask_right, Vector4i(5, 5, 5, 5))
	for point in [Vector2i(64, 0), Vector2i(127, 32), Vector2i(64, 63), Vector2i(0, 32)]:
		_require(fill.get_pixelv(point).a <= 0.01, "single fill leaks through shore tip at %s" % point)
	_require(fill.get_pixel(64, 32).a > 0.99, "single fill must retain its center")
	print("  [OK] single fill stays inside rounded shore tips")


func _verify_shape(label: String, cells: Array[Vector2i]) -> void:
	var water := {}
	for cell in cells:
		water[cell] = true
	var canvas := Image.create(CANVAS_SIZE.x, CANVAS_SIZE.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color.TRANSPARENT)
	for pos: Vector2i in cells:
		_compose_tile(canvas, _screen_center(pos), WaterAutotileClass.states(pos, water))
	var path := "%s/%s.png" % [OUTPUT_DIR, label]
	canvas.save_png(path)

	var shared_gray := 0
	for pos: Vector2i in cells:
		for direction in [
			WaterAutotileClass.FRONT_RIGHT,
			WaterAutotileClass.FRONT_LEFT,
		]:
			if not water.has(pos + direction):
				continue
			shared_gray += _count_gray_on_shared_edge(canvas, pos, direction)
	_require(shared_gray == 0, "%s has %d gray pixels on shared edges; see %s" % [label, shared_gray, path])
	if shared_gray == 0:
		print("  [OK] %s shared_gray=0 -> %s" % [label, path])


func _compose_tile(canvas: Image, center: Vector2i, states: Vector4i) -> void:
	_blend_image(canvas, WaterLayerClass.compose_edge_image(sheet_top, sheet_right, states), center)


func _blend_image(canvas: Image, image: Image, center: Vector2i) -> void:
	for y in range(FRAME_SIZE.y):
		for x in range(FRAME_SIZE.x):
			var c := image.get_pixel(x, y)
			if c.a <= 0.01:
				continue
			var dst := center + Vector2i(x - FRAME_SIZE.x / 2, y - FRAME_SIZE.y / 2)
			if Rect2i(Vector2i.ZERO, CANVAS_SIZE).has_point(dst):
				canvas.set_pixelv(dst, c)


func _blit_opaque(target: Image, source: Image) -> void:
	for y in range(FRAME_SIZE.y):
		for x in range(FRAME_SIZE.x):
			var c := source.get_pixel(x, y)
			if c.a > 0.01:
				target.set_pixel(x, y, c)


func _frame(sheet: Image, frame_index: int) -> Image:
	return sheet.get_region(Rect2i(frame_index * FRAME_SIZE.x, 0, FRAME_SIZE.x, FRAME_SIZE.y))


func _load_image(path: String) -> Image:
	var texture := load(path) as Texture2D
	return texture.get_image() if texture != null else null


func _screen_center(pos: Vector2i) -> Vector2i:
	return ORIGIN + Vector2i((pos.x - pos.y) * 64, (pos.x + pos.y) * 32)


func _count_gray_on_shared_edge(canvas: Image, pos: Vector2i, direction: Vector2i) -> int:
	var a := _screen_center(pos)
	var b := _screen_center(pos + direction)
	var start: Vector2
	var end: Vector2
	if direction == WaterAutotileClass.FRONT_RIGHT:
		start = Vector2(a + Vector2i(64, 0))
		end = Vector2(a + Vector2i(0, 32))
	else:
		start = Vector2(a + Vector2i(0, 32))
		end = Vector2(a + Vector2i(-64, 0))
	var count := 0
	# Ignore endpoint caps; this test verifies the shared edge body is empty.
	for step in range(16, 49):
		var t := float(step) / 64.0
		var p := start.lerp(end, t)
		for offset in range(-2, 3):
			var sample := Vector2i(roundi(p.x), roundi(p.y + offset))
			if Rect2i(Vector2i.ZERO, CANVAS_SIZE).has_point(sample) and _is_gray(canvas.get_pixelv(sample)):
				count += 1
	return count


func _has_gray(image: Image) -> bool:
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if _is_gray(image.get_pixel(x, y)):
				return true
	return false


func _edge_counts(image: Image) -> Array[int]:
	var counts: Array[int] = [0, 0, 0, 0]
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if not _is_gray(image.get_pixel(x, y)):
				continue
			var point := Vector2(x, y)
			var nearest := 0
			var nearest_distance := INF
			for edge in range(EDGE_POINTS.size()):
				var distance := _distance_to_segment(point, EDGE_POINTS[edge][0], EDGE_POINTS[edge][1])
				if distance < nearest_distance:
					nearest_distance = distance
					nearest = edge
			counts[nearest] += 1
	return counts


func _distance_to_segment(point: Vector2, start: Vector2, end: Vector2) -> float:
	var segment := end - start
	var t := clampf((point - start).dot(segment) / segment.length_squared(), 0.0, 1.0)
	return point.distance_to(start + segment * t)


func _is_gray(c: Color) -> bool:
	return c.a > 0.1 and c.r > 0.35 and c.g > 0.35 and c.b > 0.35 and c.g < 0.82


func _is_source_shore(c: Color) -> bool:
	return c.a > 0.01 and not (c.g > 0.8 and c.r < 0.25 and c.b < 0.25)


func _require(condition: bool, message: String) -> void:
	if condition:
		return
	failures.append(message)
