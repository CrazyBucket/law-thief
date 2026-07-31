class_name PoisonCloudRenderer
extends RefCounted

const IsoCoordinates = preload("res://scripts/map/iso_coordinates.gd")
const OverlayCloudLayoutClass := preload("res://scripts/map/overlay_cloud_layout.gd")
const CloudPartsShader := preload("res://scenes/battle/overlay_cloud_parts.gdshader")
const ATLAS_PATH := "res://assets/overlays/effects/overlay_poison_cloud_parts.png"
const FOG_TEXTURE_KEY := "overlay://poison_fog_cloud_parts"
const SMOKE_TEXTURE_KEY := "overlay://toxic_smoke_cloud_parts"

static var _layout_cache: Dictionary = {}
static var _source_rects: Array[Rect2] = []


static func shader_specs() -> Array[Dictionary]:
	return [
		{"path": ATLAS_PATH, "key": FOG_TEXTURE_KEY, "cloud_parts": true, "effect_type": Constants.TILE_MOD_POISON_FOG},
		{"path": ATLAS_PATH, "key": SMOKE_TEXTURE_KEY, "cloud_parts": true, "effect_type": Constants.TILE_MOD_TOXIC_SMOKE},
	]


static func configure_shader_material(
	material: ShaderMaterial,
	effect_type: String,
	phase: float
) -> void:
	material.shader = CloudPartsShader
	var smoke := effect_type == Constants.TILE_MOD_TOXIC_SMOKE
	material.set_shader_parameter("shadow_color", Color(0.12, 0.10, 0.16) if smoke else Color(0.08, 0.26, 0.08))
	material.set_shader_parameter("mid_color", Color(0.28, 0.22, 0.32) if smoke else Color(0.24, 0.62, 0.13))
	material.set_shader_parameter("highlight_color", Color(0.46, 0.36, 0.48) if smoke else Color(0.55, 0.82, 0.26))
	material.set_shader_parameter("breathe", 0.018 if smoke else 0.032)
	material.set_shader_parameter("speed", 0.36 if smoke else 0.72)
	material.set_shader_parameter("opacity", 1.0)
	material.set_shader_parameter("phase", phase)


static func draw(
	canvas: Control,
	texture: Texture2D,
	center: Vector2,
	cell: Vector2i,
	effect_type: String,
	front: bool,
	stage: float,
	occupied: bool,
	time_sec: float,
	overall_alpha: float = 1.0
) -> void:
	if texture == null or overall_alpha <= 0.001 or (front and not occupied):
		return
	var source_rects := _part_rects()
	if source_rects.size() != OverlayCloudLayoutClass.ATLAS_PART_COUNT:
		return
	if not front:
		_draw_cell_anchor(canvas, center, effect_type, stage, overall_alpha)
	var layout := _layout(cell, effect_type)
	var parts: Array = layout["parts"]
	var positions: Array[Vector2] = []
	for part_variant in parts:
		var part: Dictionary = part_variant
		var base_position: Vector2 = part["base_position"]
		positions.append(
			center + IsoCoordinates.visual_vec(
				base_position + OverlayCloudLayoutClass.animated_offset(part, time_sec)
			)
		)
	_draw_particles(
		canvas,
		effect_type,
		front,
		occupied,
		stage,
		layout["particles"],
		positions,
		time_sec,
		overall_alpha
	)
	for index in range(parts.size()):
		var part: Dictionary = parts[index]
		var part_front := bool(part["front"])
		if occupied:
			if part_front != front:
				continue
		elif front:
			continue
		var source_rect: Rect2 = source_rects[int(part["atlas_index"])]
		var width := IsoCoordinates._tile_w() \
			* float(part["width_ratio"]) \
			* lerpf(0.86, 1.0, stage)
		var draw_size := Vector2(
			width,
			width * source_rect.size.y / maxf(source_rect.size.x, 1.0)
		)
		var alpha := float(part["alpha"]) \
			* OverlayCloudLayoutClass.drift_alpha(part, time_sec) \
			* lerpf(0.64, 1.0, stage) \
			* overall_alpha
		if front:
			alpha *= 0.92
		canvas.draw_texture_rect_region(
			texture,
			Rect2(positions[index] - draw_size * 0.5, draw_size),
			source_rect,
			Color(1.0, 1.0, 1.0, alpha),
			false
		)


