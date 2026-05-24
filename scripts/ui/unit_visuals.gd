extends RefCounted

const _BODY_COLORS := {
	"unit_player": Color(0.2, 0.78, 0.45),
	"unit_bomber": Color(0.9, 0.28, 0.28),
	"unit_training_guard": Color(0.62, 0.68, 0.72),
	"unit_heavy_guard": Color(0.45, 0.52, 0.58),
	"unit_poison_bug": Color(0.62, 0.28, 0.78),
	"unit_gravity_eye": Color(0.28, 0.55, 0.92),
	"unit_grunt": Color(0.92, 0.55, 0.22),
}

static var _cache: Dictionary = {}


static func get_unit_texture(unit_def_id: String) -> Texture2D:
	if _cache.has(unit_def_id):
		return _cache[unit_def_id]
	var texture := _build_texture(unit_def_id)
	_cache[unit_def_id] = texture
	return texture


static func gem_color(gem_id: String) -> Color:
	match gem_id:
		"gem_explosion":
			return Color(1.0, 0.45, 0.2)
		"gem_poison":
			return Color(0.55, 0.9, 0.35)
		"gem_gravity":
			return Color(0.35, 0.65, 1.0)
		"gem_heavy_armor":
			return Color(0.7, 0.75, 0.85)
		"gem_conductive":
			return Color(0.95, 0.9, 0.3)
		"gem_fragile":
			return Color(0.85, 0.55, 0.95)
	return Color.WHITE


static func slot_color(slot_type: String) -> Color:
	match slot_type:
		"red":
			return Color(0.95, 0.35, 0.35)
		"blue":
			return Color(0.35, 0.65, 0.95)
		"black":
			return Color(0.55, 0.55, 0.65)
	return Color.WHITE


static func gem_symbol(gem_id: String) -> String:
	match gem_id:
		"gem_explosion":
			return "爆"
		"gem_poison":
			return "毒"
		"gem_gravity":
			return "引"
		"gem_heavy_armor":
			return "甲"
		"gem_conductive":
			return "电"
		"gem_fragile":
			return "碎"
	return "◆"


static func _build_texture(unit_def_id: String) -> ImageTexture:
	var image := Image.create(64, 72, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var body: Color = _BODY_COLORS.get(unit_def_id, Color(0.7, 0.7, 0.7))
	_fill_circle(image, Vector2i(32, 22), 11, Color(0.95, 0.82, 0.68))
	_fill_circle(image, Vector2i(32, 42), 16, body)
	_fill_rect(image, Rect2i(18, 38, 10, 20), body.darkened(0.15))
	_fill_rect(image, Rect2i(36, 38, 10, 20), body.darkened(0.15))
	match unit_def_id:
		"unit_bomber":
			_fill_circle(image, Vector2i(24, 20), 3, Color.BLACK)
			_fill_circle(image, Vector2i(40, 20), 3, Color.BLACK)
			_fill_rect(image, Rect2i(28, 52, 8, 10), Color(0.35, 0.35, 0.38))
		"unit_gravity_eye":
			_fill_circle(image, Vector2i(32, 24), 6, Color.WHITE)
			_fill_circle(image, Vector2i(32, 24), 3, Color.BLACK)
		"unit_poison_bug":
			_fill_circle(image, Vector2i(20, 30), 3, Color.WHITE)
			_fill_circle(image, Vector2i(44, 30), 3, Color.WHITE)
		"unit_heavy_guard":
			_fill_rect(image, Rect2i(22, 34, 20, 18), body.lightened(0.08))
		"unit_player":
			_fill_rect(image, Rect2i(26, 34, 12, 14), Color(0.28, 0.34, 0.42))
	_fill_ellipse(image, Vector2i(32, 66), 14, 4, Color(0, 0, 0, 0.25))
	return ImageTexture.create_from_image(image)


static func _fill_circle(image: Image, center: Vector2i, radius: int, color: Color) -> void:
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			if Vector2(x - center.x, y - center.y).length() <= radius:
				if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
					image.set_pixel(x, y, color)


static func _fill_rect(image: Image, rect: Rect2i, color: Color) -> void:
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
				image.set_pixel(x, y, color)


static func _fill_ellipse(image: Image, center: Vector2i, rx: int, ry: int, color: Color) -> void:
	for y in range(center.y - ry, center.y + ry + 1):
		for x in range(center.x - rx, center.x + rx + 1):
			var dx := float(x - center.x) / float(maxi(rx, 1))
			var dy := float(y - center.y) / float(maxi(ry, 1))
			if dx * dx + dy * dy <= 1.0:
				if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
					image.set_pixel(x, y, color)
