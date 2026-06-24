extends SceneTree

const SPARSE_ASSETS := {
	"res://assets/overlays/vegetation/overlay_grass_sprouts.png": 0.20,
	"res://assets/overlays/vegetation/overlay_grass_patch.png": 0.32,
	"res://assets/overlays/vegetation/overlay_grass_tall.png": 0.35,
	"res://assets/overlays/vegetation/overlay_grass_thicket.png": 0.45,
	"res://assets/overlays/effects/overlay_poison_water_glints.png": 0.10,
}

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for path in SPARSE_ASSETS:
		var image := _load_image(path)
		if image == null:
			continue
		var ratio := _alpha_ratio(image, Rect2i(Vector2i.ZERO, image.get_size()))
		_require(ratio <= float(SPARSE_ASSETS[path]), "%s is too visually dense for an overlay (%.3f)" % [path, ratio])
		_require(_transparent_corners(image), "%s must not carry an opaque tile-shaped background" % path)
	_check_fire_frames()
	if not _failures.is_empty():
		for failure in _failures:
			push_error(failure)
		quit(1)
		return
	print("OVERLAY_ASSET_CONTRACT_TEST_PASS")
	quit(0)


func _check_fire_frames() -> void:
	var image := _load_image("res://assets/overlays/effects/overlay_fire_loop.png")
	if image == null:
		return
	_require(image.get_width() % 2 == 0 and image.get_height() % 2 == 0, "fire loop must remain a 2x2 atlas")
	var frame_size := image.get_size() / 2
	for row in range(2):
		for column in range(2):
			var rect := Rect2i(Vector2i(column, row) * frame_size, frame_size)
			_require(_alpha_ratio(image, rect) <= 0.17, "fire frame %d,%d is too dense" % [column, row])
			_require(_transparent_frame_border(image, rect), "fire frame %d,%d touches its atlas edge" % [column, row])


func _load_image(path: String) -> Image:
	var texture := load(path) as Texture2D
	if texture == null:
		_require(false, "overlay texture failed to load: %s" % path)
		return null
	return texture.get_image()


func _alpha_ratio(image: Image, rect: Rect2i) -> float:
	var opaque := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if image.get_pixel(x, y).a > 0.08:
				opaque += 1
	return float(opaque) / float(rect.size.x * rect.size.y)


func _transparent_corners(image: Image) -> bool:
	var last := image.get_size() - Vector2i.ONE
	return image.get_pixel(0, 0).a <= 0.01 \
		and image.get_pixel(last.x, 0).a <= 0.01 \
		and image.get_pixel(0, last.y).a <= 0.01 \
		and image.get_pixel(last.x, last.y).a <= 0.01


func _transparent_frame_border(image: Image, rect: Rect2i) -> bool:
	for x in range(rect.position.x, rect.end.x):
		if image.get_pixel(x, rect.position.y).a > 0.01 or image.get_pixel(x, rect.end.y - 1).a > 0.01:
			return false
	for y in range(rect.position.y, rect.end.y):
		if image.get_pixel(rect.position.x, y).a > 0.01 or image.get_pixel(rect.end.x - 1, y).a > 0.01:
			return false
	return true


func _require(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