static func _draw_particles(
	canvas: Control,
	effect_type: String,
	front: bool,
	occupied: bool,
	stage: float,
	particles: Array,
	positions: Array[Vector2],
	time_sec: float,
	overall_alpha: float
) -> void:
	var color := (
		Color(0.48, 0.36, 0.52)
		if effect_type == Constants.TILE_MOD_TOXIC_SMOKE
		else Color(0.58, 0.88, 0.34)
	)
	for particle_variant in particles:
		var particle: Dictionary = particle_variant
		var particle_front := bool(particle["front"])
		if occupied:
			if particle_front != front:
				continue
		elif front:
			continue
		var position := positions[int(particle["from_index"])].lerp(
			positions[int(particle["to_index"])],
			float(particle["mix"])
		)
		position.y += IsoCoordinates.visual(
			OverlayCloudLayoutClass.particle_rise(particle, time_sec)
		)
		var alpha := float(particle["alpha"]) \
			* OverlayCloudLayoutClass.particle_life(particle, time_sec) \
			* lerpf(0.60, 1.0, stage) \
			* overall_alpha
		if front:
			alpha *= 0.86
		var pixel_size := IsoCoordinates.visual(float(particle["size"]))
		var particle_color := color
		particle_color.a = alpha
		var snapped := Vector2(roundf(position.x), roundf(position.y))
		canvas.draw_rect(
			Rect2(snapped - Vector2.ONE * pixel_size * 0.5, Vector2.ONE * pixel_size),
			particle_color
		)


static func _draw_cell_anchor(
	canvas: Control,
	center: Vector2,
	effect_type: String,
	stage: float,
	overall_alpha: float
) -> void:
	var smoke := effect_type == Constants.TILE_MOD_TOXIC_SMOKE
	var fill := Color(0.24, 0.16, 0.29, 0.14) if smoke else Color(0.22, 0.58, 0.12, 0.10)
	var edge := Color(0.60, 0.42, 0.64, 0.64) if smoke else Color(0.50, 0.84, 0.22, 0.56)
	fill.a *= overall_alpha * lerpf(0.72, 1.0, stage)
	edge.a *= overall_alpha * lerpf(0.78, 1.0, stage)
	var corners := IsoCoordinates.diamond_corners(center)
	var inset := PackedVector2Array()
	for corner in corners:
		inset.append(center + (corner - center) * 0.78)
	canvas.draw_colored_polygon(inset, fill)
	var line_width := IsoCoordinates.visual(1.7 if smoke else 1.25)
	for index in range(inset.size()):
		var from: Vector2 = inset[index]
		var to: Vector2 = inset[(index + 1) % inset.size()]
		if smoke:
			canvas.draw_line(from.lerp(to, 0.26), from.lerp(to, 0.74), edge, line_width)
		else:
			canvas.draw_line(from.lerp(to, 0.06), from.lerp(to, 0.30), edge, line_width)
			canvas.draw_line(from.lerp(to, 0.70), from.lerp(to, 0.94), edge, line_width)


static func _layout(cell: Vector2i, effect_type: String) -> Dictionary:
	var key := "%s:%d:%d" % [effect_type, cell.x, cell.y]
	if not _layout_cache.has(key):
		_layout_cache[key] = OverlayCloudLayoutClass.build(cell, effect_type)
	return _layout_cache[key]


static func _part_rects() -> Array[Rect2]:
	if not _source_rects.is_empty():
		return _source_rects
	var source := load(ATLAS_PATH) as Texture2D
	var image := source.get_image() if source != null else Image.load_from_file(ATLAS_PATH)
	if image == null or image.is_empty():
		return _source_rects
	if image.is_compressed():
		image.decompress()
	var cell_width := image.get_width() / OverlayCloudLayoutClass.ATLAS_COLUMNS
	var cell_height := image.get_height() / OverlayCloudLayoutClass.ATLAS_ROWS
	for row in range(OverlayCloudLayoutClass.ATLAS_ROWS):
		for column in range(OverlayCloudLayoutClass.ATLAS_COLUMNS):
			var frame := Rect2i(
				column * cell_width,
				row * cell_height,
				cell_width,
				cell_height
			)
			_source_rects.append(_visible_rect(image, frame))
	return _source_rects


static func _visible_rect(image: Image, frame: Rect2i) -> Rect2:
	var min_x := frame.end.x
	var min_y := frame.end.y
	var max_x := frame.position.x - 1
	var max_y := frame.position.y - 1
	for y in range(frame.position.y, frame.end.y):
		for x in range(frame.position.x, frame.end.x):
			if image.get_pixel(x, y).a <= 0.02:
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		return Rect2(frame)
	return Rect2(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
